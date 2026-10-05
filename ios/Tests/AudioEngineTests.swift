import XCTest
import AVFoundation
@testable import Loopa

final class AudioEngineTests: XCTestCase {
	
	var engine: TishAudioEngine!
	
	override func setUp() {
		super.setUp()
		engine = TishAudioEngine()
	}
	
	override func tearDown() {
		engine = nil
		super.tearDown()
	}
	
	// MARK: - Initialization Tests
	
	func testEngineInitialization() {
		XCTAssertNotNil(engine.engine, "AVAudioEngine should be initialized")
		XCTAssertNotNil(engine.left, "Left sampler should be initialized")
		XCTAssertNotNil(engine.right, "Right sampler should be initialized")
		XCTAssertNotNil(engine.click, "Click sampler should be initialized")
		XCTAssertNotNil(engine.reverb, "Reverb should be initialized")
	}
	
	func testReverbConfiguration() {
		XCTAssertEqual(engine.reverb.wetDryMix, 12, "Reverb wet/dry mix should be 12")
	}
	
	func testSamplersAttachedToEngine() {
		// Check that samplers are attached by verifying they have an engine
		XCTAssertNotNil(engine.left.sampler.engine, "Left sampler should be attached to engine")
		XCTAssertNotNil(engine.right.sampler.engine, "Right sampler should be attached to engine")
		XCTAssertNotNil(engine.click.sampler.engine, "Click sampler should be attached to engine")
		XCTAssertNotNil(engine.reverb.engine, "Reverb should be attached to engine")
	}
	
	// MARK: - Audio Session Tests
	
	func testConfigureSession() {
		// This test verifies the session configuration doesn't throw
		XCTAssertNoThrow(try engine.configureSession(), "Audio session configuration should not throw")
		
		let session = AVAudioSession.sharedInstance()
		XCTAssertEqual(session.category, .playback, "Category should be .playback")
	}
	
	// MARK: - SoundFont Loading Tests
	
	func testSoundFontURLInitiallyNil() {
		XCTAssertNil(engine.soundFontURL, "SoundFont URL should be nil before loading")
		XCTAssertNil(engine.soundFont808URL, "808 SoundFont URL should be nil before loading")
	}
	
	func testLoadSoundFonts() throws {
		// This will fail if GM.sf2 is not in the test bundle
		// In a real test, we'd mock this or include a test SoundFont
		do {
			try engine.loadSoundFonts()
			XCTAssertNotNil(engine.soundFontURL, "SoundFont URL should be set after loading")
		} catch {
			// If GM.sf2 isn't in test bundle, this is expected
			print("Note: GM.sf2 not found in test bundle - this is expected in unit tests")
		}
	}
	
	// MARK: - Engine Start Tests
	
	func testEngineStart() throws {
		try engine.configureSession()
		XCTAssertNoThrow(try engine.start(), "Engine start should not throw")
		XCTAssertTrue(engine.engine.isRunning, "Engine should be running after start")
	}
	
	func testEngineStartIdempotent() throws {
		try engine.configureSession()
		try engine.start()
		XCTAssertNoThrow(try engine.start(), "Starting an already running engine should not throw")
		XCTAssertTrue(engine.engine.isRunning, "Engine should still be running")
	}
}

/// Exercises the file users receive, independently of MIDI rendering and audio hardware.
final class AudioExporterWritingTests: XCTestCase {
    private var directory: URL!
    private let rate = 44_100.0
    private let fixtureFrames: AVAudioFrameCount = 52_920 // 1.2 seconds

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExportWriterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private enum Fixture: Equatable { case stereo, silence, missingRight, duplicateLeft, wrongGain, short, missingSuffix }

