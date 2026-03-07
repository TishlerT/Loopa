# Local Agent: iOS Baseline Capture

You are running on macOS with Xcode 15+ and an iOS 17 Simulator. Your job is to capture all iOS baseline artifacts that the Android migration agent will use as its parity oracle. You are NOT doing the Android migration — you are building the "source of truth" that the cloud agent will port against.

Everything you produce goes into `migration/` and `memory-bank/`. When you're done, commit and push so the cloud agent can pull.

## Read first

- `ios/project.yml` — the shipped build spec (tells you what's included and excluded)
- `ios/Tish88App.swift` — app entry point
- `ios/run_tests.sh` — existing test runner

## Step 1: Verify the iOS project builds and all tests pass

```bash
cd ios
xcodebuild -project Loopa.xcodeproj -scheme Loopa \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

If the project file doesn't exist (uses XcodeGen), generate it first:

```bash
cd ios && xcodegen generate
```

Then run all tests:

```bash
cd ios && ./run_tests.sh --unit
cd ios && ./run_tests.sh --ui
```

Capture the results:

```bash
mkdir -p migration/fixtures/ios_test_results
cp ios/test_output.log migration/fixtures/ios_test_results/unit_test_output.log
```

Run the test runner for both unit and UI, saving each output separately. Record the exact counts:
- Total tests, passed, failed, skipped — for both unit and UI targets.

If any tests fail, document the failures but do not block. The migration agent needs to know the current state, including any pre-existing failures.

Save the summary to `migration/fixtures/ios_test_results/test_summary.json`:

```json
{
  "timestamp": "<ISO 8601>",
  "unit_tests": { "total": 0, "passed": 0, "failed": 0, "skipped": 0 },
  "ui_tests": { "total": 0, "passed": 0, "failed": 0, "skipped": 0 },
  "pre_existing_failures": ["<list any failing test names>"]
}
```

## Step 2: Run Maestro flows and capture screenshots

Boot the simulator and install the app:

```bash
xcrun simctl boot "iPhone 16 Pro" 2>/dev/null || true
xcodebuild -project ios/Loopa.xcodeproj -scheme Loopa \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build -derivedDataPath /tmp/LoopaDerivedData
xcrun simctl install booted /tmp/LoopaDerivedData/Build/Products/Debug-iphonesimulator/Loopa.app
```

Run each Maestro flow:

```bash
mkdir -p migration/fixtures/ios_screenshots

maestro test ios/.maestro/simple_flow.yaml --output migration/fixtures/ios_screenshots/simple/
maestro test ios/.maestro/record_flow.yaml --output migration/fixtures/ios_screenshots/record/
maestro test ios/.maestro/full_flow.yaml --output migration/fixtures/ios_screenshots/full/
maestro test ios/.maestro/play_pause_flow.yaml --output migration/fixtures/ios_screenshots/play_pause/
```

If Maestro is not installed, install it:

```bash
curl -Ls "https://get.maestro.mobile.dev" | bash
```

The Maestro flows already capture screenshots at key states (initial_state, recording_in_progress, track_recorded, paused, playing, restarted, final_state). These screenshots become the visual parity baseline.

If Maestro flows fail, capture screenshots manually via simulator:

```bash
xcrun simctl io booted screenshot migration/fixtures/ios_screenshots/initial_state.png
```

Launch the app, interact to reach each canonical state, and screenshot each one.

### Canonical states to capture (minimum set)

1. `initial_state` — app just launched, no tracks, keyboard visible
2. `recording_in_progress` — count-in or actively recording
3. `track_recorded` — at least one track recorded, playing
4. `paused` — playback paused
5. `playing` — playback resumed
6. `restarted` — after restart button
7. `tracks_sheet` — tracks mixer sheet open (if accessible via Maestro/tap)
8. `editor_piano_roll` — track focus view with piano roll (if accessible)
9. `editor_drum_grid` — drum grid view (if accessible)
10. `vocal_mode` — vocal instrument selected (if accessible)

Capture whatever you can reach through the Maestro flows and manual interaction. More baselines = better parity verification later. Don't block on states that require complex multi-step flows — capture what's reachable.

## Step 3: Confirm GM.sf2 SoundFont exists

```bash
ls -la ios/GM.sf2
ls -la android/GM.sf2
```

Record the file size and checksum:

```bash
shasum -a 256 ios/GM.sf2 > migration/fixtures/gm_sf2_checksum.txt
stat -f "%z" ios/GM.sf2 >> migration/fixtures/gm_sf2_checksum.txt
```

If the file doesn't exist in `ios/GM.sf2`, check if it's referenced from elsewhere in the project (search for "GM.sf2" in the source). Document the location.

## Step 4: Create the shipped-surface inventory (SPEC.md)

Read `ios/project.yml` to determine which source files are included (and which are excluded). Then read each included source file to document every shipped screen, control, and behavior.

Create `migration/SPEC.md` with this structure:

```markdown
# Loopa — Shipped Surface Inventory

Generated from ios/project.yml and source inspection on <date>.

## Excluded files (legacy, not shipped)
- ContentView.swift
- UI/Screens/SampleBrowserView.swift
- Networking/*
- Models/FreesoundModels.swift
- ViewModels/TishViewModel.swift
- Audio/PreviewPlayer.swift
- UI/Components/SoundRow.swift
- UI/Components/LoopVisualization.swift
- UI/Components/TransportControls.swift  (legacy, replaced)
- UI/Components/KeyboardView.swift  (legacy, replaced)

## Screens
### LooperView (main screen)
- <list every control, button, state, and interaction>

### TrackFocusView (editor)
- <list every control, button, state, and interaction>

### TracksView (mixer sheet)
- <list every control, button, state, and interaction>

### SettingsView
- <list every control>

### AboutView
- <list every control>

## Audio behaviors
- <instruments, SoundFont loading, sampler pool, metronome, vocal recording, export>

## Data behaviors
- <session save/load, auto-save, .loopa import/export, MIDI export, M4A export>

## State management
- <LooperViewModel published properties, TracksViewModel, TrackFocusViewModel>
```

Be thorough. Read each source file. The Android agent will use this as its feature checklist — anything not in SPEC.md risks being missed.

## Step 5: Capture .loopa fixture files

If possible, manually create a test session in the simulator with:
- At least 2 MIDI tracks (different instruments)
- At least 1 track with quantized notes
- Different mute/solo/volume states across tracks

Then export it as a `.loopa` file. Save to `migration/fixtures/test_session.loopa`.

If .loopa export requires user interaction that's hard to automate, try through the app's save/export flow in the simulator:

```bash
# Check if there's a way to trigger export via deep link or Maestro
# Otherwise, document how to create the fixture manually
```

If you can't create a fixture programmatically, create a minimal one by:
1. Reading `ios/Models/SessionExporter.swift` to understand the .loopa format
2. Reading `ios/Models/SessionStorage.swift` to understand the JSON schema
3. Constructing a fixture JSON file manually based on the schema
4. Saving it as `migration/fixtures/test_session.json` (the raw JSON that would be inside a .loopa file)

Also capture the JSON schema itself:

```bash
# Read the SavedSession struct and document its shape
```

Save the schema to `migration/fixtures/session_schema.json`.

## Step 6: Capture state traces

Read `ios/ViewModels/LooperViewModel.swift` and identify all `@Published` properties. Create a reference document listing every piece of observable state and its type:

Save to `migration/fixtures/viewmodel_state_reference.md`:

```markdown
# LooperViewModel Published State

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| isRecording | Bool | false | ... |
| isPlaying | Bool | true | ... |
| ... | ... | ... | ... |

# TracksViewModel Published State
...

# TrackFocusViewModel Published State
...
```

This is the state parity contract — the Android ViewModels must expose equivalent state.

## Step 7: Assess iOS test coverage gaps

Read all test files in `ios/Tests/` and `ios/Tests/UI/`. Create a coverage assessment:

Save to `migration/fixtures/ios_test_coverage_assessment.md`:

```markdown
# iOS Test Coverage Assessment

## Well-covered areas
- <list areas with thorough tests>

## Gaps (no tests or shallow tests)
- <list areas missing test coverage>
- <note any tests that rely on Thread.sleep instead of proper expectations>

## Accessibility identifiers present
- <list all identifiers found in UI code>

## Accessibility identifiers missing
- <list interactive elements without identifiers>
```

The Android agent needs this to know where iOS tests are trustworthy as parity oracles vs where Android tests need to independently verify behavior.

## Step 8: Create memory-bank files

Create `memory-bank/` at the project root with these files:

### memory-bank/projectbrief.md
Read the existing codebase and write a comprehensive project brief covering:
- What the app does (loop-based music creation)
- Target platforms (iOS shipped, Android being ported)
- Key features (9 instruments, multi-track, quantization, piano roll, drum grid, vocal recording, session management)
- Tech stack (SwiftUI, AVAudioEngine, SoundFont GM.sf2)
- Design aesthetic (dark theme, neon accents, landscape-only)

### memory-bank/activeContext.md
```markdown
# Active Context

## Current focus
iOS baseline capture complete. Ready for Android migration (phases 2-12).

## Recent decisions
- Android app will be built in android-app/ (new directory)
- android/ folder is a frozen iOS mirror — do not modify
- Visual parity over Material 3 (intentional tradeoff)
- FluidSynth + Oboe for audio (de-risk in Phase 4 audio spike)

## Blockers
- <list any issues discovered during baseline capture>
```

### memory-bank/progress.md
```markdown
# Progress

## Completed
- iOS baseline capture (screenshots, test results, SPEC.md, fixtures)
- Environment setup (Android toolchain on cloud VM)

## In progress
- Phase 2: Project scaffolding

## Not started
- Phases 3-12

## Known issues
- <list any pre-existing iOS test failures>
- <list any baseline capture gaps>
```

### memory-bank/techContext.md
Document everything discovered about the iOS project that the Android agent will need:
- Build commands and their behavior
- Test runner usage
- Maestro flow structure
- SoundFont file location and size
- Simulator requirements
- Any timing constraints discovered (count-in duration, animation timings)
- Accessibility identifiers and their locations

### memory-bank/code-index.md
Write a one-paragraph summary for each active (non-excluded) iOS source file. The Android agent will use this as a quick reference instead of reading every file from scratch.

### memory-bank/io-schema.md
Document all public interfaces, state shapes, and constants:
- LooperViewModel's published interface
- Track data model shape
- MidiNote shape
- SavedSession shape
- Instrument enum values and their MIDI program numbers
- BarCount enum values
- QuantizeDivision enum values
- Design system color hex values
- Design system spacing/radius/typography values

## Step 9: Commit and push

```bash
git add migration/ memory-bank/
git commit -m "Add iOS baselines, SPEC, memory bank for Android migration

- Captured iOS test results (unit + UI)
- Captured Maestro screenshots for visual parity baselines
- Confirmed GM.sf2 SoundFont location and checksum
- Created migration/SPEC.md (shipped-surface inventory)
- Created session fixtures and state references
- Assessed iOS test coverage gaps
- Initialized memory-bank/ with full project context"

git push origin main
```

## Verification gate

Before committing, confirm all of these exist:

- [ ] `migration/SPEC.md` — lists every shipped screen and behavior
- [ ] `migration/fixtures/ios_test_results/test_summary.json` — test counts
- [ ] `migration/fixtures/ios_screenshots/` — at least 6 canonical state screenshots
- [ ] `migration/fixtures/gm_sf2_checksum.txt` — SF2 confirmed
- [ ] `migration/fixtures/viewmodel_state_reference.md` — all published state
- [ ] `migration/fixtures/ios_test_coverage_assessment.md` — coverage gaps documented
- [ ] `migration/fixtures/session_schema.json` or `test_session.loopa` — fixture data
- [ ] `memory-bank/projectbrief.md` — populated
- [ ] `memory-bank/activeContext.md` — populated
- [ ] `memory-bank/progress.md` — populated
- [ ] `memory-bank/techContext.md` — populated
- [ ] `memory-bank/code-index.md` — one paragraph per active source file
- [ ] `memory-bank/io-schema.md` — all interfaces and constants

## Rules

- Do NOT modify any iOS source code. You are capturing baselines, not changing the app.
- Do NOT start any Android work. That's the cloud agent's job.
- If a Maestro flow fails, capture what you can manually and document the failure.
- If tests fail, document the failures — do not try to fix them.
- Be thorough in SPEC.md. The Android agent treats it as the feature checklist.
- Be thorough in io-schema.md. The Android agent will port every constant and enum value listed.
- Commit everything to the repo so the cloud agent can pull it.
