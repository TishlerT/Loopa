# Loopa — Android Migration Agent Rules

## Hard Operating Rules

1. **`android/` is frozen.** It contains a copy of iOS Swift files for reference only. Never modify it. Never treat it as Android code. Never reference it as your port target.
2. **Build in `android-app/`.** This is the working directory for the real Android project.
3. **Never self-certify.** Do not claim a phase is DONE based on your own assessment. Run the verification gate commands listed in `migration/VERIFY.md`. If a gate cannot run (e.g., emulator not available), log it as `DEFERRED_TO_LOCAL(reason)` and continue — but do not claim it passed.
4. **If the same failure repeats twice, STOP.** Re-analyze the root cause before retrying. Do not loop blindly.
5. **If a required dependency is missing, output `BLOCKED(reason)`.** Do not guess or work around critical missing pieces.
6. **Update memory-bank after every phase.** Update `activeContext.md` and `progress.md` at minimum. Update `code-index.md` when you create new files.
7. **Maximize what you deliver.** Your environment has constraints (no emulator, no Maestro), but it can do a great deal: build the full project, run all JVM/Robolectric tests, run lint, produce release bundles, and execute parity comparison scripts. Exhaust every verification you _can_ run before marking anything as deferred.

## Stop Conditions

- **Same failure twice** → Stop, re-analyze root cause, re-plan before retrying.
- **Missing dependency** → Output `BLOCKED(reason)` and do not proceed past the affected phase.
- **Audio spike failure** → If FluidSynth cannot compile or load on Android, output `BLOCKED(Audio spike failed: <specific reason>. Do not proceed to Phase 5.)`.

## Judge Policy

- At milestone boundaries (after Phases 1-4, 5-8, 9-10, 11-12), a fresh-context agent should review all artifacts produced during those phases.
- The reviewing agent has no access to the implementation agent's conversation — it evaluates purely from committed code, tests, reports, and migration documents.
- No phase is considered complete until the judge confirms the verification gates passed.

## File Ownership

| Directory | Owner | Rules |
|-----------|-------|-------|
| `android/` | FROZEN | No modifications allowed by any agent |
| `android-app/` | Android migration agent | All Android code lives here |
| `ios/` | iOS baseline agent | Android agent may read, never write |
| `migration/` | Shared | Migration agent writes reports, scripts, matrices |
| `memory-bank/` | Shared | Updated by whichever agent runs last |
| `AGENTS.md` | Migration agent | Updated as rules evolve |

## FluidSynth LGPL Compliance

FluidSynth is licensed under LGPL 2.1. The Android app must:
- Use FluidSynth as a **shared library** (dynamic linking via `.so`)
- Never statically link FluidSynth into the application binary
- Include LGPL license notice in the app's About/Licenses screen
- Allow users to replace the FluidSynth library (standard LGPL requirement)

## Environment

- **Cloud VM**: Ubuntu 24.04 LTS, x86_64, Firecracker microVM
- **Java**: OpenJDK 17.0.18
- **Android SDK**: 34 (Build Tools 34.0.0, NDK 26.1.10909125, CMake 3.22.1)
- **No KVM**: Emulator and connected tests cannot run → `DEFERRED_TO_LOCAL`
- **No Maestro**: Not available on cloud or local macOS (Java version mismatch)

## Testing Strategy

- **JVM unit tests**: All pure logic (models, quantizer, looper engine, ViewModels)
- **Robolectric tests**: Android framework simulation (SessionStorage, Compose UI)
- **Connected tests**: `DEFERRED_TO_LOCAL` (no emulator)
- **Maestro E2E**: `DEFERRED_TO_LOCAL` (no emulator, Java mismatch on macOS)
- **Screenshot comparison**: `DEFERRED_TO_LOCAL` (no emulator for capture)

## Development Commands

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

# Parity scripts
python3 migration/scripts/compare_state.py <ios.json> <android.json>
python3 migration/scripts/compare_images.py <ios.png> <android.png>
python3 migration/scripts/compare_audio.py <ios.m4a> <android.m4a>
```
