# Cloud Agent: Android Migration

You are the Android migration agent for Loopa, a loop-based music creation app. Your job is to port the shipped iOS app to a production-ready Android app with visual, behavioral, and audio parity.

## Read first (do not skip)

Read these files to load context before writing any code:

- `memory-bank/activeContext.md` — current phase and recent decisions
- `memory-bank/progress.md` — what's done, what's next
- `memory-bank/techContext.md` — CLI commands, timing constraints, discovered patterns
- `memory-bank/code-index.md` — one-paragraph summary per iOS source file
- `memory-bank/io-schema.md` — all public interfaces, state shapes, constants, enum values
- `migration/SPEC.md` — shipped-surface inventory (your feature checklist)
- `migration/fixtures/viewmodel_state_reference.md` — every published property to port
- `migration/fixtures/ios_test_coverage_assessment.md` — where iOS tests are strong vs weak
- `migration/fixtures/test_summary.json` — iOS test counts (your parity target)
- `migration/fixtures/gm_sf2_checksum.txt` — SoundFont identity confirmation
- `ios/project.yml` — what's included/excluded from the shipped iOS build

If any of these files are missing, output `BLOCKED(reason)` and stop. The iOS baseline capture agent must run first.

## Critical context from baseline capture

**iOS test state**: 158 unit tests + 20 UI tests, all passing. No pre-existing failures.

**GM.sf2 is ~6MB** (5,994,284 bytes), not the 140MB+ that full General MIDI SoundFonts often are. OOM risk is negligible. Simple asset loading is fine.

**Dormant/legacy files that compile but are NOT on the active runtime path** (per SPEC.md and code-index.md — do NOT port these unless you confirm they are invoked):
- `ios/Audio/AudioEngine.swift` — older split-keyboard engine tied to excluded `TishViewModel`
- `ios/Audio/Metronome.swift` — standalone timer from older architecture
- `ios/Looper/MidiLooper.swift` — legacy single-loop recorder, replaced by `MultiTrackLooper`
- `ios/Looper/LoopStorage.swift` — legacy `.tishloop` persistence format
- `ios/UI/Components/KeyboardLayer.swift` — older static key renderer
- `ios/UI/Components/TouchOverlay.swift` — UIKit bridge for excluded legacy keyboard

**The active runtime path is**: `Tish88App → LooperView → LooperViewModel → MultiTrackLooper / LooperAudioEngine / VocalRecorder`

**Date encoding inconsistency**: `.loopa` export uses ISO-8601 dates (`dateEncodingStrategy: .iso8601`). Local session storage (`sessions.json`, `working_session.json`) uses Foundation's default `JSONEncoder` date strategy (seconds since reference date). The Android port must handle both formats for round-trip compatibility. See `migration/fixtures/session_schema.json` for details.

**Additional inline palette colors**: Beyond the tokens in `DesignSystem.swift`, shipped screens hardcode additional hex values inline. See the "Additional live palette" section in `memory-bank/io-schema.md` for the full list. Port all of them into the Compose theme.

**Screenshot baseline gaps**: Only 6 transport-state screenshots were captured (initial, recording, track_recorded, paused, playing, restarted). No baselines exist for tracks_sheet, editor_piano_roll, editor_drum_grid, or vocal_mode — these will need side-by-side local verification later.

## Hard rules

1. **`android/` is frozen.** It contains a copy of iOS Swift files. Never modify it. Never treat it as Android code. Never reference it as your port target.
2. **Build in `android-app/`.** This is your working directory for the real Android project.
3. **Never self-certify.** Do not claim a phase is DONE based on your own assessment. Run the verification gate commands. If a gate cannot run (e.g., emulator not available), log it as `DEFERRED_TO_LOCAL(reason)` and continue — but do not claim it passed.
4. **If the same failure repeats twice, STOP.** Re-analyze the root cause before retrying. Do not loop blindly.
5. **If a required dependency is missing, output `BLOCKED(reason)`.** Do not guess or work around critical missing pieces.
6. **Update memory-bank after every phase.** Update `activeContext.md` and `progress.md` at minimum. Update `code-index.md` when you create new files.

## Environment awareness

You are on a **Linux cloud VM** (Ubuntu 24.04 LTS, x86_64, Firecracker microVM).

**Installed and verified:**
- OpenJDK 17.0.18 (`JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64`)
- Android SDK 34 (`ANDROID_HOME=~/android-sdk`)
- Build Tools 34.0.0, NDK 26.1.10909125, CMake 3.22.1
- Python 3.12 with numpy, pillow, scikit-image
- Swift 6.0.3 + SwiftLint 0.57.1 (can lint/parse iOS code, cannot build or test it)

