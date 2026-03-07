# Active Context

## Current focus
iOS baseline capture completed locally on macOS. The repo now contains the reference docs, test summaries, screenshot baselines, SoundFont checksum, and schema fixtures the Android migration should consume.

## Recent decisions
- The Android port should treat the shipped iOS app as the parity oracle, not the legacy/excluded Swift files.
- The current live iOS runtime path is `Tish88App -> LooperView -> LooperViewModel -> MultiTrackLooper / LooperAudioEngine / VocalRecorder`.
- Android implementation is expected to live in `android-app/`.
- The existing `android/` directory is a frozen iOS mirror/reference area and should not be treated as the working Android app.
- Planned Android audio stack is `FluidSynth + Oboe`, with parity judged against the shipped iOS SoundFont-driven behavior.
- Screenshot baseline for this run was sourced from exported `xcresult` attachments because the checked-in Maestro setup was not runnable in the local environment.
- Visual parity should follow the shipped dark/neon Loopa UI rather than default platform styling.

## Blockers
- Local Maestro execution is blocked by Java: the installed runtime is `1.8`, while Maestro requires Java 17+.
- The checked-in `ios/Loopa.xcodeproj` required regeneration from `ios/project.yml` before build; the stale project attempted to package `.git/hooks` resources.
- This baseline run captured six canonical transport screenshots, but did not capture `tracks_sheet`, `editor_piano_roll`, `editor_drum_grid`, or `vocal_mode` screenshots.
