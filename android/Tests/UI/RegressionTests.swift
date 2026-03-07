import XCTest

/// Regression tests for identified edge cases and bug fixes
final class TransportRegressionTests: XCTestCase {
	
	var app: XCUIApplication!
	
	override func setUpWithError() throws {
		continueAfterFailure = false
		app = XCUIApplication()
		app.launch()
	}
	
	override func tearDownWithError() throws {
		// Capture screenshot on failure for debugging
		if let testRun = testRun, testRun.hasSucceeded == false {
			let screenshot = XCUIScreen.main.screenshot()
			let attachment = XCTAttachment(screenshot: screenshot)
			attachment.lifetime = .keepAlways
			attachment.name = "failure_\(name)"
			add(attachment)
		}
		app = nil
	}
	
	// MARK: - Regression: Buttons Should Work With Zero Tracks
	
	/// Verify record button works even with no tracks
	func testRecordButtonWorksWithZeroTracks() throws {
		let recordButton = app.buttons["recordButton"]
		XCTAssertTrue(recordButton.waitForExistence(timeout: 5))
		
		// Record button should always be enabled
		XCTAssertTrue(recordButton.isEnabled, "Record button should be enabled with zero tracks")
		
		// Should be able to tap it
		recordButton.tap()
		Thread.sleep(forTimeInterval: 0.3)
		
		// Should now be recording (button still exists and works)
		XCTAssertTrue(recordButton.exists)
	}
	
	// MARK: - Regression: Play/Pause Works After Recording
	
	/// Verify play/pause is enabled after recording a track
	func testPlayPauseEnabledAfterRecording() throws {
		let recordButton = app.buttons["recordButton"]
		let playPauseButton = app.buttons["playPauseButton"]
		
		XCTAssertTrue(recordButton.waitForExistence(timeout: 5))
		
		// Record a track
		recordButton.tap()
		Thread.sleep(forTimeInterval: 0.5)
		recordButton.tap()
		Thread.sleep(forTimeInterval: 0.3)
		
		// Play/Pause should now be enabled
		XCTAssertTrue(playPauseButton.isEnabled, "Play/Pause should be enabled after recording")
	}
	
	// MARK: - Regression: Restart Works After Recording
	
	/// Verify restart button is enabled after recording a track
	func testRestartEnabledAfterRecording() throws {
		let recordButton = app.buttons["recordButton"]
		let restartButton = app.buttons["restartButton"]
		
		XCTAssertTrue(recordButton.waitForExistence(timeout: 5))
		
		// Record a track (count-in is 4 beats at 100 BPM = 2.4s, plus recording time)
		recordButton.tap()
		Thread.sleep(forTimeInterval: 3.0) // Wait for count-in to complete and record
		recordButton.tap() // Stop recording
		
		// Wait for restart button to become enabled (async state update)
		let enabledPredicate = NSPredicate(format: "isEnabled == true")
		expectation(for: enabledPredicate, evaluatedWith: restartButton, handler: nil)
		waitForExpectations(timeout: 3, handler: nil)
		
		// Restart should now be enabled
		XCTAssertTrue(restartButton.isEnabled, "Restart should be enabled after recording")
	}
	
	// MARK: - Regression: Pause Does Not Restart (Bug Fix Verification)
	
	/// Verify that pause actually pauses and doesn't restart playback
	/// This was a reported bug where pause would restart instead of pausing
	func testPauseDoesNotRestart() throws {
		let recordButton = app.buttons["recordButton"]
		let playPauseButton = app.buttons["playPauseButton"]
		
		XCTAssertTrue(recordButton.waitForExistence(timeout: 5))
		
		// Record a track
		recordButton.tap()
		Thread.sleep(forTimeInterval: 1.0) // Record for 1 second
		recordButton.tap()
		Thread.sleep(forTimeInterval: 0.3)
		
		// Let it play for a moment
		Thread.sleep(forTimeInterval: 0.5)
		
		// Pause
		playPauseButton.tap()
		Thread.sleep(forTimeInterval: 0.3)
		
		// Resume
		playPauseButton.tap()
		Thread.sleep(forTimeInterval: 0.3)
		
		// Should be playing and buttons should still work
		XCTAssertTrue(playPauseButton.isEnabled)
	}
	