**What works on this VM:**
- `./gradlew assembleDebug` — builds the app
- `./gradlew test` — runs JVM unit tests (no emulator needed)
- `./gradlew testDebugUnitTest` — same as above
- `./gradlew lint` — static analysis
- `./gradlew bundleRelease` — builds release AAB
- Robolectric tests — JVM-based Android framework simulation (no emulator needed)

**What does NOT work on this VM** (confirmed — no KVM on Firecracker):
- `./gradlew connectedDebugAndroidTest` — no emulator, no KVM
- `maestro test` — no emulator (Maestro also unavailable on macOS local due to Java 8)
- Screenshot capture on device — no emulator

All connected/Maestro/screenshot tests are `DEFERRED_TO_LOCAL`. Unit tests and Robolectric are your primary verification.

## Strategy

- **Stack**: Kotlin + Jetpack Compose + Oboe (low-latency audio) + FluidSynth (SoundFont synthesis)
- **Architecture**: multi-module Gradle Kotlin DSL
- **Visual parity**: preserve the iOS look, layout, and interaction model. Intentionally forgo Material 3 shells and dynamic color. Android system surfaces (permissions, share sheet, file picker, back gesture) remain platform-native.
- **No Kotlin Multiplatform**: it adds risk without helping the first Play Store release.

## Technology mapping

| iOS | Android |
|-----|---------|
| SwiftUI | Jetpack Compose (Kotlin) |
| AVAudioEngine + AUSampler | FluidSynth-Android + Oboe |
| AVAudioSession | Android AudioManager + Oboe AudioStream |
| CADisplayLink | Choreographer.FrameCallback |
| CoreHaptics | Android VibratorManager |
| DispatchSourceTimer (Metronome) | Handler / Choreographer callbacks |
| AVAudioRecorder (Vocals) | MediaRecorder / Oboe input stream |
| AVAssetWriter (M4A export) | MediaMuxer + MediaCodec |
| UIViewRepresentable (multi-touch) | Compose `pointerInput` + `MotionEvent` |
| @Published + Combine | `mutableStateOf()` + StateFlow / SharedFlow |
| XCUITest | Compose Testing (`createComposeRule`) + Robolectric |
| Maestro iOS flows | Maestro Android flows (same YAML, different appId) |
| JSON Codable | kotlinx.serialization |
| @MainActor | viewModelScope + Dispatchers.Main |
| ObservableObject | ViewModel (AndroidX) |

## Project structure

```
android-app/
  settings.gradle.kts
  build.gradle.kts                (root — version catalog, plugins)
  gradle.properties
  gradle/
    wrapper/
    libs.versions.toml            (version catalog)
  app/                            (shell — Activity, navigation, DI)
    build.gradle.kts
    src/main/
      AndroidManifest.xml
      java/com/loopa/app/
        MainActivity.kt
      res/
      assets/
        GM.sf2
    src/test/                     (unit + Robolectric tests)
    src/androidTest/              (instrumented tests — deferred if no emulator)
  core/
    model/                        (Track, MidiNote, MidiEvent, SavedSession, enums)
      build.gradle.kts
      src/main/java/com/loopa/core/model/
      src/test/
    looper/                       (Quantizer, MidiLooper, MultiTrackLooper, MidiExporter, LoopStorage)
      build.gradle.kts
      src/main/java/com/loopa/core/looper/
      src/test/
    storage/                      (SessionStorage, SessionExporter)
      build.gradle.kts
      src/main/java/com/loopa/core/storage/
      src/test/
  audio/                          (FluidSynth wrapper, KeyboardSampler, LooperAudioEngine, Metronome, VocalRecorder, HapticManager, AudioExporter)
    build.gradle.kts
    src/main/java/com/loopa/audio/
    src/main/cpp/                 (JNI/CMake if compiling FluidSynth from source)
    src/test/
    src/androidTest/
  feature/
    looper/                       (LooperViewModel, LooperScreen, keyboard, transport, waveform)
      build.gradle.kts
      src/main/java/com/loopa/feature/looper/
      src/test/
    tracks/                       (TracksViewModel, TracksScreen, TrackMixerRow)
      build.gradle.kts
      src/main/java/com/loopa/feature/tracks/
      src/test/
    editor/                       (TrackFocusViewModel, TrackFocusScreen, PianoRollCanvas, DrumGrid)
      build.gradle.kts
      src/main/java/com/loopa/feature/editor/
      src/test/
  .maestro/                       (Maestro E2E flows — adapted from iOS)
```

## Execution model

1. Work **one phase at a time**, in order. Do not skip ahead.
2. Before editing, state the exact subgoal and files you will touch.
3. After each change set:
   a. Run the smallest relevant test (`./gradlew :core:model:test`)
   b. Then the full test suite (`./gradlew test`)
   c. Then update `migration/PARITY_MATRIX.md` with new parity rows
