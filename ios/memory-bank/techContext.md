# Technical Context

## Project Structure
```
Tish88/
├── Loopa.xcodeproj      # Generated via XcodeGen
├── project.yml          # XcodeGen configuration
├── Audio/               # Audio engine, sampler, recorder
├── Looper/              # Loop recording logic
├── Models/              # Data models
├── ViewModels/          # Business logic
├── UI/                  # SwiftUI views
│   ├── Screens/         # Full-screen views (LooperView.swift)
│   ├── Components/      # Reusable components
│   └── Theme/           # Design system
├── Tests/               # Unit tests
│   └── UI/              # XCUITest files
├── memory-bank/         # Agent persistent memory
├── run_tests.sh         # Test runner script
├── parse_results.sh     # JSON result parser
└── TESTING.md           # Testing documentation
```

## CLI Commands

### Build & Run
```bash
# Build
xcodebuild -project Loopa.xcodeproj -scheme Loopa \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build

# Install on simulator
xcrun simctl install booted /path/to/Loopa.app

# Launch
xcrun simctl launch booted com.loopa.app
```

### Testing
```bash
# Run all UI tests
./run_tests.sh

# Run specific test
xcodebuild test -project Loopa.xcodeproj -scheme Loopa \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:LoopaUITests/TransportControlsUITests/testRecordButtonStartsRecording

# Parse failures
./parse_results.sh --failures

# Get full test list
./parse_results.sh --tests
```

### Simulator
```bash
# List devices
xcrun simctl list devices available

# Take screenshot
xcrun simctl io booted screenshot /tmp/screenshot.png

# Stream logs
xcrun simctl spawn booted log stream --predicate 'subsystem == "com.loopa.app"'
```

## Key Constraints
- App is landscape-only
- Recording has 4-beat count-in at current BPM
- At 100 BPM, count-in takes ~2.4 seconds
- Tests must wait for count-in before asserting recording state

## Accessibility Identifiers
| ID | Element | Location |
|----|---------|----------|
| `recordButton` | Record/Stop button | LooperView.swift:494 |
| `playPauseButton` | Play/Pause toggle | LooperView.swift:528 |
| `restartButton` | Restart playback | LooperView.swift:550 |
| `quantizeButton` | Quantization toggle | LooperView.swift:565 |

## Test Timing Guidelines
- Wait 3+ seconds after tapping record before stopping (count-in + buffer)
- Use `waitForExistence(timeout:)` instead of `Thread.sleep` for element checks
- Use expectations with predicates for state changes

