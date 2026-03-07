# Progress

## Completed
- iOS build baseline verified after regenerating `ios/Loopa.xcodeproj` from `ios/project.yml`
- Unit test baseline captured: `158/158` passing
- UI test baseline captured: `20/20` passing
- Test logs and summaries saved to `migration/fixtures/ios_test_results/`
- Canonical screenshot baseline saved to `migration/fixtures/ios_screenshots/`
- `GM.sf2` SoundFont confirmed in both `ios/` and `android/`; checksum and file size saved
- `migration/SPEC.md` created from shipped-source inspection
- Session schema and example `.loopa` JSON fixture created
- ViewModel state reference and iOS test coverage assessment created
- Root `memory-bank/` initialized for Android migration continuity

## In progress
- Android migration Phase 2: Project Scaffolding + Design System

## Not started
- Android migration Phases 3-12
- Local verification of deferred parity items

## Known issues
- No pre-existing iOS test failures were present in this baseline run
- Maestro CLI could not run locally because Java 17+ is not installed
- `ScreenshotTests.swift` did not emit exportable screenshots outside Fastlane; `xcresult` attachment export was used instead
- Additional canonical screenshot states (`tracks_sheet`, `editor_piano_roll`, `editor_drum_grid`, `vocal_mode`) remain uncaptured in this run
- The checked-in `ios/Loopa.xcodeproj` was stale and needed regeneration before the app would build cleanly
