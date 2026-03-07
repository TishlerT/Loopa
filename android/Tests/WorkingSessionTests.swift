import XCTest
@testable import Loopa

/// Tests for auto-save/auto-restore working session functionality
final class WorkingSessionTests: XCTestCase {
	
	override func tearDown() {
		// Clean up working session after each test
		SessionStorage.shared.clearWorkingSession()
		super.tearDown()
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
}

