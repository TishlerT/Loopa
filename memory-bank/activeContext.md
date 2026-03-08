# Active Context

## Current focus
Android migration complete — all 12 phases executed. 212 tests pass, release bundle ready.

## Recent decisions
- The Android port treats the shipped iOS app as the parity oracle, not the legacy/excluded Swift files.
- The current live iOS runtime path is `Tish88App -> LooperView -> LooperViewModel -> MultiTrackLooper / LooperAudioEngine / VocalRecorder`.
- Android implementation lives in `android-app/`.
- The existing `android/` directory is a frozen iOS mirror/reference area — never modified.
- Planned Android audio stack is `FluidSynth + Oboe`, with parity judged against the shipped iOS SoundFont-driven behavior.
- Visual parity follows the shipped dark/neon Loopa UI rather than default platform styling.
- Phase 1 created: `AGENTS.md`, `migration/PARITY_MATRIX.md`, `migration/VERIFY.md`, `migration/AGENT_RUN_PROMPT.md`, and three parity comparison scripts (`compare_state.py`, `compare_images.py`, `compare_audio.py`).

## Blockers
- No emulator available on cloud VM (Firecracker, no KVM) — connected/Maestro tests are `DEFERRED_TO_LOCAL`.
- Maestro not available on either cloud or local macOS.
- 4 of 10 canonical iOS screenshots are missing (tracks_sheet, editor_piano_roll, editor_drum_grid, vocal_mode).
