import XCTest

// Stub for Fastlane snapshot helpers when not running via Fastlane
#if !canImport(SnapshotHelper)
func setupSnapshot(_ app: XCUIApplication, waitForAnimations: Bool = true) {}
func snapshot(_ name: String, waitForLoadingIndicator: Bool = true) {}
#endif

/// UI tests for capturing App Store screenshots
/// Run with: fastlane screenshots
final class ScreenshotTests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        
        // Enable screenshot mode via launch argument
        app.launchArguments.append("-SCREENSHOT_MODE")
        app.launchArguments.append("1")
        
        setupSnapshot(app)
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - App Store Screenshots
    
    func testScreenshot01_MainKeyboard() throws {
        // Wait for app to fully load
        let recordButton = app.buttons["recordButton"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5))
        
        // Capture main keyboard screen
        snapshot("01_MainKeyboard")
    }
    
    func testScreenshot02_Recording() throws {
        // Start recording
        let recordButton = app.buttons["recordButton"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5))
        recordButton.tap()
        
        // Wait for count-in to complete
        Thread.sleep(forTimeInterval: 3.0)
        
        // Capture during recording
        snapshot("02_Recording")
        
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
            snapshot("03_TracksMixer")
        }
    }
    
    func testScreenshot04_DrumKit() throws {
        // Switch to drum kit instrument
        // Note: This assumes there's an instrument picker accessible
        // May need to adjust based on actual UI
        
        snapshot("04_DrumKit")
    }
    
    func testScreenshot05_Settings() throws {
        // Open menu and settings
        let menuButton = app.buttons["ellipsis.circle"]
        if menuButton.waitForExistence(timeout: 2) {
            menuButton.tap()
            
            let settingsButton = app.buttons["Settings"]
            if settingsButton.waitForExistence(timeout: 2) {
                settingsButton.tap()
                Thread.sleep(forTimeInterval: 0.5)
                snapshot("05_Settings")
            }
        }
    }
}

