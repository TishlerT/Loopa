# Loopa Testing Guide for AI Agents

This document describes how AI agents (Cursor/Claude) can programmatically run and analyze tests for the Loopa iOS app.

## Quick Start

```bash
# Run all UI tests and get results
./run_tests.sh

# Parse results as JSON
./parse_results.sh --summary
```

## Test Architecture

```
Tests/
├── UI/
│   ├── TransportControlsUITests.swift  # UI tests for transport buttons
│   └── RegressionTests.swift           # Regression tests for bug fixes
├── AudioEngineTests.swift              # Unit tests for audio
├── ViewModelTests.swift                # Unit tests for view models
├── MidiLooperTests.swift               # Unit tests for MIDI looper
├── MultiTrackLooperTests.swift         # Unit tests for multi-track
└── QuantizerTests.swift                # Unit tests for quantization
```

## CLI Commands Reference

### Running Tests

```bash
# Run all UI tests
xcodebuild test \
  -project Loopa.xcodeproj \
  -scheme Loopa \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -resultBundlePath ./TestResults.xcresult \
  -only-testing:LoopaUITests

# Run unit tests only
xcodebuild test \
  -project Loopa.xcodeproj \
  -scheme Loopa \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -resultBundlePath ./TestResults.xcresult \
  -only-testing:LoopaTests

# Run a specific test
xcodebuild test \
  -project Loopa.xcodeproj \
  -scheme Loopa \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:LoopaUITests/TransportControlsUITests/testRecordButtonStartsRecording
```

### Parsing Results

```bash
# Get test summary (recommended for AI)
xcrun xcresulttool get test-results summary --path TestResults.xcresult

# Get full test list with status
xcrun xcresulttool get test-results tests --path TestResults.xcresult

# Get test details for specific test
xcrun xcresulttool get test-results test-details \
  --path TestResults.xcresult \
  --test-id "TransportControlsUITests/testRecordButtonStartsRecording()"
```

### Simulator Control

```bash
# List available simulators
xcrun simctl list devices available

# Boot a simulator
xcrun simctl boot "iPhone 16 Pro"

# Take screenshot
xcrun simctl io booted screenshot screenshot.png

# Record video (run in background)
xcrun simctl io booted recordVideo recording.mov &

# Stop recording
killall simctl

# Stream app logs
xcrun simctl spawn booted log stream --predicate 'subsystem == "com.loopa.app"'
```

## JSON Output Structure

### Summary Format (Recommended for AI)

```json
{
  "passedTests": 12,
  "failedTests": 3,
  "skippedTests": 0,
  "totalTestCount": 15,
  "result": "Failed",
  "testFailures": [
    {
      "testName": "testRestartEnabledAfterRecording()",
      "failureText": "XCTAssertTrue failed - Restart should be enabled after recording",
      "targetName": "LoopaUITests",
      "testIdentifierString": "TransportRegressionTests/testRestartEnabledAfterRecording()"
    }
  ]
}
```

### Test List Format

```json
{
  "testNodes": [
    {
      "name": "LoopaUITests",
      "nodeType": "UI test bundle",
      "children": [
        {
          "name": "TransportControlsUITests",
          "nodeType": "Test Suite",
          "children": [
            {
              "name": "testRecordButtonStartsRecording()",
              "nodeType": "Test Case",
              "result": "Passed",
              "duration": "5s",
              "durationInSeconds": 5.105
            }
          ]
        }
      ]
    }
  ]
}
```

## Accessibility Identifiers

The following accessibility identifiers are available for UI testing:

| Identifier | Element | Location |
|------------|---------|----------|
| `recordButton` | Record/Stop button | LooperView.swift:483 |
| `playPauseButton` | Play/Pause button | LooperView.swift:517 |
| `restartButton` | Restart button | LooperView.swift:539 |
| `quantizeButton` | Quantize toggle | LooperView.swift:565 |

## Writing New Tests

### Basic Test Structure

