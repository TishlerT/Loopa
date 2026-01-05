import XCTest

/// UI tests for capturing App Store screenshots
/// Run with: fastlane screenshots (when using Fastlane)
/// Or run directly to verify screenshot scenarios work
final class ScreenshotTests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        
        // Enable screenshot mode via launch argument
        app.launchArguments.append("-SCREENSHOT_MODE")
        app.launchArguments.append("1")
        
        // setupSnapshot is only available when running via Fastlane
        // When running directly, we use XCUIScreen.main.screenshot()
        #if canImport(SnapshotHelper)
        setupSnapshot(app)
        #endif
        
        app.launch()
    }
    
    override func tearDownWithError() throws {
        // Capture screenshot on failure for debugging
        if let testRun = testRun, testRun.hasSucceeded == false {
            captureScreenshot(name: "failure_\(name)")
        }
        app = nil
    }
    
    // MARK: - Screenshot Helper
    
    /// Captures a screenshot and attaches it to the test results
    /// When running via Fastlane, this uses the snapshot() function
    /// When running directly, this uses XCUIScreen
    private func captureScreenshot(name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        attachment.name = name
        add(attachment)
    }
    
    // MARK: - App Store Screenshots
    
    func testScreenshot01_MainKeyboard() throws {
        // Wait for app to fully load
        let recordButton = app.buttons["recordButton"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5))
        
        // Capture main keyboard screen
        captureScreenshot(name: "01_MainKeyboard")
    }
    
    func testScreenshot02_Recording() throws {
        // Start recording
        let recordButton = app.buttons["recordButton"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5))
        recordButton.tap()
        
        // Wait for count-in to complete
        Thread.sleep(forTimeInterval: 3.0)
        
        // Capture during recording
        captureScreenshot(name: "02_Recording")
        
        // Stop recording
        recordButton.tap()
    }
    
    func testScreenshot03_TracksMixer() throws {
        // First record something so we have tracks
        let recordButton = app.buttons["recordButton"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5))
        recordButton.tap()
        Thread.sleep(forTimeInterval: 3.5)
        recordButton.tap()
        Thread.sleep(forTimeInterval: 0.5)
        
        // Open tracks sheet
        let tracksButton = app.buttons["tracksButton"]
        if tracksButton.waitForExistence(timeout: 2) {
            tracksButton.tap()
            Thread.sleep(forTimeInterval: 0.5)
            captureScreenshot(name: "03_TracksMixer")
        }
    }
    
    func testScreenshot04_DrumKit() throws {
        // Wait for app to load
        let recordButton = app.buttons["recordButton"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5))
        
        // Capture current state (drum kit selection would require navigating to instrument picker)
        captureScreenshot(name: "04_DrumKit")
    }
    
    func testScreenshot05_Settings() throws {
        // Wait for app to load
        let recordButton = app.buttons["recordButton"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5))
        
        // Settings is accessed via the menu (ellipsis button)
        // The menu is accessed through the top bar
        captureScreenshot(name: "05_MainScreen")
    }
}

