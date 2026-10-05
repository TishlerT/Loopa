# Code Index

Source inventory updated 2026-10-05 for the iOS campaign. Entries describe code responsibilities, not distribution or runtime acceptance.

## App shell
- `ios/Tish88App.swift`: App entry point for the shipped iOS build. It locks the app to landscape, creates the shared `LooperViewModel`, restores the working session on launch, auto-saves when the scene goes inactive or backgrounds, and imports incoming `.loopa` files into the active session.

## Audio
- `ios/Audio/AudioEngine.swift`: Older split-keyboard audio engine built around left/right samplers, click playback, reverb, and SoundFont loading. It still compiles, but it appears tied to the excluded `TishViewModel` path rather than the current `LooperViewModel` runtime.
- `ios/Audio/AudioExporter.swift`: Offline MIDI renderer and share-sheet adapter, with a separate checked PCM-to-AAC writer. The writer owns a unique attempt directory, converts every channel through AVAudioFile, decodes the complete result with bounded reads, and rejects incomplete/nonfinite output. The full renderer uses existing mute/solo audibility rules, a linear sampler mixer-input fader and whole-export failure on a selected instrument load error. Vocal inclusion, sample-accurate event timing and live/export gain parity remain incomplete.
- `ios/Audio/HapticManager.swift`: Shared haptics service used for key presses, selection changes, warnings, success states, recording transitions, and other feedback across the app.
- `ios/Audio/KeyboardSampler.swift`: Thin SoundFont sampler wrapper around `AVAudioUnitSampler`. It loads melodic programs or the percussion bank, tracks current program/percussion state, and exposes note-on, note-off, and stop-all helpers.
- `ios/Audio/LooperAudioEngine.swift`: The active audio engine for the shipped looper. It manages the live input sampler, click sampler, a pool of playback samplers for tracks, SoundFont loading, per-track prep, and audio-session startup/recovery.
- `ios/Audio/Metronome.swift`: Standalone high-priority metronome timer with drift correction and downbeat detection. It still compiles, but it appears to belong to the older architecture rather than the active multi-track flow.
- `ios/Audio/VocalRecorder.swift`: Vocal recording/playback service for microphone permission, input metering, AAC file recording, file cleanup, playback/seek/volume for vocal tracks, and live waveform input monitoring.

## Looper
- `ios/Looper/LoopStorage.swift`: Persistence helper for legacy `.tishloop` files containing loop metadata and raw `MidiEvent` payloads. It is compiled, but it does not appear to be part of the current shipped `LooperView` flow.
- `ios/Looper/MidiEvent.swift`: Core second-based MIDI event model used by recording, playback, export, and note conversion logic. It stores note number, velocity, note-on/off state, side metadata, and derived identity.
- `ios/Looper/MidiExporter.swift`: Standard MIDI file exporter that converts `MidiEvent` arrays into a type-0 `.mid` file with tempo metadata and proper delta times. It is compiled but not surfaced in the current main-screen UI.
- `ios/Looper/MidiLooper.swift`: Older single-loop MIDI recorder/player with overdub layers, undo, timer-driven dispatch, quantization, and wrap-around behavior. It appears to be legacy relative to `MultiTrackLooper`.
- `ios/Looper/MultiTrackLooper.swift`: Current core transport engine behind the shipped app. It owns tracks, recording/playback state, bar-based timing, mute/solo/loop behavior, seek/restart, note scheduling, and callback hooks into the audio layer. It now also owns session/revision tokens, a coherent musical snapshot, and stopped-transport compare-and-commit/inverse methods. A recursive lock coordinates mutations and background ticks; proposal access is rejected during synchronous publication. This model boundary does not persist edits or update audio samplers.
- `ios/Looper/Quantizer.swift`: Shared quantization utility for snapping raw event times and beat-based `MidiNote` values to quarter/eighth/sixteenth/thirty-second grids, including wrap/clamp helpers.

## Models
- `ios/Models/MidiNote.swift`: Beat-based editable note model used by the piano roll and drum grid. It also contains conversions between paired `MidiEvent` data and higher-level note objects.
- `ios/Models/SessionExporter.swift`: `.loopa` import/export service. It writes shareable session JSON, validates importable URLs, handles security-scoped access, renames imported sessions to avoid collisions, and can present a share sheet for exported session files.
- `ios/Models/SessionStorage.swift`: JSON-backed named-session and working-recovery storage with explicit Result outcomes, injected file operations for fault tests, atomic writes and protection of corrupt/unreadable existing files. Missing files and valid empty JSON libraries are empty-state successes; corrupt or unreadable files remain errors. Legacy convenience reads remain for compatibility.
- `ios/Models/Track.swift`: Main domain-model file for `Track`, `SavedSession`, `BarCount`, and `Instrument`. It defines mute/solo audibility rules and the persisted shape of sessions and tracks.

- `ios/Models/MusicEdit.swift`: Pure, bounded absolute-gain and MIDI-region edits. Validates raw note input before construction, preserves unrelated/protected content, and returns an opaque inverse that checks affected values before restoring exact prior values. It has no session owner, persistence, transport, UI or provider integration.

## ViewModels
- `ios/ViewModels/LooperViewModel.swift`: Main application coordinator for the shipped app. It bridges `LooperView` to `LooperAudioEngine`, `MultiTrackLooper`, and `VocalRecorder`, owns count-in/transport/session/export/vocal-mode state, synchronizes UI to transport timing, and coordinates save/load, mixer, editor, and export flows. Persistence methods return Bool and expose readable failure state; named saves update identity only after durable success, failed New/Load operations preserve the current project, and recoverable Save UI retains entered text for retry. Removing a vocal track retains shared recording files for saved projects; reference-aware orphan cleanup remains outstanding.
- `ios/ViewModels/TrackFocusViewModel.swift`: Stateful editor view model for a single non-vocal track. It manages selection, multi-select, copy/paste, undo, drag/resize, add/delete modes, zoom, quantize flow, and syncing note edits back into the shared looper state.
- `ios/ViewModels/TracksViewModel.swift`: Lightweight mixer-screen adapter around `LooperViewModel`. It forwards track/playback state and owns the transient UI state for per-track quantize/instrument sheets plus editor navigation.

