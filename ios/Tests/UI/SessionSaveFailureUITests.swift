import XCTest

final class SessionSaveFailureUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--loopa-ui-test-save-failure"]
        app.launch()
    }

    override func tearDownWithError() throws {
        if testRun?.hasSucceeded == false {
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        app.terminate()
        app = nil
    }

    private func wait(_ element: XCUIElement, value: String, timeout: TimeInterval = 8) {
        let predicate = NSPredicate(format: "value == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
    }

    private func recordBeat() {
        let record = app.buttons["recordButton"]
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        record.tap()
        wait(record, value: "Recording")
        let keyboard = app.descendants(matching: .any).matching(identifier: "instrumentKeyboard").firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        keyboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            .press(forDuration: 0.25)
        record.tap()
        wait(app.buttons["tracksButton"], value: "1")
    }

    private func menu(_ item: String) {
        // SwiftUI Menu exposes a nested button whose outer AX element cannot
        // scroll-to-visible. Use that visible element's live frame for the tap.
        app.buttons["sessionMenu"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let button = app.buttons[item]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
    }

    private func nameSession(_ name: String) {
        let field = app.textFields["sessionNameField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        let old = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + name)
    }

    func testFailedSaveBeforeNewKeepsNameAndBeatUntilSuccessfulRetry() {
        recordBeat()
        menu("New Session")
        let confirmation = app.alerts["Save Session?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["Save"].tap()
        nameSession("Safety Beat")
        app.buttons["saveSessionButton"].tap()

        let error = app.staticTexts["sessionSaveError"]
        XCTAssertTrue(error.waitForExistence(timeout: 5), "A failed save must keep its sheet and show a useful error")
        XCTAssertEqual(app.textFields["sessionNameField"].value as? String, "Safety Beat")
        XCTAssertTrue(app.buttons["saveSessionButton"].isEnabled)

        let failedSave = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        failedSave.name = "save_failure_retains_project"
        failedSave.lifetime = .keepAlways
        add(failedSave)

        // Only the first named write fails. Retry must save the retained track
        // before the requested new session is allowed to clear it.
        app.buttons["saveSessionButton"].tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                 object: app.textFields["sessionNameField"])
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        wait(app.buttons["tracksButton"], value: "0")
        menu("Load Session")
        let saved = app.buttons.containing(.staticText, identifier: "Safety Beat")
        XCTAssertTrue(saved.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(saved.count, 1, "Retry should create one durable project")
        saved.firstMatch.tap()
        wait(app.buttons["tracksButton"], value: "1")
        XCTAssertTrue(app.buttons["playPauseButton"].isEnabled)
    }

    func testCancellingFailedSaveRetainsCurrentBeat() {
        recordBeat()
        menu("Save Session")
        nameSession("Keep Playing")
        app.buttons["saveSessionButton"].tap()
        XCTAssertTrue(app.staticTexts["sessionSaveError"].waitForExistence(timeout: 5))
        app.buttons["cancelSaveSessionButton"].tap()
        wait(app.buttons["tracksButton"], value: "1")
        XCTAssertTrue(app.buttons["playPauseButton"].isEnabled)
    }

    func testSwipingAwaySaveBeforeNewDoesNotClearOnLaterOrdinarySave() {
        recordBeat()
        menu("New Session")
        let confirmation = app.alerts["Save Session?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["Save"].tap()
        let save = app.buttons["saveSessionButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        XCTAssertTrue(app.staticTexts["sessionSaveError"].waitForExistence(timeout: 5))
        app.navigationBars["Save Session"].swipeDown()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                 object: app.textFields["sessionNameField"])
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        wait(app.buttons["tracksButton"], value: "1")

        menu("Save Session")
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                             object: app.textFields["sessionNameField"])
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 5), .completed)
        wait(app.buttons["tracksButton"], value: "1")
        XCTAssertTrue(app.buttons["playPauseButton"].isEnabled)
    }

    func testNewAfterDeletingLastTrackDoesNotOverwriteEarlierSavedProject() {
        recordBeat()
        menu("Save Session")
        nameSession("Original Beat")
        app.buttons["saveSessionButton"].tap()
        XCTAssertTrue(app.staticTexts["sessionSaveError"].waitForExistence(timeout: 5))
        app.buttons["saveSessionButton"].tap()
        let firstSaved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                  object: app.textFields["sessionNameField"])
        XCTAssertEqual(XCTWaiter.wait(for: [firstSaved], timeout: 5), .completed)

        app.buttons["tracksButton"].tap()
        let delete = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'deleteButton_'" )).firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        let confirmation = app.alerts["Delete Track?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["Delete"].tap()
        app.buttons["Done"].tap()
        wait(app.buttons["tracksButton"], value: "0")
        menu("New Session")

        recordBeat()
        menu("Save Session")
        nameSession("Second Beat")
        app.buttons["saveSessionButton"].tap()
        let secondSaved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                   object: app.textFields["sessionNameField"])
        XCTAssertEqual(XCTWaiter.wait(for: [secondSaved], timeout: 5), .completed)
        menu("Load Session")
        let original = app.buttons.containing(.staticText, identifier: "Original Beat")
        let second = app.buttons.containing(.staticText, identifier: "Second Beat")
        XCTAssertTrue(original.firstMatch.waitForExistence(timeout: 5), "Starting a new empty project must preserve the old saved project")
        XCTAssertTrue(second.firstMatch.exists)
        XCTAssertEqual(original.count, 1)
        XCTAssertEqual(second.count, 1)
        original.firstMatch.tap()
        wait(app.buttons["tracksButton"], value: "1")
    }
}
