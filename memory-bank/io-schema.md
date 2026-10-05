# IO Schema

Updated API additions below describe the iOS source as of 2026-10-05. Pending session-revision/UI integration is not implied.

## `LooperViewModel` published interface

| Property | Type | Default |
|----------|------|---------|
| `currentInstrument` | `Instrument` | `.piano` |
| `barCount` | `BarCount` | `.four` |
| `bpm` | `Double` | `100` |
| `isMetronomeOn` | `Bool` | `false` |
| `audioError` | `String?` | `nil` |
| `persistenceError` | `String?` | `nil` |
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

## Explicit persistence outcomes

`SessionStorageError` records operation (`read`, `decode`, `encode`, `write`, `remove`), file URL and underlying error. Present user-facing messages through the view model; do not expose local paths in product UI.

- `readSessionsResult() -> Result<[SavedSession], SessionStorageError>` returns an empty list for an absent library or a successfully decoded empty array; read/decode errors remain failures.
- `readWorkingSessionResult() -> Result<SavedSession?, SessionStorageError>` returns successful nil only for an absent recovery file.
- `saveSession`, `deleteSession`, `renameSession`, `saveWorkingSession` and `clearWorkingSession` return `Result<Void, SessionStorageError>`. Mutations do not treat a failed read as an empty file. Successful writes use atomic replacement.
- Compatibility `loadSessions` / `loadWorkingSession` convenience reads still exist; new recovery and mutation flows must use Result APIs.
- `LooperViewModel.saveCurrentSession(name:)`, `saveWorkingSession()`, `restoreWorkingSession()`, `loadSession(_:)`, `deleteSession(_:)` and `loadImportedSession(_:)` return Bool. False leaves a readable `persistenceError`; a successful named save may still return true with a nonfatal recovery-cleanup/list-refresh warning because its saved data is durable. Import may save the imported library entry but return false if clearing the previous recovery copy prevents switching the live project.

## Pure reversible musical operations

`MusicEdit.apply(_:to:protectedTrackIDs:protectedNoteIDs:) throws -> MusicEditResult` takes a copied `[Track]` snapshot and returns candidate `tracks` plus a `MusicEditInverse`. It does not publish, play or save them.

- `.gain(trackID:before:after:)` accepts finite absolute linear gains in 0...1 and requires the existing affected value to match `before`. It never implicitly unmutes a track.
- `.midiRegion(trackID:startBeat:endBeat:selection:before:after:)` scopes a half-open beat interval to explicit pitches or existing note IDs. Pitch selection can insert locally assigned new IDs; ID selection can change/delete its existing notes, including repitching, but cannot insert an unrelated ID.
- `MusicNoteInput` holds UUID, Int pitch/velocity and Double beat/duration values. They are checked before UInt8 conversion and before the clamping MidiNote initializer.
- Limits: 16 operations per batch, 512 notes per selected region, 4096 notes per track, and 16 beats per region. The caller must bound the complete session/import payload.
- Missing/duplicate IDs, wrong track kinds, invalid values, stale before-values, edge-crossing selected notes, changed protected content and no-op musical changes throw typed `MusicEditError`. A failure returns no partial state.
- `inverse.apply(to:) throws -> [Track]` checks expected affected fields and restores exact original note IDs/order and gain in reverse operation order. Newer unrelated fields survive. A changed note array conservatively prevents that note inverse; it does not rebase edits.

This foundation is not request authorization. The future session owner must enforce instance/revision freshness, duplicate/cancel handling, persistence and playback transitions. The validator rejects a positive duration if its computed end is not greater than its start, and rejects signed-zero-only net gain changes while preserving exact original gain bits in an inverse.

## Checked AAC encoding boundary

`AudioExporter.encodePCMToM4A(_:sessionName:directory:writer:) throws -> URL` writes an owned UUID attempt directory and verifies the resulting AAC container, format, channels, complete decoded length and finite samples. Verification reads only remaining declared frames and requires forward progress; decoded length must cover input with at most 1024 padding frames. Failure removes only that attempt, preserving previous exports and unrelated files. The injectable writer is an internal deterministic fault-test seam.

The existing public full-render export remains asynchronous and optional-URL based. Checked encoding alone does not prove vocals, mute/solo selection, relative mix levels or sample-accurate event scheduling in that renderer.

## Authoritative model revision boundary

- `MusicalToken` contains a session UUID and UInt64 revision. Session replacement gets a fresh identity; undo creates a later revision rather than rewinding it.
- `musicSnapshot() throws -> MusicalSnapshot` returns one coherent token/tracks/BPM/bar-count bundle. Legacy Combine streams remain display updates; callers must not combine a published willSet value with a separately read token.
- `applyMusicEdits(_:expectedToken:protectedTrackIDs:protectedNoteIDs:) throws -> MusicalEditCommit` compares the captured token, validates the complete typed batch, publishes tracks once and returns the new token/inverse.
- `applyMusicInverse(_:expectedToken:) throws -> MusicalToken` restores a validated inverse and advances the authoritative revision.
- `MusicalCommitError` distinguishes stale, busy and invalid typed edits. Apply/undo require stopped or paused transport and reject recording, playing or synchronous publication/operation reentry. Existing transport and no-op setters do not create musical edits.

This is a model commit, not a durable or audible user action. Persistence, sampler updates, already-enqueued audio callbacks, pending-response cancellation, duplicate request handling and manual editor stale-note checks remain adapter responsibilities. Legacy whole-track note writeback preserves current mixer metadata but does not independently detect stale notes. The background timer remains in place; this change does not certify every legacy UI publication as main-thread isolated.
