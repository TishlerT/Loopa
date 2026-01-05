import XCTest
@testable import Loopa

final class MidiLooperTests: XCTestCase {
	
	var looper: MidiLooper!
	
	override func setUp() {
		super.setUp()
		looper = MidiLooper()
	}
	
	override func tearDown() {
		looper.stop()
		looper = nil
		super.tearDown()
	}
	
	// MARK: - Initial State Tests
	
	func testInitialState() {
		XCTAssertFalse(looper.isRecording, "Should not be recording initially")
		XCTAssertFalse(looper.isPlaying, "Should not be playing initially")
		XCTAssertFalse(looper.isOverdubbing, "Should not be overdubbing initially")
		XCTAssertEqual(looper.loopLength, 0, "Loop length should be 0 initially")
		XCTAssertTrue(looper.events.isEmpty, "Events should be empty initially")
	}
	
	// MARK: - Recording Tests
	
	func testStartRecording() {
		looper.startRecording()
		XCTAssertTrue(looper.isRecording, "Should be recording after startRecording")
	}
	
	func testAddLiveEventDuringRecording() {
		looper.startRecording()
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true, isLeft: false)
		
		// Event should be buffered but not in final events until finalized
		XCTAssertTrue(looper.isRecording, "Should still be recording")
	}
	
	func testFinalizeLoop() {
		looper.startRecording()
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true, isLeft: false)
		looper.addLiveEvent(note: 60, velocity: 0, isNoteOn: false, isLeft: false)
		
		looper.finalizeLoop(lengthSeconds: 2.0)
		
		XCTAssertFalse(looper.isRecording, "Should not be recording after finalize")
		XCTAssertTrue(looper.isPlaying, "Should be playing after finalize")
		XCTAssertEqual(looper.loopLength, 2.0, "Loop length should be set")
		XCTAssertEqual(looper.events.count, 2, "Should have 2 events")
	}
	
	// MARK: - Playback Tests
	
	func testStopPlayback() {
		looper.startRecording()
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true, isLeft: false)
		looper.finalizeLoop(lengthSeconds: 2.0)
		
		looper.stop()
		
		XCTAssertFalse(looper.isPlaying, "Should not be playing after stop")
		XCTAssertFalse(looper.isRecording, "Should not be recording after stop")
	}
	
	// MARK: - Overdub Tests
	
	func testStartOverdub() {
		// First create a loop
		looper.startRecording()
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true, isLeft: false)
		looper.finalizeLoop(lengthSeconds: 2.0)
		
		// Then overdub
		looper.startOverdub()
		
		XCTAssertTrue(looper.isOverdubbing, "Should be overdubbing")
		XCTAssertTrue(looper.isPlaying, "Should still be playing during overdub")
	}
	
	func testOverdubAddsEvents() {
		looper.startRecording()
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true, isLeft: false)
		looper.finalizeLoop(lengthSeconds: 2.0)
		
		let initialCount = looper.events.count
		
		looper.startOverdub()
		looper.addLiveEvent(note: 64, velocity: 100, isNoteOn: true, isLeft: false)
		
		XCTAssertGreaterThan(looper.events.count, initialCount, "Overdub should add events")
	}
	
	// MARK: - Clear Tests
	
	func testClear() {
		looper.startRecording()
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true, isLeft: false)
		looper.finalizeLoop(lengthSeconds: 2.0)
		
		looper.clear()
		
		XCTAssertTrue(looper.events.isEmpty, "Events should be empty after clear")
		XCTAssertEqual(looper.loopLength, 0, "Loop length should be 0 after clear")
		XCTAssertFalse(looper.isPlaying, "Should not be playing after clear")
	}
	
	// MARK: - Undo Tests
	
	func testUndo() {
		looper.startRecording()
		looper.addLiveEvent(note: 60, velocity: 100, isNoteOn: true, isLeft: false)
		looper.finalizeLoop(lengthSeconds: 2.0)
		
		let initialCount = looper.events.count
		
		looper.startOverdub()
		looper.addLiveEvent(note: 64, velocity: 100, isNoteOn: true, isLeft: false)
		looper.stopOverdub()
		
		let afterOverdubCount = looper.events.count
		XCTAssertGreaterThan(afterOverdubCount, initialCount, "Should have more events after overdub")
		
		if looper.canUndo {
			looper.undo()
			XCTAssertEqual(looper.events.count, initialCount, "Should revert to initial count after undo")
		}
	}
	
	// MARK: - Recording Elapsed Time Tests
	
	func testCurrentRecordingElapsed() {
		looper.startRecording()
		
		// Wait a tiny bit
		Thread.sleep(forTimeInterval: 0.1)
		
		let elapsed = looper.currentRecordingElapsed()
		XCTAssertGreaterThan(elapsed, 0, "Elapsed time should be positive during recording")
	}
}


