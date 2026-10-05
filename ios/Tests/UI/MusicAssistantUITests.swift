import XCTest

/// Real UI journeys with isolated storage and no injected pairing, credentials,
/// proposal or music. The recorded-track journeys play the actual keyboard.
final class MusicAssistantUITests: XCTestCase {
    private var app: XCUIApplication!
    private let pairingMessage = "Pair this simulator with the local Mac assistant."

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Existing fixture creates a unique temporary storage directory. Only
        // named saves fail; these journeys never request a named save.
        app.launchArguments = ["--loopa-ui-test-save-failure"]
        app.launch()
        wait(app.buttons["tracksButton"], predicate: "value == %@", "0")
    }

    override func tearDownWithError() throws {
        if testRun?.hasSucceeded == false {
            let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            image.name = "assistant_failure_\(name)"
            image.lifetime = .keepAlways
            add(image)
        }
        app.terminate()
        app = nil
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func wait(_ element: XCUIElement, predicate format: String, _ arguments: CVarArg...,
                      timeout: TimeInterval = 8, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: format, argumentArray: arguments), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed,
                       "Expected UI state for \(element.identifier): \(format)", file: file, line: line)
    }

    private enum FormDirection { case towardTop, towardBottom }

    private func reveal(_ element: XCUIElement, toward direction: FormDirection = .towardBottom,
                        file: StaticString = #filePath, line: UInt = #line) {
        let navigation = app.navigationBars["Shape your sound"]
        // The captured assistant hierarchy contains one CollectionView: SwiftUI Form.
        // Drag inside its content, below the navigation bar, never on the whole app.
        let form = app.collectionViews.firstMatch
        XCTAssertTrue(navigation.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(form.waitForExistence(timeout: 5), file: file, line: line)
        for _ in 0..<10 {
            guard navigation.exists, form.exists else {
                XCTFail("Scrolling must keep the assistant sheet open", file: file, line: line)
                return
            }
            let frame = form.frame
            let top = max(frame.minY, navigation.frame.maxY) + 12
            let bottom = min(frame.maxY, app.frame.maxY) - 12
            guard bottom > top else {
                XCTFail("The assistant form must have a visible viewport", file: file, line: line)
                return
            }
            let target = element.exists ? element.frame : .zero
            if element.exists && element.isHittable && target.minY >= top && target.maxY <= bottom { return }
            let towardTop = target != .zero ? target.minY < top : direction == .towardTop
            let origin = form.coordinate(withNormalizedOffset: .zero)
            let upper = origin.withOffset(CGVector(dx: frame.width * 0.5, dy: top - frame.minY + (bottom - top) * 0.35))
            let lower = origin.withOffset(CGVector(dx: frame.width * 0.5, dy: top - frame.minY + (bottom - top) * 0.65))
            if towardTop { upper.press(forDuration: 0.05, thenDragTo: lower) }
            else { lower.press(forDuration: 0.05, thenDragTo: upper) }
            XCTAssertTrue(navigation.exists, "Scrolling must keep the assistant sheet open", file: file, line: line)
        }
        XCTAssertTrue(element.exists && element.isHittable, "The sheet control must be reachable", file: file, line: line)
    }

    private func openAssistant() {
        let menu = app.buttons["sessionMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        // Match the existing verified menu interaction: the outer SwiftUI Menu
        // AX element may not support XCTest's automatic scroll-to-visible.
        menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let open = app.buttons["openMusicAssistantButton"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        wait(open, predicate: "enabled == true")
        open.tap()
        XCTAssertTrue(app.staticTexts["Shape your sound"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("assistantConnectionStatus").waitForExistence(timeout: 5))
    }

    private func closeAssistant() {
        let close = app.buttons["assistantCloseButton"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        wait(close, predicate: "exists == false")
    }

    private func expectPairingRequired() {
        let message = element("assistantMessage")
        reveal(message)
        wait(message, predicate: "exists == true AND label == %@", pairingMessage)
        let request = app.buttons["assistantRequestButton"]
        XCTAssertTrue(request.waitForExistence(timeout: 5))
        XCTAssertFalse(request.isEnabled, "A local connection and sharing permission are required before sending text")
        XCTAssertFalse(app.buttons["assistantKeepButton"].exists)
        XCTAssertFalse(app.buttons["assistantOriginalButton"].exists)
        XCTAssertFalse(app.buttons["assistantChangeButton"].exists)
    }

    private func promptField() -> XCUIElement {
        reveal(element("assistantPromptField"), toward: .towardTop)
        // SwiftUI's axis: .vertical field can appear as either AX type.
        let textView = app.textViews["assistantPromptField"]
        if textView.exists { return textView }
        let textField = app.textFields["assistantPromptField"]
        XCTAssertTrue(textField.waitForExistence(timeout: 5))
        return textField
    }

    private func typePrompt(_ text: String) {
        let prompt = promptField()
        prompt.tap()
        prompt.typeText(text)
        wait(prompt, predicate: "value == %@", text)
        let doneTyping = app.buttons["assistantKeyboardDoneButton"]
        XCTAssertTrue(doneTyping.waitForExistence(timeout: 5))
        doneTyping.tap()
        wait(app.keyboards.firstMatch, predicate: "exists == false")
    }

    private func recordTrack() {
        let record = app.buttons["recordButton"]
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        record.tap()
        wait(record, predicate: "value == %@", "Recording")
        let keyboard = element("instrumentKeyboard")
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        keyboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).press(forDuration: 0.25)
        record.tap()
        wait(app.buttons["tracksButton"], predicate: "value == %@", "1")
    }

    private func recordedTrackIdentifier() -> String {
        app.buttons["tracksButton"].tap()
        let mute = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'muteButton_'" )).firstMatch
        XCTAssertTrue(mute.waitForExistence(timeout: 5))
        let identifier = mute.identifier
        XCTAssertFalse(identifier.isEmpty)
        app.buttons["Done"].tap()
        wait(mute, predicate: "exists == false")
        return identifier
    }

    func testEmptyProjectExplainsStartingPointAndCannotRequest() {
        openAssistant()
        let empty = element("assistantEmptyState")
        XCTAssertTrue(empty.waitForExistence(timeout: 5))
        XCTAssertEqual(empty.label, "Record a track to get started.")
        expectPairingRequired()
        closeAssistant()
        wait(app.buttons["tracksButton"], predicate: "value == %@", "0")
    }

    func testUnpairedRecordedProjectCannotSendEvenWithTrackAndPrompt() {
        recordTrack()
        openAssistant()
        expectPairingRequired()
        XCTAssertFalse(element("assistantEmptyState").exists)
        XCTAssertTrue(element("assistantTrackPicker").exists)
        typePrompt("Make this track a little quieter")
        expectPairingRequired()
        closeAssistant()
        wait(app.buttons["tracksButton"], predicate: "value == %@", "1")
    }

    func testClosingAssistantPreservesActualRecordedTrackIdentity() {
        recordTrack()
        let before = recordedTrackIdentifier()
        openAssistant()
        expectPairingRequired()
        closeAssistant()
        wait(app.buttons["tracksButton"], predicate: "value == %@", "1")
        XCTAssertEqual(recordedTrackIdentifier(), before, "Closing the assistant must retain the actual recorded track")
        XCTAssertTrue(app.buttons["playPauseButton"].isEnabled)
    }

    func testSharingDisclosureExplainsTextAndMusicMetadataWithoutSending() {
        openAssistant()
        let disclosure = element("assistantSharingDisclosure")
        reveal(disclosure)
        disclosure.tap()
        let summary = element("assistantSharingSummary")
        reveal(summary, toward: .towardBottom)
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.contains("your text"))
        XCTAssertTrue(summary.label.contains("selected track"))
        XCTAssertTrue(summary.label.contains("No recordings, audio files, MIDI notes"))
        XCTAssertFalse(app.buttons["assistantRequestButton"].isEnabled)
        closeAssistant()
        wait(app.buttons["tracksButton"], predicate: "value == %@", "0")
    }

    func testRefreshingUnpairedConnectionKeepsGuidanceAndRequestDisabled() {
        openAssistant()
        expectPairingRequired()
        let refresh = app.buttons["assistantRefreshButton"]
        reveal(refresh, toward: .towardTop)
        wait(refresh, predicate: "enabled == true")
        refresh.tap()
        expectPairingRequired()
        let modelPicker = element("assistantModelPicker")
        if modelPicker.exists { XCTAssertFalse(modelPicker.isEnabled, "Model choice requires a real discovered catalog") }
        closeAssistant()
    }

    func testReopeningAssistantPreservesUnsentPromptWithoutChangingTrack() {
        recordTrack()
        openAssistant()
        expectPairingRequired()
        typePrompt("A slightly softer piano")
        closeAssistant()
        wait(app.buttons["tracksButton"], predicate: "value == %@", "1")
        openAssistant()
        let reopened = promptField()
        XCTAssertEqual(reopened.value as? String, "A slightly softer piano")
        expectPairingRequired()
        closeAssistant()
        wait(app.buttons["tracksButton"], predicate: "value == %@", "1")
    }
}