4. At **milestone boundaries** (after phases 1, 4, 8, 10, 12), summarize what was accomplished and what verification is deferred. These summaries go into `migration/reports/`.
5. Update `memory-bank/activeContext.md` and `memory-bank/progress.md` after every phase.

---

## Phase 1: Migration Control Documents

**Goal**: Create the governance scaffolding the rest of the migration depends on. This phase requires NO Android code — only documentation.

**Prerequisite**: `migration/SPEC.md` and `memory-bank/` exist (created by the iOS baseline agent). If they don't exist, output `BLOCKED(iOS baseline capture not complete)`.

**Steps**:
1. Create `AGENTS.md` at repo root with:
   - Hard operating rules (no modifying `android/`, no self-certification, BLOCKED protocol)
   - Stop conditions (same failure twice → re-plan, missing dependency → BLOCKED)
   - Judge policy (fresh-context agent reviews artifacts at milestone boundaries)
   - File ownership rules (which agent owns which directories)

2. Create `migration/PARITY_MATRIX.md`:
   - Table with columns: Feature | iOS Source | iOS Test | Android Source | Android Test | Artifact | Status
   - Pre-populate the Feature and iOS Source columns from `migration/SPEC.md`
   - Status starts as `not_started` for all rows

3. Create `migration/VERIFY.md`:
   - For each phase, list the exact verification commands and their expected output
   - Split each gate into `cloud_verifiable` (unit tests, build, lint) and `local_verifiable` (connected tests, Maestro, screenshots)
   - A phase passes when all `cloud_verifiable` gates are green and all `local_verifiable` gates are logged as `DEFERRED_TO_LOCAL`

4. Create `migration/AGENT_RUN_PROMPT.md` — copy of this prompt for reuse in future sessions

5. Create `migration/scripts/compare_state.py`:
   - Reads two JSON state dumps (iOS vs Android)
   - Compares every key-value pair
   - Returns PASS if all match, FAIL with diffs if not

6. Create `migration/scripts/compare_images.py`:
   - Reads two screenshot images
   - Computes SSIM (structural similarity)
   - Returns PASS if SSIM ≥ 0.85 (masking top/bottom 5% for status/nav bars)
   - Returns FAIL with diff image and SSIM score if below threshold

7. Create `migration/scripts/compare_audio.py`:
   - Placeholder for now — will compare M4A export duration, onset timing
   - Returns PASS/FAIL

**Verification gate**:
- `AGENTS.md` exists with stop conditions and judge policy
- `migration/PARITY_MATRIX.md` exists with all features from SPEC.md
- `migration/VERIFY.md` exists with cloud/local split for each phase
- `migration/scripts/compare_state.py` runs without error on dummy input
- `migration/scripts/compare_images.py` runs without error on dummy input

---

## Phase 2: Project Scaffolding + Design System

**Goal**: Multi-module Gradle project that builds, plus the full Loopa design system ported to Compose.

**Steps**:
1. Create multi-module Gradle KTS project in `android-app/` matching the project structure above
2. Configure root `build.gradle.kts`:
   - Gradle version catalog (`libs.versions.toml`) for all dependencies
   - Compose BOM, kotlinx-serialization, JUnit 5, Compose Testing, Robolectric
   - Lint, detekt, ktlintCheck plugins
3. Configure `app/build.gradle.kts`:
   - `minSdk = 29`, `targetSdk = 34`, `compileSdk = 34`
   - `namespace = "com.loopa.app"`
4. Configure `AndroidManifest.xml`:
   - `screenOrientation="landscape"`
   - Permissions: `RECORD_AUDIO`, `VIBRATE`
   - Edge-to-edge theme, no action bar
5. Create minimal `MainActivity.kt` with empty Compose scaffold using the Loopa theme
6. Copy `ios/GM.sf2` to `app/src/main/assets/GM.sf2` (confirmed: exists in both `ios/GM.sf2` and `android/GM.sf2`, ~6MB, SHA-256: `82475b91a76de15cb28a104707d3247ba932e228bada3f47bba63c6b31aaf7a1`)
7. Port `ios/UI/Theme/DesignSystem.swift` → Compose theme. Read `memory-bank/io-schema.md` for exact values:
   - `ui/theme/Color.kt` — all hex colors from DesignSystem.swift PLUS the additional inline palette colors documented in io-schema.md (12 extra hex values hardcoded in shipped screens)
   - `ui/theme/Type.kt` — typography (use `google-fonts` for rounded if available, otherwise closest match)
   - `ui/theme/Theme.kt` — MaterialTheme wrapper with Loopa color scheme
   - `ui/theme/Spacing.kt` — TishSpacing values
   - `ui/theme/Radius.kt` — TishRadius values
   - `ui/components/TishButtonStyle.kt` — custom button composables
