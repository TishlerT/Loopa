# Code Index

One-paragraph summaries of source files for quick context loading.

## App Entry/
- **Tish88App.swift**: Main app entry point using SwiftUI App protocol. Configures landscape-only orientation via AppDelegate adaptor. Creates root LooperViewModel as environment object. Handles incoming .loopa file URLs for session import.
- **ContentView.swift**: [EXCLUDED FROM BUILD] Alternative content view using TishViewModel (legacy). Split-hand keyboard layout with left/right instrument pickers. Excluded to remove Freesound API dependency.

## Audio/
- **AudioEngine.swift**: Core audio engine using AVAudioEngine. Handles soundfont loading, MIDI playback, note routing between left/right sides. Supports multiple instrument programs via General MIDI.
- **AudioExporter.swift**: Exports sessions to M4A audio files. Uses offline AVAudioEngine rendering with sample-accurate MIDI event triggering and AVAssetWriter for AAC encoding. Renders all tracks with SoundFont instruments, respects mute/volume, and presents share sheet. Also used by Share Beat feature.
- **KeyboardSampler.swift**: Manages keyboard input to audio output. Routes notes to appropriate instruments based on current selection.
- **LooperAudioEngine.swift**: Audio engine extensions for loop recording. Manages audio buffer recording and playback synchronization.
- **VocalRecorder.swift**: Handles microphone input for vocal recording. Manages recording state, permissions, and audio file output.
- **Metronome.swift**: Metronome click generation. Provides audible beats synchronized with loop playback.
- **HapticManager.swift**: Centralized haptic feedback. Provides tactile responses for button presses, beat indicators, and state changes.
- **PreviewPlayer.swift**: [EXCLUDED FROM BUILD] Audio preview player for Freesound samples. Excluded to remove Freesound API dependency.

## Looper/
- **MultiTrackLooper.swift**: Core loop recording system. Manages multiple tracks, recording state, playback position, and quantization. Supports beat-based MidiNote model with solo/mute audibility logic. Converts recorded MidiEvents to MidiNotes on recording stop. Exposes `synchronizedPlaybackPosition` and `synchronizedPlaybackFraction` for UI sync - these calculate position identically to audio dispatch for guaranteed audio-visual alignment.
- **MidiLooper.swift**: MIDI event recording and playback. Captures note events with timestamps and replays them in sync with loop.
- **MidiExporter.swift**: Exports MidiEvents to Standard MIDI File format (Type 0). Builds header/track chunks with tempo meta event, variable-length delta times, and note on/off events. Saves to Documents/MIDI Exports directory.
- **Quantizer.swift**: Quantization logic. Snaps note timing to grid based on quantization setting (1/4, 1/8, 1/16, off). Supports both time-based (seconds) and beat-based quantization for MidiEvents and MidiNotes.
- **LoopStorage.swift**: Session persistence. Saves and loads loop sessions to device storage.
- **MidiEvent.swift**: Low-level MIDI event model with time, note, velocity, and note-on/off flag. Used during live recording.

## Models/
- **Track.swift**: Track model representing a recorded layer. Includes instrumentName, instrumentProgram, notes (MidiNote array), isMuted, isSolo, volume. Has isAudible() method for solo/mute logic. Supports both MIDI and audio (vocal) tracks.
- **MidiNote.swift**: Beat-based note model with pitch, velocity, startBeat, durationBeats. Includes conversion functions from/to MidiEvent pairs. Used for piano roll display and editing.
- **SessionStorage.swift**: Manages saved session persistence to disk.
- **SessionExporter.swift**: Handles exporting and importing .loopa session files. Encodes SavedSession to JSON, presents share sheet, and handles security-scoped URL access for imports.
- **FreesoundModels.swift**: [EXCLUDED FROM BUILD] Decodable models for Freesound API responses. Excluded to remove Freesound API dependency.

## ViewModels/
- **LooperViewModel.swift**: Main app state and business logic. Coordinates looper, audio engine, and UI state. Handles count-in timing, recording state, playback control, solo/mute, track quantization, and instrument changes. Uses CADisplayLink for screen-synced UI updates with `synchronizedProgressFraction` and `synchronizedBeat` computed properties that read directly from looper timing (bypasses Combine latency for audio-visual sync). Exposes state for TracksView and TrackFocusView. Includes `previewNote()` for audible feedback when adding notes in editors.
- **TracksViewModel.swift**: ViewModel for Tracks mixer screen. Wraps LooperViewModel for track-specific operations (M/S/Q, volume, instrument). Manages quantize and instrument picker sheet state.
- **TrackFocusViewModel.swift**: ViewModel for piano roll editor. Manages note selection, move, resize, delete operations. Supports grid snapping and loop bounds clamping. Syncs changes back to looper. Calls `previewNote()` when adding notes to provide audible feedback. Includes multi-select mode with `selectedNoteIds` set and multi-drag support: `beginMultiDrag()`, `updateMultiDragPosition()`, `endMultiDrag()` methods allow moving multiple selected notes together while preserving relative positions.
- **TishViewModel.swift**: [EXCLUDED FROM BUILD] Legacy view model for ContentView. Excluded along with ContentView.

