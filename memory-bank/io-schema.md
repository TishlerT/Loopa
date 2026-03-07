# IO Schema

## `LooperViewModel` published interface

| Property | Type | Default |
|----------|------|---------|
| `currentInstrument` | `Instrument` | `.piano` |
| `barCount` | `BarCount` | `.four` |
| `bpm` | `Double` | `100` |
| `isMetronomeOn` | `Bool` | `false` |
| `audioError` | `String?` | `nil` |
| `quantizeDivision` | `QuantizeDivision` | `.off` |
| `isPaused` | `Bool` | `false` |
| `isCountingIn` | `Bool` | `false` |
| `countInBeat` | `Int` | `0` |
| `tracks` | `[Track]` | `[]` |
| `isRecording` | `Bool` | `false` |
| `isPlaying` | `Bool` | `false` |
| `currentPosition` | `Double` | `0` |
| `currentBeat` | `Int` | `0` |
| `recordingProgress` | `Double` | `0` |
| `savedSessions` | `[SavedSession]` | `[]` |
| `currentSessionName` | `String` | `""` |
| `showingSaveSheet` | `Bool` | `false` |
| `showingLoadSheet` | `Bool` | `false` |
| `showingSettings` | `Bool` | `false` |
| `showingTracksSheet` | `Bool` | `false` |
| `showingBPMEditor` | `Bool` | `false` |
| `selectedTrackForFocus` | `Track?` | `nil` |
| `isRecordingVocals` | `Bool` | `false` |
| `showMicPermissionAlert` | `Bool` | `false` |
| `isVocalMode` | `Bool` | `false` |
| `showHeadphoneRecommendation` | `Bool` | `false` |
| `octaveOffset` | `Int` | `0` |
| `isExporting` | `Bool` | `false` |

### `LooperViewModel` computed state
- `countInBeats = 4`
- `keyCount = 25`
- `startNote` clamps to `24...84`, with default `48`
- `currentOctaveName` default is `"C4"`
- `synchronizedPosition: Double`
- `synchronizedProgressFraction: Double`
- `synchronizedBeat: Int`
- `anyTrackSoloed: Bool`
- `loopLengthBeats: Double`
- `loopLengthSeconds: Double`
- `totalBeats: Int`
- `progressFraction: Double`

## `TracksViewModel` published interface

| Property | Type | Default |
|----------|------|---------|
| `tracks` | `[Track]` | `[]` |
| `isPlaying` | `Bool` | `false` |
| `isPaused` | `Bool` | `false` |
| `currentPosition` | `Double` | `0` |
| `selectedTrackId` | `UUID?` | `nil` |
| `showingQuantizeSheet` | `Bool` | `false` |
| `trackToQuantize` | `Track?` | `nil` |
| `showingInstrumentPicker` | `Bool` | `false` |
| `trackToChangeInstrument` | `Track?` | `nil` |
| `selectedTrackForFocus` | `Track?` | `nil` |

### `TracksViewModel` computed state
- `anyTrackSoloed: Bool`
- `loopLengthBeats: Double`
- `bpm: Double`
- `looperViewModel: LooperViewModel`

## `TrackFocusViewModel` published interface