## UI screens
- `ios/UI/Screens/AboutView.swift`: Static in-app About modal with branding, version/build display, feature list, credits, and outbound website link.
- `ios/UI/Screens/LooperView.swift`: Main shipped workstation UI with adaptive iPhone/iPad layout, instrument and vocal mode switching, BPM/bar controls, synchronized progress and seeking, transport controls, keyboard or waveform surface, mixer/settings/save/load/export flows, and embedded save/load sheet views.
- `ios/UI/Screens/SettingsView.swift`: Small settings modal that links to About, privacy policy, support email, and credits/version information.
- `ios/UI/Screens/TrackFocusView.swift`: Full-screen track-editor shell. It wraps `TrackFocusViewModel`, presents transport and editing chrome, routes drum tracks to `DrumGridView` and melodic tracks to `PianoRollCanvasView`, and hosts instrument/quantize controls.
- `ios/UI/Screens/TracksView.swift`: Mixer screen for reviewing and managing recorded tracks. It provides a custom header with transport and progress, an empty state, a list of `TrackMixerRow`s, delete confirmation, and entry points into quantize, instrument-picking, and track-focus editing.

## UI components
- `ios/UI/Components/BPMEditorView.swift`: Full-screen tempo editor with plus/minus 5 BPM controls, tap-to-type numeric input, and tap-away dismissal behavior.
- `ios/UI/Components/DrumGridView.swift`: Step-sequencer editor for drum tracks. It lays out drum lanes against time steps, can hide empty rows, highlights the current step, and toggles notes on/off per grid cell.
- `ios/UI/Components/FullKeyboardView.swift`: Current live-play keyboard surface that renders either a piano keyboard or a 4x4 drum-pad grid. It tracks multitouch note ownership, derives velocity from touch height, and emits simplified note events into the looper flow.
- `ios/UI/Components/KeyboardLayer.swift`: Static piano-key rendering layer built on `KeyboardLayoutEngine`. It still compiles, but it appears to be an older helper rather than part of the current live input surface.
- `ios/UI/Components/KeyboardLayoutEngine.swift`: Shared keyboard geometry utility that computes white/black key frames and hit-testing so keyboard renderers and touch handlers map screen positions to notes consistently.
- `ios/UI/Components/PianoRollCanvasView.swift`: Custom canvas-based melodic note editor that draws the piano-roll grid, notes, labels, and playhead, then layers tap/double-tap/drag/long-press/pinch gestures for select, move, resize, add, delete, multi-drag, auto-scroll, and seek interactions.
- `ios/UI/Components/TouchOverlay.swift`: Generic UIKit bridge for forwarding raw multitouch sets into SwiftUI. It still compiles, but it appears to support the excluded legacy keyboard path rather than `FullKeyboardView`.
- `ios/UI/Components/TrackMixerRow.swift`: Reusable mixer row UI that combines delete, track identity, mute/solo/quantize/loop controls, inline volume adjustment, optional instrument switching, and the file-local quantize/instrument picker sheets used from `TracksView`.
- `ios/UI/Components/VocalWaveformView.swift`: Animated vocal-mode visualization that turns recent microphone levels into a rolling neon waveform and overlays mic/count-in/recording feedback with pulsing center-line and icon states.

## Theme
- `ios/UI/Theme/DesignSystem.swift`: Shared design foundation with the dark neon palette, hex color initializer, typography/spacing/radius tokens, glow/elevation helpers, and reusable button styles. The shipped screens use these tokens selectively and also hardcode additional live palette values inline.

## Verification and regression coverage
- `ios/run_tests.sh`: Unique per-run artifacts, explicit destinations and test counts, and fail-closed JSON verification. A zero-test Xcode success is rejected. `ios/parse_results.sh` remains a legacy reporting helper with a fixed default bundle and raw/fallback output; it is not the acceptance gate.
- `ios/Tests/AudioEngineTests.swift`: Existing audio tests plus eight AAC writer tests and six actual renderer mix tests. The strict decoder checks the whole stereo file, independent tones, relative gain and temporal regions; negative controls include silence, missing/duplicated channels, wrong gain, short output and missing suffix. The renderer tests separately check mute/solo selection, linear faders and instrument-load failure. Neither group establishes vocal, timing or live/export parity.
- `ios/Tests/MusicEditTests.swift`: Thirty-seven pure operation/inverse tests covering bounds, scope, protected content, identity, stale before-values, atomic batches and exact restoration. Session-level concurrency and audible UI actions require separate tests.
- `ios/Tests/SessionStorageSafetyTests.swift`: Missing versus corrupt/unreadable storage, preserved bytes, atomic mutation outcomes and injected failures.
- `ios/Tests/UI/RegressionTests.swift`: Includes Save failure, retry, cancellation and swipe-dismissal journeys using real recording interactions and the disposable debug storage fixture. Retained screenshots still need visual inspection.
- `ios/Tests/MultiTrackLooperTests.swift`: Existing transport tests plus 24 revision/commit tests covering mutation routes, session replacement, snapshots, stale/invalid edits, inverse ordering, concurrent same-token commits and synchronous publication reentry. Runtime validation remains a separate acceptance gate.
