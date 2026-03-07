# LooperViewModel Published State

## `LooperViewModel`

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `currentInstrument` | `Instrument` | `.piano` | Currently selected live instrument for keyboard/pad input. |
| `barCount` | `BarCount` | `.four` | Current loop length selection in bars. |
| `bpm` | `Double` | `100` | Tempo; forwarded into the looper engine. |
| `isMetronomeOn` | `Bool` | `false` | Click/metronome toggle. |
| `audioError` | `String?` | `nil` | User-visible audio/export error state. |
| `quantizeDivision` | `QuantizeDivision` | `.off` | Global live-recording quantization setting. |
| `isPaused` | `Bool` | `false` | Playback paused state distinct from stopped. |
| `isCountingIn` | `Bool` | `false` | True during the 4-beat pre-record count-in. |
| `countInBeat` | `Int` | `0` | Current visible count-in beat. |
| `tracks` | `[Track]` | `[]` | Full current session track list. |
| `isRecording` | `Bool` | `false` | True while MIDI recording is active. |
| `isPlaying` | `Bool` | `false` | True while transport playback is active. |
| `currentPosition` | `Double` | `0` | Current playback position in seconds. |
| `currentBeat` | `Int` | `0` | Current beat index from the looper engine. |
| `recordingProgress` | `Double` | `0` | Normalized `0...1` recording progress for the current pass. |
| `savedSessions` | `[SavedSession]` | `[]` | Named sessions available in local storage. |
| `currentSessionName` | `String` | `""` | Current session name for save/export UI. |
| `showingSaveSheet` | `Bool` | `false` | Controls save-sheet presentation. |
| `showingLoadSheet` | `Bool` | `false` | Controls load-sheet presentation. |
| `showingSettings` | `Bool` | `false` | Controls settings-sheet presentation. |
| `showingTracksSheet` | `Bool` | `false` | Controls mixer presentation. |
| `showingBPMEditor` | `Bool` | `false` | Controls BPM editor presentation. |
| `selectedTrackForFocus` | `Track?` | `nil` | Selected non-vocal track for editor navigation. |
| `isRecordingVocals` | `Bool` | `false` | True while vocal/audio recording is active. |
| `showMicPermissionAlert` | `Bool` | `false` | Controls microphone-permission alert presentation. |
| `isVocalMode` | `Bool` | `false` | Switches the main surface from keyboard/pads to vocal waveform mode. |
| `showHeadphoneRecommendation` | `Bool` | `false` | Controls the headphone recommendation alert. |
| `octaveOffset` | `Int` | `0` | Keyboard octave shift relative to the default center range. |
| `isExporting` | `Bool` | `false` | True while audio export/share is running. |

### `LooperViewModel` computed or read-only state used by shipped UI
- `countInBeats: Int = 4`
- `synchronizedPosition: Double` — screen-synced playback position from `MultiTrackLooper`
- `synchronizedProgressFraction: Double` — progress-bar source of truth
- `synchronizedBeat: Int` — beat indicator source of truth
- `startNote: UInt8` — base keyboard note; `48` (`C3`) at `octaveOffset = 0`, clamped to `24...84`
- `currentOctaveName: String` — `"C4"` at `octaveOffset = 0`
- `keyCount: Int = 25`
- `anyTrackSoloed: Bool`
- `loopLengthBeats: Double`
- `loopLengthSeconds: Double`
- `totalBeats: Int`
- `progressFraction: Double`

# TracksViewModel Published State

## `TracksViewModel`

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `tracks` | `[Track]` | `[]` | Forwarded current session tracks. |
| `isPlaying` | `Bool` | `false` | Forwarded transport-playing state. |
| `isPaused` | `Bool` | `false` | Forwarded transport-paused state. |
| `currentPosition` | `Double` | `0` | Forwarded playback position in seconds for mixer progress. |
| `selectedTrackId` | `UUID?` | `nil` | Exposed selected-track state; currently not central to the shipped flow. |
| `showingQuantizeSheet` | `Bool` | `false` | Controls per-track quantize sheet presentation. |
| `trackToQuantize` | `Track?` | `nil` | Current track targeted for quantize flow. |
| `showingInstrumentPicker` | `Bool` | `false` | Controls per-track instrument picker presentation. |
| `trackToChangeInstrument` | `Track?` | `nil` | Current track targeted for instrument-change flow. |
| `selectedTrackForFocus` | `Track?` | `nil` | Selected non-vocal track for editor navigation. |

