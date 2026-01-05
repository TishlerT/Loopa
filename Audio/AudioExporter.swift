import Foundation
import AVFoundation
import UIKit

/// Exports the current session to an M4A audio file
final class AudioExporter {
    static let shared = AudioExporter()
    
    private let fileManager = FileManager.default
    
    /// Export progress (0.0 to 1.0)
    @Published private(set) var progress: Double = 0
    
    /// Whether an export is currently in progress
    @Published private(set) var isExporting: Bool = false
    
    private init() {}
    
    // MARK: - MIDI Event for Offline Rendering
    
    /// Represents a MIDI event at a specific sample position
    private struct MidiEvent: Comparable {
        let samplePosition: Int64
        let pitch: UInt8
        let velocity: UInt8
        let isNoteOn: Bool
        let samplerIndex: Int
        
        static func < (lhs: MidiEvent, rhs: MidiEvent) -> Bool {
            lhs.samplePosition < rhs.samplePosition
        }
    }
    
    // MARK: - Export
    
    /// Export tracks to an M4A audio file
    /// - Parameters:
    ///   - tracks: The tracks to render
    ///   - bpm: Tempo in beats per minute
    ///   - loopLengthBeats: Total loop length in beats
    ///   - sessionName: Name for the output file
    ///   - soundFontURL: URL to the SoundFont file
    /// - Returns: URL to the exported M4A file, or nil if export failed
    func exportToM4A(
        tracks: [Track],
        bpm: Double,
        loopLengthBeats: Double,
        sessionName: String,
        soundFontURL: URL
    ) async -> URL? {
        guard !tracks.isEmpty else {
            print("❌ No tracks to export")
            return nil
        }
        
        await MainActor.run {
            isExporting = true
            progress = 0
        }
        
        defer {
            Task { @MainActor in
                isExporting = false
            }
        }
        
        // Calculate duration
        let secondsPerBeat = 60.0 / bpm
        let duration = loopLengthBeats * secondsPerBeat
        
        print("🎵 Exporting \(tracks.count) tracks, \(loopLengthBeats) beats, \(duration)s duration")
        
        // Setup audio format
        let sampleRate: Double = 44100
        let channels: AVAudioChannelCount = 2
        
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: channels
        ) else {
            print("❌ Failed to create audio format")
            return nil
        }
        
        // Create offline render engine
        let engine = AVAudioEngine()
        let mainMixer = engine.mainMixerNode
        
        // Create samplers for each track
        var samplers: [AVAudioUnitSampler] = []
        var validTracks: [Track] = []
        
        for track in tracks where !track.isVocal && !track.notes.isEmpty && !track.isMuted {
            let sampler = AVAudioUnitSampler()
            engine.attach(sampler)
            engine.connect(sampler, to: mainMixer, format: nil)
            
            // Load SoundFont
            do {
                try sampler.loadSoundBankInstrument(
                    at: soundFontURL,
                    program: UInt8(track.instrumentProgram),
                    bankMSB: UInt8(track.isDrumKit ? 0x78 : 0x79),
                    bankLSB: 0
                )
                sampler.masterGain = Float(track.volume)
                samplers.append(sampler)
                validTracks.append(track)
            } catch {
                print("⚠️ Failed to load instrument for track \(track.instrumentName): \(error)")
            }
        }
        
        guard !samplers.isEmpty else {
            print("❌ No valid tracks to export")
            return nil
        }
        
        // Build sorted list of MIDI events with sample positions
        let midiEvents = buildMidiEvents(
            tracks: validTracks,
            samplerIndices: Array(0..<samplers.count),
            sampleRate: sampleRate,
            bpm: bpm,
            loopLengthBeats: loopLengthBeats
        )
        
        print("📝 Scheduled \(midiEvents.count) MIDI events")
        
        // Prepare engine for manual rendering
        do {
            try engine.enableManualRenderingMode(
                .offline,
                format: format,
                maximumFrameCount: 4096
            )
            try engine.start()
        } catch {
            print("❌ Failed to start offline engine: \(error)")
            return nil
        }
        
        // Calculate total frames
        let totalFrames = AVAudioFrameCount(duration * sampleRate)
        let bufferSize: AVAudioFrameCount = 4096
        