| Property | Type | Default |
|----------|------|---------|
| `isPlaying` | `Bool` | `false` |
| `currentBeat` | `Double` | `0` |
| `track` | `Track` | initializer-provided |
| `selectedNoteId` | `UUID?` | `nil` |
| `selectedNoteIds` | `Set<UUID>` | `[]` |
| `isMultiSelectMode` | `Bool` | `false` |
| `gridStep` | `Double` | `0` |
| `showingQuantizeSheet` | `Bool` | `false` |
| `hideEmptyDrumRows` | `Bool` | `false` |
| `draggedNoteId` | `UUID?` | `nil` |
| `isResizing` | `Bool` | `false` |
| `resizeEdge` | `HorizontalEdge` | `.trailing` |
| `dragPreviewStartBeat` | `Double?` | `nil` |
| `dragPreviewDuration` | `Double?` | `nil` |
| `dragPreviewPitch` | `UInt8?` | `nil` |
| `isResizeMode` | `Bool` | `false` |
| `isAddNoteMode` | `Bool` | `false` |
| `isDeleteMode` | `Bool` | `false` |
| `lastNoteDuration` | `Double` | `0.25` |
| `isMultiDragging` | `Bool` | `false` |
| `multiDragDeltaBeats` | `Double` | `0` |
| `multiDragDeltaPitch` | `Int` | `0` |
| `isPlayheadSelected` | `Bool` | `false` |
| `zoomLevel` | `CGFloat` | `1.0` |
| `verticalZoomLevel` | `CGFloat` | `1.0` |

### `TrackFocusViewModel` computed/editor constants
- `minNoteDuration = 0.125`
- `minZoom = 0.5`
- `maxZoom = 4.0`
- `minVerticalZoom = 0.6`
- `maxVerticalZoom = 2.5`
- `canUndo: Bool`
- `loopLengthBeats: Double`
- `trackLengthBeats: Double`
- `bpm: Double`
- `selectedNote: MidiNote?`
- `pitchRange: ClosedRange<UInt8>` default `48...72`
- `isBackgroundLocked: Bool`
- `canCopy: Bool`
- `canPaste: Bool`

## `Track` shape

| Field | Type | Notes |
|-------|------|-------|
| `id` | `UUID` | Stable track identifier |
| `trackType` | `TrackType` | `"midi"` or `"audio"` |
| `instrumentName` | `String` | Human-readable instrument label or `"Vocals"` |
| `instrumentProgram` | `UInt8` | General MIDI program number |
| `isDrumKit` | `Bool` | `true` only for drum tracks |
| `notes` | `[MidiNote]` | Beat-based MIDI notes; empty for vocal tracks |
| `audioFileName` | `String?` | Non-`nil` for vocal/audio tracks |
| `recordedAt` | `Date` | Track creation date |
| `isMuted` | `Bool` | Per-track mute state |
| `isSolo` | `Bool` | Per-track solo state |
| `volume` | `Float` | `0.0...1.0`, default `0.8` |
| `recordedLengthBeats` | `Double` | Original track length in beats |
| `isLooping` | `Bool` | Whether short tracks repeat to fill the longest loop |

### `Track` derived fields
- `isVocal: Bool`
- `instrument: Instrument?`
- `isAudible(anyTrackSoloed:) -> Bool`

## `MidiNote` shape

| Field | Type | Notes |
|-------|------|-------|
| `id` | `UUID` | Stable note identifier |
| `pitch` | `UInt8` | MIDI note number `0...127` |
| `velocity` | `UInt8` | Clamped to `1...127` |
| `startBeat` | `Double` | Clamped to `>= 0` |
| `durationBeats` | `Double` | Minimum `0.0625` |

### `MidiNote` derived fields
- `endBeat: Double`
- `noteName: String`

## `SavedSession` shape

| Field | Type | Notes |
|-------|------|-------|
| `id` | `UUID` | Session identifier |
| `name` | `String` | User-facing session name |
| `createdAt` | `Date` | Set on initialization |
| `lastModifiedAt` | `Date` | Updated on save/rename |
| `bpm` | `Double` | Session tempo |
| `barCount` | `Int` | Raw bar count value, not enum case name |
| `tracks` | `[Track]` | Full session content |

## `TrackType` enum

| Case | Raw value |
|------|-----------|
| `midi` | `"midi"` |
| `audio` | `"audio"` |

## `Instrument` enum values