    private func fixture(_ kind: Fixture = .stereo) throws -> AVAudioPCMBuffer {
        let count: AVAudioFrameCount = kind == .short ? 44_100 : fixtureFrames
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count))
        buffer.frameLength = count
        let data = try XCTUnwrap(buffer.floatChannelData)
        for frame in 0..<Int(count) {
            let left = Float(0.30 * sin(2 * .pi * 660 * Double(frame) / rate))
            let right = Float(0.15 * sin(2 * .pi * 1320 * Double(frame) / rate))
            let silent = kind == .silence || (kind == .missingSuffix && frame >= Int(count) / 2)
            data[0][frame] = silent ? 0 : (kind == .wrongGain ? left * 0.5 : left)
            data[1][frame] = silent || kind == .missingRight ? 0 : (kind == .duplicateLeft ? left : (kind == .wrongGain ? right * 2 : right))
        }
        return buffer
    }

    private func decode(_ url: URL) throws -> (rate: Double, channels: [[Float]]) {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        XCTAssertEqual(file.fileFormat.streamDescription.pointee.mFormatID, kAudioFormatMPEG4AAC)
        XCTAssertEqual(file.processingFormat.channelCount, 2)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096))
        let declaredFrames = file.length
        var channels = [[Float](), [Float]()]
        var framesRead: AVAudioFramePosition = 0
        // AVAudioFile throws a context-free error if asked to read after its last frame.
        // Read the complete declared file, requiring actual progress for every request.
        while framesRead < declaredFrames {
            let requested = AVAudioFrameCount(min(Int64(buffer.frameCapacity), declaredFrames - framesRead))
            try file.read(into: buffer, frameCount: requested)
            guard buffer.frameLength > 0, buffer.frameLength <= requested else {
                throw DecodeFailure.incompleteFrames
            }
            framesRead += Int64(buffer.frameLength)
            XCTAssertEqual(file.framePosition, framesRead)
            let data = try XCTUnwrap(buffer.floatChannelData)
            for channel in 0..<2 {
                channels[channel].append(contentsOf: UnsafeBufferPointer(start: data[channel], count: Int(buffer.frameLength)))
            }
        }
        XCTAssertGreaterThan(framesRead, 0)
        XCTAssertEqual(channels[0].count, Int(declaredFrames))
        XCTAssertEqual(channels[1].count, Int(declaredFrames))
        return (file.processingFormat.sampleRate, channels)
    }

    private enum DecodeFailure: Error { case incompleteFrames }

    private func amplitude(_ samples: ArraySlice<Float>, frequency: Double) -> Double {
        var real = 0.0
        var imaginary = 0.0
        for (frame, sample) in samples.enumerated() {
            let phase = 2 * .pi * frequency * Double(frame) / rate
            real += Double(sample) * cos(phase)
            imaginary += Double(sample) * sin(phase)
        }
        return 2 * hypot(real, imaginary) / Double(samples.count)
    }

    /// Ordinary interleaved PCM16 RIFF for independent inspection with the frozen audio evaluator.
    private func decodedWAV(_ channels: [[Float]]) -> Data {
        let byteCount = channels[0].count * 2 * channels.count
        var wav = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { wav.append(contentsOf: $0) }
        }
        wav.append(contentsOf: "RIFF".utf8)
        append(UInt32(36 + byteCount))
        wav.append(contentsOf: "WAVEfmt ".utf8)
        append(UInt32(16))
        append(UInt16(1)) // PCM
        append(UInt16(channels.count))
        append(UInt32(rate))
        append(UInt32(rate) * UInt32(channels.count * 2))
        append(UInt16(channels.count * 2))
        append(UInt16(16))
        wav.append(contentsOf: "data".utf8)
        append(UInt32(byteCount))
        for frame in channels[0].indices {
            for channel in channels {
                append(Int16(clamping: Int((Double(channel[frame]) * 32_768).rounded())))
            }
        }
        return wav
    }

    /// Explicitly checks both channels and three temporal regions, not only a prefix or metadata.
    private func matchesFixture(_ decoded: (rate: Double, channels: [[Float]])) -> Bool {
        guard decoded.rate == rate, decoded.channels.count == 2,
              decoded.channels[0].count == decoded.channels[1].count,
              abs(decoded.channels[0].count - Int(fixtureFrames)) <= 1024 else { return false }
        let count = decoded.channels[0].count
        for region in [0..<count, 0..<(count / 3), (count / 3)..<(count * 2 / 3), (count * 2 / 3)..<count] {
            let left = decoded.channels[0][region]
            let right = decoded.channels[1][region]
            guard left.allSatisfy({ $0.isFinite }), right.allSatisfy({ $0.isFinite }) else { return false }
            let leftTone = amplitude(left, frequency: 660)
            let rightTone = amplitude(right, frequency: 1320)
            guard (0.27...0.33).contains(leftTone), (0.135...0.165).contains(rightTone),
                  (1.90...2.10).contains(leftTone / rightTone),
                  amplitude(left, frequency: 1320) < 0.02,
                  amplitude(right, frequency: 660) < 0.02 else { return false }
        }
        return true
    }

    func testActualAACPreservesCompleteStereoFixture() throws {
        let url = try AudioExporter.shared.encodePCMToM4A(try fixture(), sessionName: "Stereo", directory: directory)
        let decoded = try decode(url)
        XCTAssertTrue(matchesFixture(decoded), "Decoded AAC must retain both tones, routing, duration and 2:1 level ratio")
        XCTAssertLessThanOrEqual(abs(decoded.channels[0].count - Int(fixtureFrames)), 1024)
        let aac = XCTAttachment(data: try Data(contentsOf: url), uniformTypeIdentifier: "public.mpeg-4-audio")
        aac.name = "actual-export.m4a"
        aac.lifetime = .keepAlways
        add(aac)
        let wav = XCTAttachment(data: decodedWAV(decoded.channels), uniformTypeIdentifier: "com.microsoft.waveform-audio")
        wav.name = "actual-export-decoded.wav"
        wav.lifetime = .keepAlways
        add(wav)
    }

    func testDecodedOracleRejectsSilentMissingDuplicatedWrongGainShortAndDamagedSuffixControls() throws {
        for kind in [Fixture.silence, .missingRight, .duplicateLeft, .wrongGain, .short, .missingSuffix] {
            let url = try AudioExporter.shared.encodePCMToM4A(try fixture(kind), sessionName: "Control", directory: directory)
            XCTAssertFalse(matchesFixture(try decode(url)), "Negative control \(kind) must fail the listening contract")
        }
    }

    func testSameNameAttemptsPreserveEarlierExportsAndForeignFiles() throws {
        let foreign = directory.appendingPathComponent("Same.m4a")
        let foreignData = Data("existing unrelated file".utf8)
        try foreignData.write(to: foreign)
        let first = try AudioExporter.shared.encodePCMToM4A(try fixture(), sessionName: "Same", directory: directory)
        let firstData = try Data(contentsOf: first)
        let second = try AudioExporter.shared.encodePCMToM4A(try fixture(), sessionName: "Same", directory: directory)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try Data(contentsOf: first), firstData)
        XCTAssertEqual(try Data(contentsOf: foreign), foreignData)
        XCTAssertTrue(matchesFixture(try decode(second)))
    }

    func testWriteFailureCleansOnlyItsOwnedPartialAttempt() throws {
        enum Failure: Error { case injected }
        let foreign = directory.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: foreign)
        XCTAssertThrowsError(try AudioExporter.shared.encodePCMToM4A(try fixture(), sessionName: "Partial", directory: directory, writer: { _, url in
            try Data("partial".utf8).write(to: url)
            throw Failure.injected
        }))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["keep.txt"])
        XCTAssertEqual(try String(contentsOf: foreign), "keep")
    }

    func testWriterReturningWithoutCompleteAACIsRejectedAndCleaned() throws {
        for payload in [Data(), Data("not audio".utf8)] {
            XCTAssertThrowsError(try AudioExporter.shared.encodePCMToM4A(try fixture(), sessionName: "Incomplete", directory: directory, writer: { _, url in
                try payload.write(to: url)
            }))
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        }
    }

    func testValidButShortAACCannotBeReportedAsComplete() throws {
        let full = try fixture()
        XCTAssertThrowsError(try AudioExporter.shared.encodePCMToM4A(full, sessionName: "Truncated", directory: directory, writer: { buffer, url in
            let shortBuffer = try self.fixture(.short)
            let file = try AVAudioFile(forWriting: url, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: self.rate,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128_000
            ], commonFormat: buffer.format.commonFormat, interleaved: buffer.format.isInterleaved)
            try file.write(from: shortBuffer)
        })) { error in
            guard let exportError = error as? AudioExporter.ExportError,
                  case .incompleteOutput = exportError else {
                XCTFail("A valid short AAC must fail the completeness check, not an unrelated operation: \(error)")
                return
            }
        }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    func testUnwritableDestinationPreservesExistingItem() throws {
        let blocked = directory.appendingPathComponent("regular-file")
        let original = Data("not a directory".utf8)
        try original.write(to: blocked)
        XCTAssertThrowsError(try AudioExporter.shared.encodePCMToM4A(try fixture(), sessionName: "Blocked", directory: blocked))
        XCTAssertEqual(try Data(contentsOf: blocked), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["regular-file"])
    }

    func testEmptyAndNonfinitePCMFailBeforeCreatingOutput() throws {
        let empty = try fixture()
        empty.frameLength = 0
        XCTAssertThrowsError(try AudioExporter.shared.encodePCMToM4A(empty, sessionName: "Empty", directory: directory))
        let invalid = try fixture()
        invalid.floatChannelData![1][Int(fixtureFrames) - 1] = .nan
        XCTAssertThrowsError(try AudioExporter.shared.encodePCMToM4A(invalid, sessionName: "NaN", directory: directory))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
}