        // Create output buffer
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: totalFrames
        ) else {
            print("❌ Failed to create output buffer")
            engine.stop()
            return nil
        }
        
        // Render audio with inline MIDI event triggering
        var currentFrame: Int64 = 0
        let totalFramesDouble = Double(totalFrames)
        var eventIndex = 0
        
        while currentFrame < Int64(totalFrames) {
            let framesToRender = min(bufferSize, AVAudioFrameCount(Int64(totalFrames) - currentFrame))
            let frameRangeEnd = currentFrame + Int64(framesToRender)
            
            // Trigger any MIDI events that fall within this render block
            while eventIndex < midiEvents.count && midiEvents[eventIndex].samplePosition < frameRangeEnd {
                let event = midiEvents[eventIndex]
                let sampler = samplers[event.samplerIndex]
                
                if event.isNoteOn {
                    sampler.startNote(event.pitch, withVelocity: event.velocity, onChannel: 0)
                } else {
                    sampler.stopNote(event.pitch, onChannel: 0)
                }
                eventIndex += 1
            }
            
            guard let renderBuffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: framesToRender
            ) else {
                break
            }
            
            do {
                let status = try engine.renderOffline(framesToRender, to: renderBuffer)
                
                switch status {
                case .success:
                    // Copy rendered frames to output buffer
                    if let outputFloatData = outputBuffer.floatChannelData,
                       let renderFloatData = renderBuffer.floatChannelData {
                        for channel in 0..<Int(channels) {
                            let sourcePtr = renderFloatData[channel]
                            let destPtr = outputFloatData[channel].advanced(by: Int(currentFrame))
                            memcpy(destPtr, sourcePtr, Int(framesToRender) * MemoryLayout<Float>.size)
                        }
                    }
                    currentFrame += Int64(framesToRender)
                    
                    // Update progress
                    let newProgress = Double(currentFrame) / totalFramesDouble
                    Task { @MainActor in
                        self.progress = newProgress
                    }
                    
                case .insufficientDataFromInputNode:
                    // Continue rendering
                    currentFrame += Int64(framesToRender)
                    
                case .cannotDoInCurrentContext:
                    print("⚠️ Cannot render in current context")
                    break
                    
                case .error:
                    print("❌ Render error")
                    engine.stop()
                    return nil
                    
                @unknown default:
                    break
                }
            } catch {
                print("❌ Render failed: \(error)")
                engine.stop()
                return nil
            }
        }
        
        // Stop all notes at the end
        for sampler in samplers {
            for pitch: UInt8 in 0..<128 {
                sampler.stopNote(pitch, onChannel: 0)
            }
        }
        
        outputBuffer.frameLength = totalFrames
        engine.stop()
        
        // Write to M4A file
        let fileName = sanitizeFileName(sessionName) + ".m4a"
        let outputURL = fileManager.temporaryDirectory.appendingPathComponent(fileName)
        
        // Remove existing file
        try? fileManager.removeItem(at: outputURL)
        
        do {
            try await writeM4A(buffer: outputBuffer, to: outputURL)
            print("✓ Exported audio to: \(outputURL.path)")
            
            await MainActor.run {
                progress = 1.0
            }
            
            return outputURL
        } catch {
            print("❌ Failed to write M4A: \(error)")
            return nil
        }
    }
    
    // MARK: - MIDI Event Building
    
    /// Build a sorted list of all MIDI events with their sample positions
    private func buildMidiEvents(
        tracks: [Track],
        samplerIndices: [Int],
        sampleRate: Double,
        bpm: Double,
        loopLengthBeats: Double
    ) -> [MidiEvent] {
        var events: [MidiEvent] = []
        let secondsPerBeat = 60.0 / bpm
        let totalDurationSeconds = loopLengthBeats * secondsPerBeat
        
        for (trackIndex, track) in tracks.enumerated() {
            let samplerIndex = samplerIndices[trackIndex]
            
            // Calculate how many times to loop this track
            let trackLength = track.recordedLengthBeats
            guard trackLength > 0 else { continue }
            
            let loopCount = track.isLooping ? Int(ceil(loopLengthBeats / trackLength)) : 1
            
            for loopIndex in 0..<loopCount {
                let loopOffsetSeconds = Double(loopIndex) * trackLength * secondsPerBeat
                
                for note in track.notes {
                    let startTimeSeconds = note.startBeat * secondsPerBeat + loopOffsetSeconds
                    let endTimeSeconds = note.endBeat * secondsPerBeat + loopOffsetSeconds
                    
                    // Only include if within total duration
                    guard startTimeSeconds < totalDurationSeconds else { continue }
                    
                    let startSample = Int64(startTimeSeconds * sampleRate)
                    let endSample = Int64(min(endTimeSeconds, totalDurationSeconds) * sampleRate)
                    
                    // Note On event
                    events.append(MidiEvent(
                        samplePosition: startSample,
                        pitch: note.pitch,
                        velocity: note.velocity,
                        isNoteOn: true,
                        samplerIndex: samplerIndex
                    ))
                    
                    // Note Off event
                    events.append(MidiEvent(
                        samplePosition: endSample,
                        pitch: note.pitch,
                        velocity: 0,
                        isNoteOn: false,
                        samplerIndex: samplerIndex
                    ))
                }
            }
        }
        
        // Sort by sample position so we can process in order
        return events.sorted()
    }
    
    // MARK: - M4A Writing
    
    private func writeM4A(buffer: AVAudioPCMBuffer, to url: URL) async throws {
        // Create asset writer
        let assetWriter = try AVAssetWriter(outputURL: url, fileType: .m4a)
        
        // Audio settings for AAC
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: buffer.format.sampleRate,
            AVNumberOfChannelsKey: buffer.format.channelCount,
            AVEncoderBitRateKey: 128000
        ]
        
        let audioInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: audioSettings,
            sourceFormatHint: buffer.format.formatDescription
        )
        audioInput.expectsMediaDataInRealTime = false
        
        assetWriter.add(audioInput)
        
        guard assetWriter.startWriting() else {
            throw assetWriter.error ?? ExportError.writeFailed
        }
        
        assetWriter.startSession(atSourceTime: .zero)
        
        // Convert PCM buffer to CMSampleBuffer and write
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            audioInput.requestMediaDataWhenReady(on: DispatchQueue(label: "audio.export")) {
                guard let sampleBuffer = self.createSampleBuffer(from: buffer) else {
                    audioInput.markAsFinished()
                    assetWriter.finishWriting {
                        if let error = assetWriter.error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    }
                    return
                }
                
                if audioInput.isReadyForMoreMediaData {
                    audioInput.append(sampleBuffer)
                }
                
                audioInput.markAsFinished()
                assetWriter.finishWriting {
                    if let error = assetWriter.error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }
    
    private func createSampleBuffer(from buffer: AVAudioPCMBuffer) -> CMSampleBuffer? {
        let formatDescription = buffer.format.formatDescription
        
        var sampleBuffer: CMSampleBuffer?
        
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(buffer.format.sampleRate)),
            presentationTimeStamp: .zero,
            decodeTimeStamp: .invalid
        )
        
        let frameCount = buffer.frameLength
        
        guard let audioBufferList = buffer.audioBufferList.pointee.mBuffers.mData else {
            return nil
        }
        
        var blockBuffer: CMBlockBuffer?
        let dataSize = Int(buffer.frameLength) * Int(buffer.format.streamDescription.pointee.mBytesPerFrame)
        
        CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: dataSize,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: dataSize,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        
        guard let block = blockBuffer else { return nil }
        
        CMBlockBufferReplaceDataBytes(
            with: audioBufferList,
            blockBuffer: block,
            offsetIntoDestination: 0,
            dataLength: dataSize
        )
        
        CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleCount: CMItemCount(frameCount),
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        
        return sampleBuffer
    }
    
    // MARK: - Helpers
    
    private func sanitizeFileName(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let sanitized = name.components(separatedBy: invalidCharacters).joined(separator: "_")
        return sanitized.isEmpty ? "Untitled" : sanitized
    }
    
    enum ExportError: Error {
        case invalidFormat
        case writeFailed
        case noTracks
    }
}

// MARK: - Share Sheet

extension AudioExporter {
    /// Present a share sheet for the exported audio file
    @MainActor
    func shareAudio(at url: URL) {
        let activityVC = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )
        
        // Configure for iPad
        if let popover = activityVC.popoverPresentationController {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                popover.sourceView = window
                popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
        }
        
        // Present
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            var presentingVC = rootVC
            while let presented = presentingVC.presentedViewController {
                presentingVC = presented
            }
            presentingVC.present(activityVC, animated: true)
        }
    }
}
