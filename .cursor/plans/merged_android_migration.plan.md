---
name: Loopa Android Migration — Merged Runbook
overview: >
  Production-grade, agent-executable migration of Loopa from iOS to Android.
  Split into three deployable prompts: (1) cloud env setup, (2) iOS baseline capture, (3) main migration.
  See migration/prompts/ for the actual agent prompts.
todos:
  - id: deploy-env-setup
    content: "Deploy 01_cloud_env_setup.md to cloud agent — installs Android SDK, NDK, CMake, JDK 17 on Linux VM"
    status: pending
  - id: deploy-ios-baselines
    content: "Deploy 02_ios_baseline_capture.md to local macOS agent — captures screenshots, test results, SPEC.md, fixtures, memory bank (runs in parallel with env setup)"
    status: pending
  - id: deploy-migration
    content: "Deploy 03_android_migration.md to cloud agent — runs phases 1-12 of the actual Android port (after env + baselines are done)"
    status: pending
isProject: false
---

# Loopa iOS → Android Migration — Merged Runbook

This plan has been split into **three deployable agent prompts** based on environment constraints:

1. The cloud agent (Linux) cannot run iOS builds, tests, or simulators
2. The local agent (macOS) can run iOS but shouldn't do the Android migration
3. Environment setup and iOS baselines can run in parallel

## Prompt Files

| # | File | Deploy to | Purpose | Depends on |
|---|------|-----------|---------|------------|
| 1 | `migration/prompts/01_cloud_env_setup.md` | Cloud agent (Linux) | Install JDK 17, Android SDK 34, NDK, CMake, emulator (if KVM), Maestro, Python packages | Nothing — run first |
| 2 | `migration/prompts/02_ios_baseline_capture.md` | Local agent (macOS) | Build iOS, run tests, capture screenshots, create SPEC.md, export fixtures, init memory bank, push to repo | Nothing — run in parallel with #1 |
| 3 | `migration/prompts/03_android_migration.md` | Cloud agent (Linux) | Phases 1-12: migration control docs → scaffold → models → audio spike → looper → ViewModels → UI → integration → parity → polish → release | #1 and #2 must complete first |

## Deployment sequence

```
┌─────────────────────┐     ┌──────────────────────────┐
│  Cloud Agent (Linux) │     │  Local Agent (macOS)      │
│                      │     │                           │
│  01_cloud_env_setup  │     │  02_ios_baseline_capture  │
│  (install Android    │     │  (build iOS, run tests,   │
│   SDK, NDK, JDK,     │     │   capture screenshots,    │
│   emulator, etc.)    │     │   create SPEC.md,         │
│                      │     │   export fixtures,         │
│  ~10-15 minutes      │     │   init memory bank)       │
│                      │     │                           │
│  Output: env ready   │     │  Output: git push         │
│         + status log │     │          with baselines    │
└──────────┬──────────┘     └─────────────┬─────────────┘
           │                               │
           │         ┌─────────────────────┘
           │         │
           ▼         ▼
┌──────────────────────────────────────────┐
│  Cloud Agent (Linux) — git pull first    │
│                                          │
│  03_android_migration.md                 │
│                                          │
│  Phase 1:  Migration control docs        │
│  Phase 2:  Scaffold + design system      │
│  Phase 3:  Data models + pure logic      │
│  Phase 4:  Audio spike (STOP if fails)   │
│  Phase 5:  MIDI looper logic             │
│  Phase 6:  ViewModels                    │
│  Phase 7:  Main screen UI                │
│  Phase 8:  Secondary screens             │
│  Phase 9:  Integration                   │
│  Phase 10: Parity verification           │
│  Phase 11: Polish & hardening            │
│  Phase 12: Play Store release prep       │
│                                          │
│  Verification: unit tests + Robolectric  │
│  on cloud; connected/Maestro/visual      │
│  deferred to local                       │
└──────────────────────────────────────────┘
```

## Key design decisions in the split

### Cloud VM limitations shape verification strategy
The Linux cloud VM can run `./gradlew test` (JVM unit tests + Robolectric) and `./gradlew assembleDebug` / `bundleRelease`. It likely cannot run an Android emulator (no KVM). This means:
- **Cloud-verifiable**: unit tests, Robolectric Compose tests, build, lint, static analysis
- **Deferred to local**: connected instrumented tests, Maestro E2E flows, screenshot comparison, audio export validation

The main migration prompt marks every gate as either `cloud_verifiable` or `DEFERRED_TO_LOCAL` so nothing is silently skipped.

### iOS baselines captured once, used everywhere
The local macOS agent captures all iOS artifacts (screenshots, test results, state traces, fixtures) and pushes them to `migration/fixtures/`. The cloud agent reads these as immutable reference data — it never needs to run iOS.

### Memory bank provides cross-session continuity
Both the local agent (creating `memory-bank/`) and the cloud agent (reading and updating it) use the same memory bank files. This ensures context persists across agent sessions and between the local and cloud environments.

### Audio spike is a hard gate
Phase 4 is designed as a pass/fail spike. If FluidSynth + Oboe can't meet requirements on Android, the agent stops immediately instead of building 8 more phases of UI on an unsound audio foundation.

## What to do after the migration agent finishes

The cloud agent will complete as much as possible with JVM-based verification. After it finishes, you'll need to:

1. **Pull the repo** to your local macOS machine
2. **Run connected tests** on a real emulator: `cd android-app && ./gradlew connectedDebugAndroidTest`
3. **Run Maestro flows**: `maestro test android-app/.maestro/`
4. **Run visual comparison**: capture Android screenshots, then `python3 migration/scripts/compare_images.py`
5. **Run audio comparison**: export M4A/MIDI from Android, then `python3 migration/scripts/compare_audio.py`
6. **Review `migration/PARITY_MATRIX.md`** — all `DEFERRED_TO_LOCAL` items need to be verified
7. **Review `migration/reports/milestone_final.md`** for the complete status

---

## Appendix: Source plan evaluation

This merged plan was created by evaluating two prior plans. See the detailed evaluation in the original merged plan (git history) or ask for it. Summary:

- **Plan A** ("Android Migration Runbook") contributed: verification architecture, fresh-context judge, parity oracle, migration control docs, multi-module architecture, agent run prompt, AGENTS.md
- **Plan B** ("Loopa Android Migration") contributed: environment bootstrap, technology mapping, granular phases, test count targets, risk registry, agent execution strategy, design system phase, verification gates with concrete CLI commands
- The merge combined Plan A's governance with Plan B's execution clarity, adapted for the Linux cloud VM constraint