/// Exercises the production SoundFont renderer and decodes the actual AAC it returns.
final class AudioExporterMixTests: XCTestCase {
    private var ownedOutputs: [URL] = []
    private let rate = 44_100.0
    private let frames = 88_200 // Four beats at 120 BPM.

    override func tearDownWithError() throws {
        for output in ownedOutputs {
            // Every returned export owns its distinct UUID directory, never Documents.
            try FileManager.default.removeItem(at: output.deletingLastPathComponent())
        }
        ownedOutputs = []
    }

    private func track(pitch: UInt8 = 69, volume: Float = 1,
                       muted: Bool = false, solo: Bool = false) -> Track {
        Track(instrumentName: "Fixture Flute", instrumentProgram: 73, isDrumKit: false,
              notes: [MidiNote(pitch: pitch, velocity: 90, startBeat: 0, durationBeats: 4)],
              isMuted: muted, isSolo: solo, volume: volume, recordedLengthBeats: 4,
              isLooping: false)
    }

    private func export(_ tracks: [Track], name: String) async throws -> URL? {
        let soundFont = try XCTUnwrap(Bundle.main.url(forResource: "GM", withExtension: "sf2"),
                                     "The real bundled SoundFont is required; missing audio cannot pass.")
        let url = await AudioExporter.shared.exportToM4A(
            tracks: tracks, bpm: 120, loopLengthBeats: 4,
            sessionName: name, soundFontURL: soundFont)
        if let url {
            ownedOutputs.append(url)
            let attachment = XCTAttachment(data: try Data(contentsOf: url), uniformTypeIdentifier: "public.mpeg-4-audio")
            attachment.name = name + ".m4a"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        return url
    }

    private func render(_ tracks: [Track], name: String) async throws -> [[Float]] {
        let optionalURL = try await export(tracks, name: name)
        let url = try XCTUnwrap(optionalURL, "Every selected instrument must load and render successfully")
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        XCTAssertEqual(file.fileFormat.streamDescription.pointee.mFormatID, kAudioFormatMPEG4AAC)
        XCTAssertEqual(file.processingFormat.sampleRate, rate)
        XCTAssertEqual(file.processingFormat.channelCount, 2)
        guard file.processingFormat.channelCount == 2 else { throw DecodeFailure.incomplete }
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096))
        var channels = [[Float](), [Float]()]
        while file.framePosition < file.length {
            let request = AVAudioFrameCount(min(Int64(buffer.frameCapacity), file.length - file.framePosition))
            try file.read(into: buffer, frameCount: request)
            guard buffer.frameLength > 0, buffer.frameLength <= request else { throw DecodeFailure.incomplete }
            let data = try XCTUnwrap(buffer.floatChannelData)
            for channel in 0..<2 {
                channels[channel].append(contentsOf: UnsafeBufferPointer(start: data[channel], count: Int(buffer.frameLength)))
            }
            guard file.framePosition == Int64(channels[0].count) else { throw DecodeFailure.incomplete }
        }
        XCTAssertEqual(channels[0].count, Int(file.length))
        XCTAssertEqual(channels[0].count, channels[1].count)
        XCTAssertGreaterThanOrEqual(channels[0].count, frames)
        XCTAssertLessThanOrEqual(channels[0].count, frames + 1024)
        XCTAssertTrue(channels.allSatisfy { $0.allSatisfy { $0.isFinite } })
        guard channels[0].count >= frames, channels[0].count == channels[1].count,
              channels.allSatisfy({ $0.allSatisfy { $0.isFinite } }) else { throw DecodeFailure.incomplete }
        let wav = XCTAttachment(data: decodedWAV(channels), uniformTypeIdentifier: "com.microsoft.waveform-audio")
        wav.name = name + "-decoded.wav"
        wav.lifetime = .keepAlways
        add(wav)
        return channels
    }

    private enum DecodeFailure: Error { case incomplete }

    private func decodedWAV(_ channels: [[Float]]) -> Data {
        let byteCount = channels[0].count * channels.count * 2
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: "RIFF".utf8); append(UInt32(36 + byteCount))
        data.append(contentsOf: "WAVEfmt ".utf8); append(UInt32(16)); append(UInt16(1))
        append(UInt16(channels.count)); append(UInt32(rate)); append(UInt32(rate) * 4)
        append(UInt16(4)); append(UInt16(16)); data.append(contentsOf: "data".utf8)
        append(UInt32(byteCount))
        for frame in channels[0].indices {
            for channel in channels {
                append(Int16(clamping: Int((Double(channel[frame]) * 32768).rounded())))
            }
        }
        return data
    }

    private func rms(_ samples: ArraySlice<Float>) -> Double {
        sqrt(samples.reduce(0) { $0 + Double($1) * Double($1) } / Double(samples.count))
    }

    private func assertGain(_ actual: [[Float]], relativeTo reference: [[Float]],
                            expected: Double, file: StaticString = #filePath, line: UInt = #line) {
        // Three regions spanning the note; avoid initial attack and the final note-off block.
        for channel in 0..<2 {
            for region in [4_410..<22_050, 30_870..<48_510, 61_740..<79_380] {
                let baseline = rms(reference[channel][region])
                XCTAssertGreaterThan(baseline, 0.0001, "The reference must be audible", file: file, line: line)
                let ratio = rms(actual[channel][region]) / baseline
                XCTAssertEqual(ratio, expected, accuracy: 0.035,
                               "Decoded amplitude ratio in channel \(channel), region \(region)", file: file, line: line)
            }
        }
    }

    func testSoloExportsOnlySelectedMIDITrack() async throws {
        let selected = track(solo: true)
        let reference = try await render([selected], name: "solo-reference")
        let selectedMix = try await render([selected, track(pitch: 77)], name: "solo-selected")
        assertGain(selectedMix, relativeTo: reference, expected: 1)
    }

    func testMutedSoloDoesNotUnsoloOtherTracks() async throws {
        let url = try await export([track(muted: true, solo: true), track(pitch: 77)], name: "muted-only-solo")
        XCTAssertNil(url, "A muted solo still excludes non-solo tracks; no MIDI track is audible")
    }

    func testMutedSoloIsSilentBesideUnmutedSolo() async throws {
        let selected = track(solo: true)
        let reference = try await render([selected], name: "mixed-solo-reference")
        let selectedMix = try await render([selected, track(pitch: 77, muted: true, solo: true),
                                           track(pitch: 81)], name: "mixed-solo-selected")
        assertGain(selectedMix, relativeTo: reference, expected: 1)
    }

    func testZeroVolumeProducesSilentAAC() async throws {
        let reference = try await render([track()], name: "zero-reference")
        let silent = try await render([track(volume: 0)], name: "zero-volume")
        XCTAssertGreaterThan(rms(reference[0][4_410..<79_380]), 0.0001)
        for channel in silent {
            XCTAssertLessThanOrEqual(channel.map { abs($0) }.max() ?? 1, 0.000001,
                                     "Zero fader must be silent for the entire decoded export")
        }
    }

    func testHalfVolumeHalvesDecodedAmplitude() async throws {
        let reference = try await render([track()], name: "gain-reference")
        let half = try await render([track(volume: 0.5)], name: "gain-half")
        assertGain(half, relativeTo: reference, expected: 0.5)
    }

    func testMissingAudibleInstrumentRejectsWholeExport() async throws {
        // The bundled SoundFont has eight percussion programs; 127 is not one of them.
        var missing = track(pitch: 36)
        missing = Track(instrumentName: "Missing percussion preset", instrumentProgram: 127,
                        isDrumKit: true, notes: missing.notes, volume: 1, recordedLengthBeats: 4)
        let url = try await export([track(), missing], name: "missing-selected-instrument")
        XCTAssertNil(url, "Do not report a partial mix after dropping a selected instrument")
    }
}
