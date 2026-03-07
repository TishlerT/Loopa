# Loopa — Android Parity Matrix

Tracks feature-by-feature parity between the shipped iOS app and the Android port.

| Feature | iOS Source | iOS Test | Android Source | Android Test | Artifact | Status |
|---------|-----------|----------|---------------|-------------|----------|--------|
| **Design System** | | | | | | |
| Color palette (named tokens) | `UI/Theme/DesignSystem.swift` | — | `android-app/feature/looper/src/main/java/com/loopa/app/ui/theme/Color.kt` | `DesignSystemTest` | | `ported` |
| Color palette (inline hex) | Various screens | — | `android-app/feature/looper/src/main/java/com/loopa/app/ui/theme/Theme.kt` | `DesignSystemTest` | | `ported` |
| Typography | `UI/Theme/DesignSystem.swift` | — | `android-app/feature/looper/src/main/java/com/loopa/app/ui/theme/Type.kt` | `DesignSystemTest` | | `ported` |
| Spacing tokens | `UI/Theme/DesignSystem.swift` | — | `android-app/feature/looper/src/main/java/com/loopa/app/ui/theme/Spacing.kt` | `DesignSystemTest` | | `ported` |
| Radius tokens | `UI/Theme/DesignSystem.swift` | — | `android-app/feature/looper/src/main/java/com/loopa/app/ui/theme/Radius.kt` | `DesignSystemTest` | | `ported` |
| Button styles | `UI/Theme/DesignSystem.swift` | — | `android-app/feature/looper/src/main/java/com/loopa/app/ui/components/TishButtonStyle.kt` | `DesignSystemTest` | | `ported` |
| **Data Models** | | | | | | |
| TrackType enum | `Models/Track.swift` | — | `android-app/core/model/src/main/java/com/loopa/core/model/TrackType.kt` | `InstrumentTest` | | `ported` |
| Instrument enum | `Models/Track.swift` | `MultiTrackLooperTests` | `android-app/core/model/src/main/java/com/loopa/core/model/Instrument.kt` | `InstrumentTest` | | `ported` |
| BarCount enum | `Models/Track.swift` | `MultiTrackLooperTests` | `android-app/core/model/src/main/java/com/loopa/core/model/BarCount.kt` | `InstrumentTest` | | `ported` |
| QuantizeDivision enum | `Looper/Quantizer.swift` | `QuantizerTests` | `android-app/core/model/src/main/java/com/loopa/core/model/QuantizeDivision.kt` | `QuantizerTest` | | `ported` |
| MidiNote model | `Models/MidiNote.swift` | `MidiNoteTests` | `android-app/core/model/src/main/java/com/loopa/core/model/MidiNote.kt` | `MidiNoteTest` | | `ported` |
| MidiEvent model | `Looper/MidiEvent.swift` | — | `android-app/core/model/src/main/java/com/loopa/core/model/MidiEvent.kt` | `MidiNoteTest` | | `ported` |
| Track model | `Models/Track.swift` | `SoloMuteTests`, `TrackVolumeTests` | `android-app/core/model/src/main/java/com/loopa/core/model/Track.kt` | `SoloMuteTest`, `TrackVolumeTest` | | `ported` |
| SavedSession model | `Models/Track.swift` | `WorkingSessionTests` | `android-app/core/model/src/main/java/com/loopa/core/model/SavedSession.kt` | `SessionStorageTest` | | `ported` |
| MidiNote ↔ MidiEvent conversion | `Models/MidiNote.swift` | `MidiNoteTests` | `android-app/core/model/src/main/java/com/loopa/core/model/MidiNote.kt` | `MidiNoteTest` | | `ported` |
| **Pure Logic** | | | | | | |
| Quantizer (time-based) | `Looper/Quantizer.swift` | `QuantizerTests` | `android-app/core/looper/src/main/java/com/loopa/core/looper/Quantizer.kt` | `QuantizerTest` | | `ported` |
| Quantizer (beat-based) | `Looper/Quantizer.swift` | `MidiNoteTests` | `android-app/core/looper/src/main/java/com/loopa/core/looper/Quantizer.kt` | `QuantizerTest` | | `ported` |
| Quantizer (static helpers) | `Looper/Quantizer.swift` | `MidiNoteTests` | `android-app/core/looper/src/main/java/com/loopa/core/looper/Quantizer.kt` | `QuantizerTest` | | `ported` |
| Solo/Mute audibility | `Models/Track.swift` | `SoloMuteTests` | `android-app/core/model/src/main/java/com/loopa/core/model/Track.kt` | `SoloMuteTest` | | `ported` |
| Track volume independence | `Looper/MultiTrackLooper.swift` | `TrackVolumeTests` | `android-app/core/looper/src/main/java/com/loopa/core/looper/MultiTrackLooper.kt` | `TrackVolumeTest` | | `ported` |
| **Storage** | | | | | | |
| SessionStorage (named sessions) | `Models/SessionStorage.swift` | `WorkingSessionTests` | `android-app/core/storage/src/main/java/com/loopa/core/storage/SessionStorage.kt` | `SessionStorageTest` | | `ported` |
| SessionStorage (working session) | `Models/SessionStorage.swift` | `WorkingSessionTests` | `android-app/core/storage/src/main/java/com/loopa/core/storage/SessionStorage.kt` | `SessionStorageTest` | | `ported` |
| SessionExporter (.loopa export) | `Models/SessionExporter.swift` | — | `android-app/core/storage/src/main/java/com/loopa/core/storage/SessionExporter.kt` | `SessionStorageTest` | | `ported` |
| SessionExporter (.loopa import) | `Models/SessionExporter.swift` | — | `android-app/core/storage/src/main/java/com/loopa/core/storage/SessionExporter.kt` | `SessionStorageTest` | | `ported` |
| Dual date encoding | `Models/SessionStorage.swift` / `SessionExporter.swift` | — | `android-app/core/storage/src/main/java/com/loopa/core/storage/SessionStorage.kt`, `SessionExporter.kt` | `SessionStorageTest` | | `ported` |
| **Audio** | | | | | | |
| LooperAudioEngine | `Audio/LooperAudioEngine.swift` | — | `android-app/audio/src/main/java/com/loopa/audio/LooperAudioEngine.kt` | `LooperAudioEngineTest` | | `ported_deferred_local` |
| KeyboardSampler | `Audio/KeyboardSampler.swift` | `KeyboardSamplerTests` | `android-app/audio/src/main/java/com/loopa/audio/KeyboardSampler.kt` | `KeyboardSamplerTest` | | `ported_deferred_local` |
| VocalRecorder | `Audio/VocalRecorder.swift` | — | `android-app/audio/src/main/java/com/loopa/audio/VocalRecorder.kt` | — | | `ported_deferred_local` |
| Metronome | `Audio/Metronome.swift` | — | `android-app/audio/src/main/java/com/loopa/audio/Metronome.kt` | `MetronomeTest` | | `ported_deferred_local` |
| HapticManager | `Audio/HapticManager.swift` | — | `android-app/audio/src/main/java/com/loopa/audio/HapticManager.kt` | — | | `ported_deferred_local` |
| AudioExporter (M4A) | `Audio/AudioExporter.swift` | — | `android-app/audio/src/main/java/com/loopa/audio/AudioExporter.kt` | `AudioExporterTest` | | `ported_deferred_local` |
| MidiExporter (.mid) | `Looper/MidiExporter.swift` | — | `android-app/core/looper/src/main/java/com/loopa/core/looper/MidiExporter.kt` | — | | `ported_deferred_local` |
| FluidSynth + GM.sf2 loading | — | — | `android-app/audio/src/main/java/com/loopa/audio/FluidSynthEngine.kt` | — | | `ported_deferred_local` |
| **Looper Engine** | | | | | | |
| MultiTrackLooper (recording) | `Looper/MultiTrackLooper.swift` | `MultiTrackLooperTests` | `android-app/core/looper/src/main/java/com/loopa/core/looper/MultiTrackLooper.kt` | `MultiTrackLooperTest` | | `ported` |
| MultiTrackLooper (playback) | `Looper/MultiTrackLooper.swift` | `MultiTrackLooperTests` | `android-app/core/looper/src/main/java/com/loopa/core/looper/MultiTrackLooper.kt` | `MultiTrackLooperTest` | | `ported` |
| MultiTrackLooper (pause/resume) | `Looper/MultiTrackLooper.swift` | `PlaybackSyncTests` | `android-app/core/looper/src/main/java/com/loopa/core/looper/MultiTrackLooper.kt` | `MultiTrackLooperTest` | | `ported` |
| MultiTrackLooper (seek) | `Looper/MultiTrackLooper.swift` | `PlaybackSyncTests` | `android-app/core/looper/src/main/java/com/loopa/core/looper/MultiTrackLooper.kt` | `MultiTrackLooperTest` | | `ported` |
| MultiTrackLooper (mute/solo/loop) | `Looper/MultiTrackLooper.swift` | `SoloMuteTests` | `android-app/core/looper/src/main/java/com/loopa/core/looper/MultiTrackLooper.kt` | `SoloMuteTest` | | `ported` |
| MultiTrackLooper (multi-bar recording) | `Looper/MultiTrackLooper.swift` | `MultiTrackLooperTests` | `android-app/core/looper/src/main/java/com/loopa/core/looper/MultiTrackLooper.kt` | `MultiTrackLooperTest` | | `ported` |
| Playback synchronization | `Looper/MultiTrackLooper.swift` | `PlaybackSyncTests` | `android-app/core/looper/src/main/java/com/loopa/core/looper/MultiTrackLooper.kt` | `MultiTrackLooperTest` | | `ported` |
| **ViewModels** | | | | | | |
| LooperViewModel (transport) | `ViewModels/LooperViewModel.swift` | `ViewModelTests` | `android-app/feature/looper/src/main/java/com/loopa/feature/looper/LooperViewModel.kt` | `LooperViewModelTest` | | `ported` |
| LooperViewModel (count-in) | `ViewModels/LooperViewModel.swift` | `ViewModelTests` | `android-app/feature/looper/src/main/java/com/loopa/feature/looper/LooperViewModel.kt` | `LooperViewModelTest` | | `ported` |
| LooperViewModel (instruments) | `ViewModels/LooperViewModel.swift` | `ViewModelTests` | `android-app/feature/looper/src/main/java/com/loopa/feature/looper/LooperViewModel.kt` | `LooperViewModelTest` | | `ported` |
| LooperViewModel (sessions) | `ViewModels/LooperViewModel.swift` | `WorkingSessionTests` | `android-app/feature/looper/src/main/java/com/loopa/feature/looper/LooperViewModel.kt` | `LooperViewModelTest`, `SessionStorageTest` | | `ported` |
| LooperViewModel (vocal mode) | `ViewModels/LooperViewModel.swift` | — | `android-app/feature/looper/src/main/java/com/loopa/feature/looper/LooperViewModel.kt` | `LooperViewModelTest` | | `ported` |
| LooperViewModel (export) | `ViewModels/LooperViewModel.swift` | — | `android-app/feature/looper/src/main/java/com/loopa/feature/looper/LooperViewModel.kt` | `LooperViewModelTest` | | `ported` |
| TracksViewModel | `ViewModels/TracksViewModel.swift` | — | `android-app/feature/tracks/src/main/java/com/loopa/feature/tracks/TracksViewModel.kt` | — | | `ported` |
| TrackFocusViewModel (selection) | `ViewModels/TrackFocusViewModel.swift` | `TrackFocusViewModelTests` | `android-app/feature/editor/src/main/java/com/loopa/feature/editor/TrackFocusViewModel.kt` | `TrackFocusViewModelTest` | | `ported` |
| TrackFocusViewModel (move/resize) | `ViewModels/TrackFocusViewModel.swift` | `TrackFocusViewModelTests` | `android-app/feature/editor/src/main/java/com/loopa/feature/editor/TrackFocusViewModel.kt` | `TrackFocusViewModelTest` | | `ported` |
| TrackFocusViewModel (add/delete) | `ViewModels/TrackFocusViewModel.swift` | `TrackFocusViewModelTests` | `android-app/feature/editor/src/main/java/com/loopa/feature/editor/TrackFocusViewModel.kt` | `TrackFocusViewModelTest` | | `ported` |
| TrackFocusViewModel (copy/paste) | `ViewModels/TrackFocusViewModel.swift` | `TrackFocusViewModelTests` | `android-app/feature/editor/src/main/java/com/loopa/feature/editor/TrackFocusViewModel.kt` | `TrackFocusViewModelTest` | | `ported` |
| TrackFocusViewModel (multi-drag) | `ViewModels/TrackFocusViewModel.swift` | `TrackFocusViewModelTests` | `android-app/feature/editor/src/main/java/com/loopa/feature/editor/TrackFocusViewModel.kt` | `TrackFocusViewModelTest` | | `ported` |
| TrackFocusViewModel (undo) | `ViewModels/TrackFocusViewModel.swift` | `TrackFocusViewModelTests` | `android-app/feature/editor/src/main/java/com/loopa/feature/editor/TrackFocusViewModel.kt` | `TrackFocusViewModelTest` | | `ported` |
| TrackFocusViewModel (zoom) | `ViewModels/TrackFocusViewModel.swift` | `TrackFocusViewModelTests` | `android-app/feature/editor/src/main/java/com/loopa/feature/editor/TrackFocusViewModel.kt` | `TrackFocusViewModelTest` | | `ported` |
| **UI — Main Screen** | | | | | | |
| LooperScreen layout | `UI/Screens/LooperView.swift` | `TransportControlsUITests` | `android-app/feature/looper/src/main/java/com/loopa/feature/looper/ui/LooperScreen.kt` | — | | `ported_deferred_local` |
| Transport controls | `UI/Screens/LooperView.swift` | `TransportControlsUITests` | `android-app/feature/looper/src/main/java/com/loopa/feature/looper/ui/TransportControls.kt` | — | | `ported_deferred_local` |
| Instrument selector | `UI/Screens/LooperView.swift` | — | `android-app/feature/looper/src/main/java/com/loopa/feature/looper/ui/LooperScreen.kt` | — | | `ported_deferred_local` |
| FullKeyboardView (piano) | `UI/Components/FullKeyboardView.swift` | — | `android-app/feature/looper/src/main/java/com/loopa/feature/looper/ui/FullKeyboardView.kt` | — | | `ported_deferred_local` |
| FullKeyboardView (drum pads) | `UI/Components/FullKeyboardView.swift` | — | `android-app/feature/looper/src/main/java/com/loopa/feature/looper/ui/FullKeyboardView.kt` | — | | `ported_deferred_local` |
| KeyboardLayoutEngine | `UI/Components/KeyboardLayoutEngine.swift` | — | `android-app/feature/looper/src/main/java/com/loopa/feature/looper/ui/FullKeyboardView.kt` | — | | `ported_deferred_local` |
| VocalWaveformView | `UI/Components/VocalWaveformView.swift` | — | `android-app/feature/looper/src/main/java/com/loopa/feature/looper/ui/VocalWaveformView.kt` | — | | `ported_deferred_local` |
| BPMEditorView | `UI/Components/BPMEditorView.swift` | — | `android-app/feature/looper/src/main/java/com/loopa/feature/looper/ui/BPMEditorView.kt` | — | | `ported_deferred_local` |
| Loop progress bar | `UI/Screens/LooperView.swift` | — | `android-app/feature/looper/src/main/java/com/loopa/feature/looper/ui/LooperScreen.kt` | — | | `ported_deferred_local` |
| Octave controls | `UI/Screens/LooperView.swift` | — | `android-app/feature/looper/src/main/java/com/loopa/feature/looper/ui/LooperScreen.kt` | — | | `ported_deferred_local` |
| **UI — Secondary Screens** | | | | | | |
| TracksScreen | `UI/Screens/TracksView.swift` | — | `android-app/feature/tracks/src/main/java/com/loopa/feature/tracks/ui/TracksScreen.kt` | — | | `ported_deferred_local` |
| TrackMixerRow | `UI/Components/TrackMixerRow.swift` | — | `android-app/feature/tracks/src/main/java/com/loopa/feature/tracks/ui/TrackMixerRow.kt` | — | | `ported_deferred_local` |
| TrackFocusScreen | `UI/Screens/TrackFocusView.swift` | — | `android-app/feature/editor/src/main/java/com/loopa/feature/editor/ui/TrackFocusScreen.kt` | — | | `ported_deferred_local` |
| PianoRollCanvasView | `UI/Components/PianoRollCanvasView.swift` | — | `android-app/feature/editor/src/main/java/com/loopa/feature/editor/ui/PianoRollCanvasView.kt` | — | | `ported_deferred_local` |
| DrumGridView | `UI/Components/DrumGridView.swift` | — | `android-app/feature/editor/src/main/java/com/loopa/feature/editor/ui/DrumGridView.kt` | — | | `ported_deferred_local` |
| SettingsScreen | `UI/Screens/SettingsView.swift` | — | `android-app/app/src/main/java/com/loopa/app/ui/SettingsScreen.kt` | — | | `ported_deferred_local` |
| AboutScreen | `UI/Screens/AboutView.swift` | — | `android-app/app/src/main/java/com/loopa/app/ui/AboutScreen.kt` | — | | `ported_deferred_local` |
| Navigation (sheets/dialogs) | Various | — | `android-app/app/src/main/java/com/loopa/app/ui/BackHandler.kt`, `LooperScreen.kt` | — | | `ported_deferred_local` |
| **Integration** | | | | | | |
| Session save/load flow | `Tish88App.swift` / `LooperView.swift` | `WorkingSessionTests` | `android-app/feature/looper/src/main/java/com/loopa/feature/looper/LooperViewModel.kt`, `SessionStorage.kt` | `SessionStorageTest`, `LooperViewModelTest` | | `ported_deferred_local` |
| Auto-save on lifecycle | `Tish88App.swift` | — | `android-app/app/src/main/java/com/loopa/app/MainActivity.kt` | — | | `ported_deferred_local` |
| .loopa import via intent | `Tish88App.swift` | — | `android-app/core/storage/src/main/java/com/loopa/core/storage/SessionExporter.kt` | — | | `ported_deferred_local` |
| M4A export + share | `Audio/AudioExporter.swift` | — | `android-app/audio/src/main/java/com/loopa/audio/AudioExporter.kt`, `SessionExporter.kt` | `AudioExporterTest` | | `ported_deferred_local` |
| MIDI export | `Looper/MidiExporter.swift` | — | `android-app/core/looper/src/main/java/com/loopa/core/looper/MidiExporter.kt` | — | | `ported_deferred_local` |
| **Android-Specific** | | | | | | |
| Back button handling | — | — | `android-app/app/src/main/java/com/loopa/app/ui/BackHandler.kt` | — | | `ported` |
| Audio focus management | — | — | `android-app/audio/src/main/java/com/loopa/audio/LooperAudioEngine.kt` | — | | `ported` |
| Process death recovery | — | — | `android-app/app/src/main/java/com/loopa/app/MainActivity.kt` | — | | `ported` |
| ProGuard/R8 rules | — | — | `android-app/app/proguard-rules.pro` | — | | `ported` |
| Adaptive icon | — | — | `android-app/app/src/main/res` | — | | `ported` |
| Landscape lock stability | — | — | `android-app/app/src/main/AndroidManifest.xml` | — | | `ported` |
| Play Store release prep | — | — | `android-app/store/listing.md` | — | | `ported` |
