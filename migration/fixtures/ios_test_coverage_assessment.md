# iOS Test Coverage Assessment

## Well-covered areas
- Core looper engine behavior is strong at the unit-test layer. `Tests/MultiTrackLooperTests.swift` and `Tests/PlaybackSyncTests.swift` cover record/start/stop, pause/resume, loop math, seek behavior, track lifecycle, and synchronization.
- Quantization and note-shape logic are well covered by `Tests/QuantizerTests.swift` and `Tests/MidiNoteTests.swift`.
- Track-editor behavior is strong at the view-model level. `Tests/TrackFocusViewModelTests.swift` covers selection, drag/resize, add/delete, copy/paste offsets, multi-drag, grid snapping, quantization, and note preview.
- Mixer-domain behavior is well covered in unit tests. `Tests/TrackVolumeTests.swift` and `Tests/SoloMuteTests.swift` validate volume independence, mute/solo logic, and audibility rules.
- Working-session persistence is reasonably covered by `Tests/WorkingSessionTests.swift`.
- UI smoke coverage exists for the main transport controls via `Tests/UI/TransportControlsUITests.swift` and `Tests/UI/RegressionTests.swift`.

## Gaps (no tests or shallow tests)
- UI coverage is transport-heavy and does not deeply exercise the shipped feature surface beyond the main control cluster.
- There are no robust UI tests for opening `TracksView`, using mixer controls, navigating into `TrackFocusView`, or editing notes through real canvas/drum-grid gestures.
- Vocal flows are lightly covered or uncovered: microphone permission alerts, headphone recommendation flow, vocal count-in, live waveform behavior, and audio-session transitions are not comprehensively tested.
- Session flows are lightly covered or uncovered: save/load/delete/import/export UI paths are not deeply exercised end-to-end.
- `BPMEditorView`, settings/about screens, metronome toggle, bar-count changes, octave controls, and loop seeking are not meaningfully covered by UI automation.
- `TracksViewModel` has no dedicated test file; most of its behavior is only exercised indirectly.
- `ScreenshotTests.swift` is not currently a reliable parity oracle outside Fastlane because `snapshot()` is stubbed as a no-op when `SnapshotHelper` is unavailable.
- Some compiled-but-dormant files in the app target (`AudioEngine.swift`, `MidiLooper.swift`, `LoopStorage.swift`, `MidiExporter.swift`) are not relevant to current shipped UI behavior and should not be treated as parity-critical just because they compile.

## Timing-sensitive tests
- UI tests use many fixed `Thread.sleep(...)` delays, especially around recording, count-in, pause/resume, and screenshot timing.
- Several UI tests stop recording after `0.5s` to `0.8s`, which is shorter than the real 4-beat count-in at 100 BPM (~2.4s). Those tests still pass, but they do not prove a complete musical record cycle.
- Unit tests in `MultiTrackLooperTests.swift`, `PlaybackSyncTests.swift`, and `MidiLooperTests.swift` also rely on wall-clock sleeps for timing assertions.
- Timing-sensitive shipped code includes `LooperViewModel` count-in timers, delayed preview-note stop logic, delayed piano-roll scroll setup, and recurring vocal metering timers.

## Accessibility identifiers present
- `recordButton` — `UI/Screens/LooperView.swift`
- `playPauseButton` — `UI/Screens/LooperView.swift`
- `restartButton` — `UI/Screens/LooperView.swift`
- `quantizeButton` — `UI/Screens/LooperView.swift`
- `tracksButton` — `UI/Screens/LooperView.swift`
- `bpmButton` — `UI/Screens/LooperView.swift`
- `deleteButton_<track.id>` — `UI/Components/TrackMixerRow.swift`
- `muteButton_<track.id>` — `UI/Components/TrackMixerRow.swift`
- `soloButton_<track.id>` — `UI/Components/TrackMixerRow.swift`
- `quantizeButton_<track.id>` — `UI/Components/TrackMixerRow.swift`
- `loopButton_<track.id>` — `UI/Components/TrackMixerRow.swift`
- `volumeSlider_<track.id>` — `UI/Components/TrackMixerRow.swift`
- `instrumentButton_<track.id>` — `UI/Components/TrackMixerRow.swift`

## Accessibility identifiers missing
- Instrument picker menu on the main screen
- Metronome toggle
- Bar-count picker
- Overflow menu button and its menu actions
- Octave up/down controls
- Beat strip / seek gestures / progress drag surface
- Save-sheet text field and actions
- Load-sheet rows and delete actions
- Settings screen rows/buttons/links
- About screen links/buttons
- Tracks screen `Done`, header transport buttons, and track row primary tap target
- Track editor controls: close, transport, grid-step menu, add/delete/multi-select toggles, copy/paste, quantize, undo, zoom, hide-empty-rows
- Piano-roll canvas gestures and playhead drag surface
- Drum-grid cells
- Full keyboard / drum-pad live input surface

## Visual-baseline capture note
- Maestro flows were present in `ios/.maestro/` but not runnable on this machine because the installed Java runtime was `1.8` and Maestro requires Java 17+.
- Because `ScreenshotTests.swift` did not emit exportable screenshots outside Fastlane, the screenshot baseline for this run was taken from exported `xcresult` attachments from the passing UI suite.
- Result: six canonical transport screenshots were captured (`initial_state`, `recording_in_progress`, `track_recorded`, `paused`, `playing`, `restarted`), but mixer/editor/vocal-mode screenshots remain gaps in this baseline run.
