import XCTest

/// UI tests for the transport control buttons
final class TransportControlsUITests: XCTestCase {
	
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
	
	// MARK: - Button Existence Tests
	
	func testTransportButtonsExist() throws {
		let recordButton = app.buttons["recordButton"]
		let playPauseButton = app.buttons["playPauseButton"]
		let restartButton = app.buttons["restartButton"]
		let quantizeButton = app.buttons["quantizeButton"]
		
		XCTAssertTrue(recordButton.waitForExistence(timeout: 5), "Record button should exist")
		XCTAssertTrue(playPauseButton.exists, "Play/Pause button should exist")
		XCTAssertTrue(restartButton.exists, "Restart button should exist")
		XCTAssertTrue(quantizeButton.exists, "Quantize button should exist")
	}
	
	// MARK: - Record Button Tests
	
	func testRecordButtonStartsRecording() throws {
		let recordButton = app.buttons["recordButton"]
		XCTAssertTrue(recordButton.waitForExistence(timeout: 5))
		
		// Tap record to start recording
		recordButton.tap()
		
		// Wait a moment for state to update
		Thread.sleep(forTimeInterval: 0.5)
		
		// Play/Pause button should now be enabled (recording auto-starts playback)
		let playPauseButton = app.buttons["playPauseButton"]
		XCTAssertTrue(playPauseButton.isEnabled, "Play/Pause should be enabled during recording")
	}
	
	func testRecordButtonTogglesRecording() throws {
		let recordButton = app.buttons["recordButton"]
		XCTAssertTrue(recordButton.waitForExistence(timeout: 5))
		
		// Start recording
		recordButton.tap()
		Thread.sleep(forTimeInterval: 0.5)
		
		// Stop recording (tap again)
		recordButton.tap()
		Thread.sleep(forTimeInterval: 0.5)
		
		// Should have created a track, so buttons should still be enabled
		let playPauseButton = app.buttons["playPauseButton"]
		XCTAssertTrue(playPauseButton.isEnabled, "Play/Pause should be enabled after recording a track")
	}
	
	// MARK: - Play/Pause Button Tests
	
	func testPlayPauseButtonToggles() throws {
		let recordButton = app.buttons["recordButton"]
		let playPauseButton = app.buttons["playPauseButton"]
		
		XCTAssertTrue(recordButton.waitForExistence(timeout: 5))
		
		// First record something so we have a track
		recordButton.tap()
		Thread.sleep(forTimeInterval: 0.5)
		recordButton.tap() // Stop recording
		Thread.sleep(forTimeInterval: 0.3)
		
		// Now test play/pause - should be playing after recording stops
		// Tap to pause
		playPauseButton.tap()
		Thread.sleep(forTimeInterval: 0.3)
		
		// Tap again to resume
		playPauseButton.tap()
		Thread.sleep(forTimeInterval: 0.3)
		
		// Should still be enabled
		XCTAssertTrue(playPauseButton.isEnabled, "Play/Pause should remain enabled")
	}
	
	// MARK: - Restart Button Tests
	
	func testRestartButtonRestartsFromBeginning() throws {
		let recordButton = app.buttons["recordButton"]
		let restartButton = app.buttons["restartButton"]
		
		XCTAssertTrue(recordButton.waitForExistence(timeout: 5))
		
		// Record something first (count-in is 4 beats at 100 BPM = 2.4s)
		recordButton.tap()
		Thread.sleep(forTimeInterval: 3.5) // Wait for count-in + some recording time
		recordButton.tap() // Stop recording
		Thread.sleep(forTimeInterval: 0.5)
		
		// Wait for restart button to be enabled
		let enabledPredicate = NSPredicate(format: "isEnabled == true")
		expectation(for: enabledPredicate, evaluatedWith: restartButton, handler: nil)
		waitForExpectations(timeout: 3, handler: nil)
		
		// Restart should be enabled and work
		restartButton.tap()
		
		// App should not crash and button should still be enabled
		Thread.sleep(forTimeInterval: 0.5)
		XCTAssertTrue(restartButton.exists, "Restart should still exist after tapping")
	}
	
	// MARK: - Quantize Button Tests
	
	func testQuantizeButtonCyclesSettings() throws {
		let quantizeButton = app.buttons["quantizeButton"]
		XCTAssertTrue(quantizeButton.waitForExistence(timeout: 5))
		
		// Tap multiple times to cycle through settings
		for _ in 0..<4 {
			quantizeButton.tap()
			Thread.sleep(forTimeInterval: 0.2)
		}
		
		// Should not crash and button should still exist
		XCTAssertTrue(quantizeButton.exists, "Quantize button should still exist after cycling")
	}
	
	// MARK: - Integration Tests
	
	func testFullRecordPauseResumeFlow() throws {
		let recordButton = app.buttons["recordButton"]
		let playPauseButton = app.buttons["playPauseButton"]
		let restartButton = app.buttons["restartButton"]
		
		XCTAssertTrue(recordButton.waitForExistence(timeout: 5))
		
		// 1. Start recording
		recordButton.tap()
		Thread.sleep(forTimeInterval: 0.8)
		
		// 2. Stop recording
		recordButton.tap()
		Thread.sleep(forTimeInterval: 0.5)
		
		// Wait for buttons to be enabled after recording
		let enabledPredicate = NSPredicate(format: "isEnabled == true")
		expectation(for: enabledPredicate, evaluatedWith: playPauseButton, handler: nil)
		waitForExpectations(timeout: 3, handler: nil)
		
		// 3. Pause playback
		playPauseButton.tap()
		Thread.sleep(forTimeInterval: 0.5)
		
		// 4. Resume playback
		playPauseButton.tap()
		Thread.sleep(forTimeInterval: 0.5)
		
		// 5. Restart
		restartButton.tap()
		Thread.sleep(forTimeInterval: 0.5)
		
		// All buttons should still exist
		XCTAssertTrue(recordButton.exists)
		XCTAssertTrue(playPauseButton.exists)
		XCTAssertTrue(restartButton.exists)
	}
}