| Case | Raw value | Program | `isDrumKit` | Icon |
|------|-----------|---------|-------------|------|
| `piano` | `"Piano"` | `0` | `false` | `pianokeys` |
| `electricPiano` | `"E-Piano"` | `4` | `false` | `pianokeys.inverse` |
| `organ` | `"Organ"` | `16` | `false` | `music.note.house` |
| `guitar` | `"Guitar"` | `24` | `false` | `guitars` |
| `strings` | `"Strings"` | `48` | `false` | `music.quarternote.3` |
| `lead` | `"Lead"` | `80` | `false` | `waveform` |
| `pad` | `"Pad"` | `88` | `false` | `waveform.path` |
| `drums` | `"Drums"` | `0` | `true` | `cylinder.split.1x2.fill` |
| `bass` | `"Bass"` | `32` | `false` | `speaker.wave.2` |

## `BarCount` enum values

| Case | Raw value | Display |
|------|-----------|---------|
| `one` | `1` | `1 bar` |
| `two` | `2` | `2 bars` |
| `four` | `4` | `4 bars` |
| `eight` | `8` | `8 bars` |
| `sixteen` | `16` | `16 bars` |

## `QuantizeDivision` enum values

| Case | Raw value | Beat fraction |
|------|-----------|---------------|
| `off` | `"Off"` | `nil` |
| `quarter` | `"1/4"` | `1.0` |
| `eighth` | `"1/8"` | `0.5` |
| `sixteenth` | `"1/16"` | `0.25` |
| `thirtysecond` | `"1/32"` | `0.125` |

## Design system color constants (`DesignSystem.swift`)

| Token | Hex / value |
|-------|-------------|
| `tishBackground` | `#0D0D0D` |
| `tishSurface` | `#1A1A1A` |
| `tishElevated` | `#242424` |
| `tishAccent` | `#00E5FF` |
| `tishAccentSecondary` | `#FF0080` |
| `tishAccentTertiary` | `#FFB800` |
| `tishRecording` | `#FF3B3B` |
| `tishPlaying` | `#00FF88` |
| `tishOverdub` | `#B366FF` |
| `tishBeat` | `#FFFFFF` with `0.9` opacity |
| `tishDownbeat` | `#00E5FF` |
| `tishTextPrimary` | `#F5F5F5` |
| `tishTextSecondary` | `#9E9E9E` |
| `tishTextTertiary` | `#616161` |
| `tishKeyWhite` | `#F8F8F8` |
| `tishKeyWhitePressed` | `#00E5FF` with `0.3` opacity |
| `tishKeyBlack` | `#1A1A1A` |
| `tishKeyBlackPressed` | `#00E5FF` with `0.5` opacity |
| `tishKeyBorder` | `#333333` |

## Additional live palette repeated in shipped screens
- `#0D0D1A`
- `#1A1A2E`
- `#1A1A30`
- `#2A2A4A`
- `#3A2A4A`
- `#00FFCC`
- `#00CCFF`
- `#34C759`
- `#FF9500`
- `#FF3B30`
- `#4A4A6A`
- `#FFD700`

## Spacing constants

| Token | Value |
|-------|-------|
| `TishSpacing.xs` | `4` |
| `TishSpacing.sm` | `8` |
| `TishSpacing.md` | `12` |
| `TishSpacing.lg` | `16` |
| `TishSpacing.xl` | `24` |
| `TishSpacing.xxl` | `32` |

## Radius constants

| Token | Value |
|-------|-------|
| `TishRadius.sm` | `4` |
| `TishRadius.md` | `8` |
| `TishRadius.lg` | `12` |
| `TishRadius.xl` | `16` |
| `TishRadius.full` | `9999` |

## Typography constants

| Token | Definition |
|-------|------------|
| `tishLargeTitle` | `system 28 bold rounded` |
| `tishTitle` | `system 20 semibold rounded` |
| `tishHeadline` | `system 16 semibold rounded` |
| `tishBody` | `system 14 regular default` |
| `tishCaption` | `system 12 regular default` |
| `tishMono` | `system 16 medium monospaced` |
| `tishMonoLarge` | `system 24 bold monospaced` |