```swift
import XCTest

final class MyUITests: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    override func tearDownWithError() throws {
        // Capture screenshot on failure
        if let testRun = testRun, testRun.hasSucceeded == false {
            let screenshot = XCUIScreen.main.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.lifetime = .keepAlways
            attachment.name = "failure_\(name)"
            add(attachment)
        }
        app = nil
    }
    
    func testExample() throws {
        let button = app.buttons["recordButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        // Add assertions...
    }
}
```

### Timing-Sensitive Tests

```swift
// Use waitForExistence instead of Thread.sleep
let button = app.buttons["playPauseButton"]
XCTAssertTrue(button.waitForExistence(timeout: 5))

// Use expectations for async operations
let enabledPredicate = NSPredicate(format: "isEnabled == true")
expectation(for: enabledPredicate, evaluatedWith: button, handler: nil)
waitForExpectations(timeout: 3, handler: nil)
```

## AI Agent Workflow

1. **Modify Code**: Make changes to fix bugs or add features
2. **Run Tests**: Execute `./run_tests.sh` or specific xcodebuild command
3. **Parse Results**: Use `./parse_results.sh --summary` to get JSON
4. **Analyze Failures**: Check `testFailures` array for error messages
5. **Review Screenshots**: Check TestResults.xcresult for failure screenshots
6. **Iterate**: Fix issues and re-run tests

### Example Workflow Script

```bash
# Run tests and check result
./run_tests.sh --quick
if [ $? -ne 0 ]; then
    echo "Tests failed, getting failure details..."
    ./parse_results.sh --failures
fi
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All tests passed |
| 65 | One or more tests failed |
| 66 | Build error |
| 70 | Test timeout or crash |

## Troubleshooting

### Common Issues

1. **Simulator not found**: Run `xcrun simctl list devices` to see available simulators
2. **Build failures**: Check for Swift compilation errors in the log
3. **Timeout errors**: Tests may need longer waits; use `waitForExistence(timeout:)`
4. **Button not enabled**: UI state may not be ready; add appropriate waits

### Viewing Logs

```bash
# View build/test log
cat test_output.log

# Extract just errors
grep -i error test_output.log

# View specific test failure
grep -A5 "failed" test_output.log
```

## Maestro (Optional Alternative)

Maestro is a CLI-first mobile testing framework with YAML-based test definitions. It's simpler for AI agents to generate and modify.

### Setup

```bash
./setup_maestro.sh
```

### Running Maestro Tests

```bash
# Run a single flow
maestro test .maestro/record_flow.yaml

# Run all flows
maestro test .maestro/

# Interactive studio
maestro studio
```

### Maestro Flow Files

```
.maestro/
├── record_flow.yaml       # Basic record button test
├── play_pause_flow.yaml   # Play/pause toggle test
└── full_flow.yaml         # Comprehensive app flow
```

### Example Maestro Flow

```yaml
appId: com.loopa.app
---
- launchApp:
    clearState: true
- assertVisible:
    id: "recordButton"
- tapOn:
    id: "recordButton"
- wait: 1000
- tapOn:
    id: "recordButton"
- takeScreenshot: recording_complete
```

### When to Use Maestro vs XCUITest

| Scenario | Recommended |
|----------|-------------|
| Complex assertions | XCUITest |
| Quick smoke tests | Maestro |
| AI-generated tests | Maestro |
| Timing-sensitive tests | XCUITest |
| Visual verification | Maestro |
| Unit test integration | XCUITest |

## Known Limitations

1. **Audio Testing**: XCUITest cannot verify audio output directly. Use unit tests for audio engine.
2. **Precise Timing**: Avoid `Thread.sleep`; use `waitForExistence` and expectations.
3. **Visual Verification**: Consider adding snapshot tests for visual regression.
4. **Background Audio**: Testing audio in background mode requires special configuration.
5. **Maestro Timing**: Maestro has limited control over precise timing; use XCUITest for timing-sensitive tests.