8. Write `DesignSystemTest.kt` validating color hex values match iOS values from io-schema.md

**Verification gate**:
```bash
cd android-app && ./gradlew assembleDebug       # builds
cd android-app && ./gradlew test                 # design system tests pass
cd android-app && ./gradlew lint                 # no errors
```
- Update `migration/PARITY_MATRIX.md`: mark design system row as `ported`
- Update `memory-bank/code-index.md` with new files

---

## Phase 3: Data Models & Pure Logic

**Goal**: Port all data models and deterministic business logic. Zero platform dependencies.

**iOS sources to read**: `ios/Models/Track.swift`, `ios/Models/MidiNote.swift`, `ios/Looper/MidiEvent.swift`, `ios/Looper/Quantizer.swift`, `ios/Models/SessionStorage.swift`

**Also read**: `memory-bank/io-schema.md` for exact type definitions, enum values, and constants.

**Steps**:
1. Create Kotlin data classes in `core/model/`:
   - `Track.kt` — `data class Track(...)`, `enum class TrackType`, `enum class Instrument` (with MIDI program numbers), `enum class BarCount`, `enum class QuantizeDivision`
   - `MidiNote.kt` — `data class MidiNote(...)` with all properties matching iOS
   - `MidiEvent.kt` — `data class MidiEvent(...)`
   - `SavedSession.kt` — `data class SavedSession(...)` with kotlinx.serialization annotations
2. Create `core/looper/Quantizer.kt` — port quantization logic exactly
3. Create `core/storage/SessionStorage.kt` — JSON serialization via kotlinx.serialization. **Important**: implement dual date encoding — ISO-8601 for `.loopa` import/export and epoch-seconds for local `sessions.json` / `working_session.json`. See `migration/fixtures/session_schema.json` `x-loopa-export` and `x-local-storage` sections.
4. Port **all** corresponding iOS unit tests (read the iOS test files directly):
   - `ios/Tests/QuantizerTests.swift` → `QuantizerTest.kt`
   - `ios/Tests/MidiNoteTests.swift` → `MidiNoteTest.kt`
   - `ios/Tests/SoloMuteTests.swift` → `SoloMuteTest.kt`
   - `ios/Tests/TrackVolumeTests.swift` → `TrackVolumeTest.kt`
   - `ios/Tests/WorkingSessionTests.swift` → `WorkingSessionTest.kt`
5. If a test uses iOS-specific APIs (Context for file I/O), use Robolectric so it runs on JVM

**Verification gate**:
```bash
cd android-app && ./gradlew :core:model:test     # model tests pass
cd android-app && ./gradlew :core:looper:test    # quantizer tests pass
cd android-app && ./gradlew :core:storage:test   # storage tests pass
cd android-app && ./gradlew test                  # all tests pass (regression check)
```
- Update `migration/PARITY_MATRIX.md` with model parity rows

---

## Phase 4: Audio Feasibility Spike (Highest Risk)

**Goal**: Prove four hard requirements. If any fail, output `BLOCKED` and stop.

**Requirements**:
1. FluidSynth loads GM.sf2 and plays a note via JNI
2. Metronome produces beat-accurate timing callbacks
3. Vocal recording captures mic input (MediaRecorder)
4. M4A export produces a valid file (MediaCodec + MediaMuxer)

**Steps**:
1. Add FluidSynth-Android dependency:
   - Try AAR from Maven first: check `com.github.nicholasgasior:fluidsynth-android` or similar
   - If no AAR works: compile FluidSynth from source via CMake/NDK in `audio/src/main/cpp/`
   - FluidSynth is LGPL — use as a shared library (dynamic linking), not static
2. Create `audio/` module:
   - `FluidSynthEngine.kt` — JNI wrapper: init, loadSoundFont, noteOn, noteOff, setProgram
   - `KeyboardSampler.kt` — mirrors iOS `KeyboardSampler` interface exactly
   - `LooperAudioEngine.kt` — live sampler + 16 pooled samplers + click sampler (mirrors iOS)
   - `Metronome.kt` — beat callback via Handler or Choreographer
   - `VocalRecorder.kt` — MediaRecorder wrapper
   - `HapticManager.kt` — VibratorManager wrapper
   - `AudioExporter.kt` — MediaCodec + MediaMuxer for M4A
3. Write tests:
   - `FluidSynthEngineTest.kt` — JNI loading, SoundFont loading (may need Robolectric or instrumented)
   - `KeyboardSamplerTest.kt` — note routing, program changes
   - `MetronomeTest.kt` — timing accuracy within tolerance
   - `AudioExporterTest.kt` — M4A file creation

