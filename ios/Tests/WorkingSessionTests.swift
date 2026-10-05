import XCTest
import AVFoundation
import Combine
@testable import Loopa

/// Tests for auto-save/auto-restore working session functionality
final class WorkingSessionTests: XCTestCase {
	private var originalWorkingSessionData: Data?
	private var workingSessionURL: URL {
		FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
			.appendingPathComponent("working_session.json")
	}
	
	override func setUpWithError() throws {
		try super.setUpWithError()
		if FileManager.default.fileExists(atPath: workingSessionURL.path) {
			originalWorkingSessionData = try Data(contentsOf: workingSessionURL)
		}
		// Tests use an empty working session and restore any pre-existing bytes.
		SessionStorage.shared.clearWorkingSession()
	}

	override func tearDownWithError() throws {
		if let originalWorkingSessionData {
			try originalWorkingSessionData.write(to: workingSessionURL, options: .atomic)
		} else {
			SessionStorage.shared.clearWorkingSession()
		}
		try super.tearDownWithError()
	}
	
	// MARK: - SessionStorage Tests
	
	func testSaveAndLoadWorkingSession() {
		// Create a test session
		let track = Track(
			instrumentName: "Piano",
			instrumentProgram: 0,
			isDrumKit: false,
			notes: [MidiNote(pitch: 60, velocity: 100, startBeat: 0, durationBeats: 1)]
		)
		
		let session = SavedSession(
			name: "Test Session",
			bpm: 120,
			barCount: 4,
			tracks: [track]
		)
		
		// Save working session
		SessionStorage.shared.saveWorkingSession(session)
		
		// Load it back
		let loaded = SessionStorage.shared.loadWorkingSession()
		
		XCTAssertNotNil(loaded, "Working session should be loaded")
		XCTAssertEqual(loaded?.name, "Test Session")
		XCTAssertEqual(loaded?.bpm, 120)
		XCTAssertEqual(loaded?.barCount, 4)
		XCTAssertEqual(loaded?.tracks.count, 1)
		XCTAssertEqual(loaded?.tracks.first?.notes.count, 1)
	}
	
	func testClearWorkingSession() {
		// Save a session first
		let session = SavedSession(
			name: "To Be Cleared",
			bpm: 100,
			barCount: 2,
			tracks: []
		)
		SessionStorage.shared.saveWorkingSession(session)
		
		// Verify it exists
		XCTAssertNotNil(SessionStorage.shared.loadWorkingSession())
		
		// Clear it
		SessionStorage.shared.clearWorkingSession()
		
		// Verify it's gone
		XCTAssertNil(SessionStorage.shared.loadWorkingSession())
	}
	
	func testLoadWorkingSessionReturnsNilWhenEmpty() {
		// Clear any existing session
		SessionStorage.shared.clearWorkingSession()
		
		// Should return nil
		XCTAssertNil(SessionStorage.shared.loadWorkingSession())
	}
	
	func testWorkingSessionPreservesTrackData() {
		// Create a session with multiple tracks and various data
		let note1 = MidiNote(pitch: 60, velocity: 100, startBeat: 0, durationBeats: 0.5)
		let note2 = MidiNote(pitch: 64, velocity: 80, startBeat: 1, durationBeats: 1)
		
		let pianoTrack = Track(
			instrumentName: "Piano",
			instrumentProgram: 0,
			isDrumKit: false,
			notes: [note1, note2],
			volume: 0.7
		)
		
		let drumTrack = Track(
			instrumentName: "Drums",
			instrumentProgram: 0,
			isDrumKit: true,
			notes: [MidiNote(pitch: 36, velocity: 127, startBeat: 0, durationBeats: 0.25)],
			volume: 0.9
		)
		
		let session = SavedSession(
			name: "Multi-Track",
			bpm: 95,
			barCount: 8,
			tracks: [pianoTrack, drumTrack]
		)
		
		SessionStorage.shared.saveWorkingSession(session)
		let loaded = SessionStorage.shared.loadWorkingSession()!
		
		XCTAssertEqual(loaded.tracks.count, 2)
		
		// Verify piano track
		let loadedPiano = loaded.tracks[0]
		XCTAssertEqual(loadedPiano.instrumentName, "Piano")
		XCTAssertFalse(loadedPiano.isDrumKit)
		XCTAssertEqual(loadedPiano.notes.count, 2)
		XCTAssertEqual(loadedPiano.volume, 0.7, accuracy: 0.01)
		
		// Verify drum track
		let loadedDrums = loaded.tracks[1]
		XCTAssertEqual(loadedDrums.instrumentName, "Drums")
		XCTAssertTrue(loadedDrums.isDrumKit)
		XCTAssertEqual(loadedDrums.notes.count, 1)
		XCTAssertEqual(loadedDrums.volume, 0.9, accuracy: 0.01)
	}
	
	// MARK: - LooperViewModel Integration Tests
	
	@MainActor
	func testSaveWorkingSessionWithNoTracksClears() {
		let vm = LooperViewModel()
		
		// First, save a session manually
		let session = SavedSession(name: "Existing", bpm: 100, barCount: 4, tracks: [])
		SessionStorage.shared.saveWorkingSession(session)
		
		// Now call saveWorkingSession with empty tracks - should clear
		vm.saveWorkingSession()
		
		// Should be cleared because tracks is empty
		XCTAssertNil(SessionStorage.shared.loadWorkingSession())
	}
	