### `TracksViewModel` computed state used by shipped UI
- `anyTrackSoloed: Bool`
- `loopLengthBeats: Double`
- `bpm: Double`
- `looperViewModel: LooperViewModel`

# TrackFocusViewModel Published State

## `TrackFocusViewModel`

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `isPlaying` | `Bool` | `false` | Forwarded transport-playing state for the editor header and playhead. |
| `currentBeat` | `Double` | `0` | Current playhead position in beats. |
| `track` | `Track` | initializer-provided | Editable track snapshot for the current editor session. |
| `selectedNoteId` | `UUID?` | `nil` | Primary selected note in piano-roll mode. |
| `selectedNoteIds` | `Set<UUID>` | `[]` | Multi-selection set. |
| `isMultiSelectMode` | `Bool` | `false` | Enables multi-select editing flow. |
| `gridStep` | `Double` | `0` | Grid snapping step in beats; `0` means off. |
| `showingQuantizeSheet` | `Bool` | `false` | Controls the per-track quantize sheet. |
| `hideEmptyDrumRows` | `Bool` | `false` | Hides drum lanes with no notes. |
| `draggedNoteId` | `UUID?` | `nil` | Note currently being dragged. |
| `isResizing` | `Bool` | `false` | Distinguishes resize vs move during drag. |
| `resizeEdge` | `HorizontalEdge` | `.trailing` | Active resize edge. |
| `dragPreviewStartBeat` | `Double?` | `nil` | Preview start beat during drag/resize. |
| `dragPreviewDuration` | `Double?` | `nil` | Preview duration during drag/resize. |
| `dragPreviewPitch` | `UInt8?` | `nil` | Preview pitch during drag. |
| `isResizeMode` | `Bool` | `false` | Toggles explicit resize mode. |
| `isAddNoteMode` | `Bool` | `false` | Tapping empty space adds notes when true. |
| `isDeleteMode` | `Bool` | `false` | Tapping notes deletes them when true. |
| `lastNoteDuration` | `Double` | `0.25` | New-note default duration in beats. |
| `isMultiDragging` | `Bool` | `false` | True while multiple selected notes are being dragged together. |
| `multiDragDeltaBeats` | `Double` | `0` | Beat delta preview during multi-drag. |
| `multiDragDeltaPitch` | `Int` | `0` | Pitch delta preview during multi-drag. |
| `isPlayheadSelected` | `Bool` | `false` | Whether the playhead is selected for dragging. |
| `zoomLevel` | `CGFloat` | `1.0` | Horizontal zoom multiplier. |
| `verticalZoomLevel` | `CGFloat` | `1.0` | Vertical zoom multiplier. |

### `TrackFocusViewModel` computed/editor constants
- `minNoteDuration: Double = 0.125`
- `maxUndoSteps: Int = 50`
- `minZoom: CGFloat = 0.5`
- `maxZoom: CGFloat = 4.0`
- `minVerticalZoom: CGFloat = 0.6`
- `maxVerticalZoom: CGFloat = 2.5`
- `canUndo: Bool`
- `loopLengthBeats: Double`
- `trackLengthBeats: Double`
- `bpm: Double`
- `selectedNote: MidiNote?`
- `pitchRange: ClosedRange<UInt8>` — defaults to `48...72` when no notes exist
- `isBackgroundLocked: Bool`
- `canCopy: Bool`
- `canPaste: Bool`
- `selectedNotes: [MidiNote]`

# Observable-state parity notes
- `LooperViewModel` is the parity-critical source of truth for transport, recording, count-in, sessions, vocal mode, export, and the main playable surface.
- `TracksViewModel` is a presentation wrapper over shared looper state; Android does not need a separate domain engine here, but it does need equivalent presentation state for per-track modal flows.
- `TrackFocusViewModel` contains the bulk of editor-specific transient state that Android will need to mirror for piano-roll and drum-grid UX parity.
