# Technical Context

## Repo structure relevant to the iOS parity baseline
- `ios/` is the shipped iOS app
- `migration/` now holds generated baseline artifacts for the Android agent
- `memory-bank/` at repo root is the shared persistent context for migration work

## iOS build commands

### Generate project
Use this first if the checked-in project file is stale:

```bash
cd ios
xcodegen generate
```

Why it mattered in this run:
- The checked-in `ios/Loopa.xcodeproj` initially failed to build because it attempted to copy `.git/hooks/*` into the app bundle.
- Regenerating from `ios/project.yml` fixed the build graph for baseline capture.

### Build
```bash
cd ios
xcodebuild -project Loopa.xcodeproj -scheme Loopa \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

Observed environment in this run:
- Simulator destination resolved to `iPhone 16 Pro`
- iOS Simulator OS available locally: `18.6`

## Test runner usage

### Unit tests
```bash
cd ios
./run_tests.sh --unit
```

Observed result:
- `158` total
- `158` passed
- `0` failed
- `0` skipped

### UI tests
```bash
cd ios
./run_tests.sh --ui
```

Observed result:
- `20` total
- `20` passed
- `0` failed
- `0` skipped

### Test runner artifacts
- Log file: `ios/test_output.log`
- Result bundle: `ios/TestResults.xcresult`
- Saved baseline logs/summaries: `migration/fixtures/ios_test_results/`

### Test runner quirk
- `run_tests.sh` parses `xcresulttool` output with `grep`, which produced duplicate `0\n0` strings for failed/skipped counts in this run and emitted `integer expression expected`.
- The underlying test results were still correct; use the raw `xcresulttool` JSON summaries as source of truth for counts.

## Screenshot / visual baseline capture

### Maestro flows present in repo
- `ios/.maestro/simple_flow.yaml`
- `ios/.maestro/record_flow.yaml`
- `ios/.maestro/full_flow.yaml`
- `ios/.maestro/play_pause_flow.yaml`

### Local Maestro blocker
- `maestro --version` failed because the local machine only has Java `1.8.0_411`
- Maestro requires Java 17+

### Screenshot fallback used in this run
```bash
xcrun xcresulttool export attachments --path ios/TestResults.xcresult --output-path migration/fixtures/ios_screenshots/ui_test_attachments
```

Result:
- Exported attachments from the passing UI suite
- Promoted six canonical transport screenshots to stable names:
  - `initial_state.png`
  - `recording_in_progress.png`
  - `track_recorded.png`
  - `paused.png`
  - `playing.png`
  - `restarted.png`

Remaining screenshot gaps:
- `tracks_sheet`
- `editor_piano_roll`
- `editor_drum_grid`
- `vocal_mode`

## SoundFont baseline
- iOS path: `ios/GM.sf2`
- Android mirror path: `android/GM.sf2`
- File size: `5994284` bytes
- SHA-256: `82475b91a76de15cb28a104707d3247ba932e228bada3f47bba63c6b31aaf7a1`

## Timing constraints discovered
- Count-in is always `4` beats
- At `100 BPM`, count-in is about `2.4s`
- Several UI tests use shorter sleeps (`0.5s` to `0.8s`) that do not represent a full musical record pass
- `TrackFocusViewModel` editor zoom limits:
  - horizontal: `0.5...4.0`
  - vertical: `0.6...2.5`
- `TrackFocusViewModel` minimum note duration: `0.125` beats

## Accessibility identifiers currently present
- Main screen: `recordButton`, `playPauseButton`, `restartButton`, `quantizeButton`, `tracksButton`, `bpmButton`
- Mixer rows: `deleteButton_<track.id>`, `muteButton_<track.id>`, `soloButton_<track.id>`, `quantizeButton_<track.id>`, `loopButton_<track.id>`, `volumeSlider_<track.id>`, `instrumentButton_<track.id>`

## Important product/runtime notes for Android parity
- App is landscape-only on iPhone and iPad
- App launches straight into the looper workstation
- Current runtime path is `Tish88App -> LooperView -> LooperViewModel -> MultiTrackLooper / LooperAudioEngine / VocalRecorder`
- `.loopa` import is active; `.loopa` export exists in code via `SessionExporter`, but the shipped main-screen export actions currently share audio (`.m4a`) rather than the project file
- Several legacy files still compile, but the excluded/network/sample-browser path should not be treated as parity scope