**GM.sf2 is only ~6MB** (5,994,284 bytes), not the 140MB+ that General MIDI SoundFonts often are. This eliminates OOM concerns for asset loading. A simple `context.assets.open("GM.sf2")` into FluidSynth is fine — no streaming, compression, or Play Asset Delivery needed.

**Critical note on testing audio on Linux**: FluidSynth JNI and actual audio playback cannot be verified on this headless Linux VM (no emulator, no KVM). Structure the audio module so that:
- Pure logic (note routing, timing math, state management) is testable via JVM unit tests
- Hardware interaction (actual JNI calls, audio output) is behind interfaces that can be mocked in unit tests and tested for real on an emulator/device locally

**STOP condition**: If FluidSynth cannot be compiled or loaded on Android (JNI failure, licensing issue, missing native libs), output:
```
BLOCKED(Audio spike failed: <specific reason>. Do not proceed to Phase 5.)
```

**Verification gate**:
```bash
cd android-app && ./gradlew :audio:test          # audio unit tests pass
cd android-app && ./gradlew assembleDebug        # builds with native libs
cd android-app && ./gradlew test                  # all tests still pass
```
- `DEFERRED_TO_LOCAL`: actual audio playback, M4A export validation, latency measurement (need emulator/device)
- Document spike findings in `memory-bank/techContext.md`
- Write `migration/reports/phase4_audio_spike.md` summarizing what was proven and what's deferred

**Milestone boundary**: Summarize Phase 1-4 results in `migration/reports/milestone_1.md`.

---

## Phase 5: MIDI Looper Logic

**Goal**: Port the multi-track MIDI recording and playback engine.

**Active iOS source**: `ios/Looper/MultiTrackLooper.swift` (the current shipped transport engine)

**Also shipped but not on primary runtime path** (verify before porting — may be dead code):
- `ios/Looper/MidiLooper.swift` — legacy single-loop recorder. Check if `MultiTrackLooper` delegates to it. If not, skip.
- `ios/Looper/MidiExporter.swift` — MIDI file export exists but is not surfaced in the current UI. Port it as a lower priority.
- `ios/Looper/LoopStorage.swift` — legacy `.tishloop` format. Likely not needed for the Android port.

**Steps**:
1. Create in `core/looper/`:
   - `MultiTrackLooper.kt` — multi-track orchestration, solo/mute, BPM-synced playback (this is the core, port it thoroughly)
   - `MidiExporter.kt` — standard MIDI file export (port for feature completeness)
   - Skip `MidiLooper.kt` and `LoopStorage.kt` unless you confirm `MultiTrackLooper` depends on them
2. Port all tests:
   - `ios/Tests/MidiLooperTests.swift` → `MidiLooperTest.kt`
   - `ios/Tests/MultiTrackLooperTests.swift` → `MultiTrackLooperTest.kt`
   - `ios/Tests/PlaybackSyncTests.swift` → `PlaybackSyncTest.kt`
3. Add Android-specific tests: process death mid-recording, audio focus interruption edge cases

**Verification gate**:
```bash
cd android-app && ./gradlew :core:looper:test    # all looper tests pass
cd android-app && ./gradlew test                  # full regression pass
```
- Update `migration/PARITY_MATRIX.md` with looper parity rows
- Test count for this layer should meet or exceed iOS count

---

## Phase 6: ViewModels

**Goal**: Port all ViewModels. These are the behavioral core of the app.

**iOS sources**: `ios/ViewModels/LooperViewModel.swift` (1200+ lines), `ios/ViewModels/TracksViewModel.swift`, `ios/ViewModels/TrackFocusViewModel.swift`

**Also read**: `migration/fixtures/viewmodel_state_reference.md` for the complete list of published properties.

**Architecture mapping**:
- `@Published var` → `mutableStateOf()` or `MutableStateFlow`
- `@MainActor` → `viewModelScope` with `Dispatchers.Main`
- `CADisplayLink` → `Choreographer.FrameCallback`
- Combine publishers → Kotlin Flow
- `ObservableObject` → `ViewModel` (AndroidX)

**Steps**:
1. `feature/looper/LooperViewModel.kt` — all published state, transport controls, count-in, instrument switching, BPM, session save/load, display sync via Choreographer
2. `feature/tracks/TracksViewModel.kt` — thin wrapper forwarding from LooperViewModel
3. `feature/editor/TrackFocusViewModel.kt` — piano roll editor: selection, move, resize, delete, add, copy/paste, undo, zoom
4. `core/storage/SessionExporter.kt` — .loopa file I/O, share intent
5. Port all tests:
   - `ios/Tests/ViewModelTests.swift` → `ViewModelTest.kt`
   - `ios/Tests/TrackFocusViewModelTests.swift` → `TrackFocusViewModelTest.kt`

