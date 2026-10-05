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
    ///   - vocalsDirectory: Internal fixture seam; production defaults to Documents/Vocals.
    /// - Returns: URL to the exported M4A file, or nil if export failed
    func exportToM4A(
        tracks: [Track],
        bpm: Double,
        loopLengthBeats: Double,
        sessionName: String,
        soundFontURL: URL,
        vocalsDirectory: URL? = nil
    ) async -> URL? {
        // Bound frame conversions, output allocation (about 106 MB), and event work.
        guard !tracks.isEmpty, tracks.count <= 64,
              bpm.isFinite, bpm > 0, loopLengthBeats.isFinite, loopLengthBeats > 0 else {
            print("❌ No tracks to export")
            return nil
        }
        
        let secondsPerBeat = 60.0 / bpm
        let duration = loopLengthBeats * secondsPerBeat
        let sampleRate = 44_100.0
        guard duration.isFinite, duration >= 1 / sampleRate, duration <= 300 else { return nil }
        let anyTrackSoloed = tracks.contains { $0.isSolo }
        let selectedTracks = tracks.filter { $0.isAudible(anyTrackSoloed: anyTrackSoloed) }
        var eventBudget = 0.0
        for track in selectedTracks {
            let period = track.recordedLengthBeats * secondsPerBeat
            guard track.volume.isFinite, (0...1).contains(track.volume),
                  period.isFinite, period >= 1 / sampleRate, period <= 600 else { return nil }
            if !track.isVocal {
                guard track.notes.count <= 10_000, track.notes.allSatisfy({
                    $0.startBeat.isFinite && $0.startBeat >= 0 && $0.endBeat.isFinite &&
                    $0.endBeat >= $0.startBeat && $0.pitch < 128 && $0.velocity < 128
                }) else { return nil }
                eventBudget += Double(track.notes.count) * 2 * (track.isLooping ? ceil(duration / period) : 1)
                guard eventBudget <= 200_000 else { return nil }
            }
        }
        let vocalTracks = selectedTracks.filter { $0.isVocal }

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
        print("🎵 Exporting \(tracks.count) tracks, \(loopLengthBeats) beats, \(duration)s duration")
        
        // Setup audio format
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
        
        for track in selectedTracks where !track.isVocal && !track.notes.isEmpty {
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
                // The sampler's gain is in decibels. The downstream mixer input's
                // volume is the linear 0...1 fader, including exact silence at zero.
                sampler.overallGain = 0
                sampler.volume = track.volume
                samplers.append(sampler)
                validTracks.append(track)
            } catch {
                print("❌ Failed to load selected instrument for track \(track.instrumentName): \(error)")
                return nil
            }
        }
        
        guard !samplers.isEmpty || !vocalTracks.isEmpty else {
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
        defer { engine.stop() }
        do {
            if !samplers.isEmpty {
                try engine.enableManualRenderingMode(
                    .offline,
                    format: format,
                    maximumFrameCount: 4096
                )
                try engine.start()
            }
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
        
        guard let outputData = outputBuffer.floatChannelData else { return nil }
        for channel in 0..<Int(channels) {
            outputData[channel].initialize(repeating: 0, count: Int(totalFrames))
        }

        // Render audio with inline MIDI event triggering
        var currentFrame: Int64 = 0
        let totalFramesDouble = Double(totalFrames)
        var eventIndex = 0
        
        while !samplers.isEmpty && currentFrame < Int64(totalFrames) {
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
                return nil
            }
            
            do {
                let status = try engine.renderOffline(framesToRender, to: renderBuffer)
                
                switch status {
                case .success:
                    guard renderBuffer.frameLength == framesToRender,
                          renderBuffer.floatChannelData != nil else { return nil }
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
                    
                case .insufficientDataFromInputNode, .cannotDoInCurrentContext:
                    // A partial or stalled render must never become a successful export.
                    return nil
                    
                case .error:
                    print("❌ Render error")
                    engine.stop()
                    return nil
                    
                @unknown default:
                    return nil
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
        
        do {
            let sourceDirectory = vocalsDirectory ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Vocals", isDirectory: true)
            var sourceSecondsRemaining = 600.0
            for track in vocalTracks {
                try mixVocal(track, from: sourceDirectory, into: outputBuffer,
                             secondsPerBeat: secondsPerBeat, sourceSecondsRemaining: &sourceSecondsRemaining)
            }
            let outputURL = try encodePCMToM4A(outputBuffer, sessionName: sessionName)
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
    
    // MARK: - Recorded Audio

    /// Read only one direct regular file under the owned media directory. No path components or
    /// symlinks are accepted, including a symlink whose target happens to be inside the directory.
    private func vocalURL(_ filename: String?, in directory: URL) throws -> URL {
        guard directory.isFileURL, let filename, !filename.isEmpty,
              filename != ".", filename != "..",
              !filename.contains("/"), !filename.contains("\\"), !filename.contains("\0") else {
            throw ExportError.invalidFormat
        }
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        let url = root.appendingPathComponent(filename)
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              url.resolvingSymlinksInPath().deletingLastPathComponent().standardizedFileURL == root else {
            throw ExportError.invalidFormat
        }
        return url
    }

    /// Source duration does not define musical timing: trim a long source at recordedLengthBeats,
    /// pad a short source with silence, then repeat that period only when isLooping is true.
    /// AVAudioConverter performs sample-rate conversion; mono is duplicated at unity to L/R.
    /// Decode the entire selected source even beyond the trim, so corrupt/nonfinite tails fail.
    private func mixVocal(_ track: Track, from directory: URL, into output: AVAudioPCMBuffer,
                          secondsPerBeat: Double, sourceSecondsRemaining: inout Double) throws {
        let file = try AVAudioFile(forReading: vocalURL(track.audioFileName, in: directory),
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        let sourceFormat = file.processingFormat
        let sourceRate = sourceFormat.sampleRate
        guard sourceRate.isFinite, (8_000...192_000).contains(sourceRate),
              (1...2).contains(sourceFormat.channelCount), file.length > 0 else {
            throw ExportError.invalidFormat
        }
        let sourceSeconds = Double(file.length) / sourceRate
        guard sourceSeconds.isFinite, sourceSeconds <= sourceSecondsRemaining else {
            throw ExportError.invalidFormat
        }
        sourceSecondsRemaining -= sourceSeconds
        let periodFrames = Int((track.recordedLengthBeats * secondsPerBeat * output.format.sampleRate).rounded(.down))
        let retainedFrames = min(periodFrames, Int(output.frameLength))
        guard let clip = AVAudioPCMBuffer(pcmFormat: output.format, frameCapacity: AVAudioFrameCount(retainedFrames)),
              let clipData = clip.floatChannelData, let outputData = output.floatChannelData,
              let input = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: 4096),
              let converted = AVAudioPCMBuffer(pcmFormat: output.format, frameCapacity: 4096),
              let converter = AVAudioConverter(from: sourceFormat, to: output.format) else {
            throw ExportError.invalidFormat
        }
        converter.channelMap = sourceFormat.channelCount == 1 ? [0, 0] : [0, 1]
        converter.primeMethod = .normal
        clip.frameLength = clip.frameCapacity
        for channel in 0..<2 { clipData[channel].initialize(repeating: 0, count: retainedFrames) }
        let expectedFrames = Int((sourceSeconds * output.format.sampleRate).rounded(.down))
        var decodedFrames = 0
        var readFailure: Error?
        var completed = false
        // Two extra blocks accommodate the converter's terminal call and rounding, never retries.
        let maximumCalls = (expectedFrames + 4095) / 4096 + 2
        for _ in 0..<maximumCalls {
            let before = file.framePosition
            var conversionError: NSError?
            converted.frameLength = 0
            let status = converter.convert(to: converted, error: &conversionError) { requested, status in
                guard readFailure == nil, file.framePosition < file.length else {
                    status.pointee = .endOfStream
                    return nil
                }
                do {
                    let count = AVAudioFrameCount(min(Int64(min(requested, input.frameCapacity)),
                                                     file.length - file.framePosition))
                    let start = file.framePosition
                    guard count > 0 else { throw ExportError.incompleteOutput }
                    try file.read(into: input, frameCount: count)
                    guard input.frameLength == count, file.framePosition == start + Int64(count),
                          let data = input.floatChannelData else { throw ExportError.incompleteOutput }
                    for channel in 0..<Int(sourceFormat.channelCount) {
                        for frame in 0..<Int(count) where !data[channel][frame].isFinite {
                            throw ExportError.invalidFormat
                        }
                    }
                    status.pointee = .haveData
                    return input
                } catch {
                    readFailure = error
                    status.pointee = .endOfStream
                    return nil
                }
            }
            if let readFailure { throw readFailure }
            if let conversionError { throw conversionError }
            guard status != .error, let data = converted.floatChannelData,
                  converted.frameLength <= converted.frameCapacity else { throw ExportError.incompleteOutput }
            let count = Int(converted.frameLength)
            guard decodedFrames + count <= expectedFrames + 4096 else { throw ExportError.incompleteOutput }
            for channel in 0..<2 {
                for frame in 0..<count {
                    let sample = data[channel][frame]
                    guard sample.isFinite else { throw ExportError.invalidFormat }
                    if decodedFrames + frame < retainedFrames { clipData[channel][decodedFrames + frame] = sample }
                }
            }
            decodedFrames += count
            if status == .endOfStream {
                completed = true
                break
            }
            guard count > 0 || file.framePosition > before else { throw ExportError.incompleteOutput }
        }
        // PCM sample-rate conversion can round by one frame. Larger loss is not silent padding.
        guard completed, file.framePosition == file.length,
              decodedFrames >= max(1, expectedFrames - 1), decodedFrames <= expectedFrames + 1 else {
            throw ExportError.incompleteOutput
        }
        // Sum at each track's linear fader; do not normalize the backing or change its gain.
        // As with the existing MIDI mixer, excessive combined peaks can clip during AAC encoding.
        for frame in 0..<Int(output.frameLength) {
            if !track.isLooping && frame >= periodFrames { break }
            let sourceFrame = track.isLooping ? frame % periodFrames : frame
            for channel in 0..<2 {
                outputData[channel][frame] += clipData[channel][sourceFrame] * track.volume
            }
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
    
    /// Encodes the rendered PCM into one independently owned, verified shareable file.
    /// The writer override is a narrow failure-injection seam; normal calls always use AAC.
    func encodePCMToM4A(
        _ buffer: AVAudioPCMBuffer,
        sessionName: String,
        directory: URL? = nil,
        writer: ((AVAudioPCMBuffer, URL) throws -> Void)? = nil
    ) throws -> URL {
        guard buffer.frameLength > 0,
              buffer.frameLength <= buffer.frameCapacity,
              buffer.format.commonFormat == .pcmFormatFloat32,
              !buffer.format.isInterleaved,
              (1...2).contains(buffer.format.channelCount),
              buffer.format.sampleRate.isFinite, buffer.format.sampleRate > 0,
              let channels = buffer.floatChannelData else {
            throw ExportError.invalidFormat
        }
        // Reject invalid data anywhere in the render, including its last frame.
        for channel in 0..<Int(buffer.format.channelCount) {
            for frame in 0..<Int(buffer.frameLength) where !channels[channel][frame].isFinite {
                throw ExportError.invalidFormat
            }
        }

        let parent = directory ?? fileManager.temporaryDirectory
        guard parent.isFileURL else { throw ExportError.writeFailed }
        let attempt = parent.appendingPathComponent("LoopaExport-\(UUID().uuidString)", isDirectory: true)
        // Creation must succeed before this call owns anything it may remove.
        try fileManager.createDirectory(at: attempt, withIntermediateDirectories: false)
        var complete = false
        defer {
            if !complete { try? fileManager.removeItem(at: attempt) }
        }
        let output = attempt.appendingPathComponent(sanitizeFileName(sessionName) + ".m4a")

        // AVAudioFile converts every channel from its processing format to AAC. Letting
        // the file leave this autorelease pool finalizes it on iOS 17 too; close() is iOS 18+.
        try autoreleasepool {
            if let writer = writer {
                try writer(buffer, output)
            } else {
                try writeAAC(buffer, to: output)
            }
        }
        try verifyAAC(at: output, expectedFormat: buffer.format, expectedFrames: buffer.frameLength)
        complete = true
        return output
    }

    private func writeAAC(_ buffer: AVAudioPCMBuffer, to url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: buffer.format.sampleRate,
            AVNumberOfChannelsKey: buffer.format.channelCount,
            AVEncoderBitRateKey: 128_000
        ]
        let file = try atAACStage("create writer") {
            try AVAudioFile(forWriting: url, settings: settings,
                            commonFormat: buffer.format.commonFormat,
                            interleaved: buffer.format.isInterleaved)
        }
        try atAACStage("write \(buffer.frameLength) PCM frames") { try file.write(from: buffer) }
    }

    private func verifyAAC(at url: URL, expectedFormat: AVAudioFormat, expectedFrames: AVAudioFrameCount) throws {
        let file = try atAACStage("open encoded file") {
            try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        }
        guard file.fileFormat.streamDescription.pointee.mFormatID == kAudioFormatMPEG4AAC,
              file.processingFormat.sampleRate == expectedFormat.sampleRate,
              file.processingFormat.channelCount == expectedFormat.channelCount,
              let decoded = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096) else {
            throw ExportError.incompleteOutput
        }
        // AAC encodes 1024-frame packets. Permit at most one packet of decoder-visible
        // end padding; do not accept missing source frames or an arbitrarily short file.
        let expected = Int64(expectedFrames)
        let maximum = expected + 1024
        let declaredFrames = file.length
        guard declaredFrames >= expected, declaredFrames <= maximum else {
            throw ExportError.incompleteOutput
        }
        var frames: Int64 = 0
        // AVAudioFile can return false without an NSError at EOF, which Swift imports
        // as nilError. Stop at the declared end, but verify every frame was really read.
        while frames < declaredFrames {
            let requested = AVAudioFrameCount(min(Int64(decoded.frameCapacity), declaredFrames - frames))
            try atAACStage("decode at frame \(file.framePosition), length \(declaredFrames), decoded \(frames)") {
                try file.read(into: decoded, frameCount: requested)
            }
            guard decoded.frameLength > 0, decoded.frameLength <= requested else {
                throw ExportError.incompleteOutput
            }
            frames += Int64(decoded.frameLength)
            guard file.framePosition == frames, let channels = decoded.floatChannelData else {
                throw ExportError.incompleteOutput
            }
            for channel in 0..<Int(decoded.format.channelCount) {
                for frame in 0..<Int(decoded.frameLength) where !channels[channel][frame].isFinite {
                    throw ExportError.incompleteOutput
                }
            }
        }
        guard frames == declaredFrames, frames >= expected else { throw ExportError.incompleteOutput }
    }

    /// Preserve the stage when AVAudioFile supplies an otherwise context-free error.
    private func atAACStage<T>(_ stage: String, _ operation: () throws -> T) throws -> T {
        do { return try operation() }
        catch { throw AACOperationError(stage: stage, underlying: error) }
    }

    private struct AACOperationError: Error, CustomStringConvertible {
        let stage: String
        let underlying: Error
        var description: String { "AAC \(stage) failed: \(String(reflecting: underlying))" }
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
        case incompleteOutput
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