	@MainActor
	func testClearAllClearsWorkingSession() {
		// Save a working session first
		let track = Track(instrumentName: "Piano", instrumentProgram: 0, isDrumKit: false, notes: [])
		let session = SavedSession(name: "Test", bpm: 100, barCount: 4, tracks: [track])
		SessionStorage.shared.saveWorkingSession(session)
		
		XCTAssertNotNil(SessionStorage.shared.loadWorkingSession())
		
		// Clear all in viewmodel
		let vm = LooperViewModel()
		vm.clearAll()
		
		// Working session should be cleared
		XCTAssertNil(SessionStorage.shared.loadWorkingSession())
	}

	@MainActor
	func testDeletingVocalPreservesAudioInSavedSession() async throws {
		try await assertSavedVocalSurvivesRemoval(undo: false)
	}

	@MainActor
	func testUndoingVocalPreservesAudioInSavedSession() async throws {
		try await assertSavedVocalSurvivesRemoval(undo: true)
	}

	@MainActor
	private func assertSavedVocalSurvivesRemoval(undo: Bool) async throws {
		let fileManager = FileManager.default
		let sessionsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
			.appendingPathComponent("sessions.json")
		// Do not let saveSession replace an unreadable pre-existing registry.
		if fileManager.fileExists(atPath: sessionsURL.path) {
			_ = try JSONDecoder().decode([SavedSession].self, from: Data(contentsOf: sessionsURL))
		}

		let vm = LooperViewModel()
		let filename = "working-session-test-\(UUID().uuidString).wav"
		let audioURL = vm.vocalRecorder.getAudioURL(for: filename)
		let vocal = Track(audioFileName: filename, recordedLengthBeats: 4)
		let session = SavedSession(name: "Vocal fixture \(UUID().uuidString)",
			bpm: 100, barCount: 1, tracks: [vocal])
		var savedFixture = false
		defer {
			vm.stopPlayback()
			vm.vocalRecorder.removePlayer(for: vocal.id)
			// Remove only this test's uniquely identified session and audio file.
			if savedFixture { SessionStorage.shared.deleteSession(session) }
			try? fileManager.removeItem(at: audioURL)
		}

		try writeSyntheticVocal(to: audioURL)
		let originalAudio = try Data(contentsOf: audioURL)
		try assertDecodableVocal(at: audioURL)
		vm.loadSession(session)
		await waitForTracks(in: vm, ids: [vocal.id])
		vm.saveCurrentSession(name: session.name)
		savedFixture = true
		XCTAssertNotNil(SessionStorage.shared.loadSessions().first { $0.id == session.id })

		if undo {
			vm.undoLastTrack()
		} else {
			vm.deleteTrack(vocal)
		}
		await waitForTracks(in: vm, ids: [])
		XCTAssertTrue(vm.looper.tracks.isEmpty, "Removing the vocal must still remove the current track")

		let saved = try XCTUnwrap(SessionStorage.shared.loadSessions().first { $0.id == session.id })
		XCTAssertEqual(saved.tracks.map(\.id), [vocal.id], "Editing the current loop must not rewrite its saved version")
		vm.loadSession(saved)
		await waitForTracks(in: vm, ids: [vocal.id])
		let restored = try XCTUnwrap(vm.tracks.first)
		XCTAssertTrue(restored.isVocal)
		let restoredURL = vm.vocalRecorder.getAudioURL(for: try XCTUnwrap(restored.audioFileName))
		XCTAssertTrue(fileManager.fileExists(atPath: restoredURL.path), "The saved vocal must retain its media after track removal")
		try assertDecodableVocal(at: restoredURL)
		XCTAssertEqual(try Data(contentsOf: restoredURL), originalAudio, "The saved recording must remain unchanged")
	}

	@MainActor
	private func waitForTracks(in vm: LooperViewModel, ids: [UUID]) async {
		let updated = expectation(description: "Published tracks match \(ids)")
		let subscription = vm.$tracks
			.first { $0.map(\.id) == ids }
			.sink { _ in updated.fulfill() }
		await fulfillment(of: [updated], timeout: 3)
		withExtendedLifetime(subscription) {}
	}

	private func writeSyntheticVocal(to url: URL) throws {
		let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
		let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_410))
		buffer.frameLength = 4_410
		let channel = try XCTUnwrap(buffer.floatChannelData)[0]
		for frame in 0..<Int(buffer.frameLength) {
			channel[frame] = Float(0.2 * sin(2 * Double.pi * 440 * Double(frame) / format.sampleRate))
		}
		let file = try AVAudioFile(forWriting: url, settings: format.settings)
		try file.write(from: buffer)
	}

	private func assertDecodableVocal(at url: URL) throws {
		let file = try AVAudioFile(forReading: url)
		XCTAssertEqual(file.length, 4_410)
		XCTAssertEqual(file.processingFormat.sampleRate, 44_100)
		let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4_410))
		try file.read(into: buffer)
		XCTAssertEqual(buffer.frameLength, 4_410)
		let channel = try XCTUnwrap(buffer.floatChannelData)[0]
		let peak = (0..<Int(buffer.frameLength)).map { abs(channel[$0]) }.max() ?? 0
		XCTAssertGreaterThan(peak, 0.19, "The decoded vocal must contain the fixture's audible signal")
	}
}