## UI/Screens/
- **LooperView.swift**: Main app screen. Loop-first design with centered transport controls, BPM button (opens BPMEditorView), right-edge chevron button for TracksView. Keyboard with octave controls. Uses EnvironmentObject for LooperViewModel (single instance from App). Progress bar uses `synchronizedProgressFraction` and `synchronizedBeat` for audio-visual sync. Removed old sidebar; tracks now accessible via TracksView sheet.
- **TracksView.swift**: Tracks mixer screen showing all tracks with M/S/Q buttons, volume slider, and instrument picker. Tapping a track opens TrackFocusView for piano roll editing.
- **TrackFocusView.swift**: Full-screen piano roll editor for a single track. Header with back button, track name, instrument picker, and quantize button. Shows PianoRollCanvasView with helper text and delete confirmation bar.
- **SettingsView.swift**: App settings screen with links to About, Privacy Policy (external link to tishstudios.com/privacy), and contact support. Displays version info and credits.
- **AboutView.swift**: In-app About page showing app icon, version, feature list, and developer credits (TishStudios).
- **SampleBrowserView.swift**: [EXCLUDED FROM BUILD] Freesound sample browser. Excluded to remove Freesound API dependency.

## UI/Components/
- **TransportControls.swift**: [EXCLUDED FROM BUILD] Transport button components for legacy ContentView.
- **KeyboardView.swift**: [EXCLUDED FROM BUILD] Piano keyboard UI for legacy ContentView.
- **FullKeyboardView.swift**: Extended keyboard with split-hand support.
- **LoopVisualization.swift**: [EXCLUDED FROM BUILD] Loop timeline visualization for legacy ContentView.
- **BPMEditorView.swift**: BPM editor sheet with +/- 1 and +/- 5 stepper buttons, numeric input field, and common tempo presets (80/100/120/140). Range clamped 40-240.
- **TrackMixerRow.swift**: Single track row for Tracks mixer. Shows track icon, name, M/S/Q toggle buttons, volume slider (with real-time audio feedback during drag), and instrument picker button. Includes QuantizeOptionsSheet and InstrumentPickerSheet.
- **PianoRollCanvasView.swift**: Canvas-based piano roll rendering. Draws grid lines, note rectangles (rounded, color-coded), selection border, and resize handles. Supports tap-to-select, drag-to-move, handle-drag-to-resize, and long-press-to-delete gestures. In multi-select mode, supports dragging multiple selected notes together with visual preview for all notes during drag. Tapping empty space in multi-select mode does not deselect (allows panning with selection). Scroll is only disabled during active note/playhead drag (not just when notes are selected), so users can pan the canvas freely even with notes selected.
- **DrumGridView.swift**: Step sequencer grid for drum tracks. Shows 16th-note cells per drum sound (General MIDI pitches). Tap to toggle notes; supports velocity display and current-step highlighting.
- **KeyboardLayer.swift**: Static visual layer for piano key rendering. Uses KeyboardLayoutEngine to build white/black key rectangles.
- **KeyboardLayoutEngine.swift**: Shared keyboard layout engine for consistent key positioning. Calculates key frames, handles hit testing (black keys prioritized), used by KeyboardView and KeyboardLayer.
- **SoundRow.swift**: [EXCLUDED FROM BUILD] Freesound result row. Excluded with SampleBrowserView.
- **TouchOverlay.swift**: UIViewRepresentable bridge for multi-touch handling. Wraps TouchView (UIView subclass) that forwards touchesBegan/Moved/Ended/Cancelled to SwiftUI callbacks.

## UI/Theme/
- **DesignSystem.swift**: Tish88 design system defining dark studio aesthetic. Includes Color extensions (tishBackground, tishAccent, tishRecording, etc.), Font extensions (tishLargeTitle, tishMono), TishSpacing/TishRadius enums, button styles (TishButtonStyle, TishTransportButtonStyle), and view modifiers (tishGlow, tishElevation).

## Networking/ [EXCLUDED FROM BUILD]
- **FreesoundClient.swift**: [EXCLUDED] Freesound API client.
- **HTTPClient.swift**: [EXCLUDED] Generic HTTP client for Freesound.

## Tests/
- **MidiNoteTests.swift**: Tests for beat-based quantization, grid snapping, duration clamping, and MidiEvent-to-MidiNote conversion.
- **SoloMuteTests.swift**: Tests for Track.isAudible() logic covering mute, solo, and combinations.
- **TrackVolumeTests.swift**: Tests for track volume independence. Verifies that changing one track's volume doesn't affect other tracks. Covers MIDI tracks, vocal tracks, mixed types, volume clamping (0-1), mute/solo interactions, and session loading.
- **TrackFocusViewModelTests.swift**: Tests for note selection, move (with snap/clamp), resize (with minimum/clamp), delete, add, chords independence, grid step, quantize track, copy/paste with relative offset preservation, and multi-drag (preserves relative positions, preview positions, background lock state, grid snapping, state cleanup on deselect).
- **AudioEngineTests.swift**: Unit tests for AudioEngine initialization and playback.
- **KeyboardSamplerTests.swift**: Unit tests for keyboard sampler note routing.
- **MidiLooperTests.swift**: Unit tests for MIDI looper recording and playback.
- **MultiTrackLooperTests.swift**: Unit tests for multi-track looper state management.
- **QuantizerTests.swift**: Unit tests for quantization logic at various grid divisions.
- **ViewModelTests.swift**: Unit tests for LooperViewModel state and actions.
- **PlaybackSyncTests.swift**: Tests for audio-visual synchronization. Verifies synchronized position during playback, pause/resume continuity, loop boundary wraparound, and seek behavior. Includes EventTimingTests for event dispatch timing validation.
- **UI/TransportControlsUITests.swift**: XCUITest for transport buttons. Tests button existence, recording flow, play/pause toggle, restart, and quantize.
- **UI/RegressionTests.swift**: Regression tests for identified bugs.
- **UI/ScreenshotTests.swift**: Fastlane screenshot automation tests for App Store assets.

## Scripts
- **run_tests.sh**: Bash script to run XCUITests via CLI. Outputs colored pass/fail summary and saves results to xcresult bundle.
- **parse_results.sh**: Parses xcresult bundle to JSON. Supports --summary, --tests, and --failures modes.
