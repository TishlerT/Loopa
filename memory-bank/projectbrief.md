# Project Brief

## What Loopa is
Loopa is a landscape-only loop-based music creation app. The shipped iOS app lets the user pick an instrument, record short looped performances, layer multiple tracks, edit MIDI notes in a piano roll or drum grid, record vocals, and export a finished beat as audio.

## Target platforms
- iOS is the shipped reference implementation.
- Android is the in-progress port target and should treat the iOS app as the parity oracle.
- The existing `android/` directory is a frozen mirror/reference area, not the new Android product implementation.

## Key shipped features
- 9 playable instrument choices: `Piano`, `E-Piano`, `Organ`, `Guitar`, `Strings`, `Lead`, `Pad`, `Drums`, `Bass`
- Separate vocal recording mode with live waveform feedback
- Multi-track looping with mute, solo, loop-on/off, volume, and per-track instrument changes
- Configurable loop lengths: `1`, `2`, `4`, `8`, `16` bars
- Global live-recording quantization and per-track post-record quantization
- Full-screen MIDI editor with piano-roll editing, drum-grid editing, multi-select, copy/paste, resize, undo, and zoom
- Session save/load, working-session auto-save/restore, and `.loopa` import
- Audio export/share to `.m4a`

## Product and UX characteristics
- Dark studio aesthetic with neon cyan/orange/green accents
- Landscape-only workflow on both iPhone and iPad
- Direct-launch workstation UX: the app opens straight into the looper, not a menu system
- Visual parity matters more than adopting default platform styling

## Technical stack
- SwiftUI app architecture
- Shared `LooperViewModel` injected from `Tish88App`
- `MultiTrackLooper` as the active transport/recording engine
- `LooperAudioEngine`, `KeyboardSampler`, and `VocalRecorder` for audio
- `GM.sf2` SoundFont resource for instrument playback
- JSON-based session persistence plus `.loopa` project-file import/export

## Migration posture
The Android migration should mirror the shipped iOS behavior, not every compiled Swift file. The current source-of-truth runtime path is `Tish88App -> LooperView -> LooperViewModel -> MultiTrackLooper / LooperAudioEngine / VocalRecorder`, with mixer/editor flows layered on top via `TracksViewModel` and `TrackFocusViewModel`.