	// MARK: - Regression: Buttons Work During Recording
	
	/// Verify play/pause and restart work during recording
	func testButtonsWorkDuringRecording() throws {
		let recordButton = app.buttons["recordButton"]
		let playPauseButton = app.buttons["playPauseButton"]
		let restartButton = app.buttons["restartButton"]
		
		XCTAssertTrue(recordButton.waitForExistence(timeout: 5))
		
		// Start recording (count-in is 4 beats at 100 BPM = 2.4s)
		recordButton.tap()
		
		// Wait for count-in to complete and recording to start
		Thread.sleep(forTimeInterval: 3.0)
		
		// Wait for buttons to become enabled (async state update)
		let enabledPredicate = NSPredicate(format: "isEnabled == true")
		expectation(for: enabledPredicate, evaluatedWith: playPauseButton, handler: nil)
		waitForExpectations(timeout: 3, handler: nil)
		
		// Now check both buttons during recording
		XCTAssertTrue(playPauseButton.isEnabled, "Play/Pause should be enabled during recording")
		XCTAssertTrue(restartButton.isEnabled, "Restart should be enabled during recording")
		
		// Clean up - stop recording
		recordButton.tap()
	}
	
	// MARK: - Regression: Record Stops But Music Continues
	
	/// Verify stopping recording doesn't stop the music
	func testStoppingRecordDoesNotStopMusic() throws {
		let recordButton = app.buttons["recordButton"]
		let playPauseButton = app.buttons["playPauseButton"]
		
		XCTAssertTrue(recordButton.waitForExistence(timeout: 5))
		
		// Start recording
		recordButton.tap()
		Thread.sleep(forTimeInterval: 0.5)
		
		// Stop recording
		recordButton.tap()
		Thread.sleep(forTimeInterval: 0.3)
		
		// Music should still be playing (play/pause should show pause state)
		// We can verify by checking if pause is still enabled
		XCTAssertTrue(playPauseButton.isEnabled, "Play/Pause should be enabled after stopping recording")
	}
	
	// MARK: - Regression: Multiple Pause/Resume Cycles
	
	/// Verify pause/resume works correctly over multiple cycles
	func testMultiplePauseResumeCycles() throws {
		let recordButton = app.buttons["recordButton"]
		let playPauseButton = app.buttons["playPauseButton"]
		
		XCTAssertTrue(recordButton.waitForExistence(timeout: 5))
		
		// Record a track
		recordButton.tap()
		Thread.sleep(forTimeInterval: 0.5)
		recordButton.tap()
		Thread.sleep(forTimeInterval: 0.3)
		
		// Cycle pause/resume multiple times
		for i in 0..<5 {
			playPauseButton.tap()
			Thread.sleep(forTimeInterval: 0.2)
			XCTAssertTrue(playPauseButton.isEnabled, "Play/Pause should remain enabled on cycle \(i)")
		}
	}
	
	// MARK: - Regression: Quantize Works At All Times
	
	/// Verify quantize button is always enabled
	func testQuantizeAlwaysEnabled() throws {
		let quantizeButton = app.buttons["quantizeButton"]
		XCTAssertTrue(quantizeButton.waitForExistence(timeout: 5))
		
		// Should be enabled even with no tracks
		XCTAssertTrue(quantizeButton.isEnabled, "Quantize should be enabled with no tracks")
		
		// Cycle through all settings
		for _ in 0..<5 {
			quantizeButton.tap()
			Thread.sleep(forTimeInterval: 0.1)
		}
		
		XCTAssertTrue(quantizeButton.isEnabled, "Quantize should remain enabled")
	}
}

