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
	
	// MARK: - Multi-Bar Recording After Shorter Track
	
	func testRecordingLongerTrackAfterShorterTrack() {
		// This test verifies the fix for the bug where recording a 4-bar track
		// after a 1-bar track caused notes to get "crammed" into the first bar.
		// The issue was that addLiveEvent used global loopLength (based on max track length)
		// instead of recordingLoopLength (based on barCount setting).
		
		looper.bpm = 120  // 0.5 seconds per beat, 2 seconds per bar
		
		// Step 1: Record a 1-bar drum track
		looper.setBarCount(.one)
		looper.startRecording(instrument: .drums)
		looper.addLiveEvent(note: 36, velocity: 100, isNoteOn: true)
		looper.addLiveEvent(note: 36, velocity: 0, isNoteOn: false)
		looper.stopRecording()
		
		XCTAssertEqual(looper.tracks.count, 1)
		XCTAssertEqual(looper.tracks[0].recordedLengthBeats, 4.0, "1 bar = 4 beats")
		
		// Step 2: Record a 4-bar piano track with notes at various positions
		// At 120 BPM, event times: beat 1 = 0.5s, beat 5 = 2.5s, beat 9 = 4.5s, beat 13 = 6.5s
		looper.setBarCount(.four)
		looper.startRecording(instrument: .piano)
		
		// Simulate notes at beats 1, 5, 9, 13 (one per bar)
		let secondsPerBeat = 60.0 / looper.bpm
		
		// Note at beat 1 (bar 1)
		Thread.sleep(forTimeInterval: 0.1)  // Small delay
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true)
		looper.addLiveEvent(note: 60, velocity: 0, isNoteOn: false)
		
		// Note at beat 5 (bar 2) - should NOT wrap to beat 1
		Thread.sleep(forTimeInterval: secondsPerBeat * 4)  // 4 beats later
		looper.addLiveEvent(note: 62, velocity: 100, isNoteOn: true)
		looper.addLiveEvent(note: 62, velocity: 0, isNoteOn: false)
		
		// Note at beat 9 (bar 3) - should NOT wrap to beat 1
		Thread.sleep(forTimeInterval: secondsPerBeat * 4)  // 4 beats later
		looper.addLiveEvent(note: 64, velocity: 100, isNoteOn: true)
		looper.addLiveEvent(note: 64, velocity: 0, isNoteOn: false)
		
		looper.stopRecording()
		
		// Verify we have 2 tracks now
		XCTAssertEqual(looper.tracks.count, 2, "Should have 2 tracks")
		
		// Verify the piano track has the correct recorded length
		let pianoTrack = looper.tracks[1]
		XCTAssertEqual(pianoTrack.recordedLengthBeats, 16.0, "4 bars = 16 beats")
		XCTAssertEqual(pianoTrack.notes.count, 3, "Should have 3 notes")
		
		// Verify notes are spread across bars (not all crammed into first bar)
		// Note at beat ~0 (bar 1)
		let note1 = pianoTrack.notes.first { $0.pitch == 60 }
		XCTAssertNotNil(note1, "Should have note at pitch 60")
		XCTAssertLessThan(note1!.startBeat, 4.0, "First note should be in bar 1 (beats 0-4)")
		
		// Note at beat ~4-8 (bar 2) - the critical test!
		let note2 = pianoTrack.notes.first { $0.pitch == 62 }
		XCTAssertNotNil(note2, "Should have note at pitch 62")
		XCTAssertGreaterThanOrEqual(note2!.startBeat, 4.0, "Second note should be in bar 2+ (beat 4+)")
		XCTAssertLessThan(note2!.startBeat, 8.0, "Second note should be in bar 2 (beats 4-8)")
		
		// Note at beat ~8-12 (bar 3) - another critical test!
		let note3 = pianoTrack.notes.first { $0.pitch == 64 }
		XCTAssertNotNil(note3, "Should have note at pitch 64")
		XCTAssertGreaterThanOrEqual(note3!.startBeat, 8.0, "Third note should be in bar 3+ (beat 8+)")
		XCTAssertLessThan(note3!.startBeat, 12.0, "Third note should be in bar 3 (beats 8-12)")
	}
	
	func testRecordingFourBarsAfterTwoBars() {
		// Variation: 4 bars after 2 bars (notes should not wrap to first 2 bars)
		looper.bpm = 120
		
		// Record a 2-bar track first
		looper.setBarCount(.two)
		looper.startRecording(instrument: .drums)
		looper.addLiveEvent(note: 36, velocity: 100, isNoteOn: true)
		looper.stopRecording()
		
		XCTAssertEqual(looper.tracks[0].recordedLengthBeats, 8.0, "2 bars = 8 beats")
		
		// Now record a 4-bar track
		looper.setBarCount(.four)
		looper.startRecording(instrument: .piano)
		
		let secondsPerBeat = 60.0 / looper.bpm
		
		// Note in bar 3 (beat 9)
		Thread.sleep(forTimeInterval: secondsPerBeat * 9)
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true)
		looper.addLiveEvent(note: 60, velocity: 0, isNoteOn: false)
		
		looper.stopRecording()
		
		let pianoTrack = looper.tracks[1]
		XCTAssertEqual(pianoTrack.notes.count, 1)
		
		// The note should be around beat 9, NOT wrapped to beat 1 (9 mod 8 = 1)
		let note = pianoTrack.notes[0]
		XCTAssertGreaterThanOrEqual(note.startBeat, 8.0, "Note should be in bar 3+ (beat 8+)")
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