**Verification gate**:
```bash
cd android-app && ./gradlew :feature:looper:test  # ViewModel tests pass
cd android-app && ./gradlew :feature:editor:test   # TrackFocus tests pass
cd android-app && ./gradlew test                    # full regression pass
```
- Update `migration/PARITY_MATRIX.md` with ViewModel parity rows

---

## Phase 7: Main Screen UI

**Goal**: Build LooperScreen — transport, keyboard, waveform. First visually verifiable screen.

**iOS source**: `ios/UI/Screens/LooperView.swift`, `ios/UI/Components/FullKeyboardView.swift`, `ios/UI/Components/KeyboardLayoutEngine.swift`, `ios/UI/Components/VocalWaveformView.swift`, `ios/UI/Components/BPMEditorView.swift`

**Not active in current runtime** (confirmed by code-index — do NOT port these): `KeyboardLayer.swift` (older static renderer, replaced by `FullKeyboardView`), `TouchOverlay.swift` (UIKit bridge for excluded legacy keyboard path)

**Steps**:
1. `feature/looper/ui/LooperScreen.kt`:
   - Top bar ("L∞PA" logo, BPM button, tracks button, settings, about)
   - Loop progress bar with beat indicators
   - Transport controls (record, play/pause, restart, quantize)
   - Instrument/vocal selector
   - Keyboard or vocal waveform area
2. UI components in `feature/looper/ui/`:
   - `FullKeyboardView.kt` — multi-touch piano + drum-pad surface via `pointerInput` (port from `FullKeyboardView.swift`, the active live input surface)
   - `KeyboardLayoutEngine.kt` — key geometry and hit testing (port from `KeyboardLayoutEngine.swift`)
   - `VocalWaveformView.kt` — waveform Canvas (port from `VocalWaveformView.swift`)
   - `TransportControls.kt` — record, play/pause, restart, quantize buttons
   - `BPMEditorView.kt` — BPM editing overlay
3. Set `Modifier.testTag(...)` matching iOS accessibility identifiers:
   - `recordButton`, `playPauseButton`, `restartButton`, `quantizeButton`, `bpmButton`, `tracksButton`, `settingsButton`, `aboutButton`
4. Write Compose UI tests (Robolectric-based, run on JVM):
   - Transport button existence and tapping
   - Instrument selector switching
   - BPM editor open/close
5. Create Maestro flows in `android-app/.maestro/` adapted from iOS:
   - Copy `ios/.maestro/*.yaml`, change `appId` if needed
   - These WILL NOT run on this VM (no emulator) or locally (Java 8). They exist for future verification when Maestro becomes available.

**Verification gate**:
```bash
cd android-app && ./gradlew assembleDebug          # builds
cd android-app && ./gradlew :feature:looper:test   # Compose UI tests pass (Robolectric)
cd android-app && ./gradlew test                    # full regression pass
```
- `DEFERRED_TO_LOCAL`: Maestro flows, visual screenshot comparison
- Informal: compare LooperScreen layout against `migration/fixtures/ios_screenshots/` by reading the screenshot and checking layout matches

---

## Phase 8: Secondary Screens

**Goal**: TracksView, TrackFocusView (piano roll + drum grid), Settings, About.

**iOS sources**: `ios/UI/Screens/TracksView.swift`, `ios/UI/Components/TrackMixerRow.swift`, `ios/UI/Screens/TrackFocusView.swift`, `ios/UI/Components/PianoRollCanvasView.swift`, `ios/UI/Components/DrumGridView.swift`, `ios/UI/Screens/SettingsView.swift`, `ios/UI/Screens/AboutView.swift`

**Steps**:
1. `feature/tracks/ui/TracksScreen.kt` — track mixer sheet
2. `feature/tracks/ui/TrackMixerRow.kt` — mute/solo/quantize/loop buttons, volume slider, instrument picker
3. `feature/editor/ui/TrackFocusScreen.kt` — editor shell with toolbar
4. `feature/editor/ui/PianoRollCanvasView.kt` — Compose Canvas, gestures: tap-to-add, drag, resize, multi-select, zoom, playhead
5. `feature/editor/ui/DrumGridView.kt` — step sequencer grid
6. `app/ui/SettingsScreen.kt`, `app/ui/AboutScreen.kt`
7. Navigation: sheet/dialog patterns matching iOS (tracks = bottom sheet, editor = full screen)
8. Write Compose UI tests for each screen (Robolectric)

