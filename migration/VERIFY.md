# Loopa — Verification Gates

Each phase has specific verification commands. A phase passes when all `cloud_verifiable` gates are green and all `local_verifiable` gates are logged as `DEFERRED_TO_LOCAL`.

---

## Phase 1: Migration Control Documents

### cloud_verifiable
```bash
test -f AGENTS.md && echo "PASS: AGENTS.md exists"
test -f migration/PARITY_MATRIX.md && echo "PASS: PARITY_MATRIX.md exists"
test -f migration/VERIFY.md && echo "PASS: VERIFY.md exists"
test -f migration/AGENT_RUN_PROMPT.md && echo "PASS: AGENT_RUN_PROMPT.md exists"

# Scripts run without error on dummy input
python3 migration/scripts/compare_state.py --test && echo "PASS: compare_state.py"
python3 migration/scripts/compare_images.py --test && echo "PASS: compare_images.py"
python3 migration/scripts/compare_audio.py --test && echo "PASS: compare_audio.py"
```

### local_verifiable
None — Phase 1 is fully cloud-verifiable.

---

## Phase 2: Project Scaffolding + Design System

### cloud_verifiable
```bash
cd android-app && ./gradlew assembleDebug && echo "PASS: assembleDebug"
cd android-app && ./gradlew test && echo "PASS: all tests"
cd android-app && ./gradlew lint && echo "PASS: lint clean"
```

### local_verifiable
- Visual inspection of theme colors on device/emulator

---

## Phase 3: Data Models & Pure Logic

### cloud_verifiable
```bash
cd android-app && ./gradlew :core:model:test && echo "PASS: model tests"
cd android-app && ./gradlew :core:looper:test && echo "PASS: looper tests"
cd android-app && ./gradlew :core:storage:test && echo "PASS: storage tests"
cd android-app && ./gradlew test && echo "PASS: all tests (regression)"
```

### local_verifiable
None — Phase 3 is fully cloud-verifiable.

---

## Phase 4: Audio Feasibility Spike

### cloud_verifiable
```bash
cd android-app && ./gradlew :audio:test && echo "PASS: audio unit tests"
cd android-app && ./gradlew assembleDebug && echo "PASS: builds with native libs"
cd android-app && ./gradlew test && echo "PASS: all tests (regression)"
```

### local_verifiable
- `DEFERRED_TO_LOCAL`: Actual audio playback via FluidSynth on device
- `DEFERRED_TO_LOCAL`: M4A export file validation on device
- `DEFERRED_TO_LOCAL`: Audio latency measurement on device

---

## Phase 5: MIDI Looper Logic

### cloud_verifiable
```bash
cd android-app && ./gradlew :core:looper:test && echo "PASS: looper tests"
cd android-app && ./gradlew test && echo "PASS: all tests (regression)"
```

### local_verifiable
None — Phase 5 is fully cloud-verifiable.

---

## Phase 6: ViewModels

### cloud_verifiable
```bash
cd android-app && ./gradlew :feature:looper:test && echo "PASS: looper VM tests"
cd android-app && ./gradlew :feature:editor:test && echo "PASS: editor VM tests"
cd android-app && ./gradlew test && echo "PASS: all tests (regression)"
```

### local_verifiable
None — Phase 6 is fully cloud-verifiable.

---

## Phase 7: Main Screen UI

### cloud_verifiable
```bash
cd android-app && ./gradlew assembleDebug && echo "PASS: assembleDebug"
cd android-app && ./gradlew :feature:looper:test && echo "PASS: Compose UI tests"
cd android-app && ./gradlew test && echo "PASS: all tests (regression)"
```

### local_verifiable
- `DEFERRED_TO_LOCAL`: Visual comparison against `migration/fixtures/ios_screenshots/`
- `DEFERRED_TO_LOCAL`: Maestro flows (`android-app/.maestro/*.yaml`)
- `DEFERRED_TO_LOCAL`: Multi-touch keyboard interaction on device

---

## Phase 8: Secondary Screens

### cloud_verifiable
```bash
cd android-app && ./gradlew assembleDebug && echo "PASS: assembleDebug"
cd android-app && ./gradlew test && echo "PASS: all tests including new UI tests"
```

### local_verifiable
- `DEFERRED_TO_LOCAL`: Maestro `full_flow.yaml`, `play_pause_flow.yaml`
- `DEFERRED_TO_LOCAL`: Visual comparison of mixer, editor, settings screens
- `DEFERRED_TO_LOCAL`: Piano roll and drum grid gesture interaction on device

---

## Phase 9: Integration & Session Management

### cloud_verifiable
```bash
cd android-app && ./gradlew :core:storage:test && echo "PASS: storage tests"
cd android-app && ./gradlew test && echo "PASS: all tests (regression)"
cd android-app && ./gradlew assembleDebug && echo "PASS: builds with integration"
```

### local_verifiable
- `DEFERRED_TO_LOCAL`: Kill/restore cycle on device
- `DEFERRED_TO_LOCAL`: .loopa round-trip (export from iOS, import on Android, re-export, compare)
- `DEFERRED_TO_LOCAL`: Actual M4A export playback validation

---

## Phase 10: Parity Verification

### cloud_verifiable
```bash
cd android-app && ./gradlew test && echo "PASS: all tests"
# State parity (if reference data available):
python3 migration/scripts/compare_state.py migration/fixtures/ios_state.json android-app/build/android_state.json
```

### local_verifiable
- `DEFERRED_TO_LOCAL`: Visual parity screenshots (only 6 of 10 iOS baselines exist)
- `DEFERRED_TO_LOCAL`: Audio parity (M4A/MIDI export comparison)

---

## Phase 11: Polish & Hardening

### cloud_verifiable
```bash
cd android-app && ./gradlew test && echo "PASS: all tests"
cd android-app && ./gradlew assembleRelease && echo "PASS: release build with R8"
cd android-app && ./gradlew lint && echo "PASS: lint clean"
```

### local_verifiable
- `DEFERRED_TO_LOCAL`: Device matrix testing (phone/tablet/foldable)
- `DEFERRED_TO_LOCAL`: Multi-window behavior
- `DEFERRED_TO_LOCAL`: Bluetooth audio route changes
- `DEFERRED_TO_LOCAL`: Stress testing (rapid recording/playback)

---

## Phase 12: Play Store Release Prep

### cloud_verifiable
```bash
cd android-app && ./gradlew bundleRelease && echo "PASS: release bundle"
ls -la android-app/app/build/outputs/bundle/release/*.aab && echo "PASS: AAB exists"
cd android-app && ./gradlew lint && echo "PASS: lint clean"
test -f PLAY_STORE_SUBMISSION_GUIDE.md && echo "PASS: submission guide"
test -f PRIVACY_POLICY.md && echo "PASS: privacy policy"
```

### local_verifiable
- `DEFERRED_TO_LOCAL`: Screenshot capture for store listing (requires emulator/device)
- `DEFERRED_TO_LOCAL`: Install AAB on device and verify
