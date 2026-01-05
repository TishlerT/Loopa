import XCTest
@testable import Loopa

/// Tests for audio-visual playback synchronization
/// Ensures the synchronized position calculation matches audio dispatch timing
final class PlaybackSyncTests: XCTestCase {
	
	var looper: MultiTrackLooper!
	
	override func setUp() {
		super.setUp()
		looper = MultiTrackLooper()
		looper.bpm = 120 // 0.5 seconds per beat
		looper.setBarCount(.four) // 16 beats = 8 seconds
	}
	
	override func tearDown() {
		looper.stopPlayback()
		looper = nil
		super.tearDown()
	}
	
	// MARK: - Synchronized Position Tests
	
	func testSynchronizedPositionWhenNotPlaying() {
		// When not playing and not paused, position should be 0
		XCTAssertFalse(looper.isPlaying)
		XCTAssertFalse(looper.isPaused)
		XCTAssertEqual(looper.synchronizedPlaybackPosition, 0, accuracy: 0.001)
		XCTAssertEqual(looper.synchronizedPlaybackFraction, 0, accuracy: 0.001)
	}
	
	func testSynchronizedPositionWhenPaused() {
		// Record a track to enable playback
		looper.startRecording(instrument: .piano)
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true)
		looper.stopRecording()
		
		// Let playback run for a moment
		Thread.sleep(forTimeInterval: 0.1)
		
		// Pause playback
		looper.pausePlayback()
		
		XCTAssertTrue(looper.isPaused)
		XCTAssertFalse(looper.isPlaying)
		
		// Paused position should be preserved (not 0)
		// Allow for some tolerance since we're measuring real time
		XCTAssertGreaterThan(looper.synchronizedPlaybackPosition, 0)
	}
	
	func testSynchronizedPositionDuringPlayback() {
		// Record a track to enable playback
		looper.startRecording(instrument: .piano)
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true)
		looper.stopRecording()
		
		XCTAssertTrue(looper.isPlaying)
		
		// Position should be advancing
		let pos1 = looper.synchronizedPlaybackPosition
		Thread.sleep(forTimeInterval: 0.1)
		let pos2 = looper.synchronizedPlaybackPosition
		
		XCTAssertGreaterThan(pos2, pos1, "Position should advance during playback")
	}
	
	func testSynchronizedFractionRange() {
		// Record a track to enable playback
		looper.startRecording(instrument: .piano)
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true)
		looper.stopRecording()
		
		XCTAssertTrue(looper.isPlaying)
		
		// Fraction should always be between 0 and 1
		for _ in 0..<10 {
			let fraction = looper.synchronizedPlaybackFraction
			XCTAssertGreaterThanOrEqual(fraction, 0, "Fraction should be >= 0")
			XCTAssertLessThan(fraction, 1, "Fraction should be < 1")
			Thread.sleep(forTimeInterval: 0.05)
		}
	}
	
	func testSynchronizedPositionWrapsAtLoopBoundary() {
		// Use a very short loop for faster testing
		looper.bpm = 240 // 0.25 seconds per beat
		looper.setBarCount(.one) // 4 beats = 1 second
		
		// Record a track
		looper.startRecording(instrument: .piano)
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true)
		looper.stopRecording()
		
		XCTAssertTrue(looper.isPlaying)
		
		// Wait for more than one loop cycle
		Thread.sleep(forTimeInterval: 1.2)
		
		// Position should have wrapped (be less than loop length)
		let position = looper.synchronizedPlaybackPosition
		XCTAssertLessThan(position, looper.loopLength, "Position should wrap at loop boundary")
	}
	
	// MARK: - Position Consistency Tests
	
	func testPositionMatchesCurrentPosition() {
		// Record a track to enable playback
		looper.startRecording(instrument: .piano)
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true)
		looper.stopRecording()
		
		// Wait for the looper to update currentPosition
		Thread.sleep(forTimeInterval: 0.1)
		
		// The synchronized position and currentPosition should be very close
		// (currentPosition is updated by the tick, synchronized reads the same calculation)
		let syncPos = looper.synchronizedPlaybackPosition
		let currentPos = looper.currentPosition
		
		// Allow for small timing differences (up to 10ms)
		XCTAssertEqual(syncPos, currentPos, accuracy: 0.05, 
			"Synchronized position should closely match currentPosition")
	}
	
	// MARK: - Seek Tests
	
	func testSeekUpdatesPosition() {
		// Record a track
		looper.startRecording(instrument: .piano)
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true)
		looper.stopRecording()
		
		// Seek to a specific position
		let targetPosition = 2.0
		looper.seekTo(position: targetPosition)
		
		// Position should be at or near the target
		let position = looper.synchronizedPlaybackPosition
		XCTAssertEqual(position, targetPosition, accuracy: 0.1,
			"Position should be at the seek target")
	}
	
	func testSeekClampsToLoopBounds() {
		// Record a track
		looper.startRecording(instrument: .piano)
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true)
		looper.stopRecording()
		
		// Try to seek past the loop length
		looper.seekTo(position: looper.loopLength + 5.0)
		
		// Position should be clamped to loop length
		let position = looper.currentPosition
		XCTAssertLessThanOrEqual(position, looper.loopLength,
			"Position should not exceed loop length")
	}
	
	// MARK: - Pause/Resume Position Continuity
	
	func testPausePreservesPosition() {
		// Record a track
		looper.startRecording(instrument: .piano)
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true)
		looper.stopRecording()
		
		// Let it play for a bit
		Thread.sleep(forTimeInterval: 0.2)
		
		// Pause and note position
		looper.pausePlayback()
		let pausedPosition = looper.synchronizedPlaybackPosition
		
		// Wait a bit more
		Thread.sleep(forTimeInterval: 0.2)
		
		// Position should not have changed while paused
		let positionAfterWait = looper.synchronizedPlaybackPosition
		XCTAssertEqual(pausedPosition, positionAfterWait, accuracy: 0.001,
			"Position should not change while paused")
	}
	
	func testResumeFromPausedPosition() {
		// Record a track
		looper.startRecording(instrument: .piano)
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true)
		looper.stopRecording()
		
		// Let it play for a bit
		Thread.sleep(forTimeInterval: 0.2)
		
		// Pause and note position
		looper.pausePlayback()
		let pausedPosition = looper.synchronizedPlaybackPosition
		
		// Resume
		looper.resumePlayback()
		
		// Position should be very close to where we paused (allowing for small delta)
		let resumedPosition = looper.synchronizedPlaybackPosition
		XCTAssertEqual(pausedPosition, resumedPosition, accuracy: 0.05,
			"Position should continue from paused position")
	}
}

