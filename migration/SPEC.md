# Loopa — Shipped Surface Inventory

Generated from `ios/project.yml` and source inspection on 2026-03-07.

## Excluded files (legacy, not shipped)
- `ContentView.swift`
- `UI/Screens/SampleBrowserView.swift`
- `Networking/**`
- `Models/FreesoundModels.swift`
- `ViewModels/TishViewModel.swift`
- `Audio/PreviewPlayer.swift`
- `UI/Components/SoundRow.swift`
- `UI/Components/LoopVisualization.swift`
- `UI/Components/TransportControls.swift`
- `UI/Components/KeyboardView.swift`

## Included but not on the primary shipped runtime path
- `Audio/AudioEngine.swift`
- `Audio/Metronome.swift`
- `Looper/LoopStorage.swift`
- `Looper/MidiExporter.swift`
- `Looper/MidiLooper.swift`
- `UI/Components/KeyboardLayer.swift`
- `UI/Components/TouchOverlay.swift`

The current live app path is `Tish88App -> LooperView -> LooperViewModel -> MultiTrackLooper / LooperAudioEngine / VocalRecorder`. The files above are still compiled, but they do not appear to drive the current shipped looper flow.

## Screens
### LooperView (main screen)
- App launches directly into `LooperView`; there is no splash menu or home dashboard.
- Layout is landscape-only and adapts for iPhone vs iPad.
- Instrument control is a top-left menu with `Piano`, `E-Piano`, `Organ`, `Guitar`, `Strings`, `Lead`, `Pad`, `Drums`, `Bass`, plus a separate vocal mode entry.
- Vocal mode swaps the keyboard/drum pad surface for a live waveform panel and microphone-driven recording flow.
- Main transport row exposes `Record`, `Play/Pause`, `Restart`, and global quantize-cycle `Q`.
- `Record` starts a 4-beat count-in before actual recording; record button becomes a countdown badge during count-in.
- `Play/Pause` shows stopped, paused, and playing states with distinct colors and icons.
- `Restart` is enabled once playback or recorded material exists.
- Quantize button cycles global live-recording quantization through `Off`, `1/16`, `1/8`, and `1/4`.
- A vertical progress strip and beat indicators show synchronized loop position and allow seeking when not recording/counting in.
- Octave up/down controls change the playable keyboard range.
- `TRACKS` opens the mixer surface; on iPhone it is a sheet, on iPad it is presented full-screen.
- `BPM` opens `BPMEditorView` full-screen.
- Metronome toggle turns click playback on and off.
- Bar-count picker exposes `1`, `2`, `4`, `8`, and `16` bar loops.
- Overflow menu exposes `New Session`, `Save Session`, `Load Session`, `Share Beat`, `Export to Audio`, `Clear All`, and `Settings`.
- Save flow opens an inline `SaveSessionSheet` with session-name text field plus `Cancel` and `Save`.
- Load flow opens an inline `LoadSessionSheet` listing saved sessions, metadata, row tap to load, and swipe-to-delete.
- Export actions share an `.m4a` audio render through the iOS share sheet.
- Alerts exist for microphone permission, headphone recommendation before vocal recording, and save-before-clearing/new-session protection.
- Error banner exists for audio initialization/export failures.

### TracksView (mixer sheet / full-screen on iPad)
- Header has `Done`, `Restart`, `Play/Pause`, and a passive progress indicator.
- Empty state displays `No Tracks Yet`.
- When tracks exist, a first-use hint tells the user to tap a track to open the editor.
- Each track row shows track identity, delete button, mute (`M`), solo (`S`), quantize (`Q`) for MIDI tracks, loop (`L`), inline volume slider, and optional instrument picker for non-drum MIDI tracks.
- Track rows visually dim or highlight based on mute/solo audibility state.
- Tapping a non-vocal track opens `TrackFocusView`; vocal tracks do not open the editor.
- Quantize opens a per-track sheet with `Off`, `1/4`, `1/8`, `1/16`, `1/32`, and `Cancel`.
- Instrument change opens a per-track picker sheet covering the app’s instrument enum values except vocals.
- Delete requires confirmation.
- Loop toggle controls whether short tracks keep repeating to fill the longest loop or only play through their originally recorded length.

