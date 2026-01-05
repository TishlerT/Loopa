import XCTest
@testable import Loopa

final class MultiTrackLooperTests: XCTestCase {
	
	var looper: MultiTrackLooper!
	
	override func setUp() {
		super.setUp()
		looper = MultiTrackLooper()
	}
	
	override func tearDown() {
		looper.stopPlayback()
		looper = nil
		super.tearDown()
	}
	
	// MARK: - Initial State
	
	func testInitialState() {
		XCTAssertFalse(looper.isRecording)
		XCTAssertFalse(looper.isPlaying)
		XCTAssertFalse(looper.isPaused)
		XCTAssertTrue(looper.tracks.isEmpty)
		XCTAssertEqual(looper.barCount, .four)
	}
	
	// MARK: - Bar Count
	
	func testSetBarCount() {
		looper.setBarCount(.eight)
		XCTAssertEqual(looper.barCount, .eight)
		
		looper.setBarCount(.sixteen)
		XCTAssertEqual(looper.barCount, .sixteen)
	}
	
	func testLoopLengthCalculation() {
		looper.bpm = 120
		looper.setBarCount(.four)
		
		// 4 bars * 4 beats/bar = 16 beats
		// At 120 BPM, 1 beat = 0.5 seconds
		// 16 beats * 0.5 = 8 seconds
		XCTAssertEqual(looper.loopLength, 8.0, accuracy: 0.01)
		
		looper.setBarCount(.eight)
		XCTAssertEqual(looper.loopLength, 16.0, accuracy: 0.01)
	}
	
	func testLoopLengthWithDifferentBPM() {
		looper.setBarCount(.four)
		
		looper.bpm = 60
		// 16 beats * 1.0 second/beat = 16 seconds
		XCTAssertEqual(looper.loopLength, 16.0, accuracy: 0.01)
		
		looper.bpm = 180
		// 16 beats * 0.333 second/beat ≈ 5.33 seconds
		XCTAssertEqual(looper.loopLength, 16.0 / 3.0, accuracy: 0.01)
	}
	
	// MARK: - Recording
	
	func testStartRecording() {
		looper.startRecording(instrument: .piano)
		
		XCTAssertTrue(looper.isRecording)
		XCTAssertTrue(looper.isPlaying, "Recording should auto-start playback")
	}
	
	func testStopRecordingCreatesTrack() {
		looper.startRecording(instrument: .piano)
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true)
		looper.addLiveEvent(note: 60, velocity: 0, isNoteOn: false)
		looper.stopRecording()
		
