# Loopa — Android Parity Matrix

Tracks feature-by-feature parity between the shipped iOS app and the Android port.

| Feature | iOS Source | iOS Test | Android Source | Android Test | Artifact | Status |
|---------|-----------|----------|---------------|-------------|----------|--------|
| **Design System** | | | | | | |
| Color palette (named tokens) | `UI/Theme/DesignSystem.swift` | — | | | | `not_started` |
| Color palette (inline hex) | Various screens | — | | | | `not_started` |
| Typography | `UI/Theme/DesignSystem.swift` | — | | | | `not_started` |
| Spacing tokens | `UI/Theme/DesignSystem.swift` | — | | | | `not_started` |
| Radius tokens | `UI/Theme/DesignSystem.swift` | — | | | | `not_started` |
| Button styles | `UI/Theme/DesignSystem.swift` | — | | | | `not_started` |
| **Data Models** | | | | | | |
| TrackType enum | `Models/Track.swift` | — | | | | `not_started` |
| Instrument enum | `Models/Track.swift` | `MultiTrackLooperTests` | | | | `not_started` |
| BarCount enum | `Models/Track.swift` | `MultiTrackLooperTests` | | | | `not_started` |
| QuantizeDivision enum | `Looper/Quantizer.swift` | `QuantizerTests` | | | | `not_started` |
| MidiNote model | `Models/MidiNote.swift` | `MidiNoteTests` | | | | `not_started` |
| MidiEvent model | `Looper/MidiEvent.swift` | — | | | | `not_started` |
| Track model | `Models/Track.swift` | `SoloMuteTests`, `TrackVolumeTests` | | | | `not_started` |
| SavedSession model | `Models/Track.swift` | `WorkingSessionTests` | | | | `not_started` |
| MidiNote ↔ MidiEvent conversion | `Models/MidiNote.swift` | `MidiNoteTests` | | | | `not_started` |
| **Pure Logic** | | | | | | |
| Quantizer (time-based) | `Looper/Quantizer.swift` | `QuantizerTests` | | | | `not_started` |
| Quantizer (beat-based) | `Looper/Quantizer.swift` | `MidiNoteTests` | | | | `not_started` |
| Quantizer (static helpers) | `Looper/Quantizer.swift` | `MidiNoteTests` | | | | `not_started` |
| Solo/Mute audibility | `Models/Track.swift` | `SoloMuteTests` | | | | `not_started` |
| Track volume independence | `Looper/MultiTrackLooper.swift` | `TrackVolumeTests` | | | | `not_started` |
| **Storage** | | | | | | |
| SessionStorage (named sessions) | `Models/SessionStorage.swift` | `WorkingSessionTests` | | | | `not_started` |
| SessionStorage (working session) | `Models/SessionStorage.swift` | `WorkingSessionTests` | | | | `not_started` |
| SessionExporter (.loopa export) | `Models/SessionExporter.swift` | — | | | | `not_started` |
| SessionExporter (.loopa import) | `Models/SessionExporter.swift` | — | | | | `not_started` |
| Dual date encoding | `Models/SessionStorage.swift` / `SessionExporter.swift` | — | | | | `not_started` |
| **Audio** | | | | | | |
| LooperAudioEngine | `Audio/LooperAudioEngine.swift` | — | | | | `not_started` |
| KeyboardSampler | `Audio/KeyboardSampler.swift` | `KeyboardSamplerTests` | | | | `not_started` |
| VocalRecorder | `Audio/VocalRecorder.swift` | — | | | | `not_started` |
| Metronome | `Audio/Metronome.swift` | — | | | | `not_started` |
| HapticManager | `Audio/HapticManager.swift` | — | | | | `not_started` |
| AudioExporter (M4A) | `Audio/AudioExporter.swift` | — | | | | `not_started` |
| MidiExporter (.mid) | `Looper/MidiExporter.swift` | — | | | | `not_started` |
| FluidSynth + GM.sf2 loading | — | — | | | | `not_started` |
| **Looper Engine** | | | | | | |
| MultiTrackLooper (recording) | `Looper/MultiTrackLooper.swift` | `MultiTrackLooperTests` | | | | `not_started` |
| MultiTrackLooper (playback) | `Looper/MultiTrackLooper.swift` | `MultiTrackLooperTests` | | | | `not_started` |
| MultiTrackLooper (pause/resume) | `Looper/MultiTrackLooper.swift` | `PlaybackSyncTests` | | | | `not_started` |
| MultiTrackLooper (seek) | `Looper/MultiTrackLooper.swift` | `PlaybackSyncTests` | | | | `not_started` |
| MultiTrackLooper (mute/solo/loop) | `Looper/MultiTrackLooper.swift` | `SoloMuteTests` | | | | `not_started` |
| MultiTrackLooper (multi-bar recording) | `Looper/MultiTrackLooper.swift` | `MultiTrackLooperTests` | | | | `not_started` |
| Playback synchronization | `Looper/MultiTrackLooper.swift` | `PlaybackSyncTests` | | | | `not_started` |
| **ViewModels** | | | | | | |
| LooperViewModel (transport) | `ViewModels/LooperViewModel.swift` | `ViewModelTests` | | | | `not_started` |
| LooperViewModel (count-in) | `ViewModels/LooperViewModel.swift` | `ViewModelTests` | | | | `not_started` |
| LooperViewModel (instruments) | `ViewModels/LooperViewModel.swift` | `ViewModelTests` | | | | `not_started` |
| LooperViewModel (sessions) | `ViewModels/LooperViewModel.swift` | `WorkingSessionTests` | | | | `not_started` |
| LooperViewModel (vocal mode) | `ViewModels/LooperViewModel.swift` | — | | | | `not_started` |
| LooperViewModel (export) | `ViewModels/LooperViewModel.swift` | — | | | | `not_started` |
| TracksViewModel | `ViewModels/TracksViewModel.swift` | — | | | | `not_started` |
| TrackFocusViewModel (selection) | `ViewModels/TrackFocusViewModel.swift` | `TrackFocusViewModelTests` | | | | `not_started` |
| TrackFocusViewModel (move/resize) | `ViewModels/TrackFocusViewModel.swift` | `TrackFocusViewModelTests` | | | | `not_started` |
| TrackFocusViewModel (add/delete) | `ViewModels/TrackFocusViewModel.swift` | `TrackFocusViewModelTests` | | | | `not_started` |
| TrackFocusViewModel (copy/paste) | `ViewModels/TrackFocusViewModel.swift` | `TrackFocusViewModelTests` | | | | `not_started` |
| TrackFocusViewModel (multi-drag) | `ViewModels/TrackFocusViewModel.swift` | `TrackFocusViewModelTests` | | | | `not_started` |
| TrackFocusViewModel (undo) | `ViewModels/TrackFocusViewModel.swift` | `TrackFocusViewModelTests` | | | | `not_started` |
| TrackFocusViewModel (zoom) | `ViewModels/TrackFocusViewModel.swift` | `TrackFocusViewModelTests` | | | | `not_started` |
| **UI — Main Screen** | | | | | | |
| LooperScreen layout | `UI/Screens/LooperView.swift` | `TransportControlsUITests` | | | | `not_started` |
| Transport controls | `UI/Screens/LooperView.swift` | `TransportControlsUITests` | | | | `not_started` |
| Instrument selector | `UI/Screens/LooperView.swift` | — | | | | `not_started` |
| FullKeyboardView (piano) | `UI/Components/FullKeyboardView.swift` | — | | | | `not_started` |
| FullKeyboardView (drum pads) | `UI/Components/FullKeyboardView.swift` | — | | | | `not_started` |
| KeyboardLayoutEngine | `UI/Components/KeyboardLayoutEngine.swift` | — | | | | `not_started` |
| VocalWaveformView | `UI/Components/VocalWaveformView.swift` | — | | | | `not_started` |
| BPMEditorView | `UI/Components/BPMEditorView.swift` | — | | | | `not_started` |
| Loop progress bar | `UI/Screens/LooperView.swift` | — | | | | `not_started` |
| Octave controls | `UI/Screens/LooperView.swift` | — | | | | `not_started` |
| **UI — Secondary Screens** | | | | | | |
| TracksScreen | `UI/Screens/TracksView.swift` | — | | | | `not_started` |
| TrackMixerRow | `UI/Components/TrackMixerRow.swift` | — | | | | `not_started` |
| TrackFocusScreen | `UI/Screens/TrackFocusView.swift` | — | | | | `not_started` |
| PianoRollCanvasView | `UI/Components/PianoRollCanvasView.swift` | — | | | | `not_started` |
| DrumGridView | `UI/Components/DrumGridView.swift` | — | | | | `not_started` |
| SettingsScreen | `UI/Screens/SettingsView.swift` | — | | | | `not_started` |
| AboutScreen | `UI/Screens/AboutView.swift` | — | | | | `not_started` |
| Navigation (sheets/dialogs) | Various | — | | | | `not_started` |
| **Integration** | | | | | | |
| Session save/load flow | `Tish88App.swift` / `LooperView.swift` | `WorkingSessionTests` | | | | `not_started` |
| Auto-save on lifecycle | `Tish88App.swift` | — | | | | `not_started` |
| .loopa import via intent | `Tish88App.swift` | — | | | | `not_started` |
| M4A export + share | `Audio/AudioExporter.swift` | — | | | | `not_started` |
| MIDI export | `Looper/MidiExporter.swift` | — | | | | `not_started` |
| **Android-Specific** | | | | | | |
| Back button handling | — | — | | | | `not_started` |
| Audio focus management | — | — | | | | `not_started` |
| Process death recovery | — | — | | | | `not_started` |
| ProGuard/R8 rules | — | — | | | | `not_started` |
| Adaptive icon | — | — | | | | `not_started` |
| Landscape lock stability | — | — | | | | `not_started` |
| Play Store release prep | — | — | | | | `not_started` |