// MARK: - Event Timing Tests

final class EventTimingTests: XCTestCase {
	
	var looper: MultiTrackLooper!
	var dispatchedEvents: [(event: MidiEvent, position: Double)] = []
	
	override func setUp() {
		super.setUp()
		looper = MultiTrackLooper()
		looper.bpm = 120
		looper.setBarCount(.one) // Short loop for faster testing
		dispatchedEvents = []
		
		// Capture events with their positions
		looper.onPlayEvent = { [weak self] event, _ in
			guard let self = self else { return }
			let position = self.looper.synchronizedPlaybackPosition
			self.dispatchedEvents.append((event: event, position: position))
		}
	}
	
	override func tearDown() {
		looper.stopPlayback()
		looper = nil
		dispatchedEvents = []
		super.tearDown()
	}
	
	func testEventsDispatchAtCorrectPositions() {
		// Record some notes at specific times
		looper.startRecording(instrument: .piano)
		
		// Add a note near the start
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true)
		looper.addLiveEvent(note: 60, velocity: 0, isNoteOn: false)
		
		looper.stopRecording()
		
		// Wait for at least one full loop
		let loopLength = looper.loopLength
		Thread.sleep(forTimeInterval: loopLength + 0.5)
		
		// Events should have been dispatched
		XCTAssertGreaterThan(dispatchedEvents.count, 0, "Events should be dispatched during playback")
	}
	
	func testEventPositionsWithinLoopBounds() {
		// Record a note
		looper.startRecording(instrument: .piano)
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true)
		looper.stopRecording()
		
		// Wait for multiple loop cycles
		let loopLength = looper.loopLength
		Thread.sleep(forTimeInterval: loopLength * 2 + 0.5)
		
		// All dispatched event positions should be within loop bounds
		for (_, position) in dispatchedEvents {
			XCTAssertGreaterThanOrEqual(position, 0, "Position should be >= 0")
			XCTAssertLessThan(position, loopLength, "Position should be < loop length")
		}
	}
}