### TrackFocusView (editor)
- Opens only for non-vocal tracks.
- Wraps `TrackFocusViewModel` and chooses melodic piano-roll editing vs drum-grid editing based on `track.isDrumKit`.
- Header exposes `Close`, `Restart`, `Play/Pause`, current beat display, track/instrument button, and grid-step menu.
- Editing toolbar exposes multi-select, add-note mode, delete mode, copy, paste, undo, quantize, horizontal zoom, and vertical zoom.
- Drum tracks also expose `Hide Empty Rows`.
- Piano-roll mode supports note select/deselect, move, resize, add on empty space, delete, long-press delete, multi-select, multi-drag, copy/paste at playhead, playhead select/drag, and pinch zoom.
- Drum-grid mode supports tap-to-toggle per-step drum hits and highlights the current playback step.
- Helper text changes based on current edit mode.
- Track instrument can be changed from this screen for applicable MIDI tracks.

### SettingsView
- Opens from the overflow menu.
- Exposes `About Loopa`, privacy policy link, support mail link, credits, and `Done`.
- Shows current app version inline.

### AboutView
- Scrollable informational view with app branding, version/build, feature summary, credits, website link, and `Done`.

## Audio behaviors
- Uses `GM.sf2` as the shipped SoundFont resource.
- `LooperAudioEngine` owns the live performance sampler, click sampler, and a pool of playback samplers for concurrent track playback.
- `KeyboardSampler` loads melodic programs by General MIDI program number and switches to percussion mode for drums.
- Shipped instrument set is `Piano`, `E-Piano`, `Organ`, `Guitar`, `Strings`, `Lead`, `Pad`, `Drums`, and `Bass`; vocal recording is a separate audio-track mode, not an `Instrument` case.
- `MultiTrackLooper` is the live transport engine for recording, playback, seeking, loop wrap, mute/solo/loop behavior, and bar-based synchronization.
- Count-in is always 4 beats and is tempo-sensitive; at 100 BPM it is about 2.4 seconds.
- MIDI recording can be globally quantized while recording.
- Per-track quantize in the mixer/editor supports `Off`, `1/4`, `1/8`, `1/16`, and `1/32`.
- Vocal recording is handled by `VocalRecorder`, including permission checks, live input metering, AAC file recording, file cleanup, and per-track playback/seek/volume.
- `AudioExporter` renders non-muted, non-vocal MIDI playback offline to `.m4a`.
- `Share Beat` and `Export to Audio` currently expose audio export, not `.loopa` sharing.
- `HapticManager` provides feedback for key presses, recording transitions, warnings, selection changes, and metronome-style cues.

## Data behaviors
- Named sessions are stored in `Documents/sessions.json`.
- Working-session autosave is stored separately in `Documents/working_session.json`.
- App auto-restores the working session on launch and auto-saves it when the scene goes inactive/background.
- `.loopa` files are JSON-encoded `SavedSession` payloads exported with ISO-8601 dates, pretty printing, and sorted keys.
- `.loopa` import accepts files by extension, decodes them into `SavedSession`, then creates a fresh session with a new ID and a ` (Imported)` suffix on the name.
- Named-session storage uses default `JSONEncoder` / `JSONDecoder` date handling, which differs from `.loopa` export/import.
- `SavedSession` persists `bpm`, `barCount`, and `[Track]`.
- `barCount` is serialized as an integer, not an enum case name.
- `Track` persists mute, solo, volume, recorded length, looping behavior, instrument name/program, notes, and optional vocal audio filename.
- `MidiExporter` exists in the codebase for `.mid` generation, but it is not exposed from the current main-screen UI.

## State management
- `LooperViewModel` is the shared app-wide source of truth injected from `Tish88App`.
- `LooperViewModel` owns transport state, count-in, instrument/bar/BPM selection, session save/load, auto-save restore, vocal mode state, export state, and bridges UI updates from `MultiTrackLooper`.
- `TracksViewModel` is a thin wrapper for the mixer surface. It forwards track/playback state from `LooperViewModel` and owns per-track modal/navigation state.
- `TrackFocusViewModel` owns editor-only state for one track: selection, undo, multi-select, playhead manipulation, zoom, add/delete/resize modes, quantize flow, and copy/paste clipboard state.
- Core persistent model layer is `Track`, `SavedSession`, and `MidiNote`.
- `DesignSystem.swift` defines the canonical dark/neon theme, but several shipped screens also hardcode additional production palette values inline.
