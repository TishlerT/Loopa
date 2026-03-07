# iOS Screenshot Baseline

These baseline images were extracted from the passing UI test result bundle at `ios/TestResults.xcresult` using:

```bash
xcrun xcresulttool export attachments --path ios/TestResults.xcresult --output-path migration/fixtures/ios_screenshots/ui_test_attachments
```

## Canonical screenshots
- `initial_state.png` — extracted from `TransportControlsUITests/testTransportButtonsExist()`
- `recording_in_progress.png` — extracted from `TransportControlsUITests/testRecordButtonStartsRecording()`; shows count-in/recording badge
- `track_recorded.png` — extracted from `TransportRegressionTests/testRestartEnabledAfterRecording()`; shows a recorded loop with transport enabled
- `paused.png` — extracted from `TransportControlsUITests/testPlayPauseButtonToggles()`
- `playing.png` — extracted from `TransportRegressionTests/testMultiplePauseResumeCycles()`
- `restarted.png` — extracted from `TransportControlsUITests/testRestartButtonRestartsFromBeginning()`

## Raw attachments
- `ui_test_attachments/` contains every exported attachment plus `manifest.json`.

## Capture gaps
- Checked-in `ScreenshotTests.swift` uses `snapshot()` stubs outside Fastlane, so it did not emit exportable screenshots in this run.
- Checked-in Maestro flows were not runnable on this machine because the installed Java runtime is `1.8`, while Maestro requires Java 17+.
- As a result, this baseline captures the six canonical transport states required by the verification gate, but does not include `tracks_sheet`, `editor_piano_roll`, `editor_drum_grid`, or `vocal_mode` screenshots from this run.