		XCTAssertFalse(looper.isRecording)
		XCTAssertEqual(looper.tracks.count, 1)
		XCTAssertEqual(looper.tracks.first?.instrumentName, "Piano")
	}
	
	func testEmptyRecordingDoesNotCreateTrack() {
		looper.startRecording(instrument: .piano)
		looper.stopRecording()
		
		XCTAssertTrue(looper.tracks.isEmpty, "Empty recording should not create a track")
	}
	
	// MARK: - Multi-Track
	
	func testMultipleTracks() {
		// Record first track
		looper.startRecording(instrument: .piano)
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true)
		looper.stopRecording()
		
		// Record second track
		looper.startRecording(instrument: .drums)
		looper.addLiveEvent(note: 36, velocity: 100, isNoteOn: true)
		looper.stopRecording()
		
		XCTAssertEqual(looper.tracks.count, 2)
		XCTAssertEqual(looper.tracks[0].instrumentName, "Piano")
		XCTAssertEqual(looper.tracks[1].instrumentName, "Drums")
	}
	
	// MARK: - Track Management
	
	func testUndoLastTrack() {
		looper.startRecording(instrument: .piano)
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true)
		looper.stopRecording()
		
		looper.startRecording(instrument: .drums)
		looper.addLiveEvent(note: 36, velocity: 100, isNoteOn: true)
		looper.stopRecording()
		
		XCTAssertEqual(looper.tracks.count, 2)
		
		looper.undoLastTrack()
		XCTAssertEqual(looper.tracks.count, 1)
		XCTAssertEqual(looper.tracks.first?.instrumentName, "Piano")
	}
	
	func testClearAllTracks() {
		looper.startRecording(instrument: .piano)
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true)
		looper.stopRecording()
		
		looper.startRecording(instrument: .drums)
		looper.addLiveEvent(note: 36, velocity: 100, isNoteOn: true)
		looper.stopRecording()
		
		looper.clearAllTracks()
		
		XCTAssertTrue(looper.tracks.isEmpty)
		XCTAssertFalse(looper.isPlaying)
	}
	
	func testDeleteSpecificTrack() {
		looper.startRecording(instrument: .piano)
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true)
		looper.stopRecording()
		
		looper.startRecording(instrument: .drums)
		looper.addLiveEvent(note: 36, velocity: 100, isNoteOn: true)
		looper.stopRecording()
		
		let pianoTrack = looper.tracks[0]
		looper.deleteTrack(pianoTrack)
		
		XCTAssertEqual(looper.tracks.count, 1)
		XCTAssertEqual(looper.tracks.first?.instrumentName, "Drums")
	}
	
	// MARK: - Mute
	
	func testToggleMute() {
		looper.startRecording(instrument: .piano)
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true)
		looper.stopRecording()
		
		var track = looper.tracks[0]
		XCTAssertFalse(track.isMuted)
		
		looper.toggleMute(track)
		track = looper.tracks[0]
		XCTAssertTrue(track.isMuted)
		
		looper.toggleMute(track)
		track = looper.tracks[0]
		XCTAssertFalse(track.isMuted)
	}
	
	// MARK: - Playback
	
	func testStartPlayback() {
		looper.startRecording(instrument: .piano)
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true)
		looper.stopRecording()
		looper.stopPlayback()
		
		looper.startPlayback()
		XCTAssertTrue(looper.isPlaying)
		XCTAssertFalse(looper.isPaused)
	}
	
	func testStopPlayback() {
		looper.startRecording(instrument: .piano)
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true)
		looper.stopRecording()
		
		looper.stopPlayback()
		XCTAssertFalse(looper.isPlaying)
		XCTAssertFalse(looper.isRecording)
		XCTAssertFalse(looper.isPaused)
	}
	
	// MARK: - Pause/Resume
	
	func testPausePlayback() {
		looper.startRecording(instrument: .piano)
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true)
		looper.stopRecording()
		
		// Should be playing after recording stops
		XCTAssertTrue(looper.isPlaying)
		
		// Pause
		looper.pausePlayback()
		XCTAssertFalse(looper.isPlaying)
		XCTAssertTrue(looper.isPaused)
	}
	
	func testResumePlayback() {
		looper.startRecording(instrument: .piano)
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true)
		looper.stopRecording()
		
		// Pause
		looper.pausePlayback()
		XCTAssertTrue(looper.isPaused)
		
		// Resume
		looper.resumePlayback()
		XCTAssertTrue(looper.isPlaying)
		XCTAssertFalse(looper.isPaused)
	}
	
	func testPauseDoesNothingWhenNotPlaying() {
		// Not playing, not paused
		XCTAssertFalse(looper.isPlaying)
		XCTAssertFalse(looper.isPaused)
		
		looper.pausePlayback()
		
		// Should still not be paused (nothing to pause)
		XCTAssertFalse(looper.isPaused)
	}
	
	func testResumeStartsPlaybackWhenNotPaused() {
		looper.startRecording(instrument: .piano)
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true)
		looper.stopRecording()
		looper.stopPlayback()
		
		// Not paused, just stopped
		XCTAssertFalse(looper.isPaused)
		XCTAssertFalse(looper.isPlaying)
		
		// Resume should start playback from beginning
		looper.resumePlayback()
		XCTAssertTrue(looper.isPlaying)
	}
	
	func testStopClearsPausedState() {
		looper.startRecording(instrument: .piano)
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true)
		looper.stopRecording()
		
		// Pause first
		looper.pausePlayback()
		XCTAssertTrue(looper.isPaused)
		
		// Stop should clear paused state
		looper.stopPlayback()
		XCTAssertFalse(looper.isPaused)
		XCTAssertFalse(looper.isPlaying)
	}
}

// MARK: - Instrument Tests

final class InstrumentTests: XCTestCase {
	
	func testAllInstrumentsHaveIcons() {
		for instrument in Instrument.allCases {
			XCTAssertFalse(instrument.icon.isEmpty, "\(instrument.rawValue) should have an icon")
		}
	}
	
	func testDrumKitIdentification() {
		XCTAssertTrue(Instrument.drums.isDrumKit)
		XCTAssertFalse(Instrument.piano.isDrumKit)
		XCTAssertFalse(Instrument.bass.isDrumKit)
	}
	
	func testProgramNumbers() {
		XCTAssertEqual(Instrument.piano.programNumber, 0)
		XCTAssertEqual(Instrument.electricPiano.programNumber, 4)
		XCTAssertEqual(Instrument.bass.programNumber, 32)
	}
}

// MARK: - Bar Count Tests

final class BarCountTests: XCTestCase {
	
	func testAllBarCounts() {
		let expectedCounts = [1, 2, 4, 8, 16]
		let actualCounts = BarCount.allCases.map { $0.rawValue }
		XCTAssertEqual(actualCounts, expectedCounts)
	}
	
	func testDisplayNames() {
		XCTAssertEqual(BarCount.one.displayName, "1 bar")
		XCTAssertEqual(BarCount.four.displayName, "4 bars")
		XCTAssertEqual(BarCount.sixteen.displayName, "16 bars")
	}
}