**Verification gate**:
```bash
cd android-app && ./gradlew assembleDebug
cd android-app && ./gradlew test                    # all tests pass including new UI tests
```
- `DEFERRED_TO_LOCAL`: Maestro full_flow.yaml, play_pause_flow.yaml, visual comparison

**Milestone boundary**: Summarize Phases 5-8 in `migration/reports/milestone_2.md`.

---

## Phase 9: Integration & Session Management

**Goal**: Wire everything end-to-end. Save/load, auto-save, import/export.

**Steps**:
1. Session save/load via `SessionStorage` (JSON to internal storage)
2. Auto-save working session on `onPause`/`onStop` lifecycle
3. Restore working session on launch
4. `.loopa` file import/export via Android intent filters and ShareSheet
5. M4A export via AudioExporter
6. MIDI file export via MidiExporter
7. Wire `MainActivity` with navigation, ViewModel injection, lifecycle handling
8. Handle `onNewIntent` for incoming .loopa files (mirrors iOS `onOpenURL`)

**Verification gate**:
```bash
cd android-app && ./gradlew :core:storage:test     # session save/load tests
cd android-app && ./gradlew test                    # full regression
cd android-app && ./gradlew assembleDebug           # builds with all integration
```
- `DEFERRED_TO_LOCAL`: kill/restore cycle, .loopa round-trip, actual M4A export

---

## Phase 10: Parity Verification

**Goal**: Systematic proof that Android matches iOS across all three parity layers. Some verification runs on this VM, some is deferred.

**What you CAN do on this VM**:
1. **State parity**: Create a test that instantiates `LooperViewModel` with known inputs and dumps its state as JSON. Compare against `migration/fixtures/viewmodel_state_reference.md` using `migration/scripts/compare_state.py`.
2. **Logic parity**: Run shared fixture data (identical MIDI input) through both iOS test expectations and Android tests. Confirm identical quantized output.
3. **Model parity**: Confirm every enum value, constant, and data shape matches io-schema.md.

**What must be DEFERRED_TO_LOCAL**:
4. **Visual parity**: Capture Android screenshots, compare against iOS baselines using `compare_images.py`. Note: only 6 iOS baseline screenshots exist (initial_state, recording_in_progress, track_recorded, paused, playing, restarted). Baselines for tracks_sheet, editor_piano_roll, editor_drum_grid, and vocal_mode were NOT captured. For those 4 states, the local verifier must capture iOS and Android side-by-side.
5. **Audio parity**: Export M4A/MIDI from Android, compare against iOS exports using `compare_audio.py`. No iOS audio export baselines exist yet — local verifier must capture both.

**Steps**:
1. Write state comparison tests that serialize ViewModel state and validate against reference
2. Ensure all fixture-driven tests pass
3. Fill in remaining `migration/PARITY_MATRIX.md` rows — every feature must have at least one proof (test, screenshot ref, or DEFERRED note)
4. Create `migration/reports/parity_report.md` documenting what's proven on this VM vs what needs local verification

**Verification gate**:
```bash
cd android-app && ./gradlew test                    # all tests pass
python3 migration/scripts/compare_state.py          # state parity PASS (if reference data available)
```
- `DEFERRED_TO_LOCAL`: visual comparison, audio comparison, Maestro flows
- `migration/PARITY_MATRIX.md` must be fully populated (every row has status)

**Milestone boundary**: Write `migration/reports/milestone_3.md`.

---

## Phase 11: Polish & Hardening

**Goal**: Android-specific production concerns.

**Steps**:
1. **Back button**: `BackHandler` for sheets/overlays in Compose
2. **Audio focus**: `AudioManager.requestAudioFocus` / release in LooperAudioEngine
3. **Process death**: ensure `SavedStateHandle` or working session restore handles system kill
4. **Performance**: profile-guard the editor Canvas (no allocations in draw loop)
5. **Memory**: ensure GM.sf2 loads without OOM — consider lazy/streaming load
6. **ProGuard/R8**: keep rules for FluidSynth JNI classes and kotlinx.serialization
7. **Adaptive icon**: create foreground + background layer from `ios/Assets.xcassets/AppIcon.appiconset/AppIcon.png`
8. **Configuration stability**: verify landscape lock holds (no rotation crash)

**Verification gate**:
```bash
cd android-app && ./gradlew test                    # all tests pass
cd android-app && ./gradlew assembleRelease         # release build with R8
cd android-app && ./gradlew lint                    # clean
```
- `DEFERRED_TO_LOCAL`: device matrix (phone/tablet/foldable), multi-window, Bluetooth route changes, stress test

---

## Phase 12: Play Store Release Prep

**Goal**: Signed release bundle and all submission assets.

**Steps**:
1. Generate signing keystore (or placeholder — user will supply real keystore)
2. Configure signing in `app/build.gradle.kts`
3. Build release bundle: `./gradlew bundleRelease`
4. Create store listing assets directory: `android-app/store/`
   - App icon: 512×512 PNG
   - Feature graphic: 1024×500 PNG
   - Note: actual screenshots must be captured locally via Maestro on emulator
5. Write store listing text:
   - App name, short description (80 chars), full description (4000 chars)
6. Create `PLAY_STORE_SUBMISSION_GUIDE.md` with step-by-step instructions for the user
7. Create `PRIVACY_POLICY.md` (Loopa collects no user data, all local storage)
8. Document Data Safety responses (no data collection, no data sharing)

**Verification gate**:
```bash
cd android-app && ./gradlew bundleRelease           # produces valid AAB
ls -la android-app/app/build/outputs/bundle/release/*.aab  # AAB exists
cd android-app && ./gradlew lint                    # clean
```
- Check AAB size. GM.sf2 is only ~6MB so the bundle should be well under 150MB. If it exceeds 150MB for other reasons, investigate.
- `PLAY_STORE_SUBMISSION_GUIDE.md` exists
- `PRIVACY_POLICY.md` exists

**Milestone boundary**: Write `migration/reports/milestone_final.md` — comprehensive summary of everything built, tested, proven, and deferred.

---

## Test count targets

| Category | iOS Count | Android Target | Test Type |
|----------|-----------|----------------|-----------|
| Model unit tests | ~30 | 30+ | JVM |
| Quantizer tests | ~10 | 10+ | JVM |
| Audio engine tests | ~15 | 15+ | JVM + mocks |
| MIDI looper tests | ~25 | 25+ | JVM |
| ViewModel tests | ~40 | 40+ | JVM + Robolectric |
| Track focus tests | ~30 | 30+ | JVM |
| Playback sync tests | ~8 | 8+ | JVM |
| Compose UI tests | — | 20+ | Robolectric |
| Maestro E2E flows | 4 | 4+ | DEFERRED (no emulator or Maestro anywhere) |
| **Total** | **178+** | **182+** | |

All "JVM" and "Robolectric" tests run via `./gradlew test` — no emulator required. Maestro flows exist in the repo but require local device/emulator to execute.

---

## Risk registry

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| FluidSynth AAR not available | Medium | Critical | Compile from source via CMake/NDK. Phase 4 spike catches early. |
| Audio latency too high | Medium | High | Oboe AAudio backend, low buffers. Spike in Phase 4. DEFERRED_TO_LOCAL for measurement. |
| Multi-touch keyboard laggy | Low | Medium | Fall back to `MotionEvent` in `AndroidView` if `pointerInput` insufficient. |
| No emulator on cloud VM | Confirmed | Medium | Unit tests + Robolectric for all logic. Connected/Maestro/screenshots deferred to local. |
| No Maestro anywhere | Confirmed | Low | Create YAML flows for future use. All E2E execution deferred. |
| FluidSynth LGPL licensing | Low | High | Dynamic linking only. Document in AGENTS.md. |
| Dual date encoding formats | Certain | Medium | `.loopa` uses ISO-8601, local storage uses epoch seconds. Android must handle both. |
| Missing screenshot baselines | Confirmed | Low | 6 of 10 canonical states captured. Remaining 4 need side-by-side local comparison. |
| Context window exhaustion | Medium | Medium | Phases scoped to single sessions. Memory bank provides continuity. |
| Porting dormant/legacy code | Medium | Low | SPEC.md + code-index identify 6 legacy files. Verify they're actually invoked before porting. |

---

## CLI commands reference

```bash
# Build
cd android-app && ./gradlew assembleDebug
cd android-app && ./gradlew assembleRelease
cd android-app && ./gradlew bundleRelease

# Test (all run on JVM — no emulator needed)
cd android-app && ./gradlew test
cd android-app && ./gradlew :core:model:test
cd android-app && ./gradlew :core:looper:test
cd android-app && ./gradlew :core:storage:test
cd android-app && ./gradlew :audio:test
cd android-app && ./gradlew :feature:looper:test
cd android-app && ./gradlew :feature:tracks:test
cd android-app && ./gradlew :feature:editor:test

# Static analysis
cd android-app && ./gradlew lint
cd android-app && ./gradlew detekt
cd android-app && ./gradlew ktlintCheck

# Emulator (only if available)
cd android-app && ./gradlew connectedDebugAndroidTest
maestro test android-app/.maestro/

# Parity scripts
python3 migration/scripts/compare_state.py
python3 migration/scripts/compare_images.py
python3 migration/scripts/compare_audio.py
```
