# IO Schema

Updated 2026-10-05. Local assistant contracts below include the pending controller/UI repair and personal launcher; documenting an API does not establish combined iOS acceptance or real-account eligibility. See the code index for source and verification boundaries.

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

This foundation is not request authorization. MusicProposalSession supplies request/scope/revision and duplicate/cancel checks; MusicAssistantController supplies preview, explicit acceptance and persistence transitions. The validator rejects a positive duration if its computed end is not greater than its start, and rejects signed-zero-only net gain changes while preserving exact original gain bits in an inverse.

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


## Local text-gain assistant authority

The current personal pilot proposes one finite absolute gain in `0...1` for one existing selected track. Broader pure MIDI-edit support above does not grant the model MIDI authority. Input consists of user text (at most 2,048 UTF-8 bytes), chosen visible model, project tempo/loop length and selected-track ID, kind/instrument, gain, mute/solo, length and audibility. No recordings, file paths, note arrays or other tracks' content are sent.

`MusicProposalSession.beginRequest(scope:)` captures a request UUID and coherent `MusicalSnapshot`. `receive(_:for:)` validates into a separate candidate; `candidate(for:)`, `keep(requestID:)` and `undo(requestID:)` recheck authority. Keep is a stopped-transport model commit followed by the controller's save. At most 50 receipts are retained in memory; saved music does not serialize Undo history.

### iOS controller and preview

`MusicAssistantController` publishes one `State`: phase (`idle`, `discovering`, `requesting`, `ready`, `preparing`, `kept`, `undone`), connection/sharing, models/selection, track selection, prompt/message, preview state, `canUndo` and save state (`notNeeded`, `saved`, `unsaved`). MainActor entry points are `discover()`, `requestGain()`, `preparePreview()`, `playOriginal()`, `playChange()`, `pausePreview()`, `keep()`, `undo()`, `retrySave()` and lifecycle invalidation methods.

- Request IDs, controller epochs and canonical session/revision tokens fence late results and manual changes. Text/model/track changes discard active proposal authority. Initial track selection without a request preserves discovery/pairing messages.
- The repair exposes `canAcceptPairing: Bool`, `pair(_ pairing: LocalMusicAssistant.Pairing) -> Bool` and the test seam `replaceClient(_:) -> Bool`. Pairing renews only the client: old requests/audio stop, connection/catalog clear, and project, prompt and session-local Undo remain. It returns false while mutating or while music is unsaved. Check `canAcceptPairing` **before** consuming the one-use file; retain the same controller across panel presentations.
- `Host.begin() async throws -> AudioLease` must pause/drain canonical audio before rendering. The lease exposes `isStopped()` and `end()`; controller cleanup calls `MusicPreview.stop()` before `end()`, then `Host.cancelPending()`. `LooperViewModel.beginMusicPreviewAudio()`, `musicPreviewAudioIsStopped(for:)`, `cancelMusicPreviewAudioPreparation()` and `endMusicPreviewAudio(_:)` implement that token boundary. `canonicalAudioControlsEnabled` reflects the reservation. Release does not resume playback automatically.
- `MusicPreview.prepare(requestID:)` renders a separate Original/Change pair, capped at 30 seconds. `play(_:)` is explicit, `pause()` retains prepared media and `stop()` invalidates callbacks and deletes owned temporary media. The panel enables Keep only with prepared comparison audio; the controller still independently checks the canonical token on Keep.
- Keep/Undo invoke `Host.save() -> Bool` after changing music. Failure retains in-memory music and recovery state, exposes Retry saving, and blocks new requests/discovery/re-pairing. Retry refuses a replaced session; a reentrant edit during a reported save prevents a false saved state. Undo may restore an unsaved Keep and then save the original.
- Dismiss/background/interruption stop requests and comparison audio. Unsaved state survives those calls. UI must call `dismiss()` before dropping the controller; deallocation alone is not an audio-lease cleanup contract. The repaired panel presents Undo whenever `canUndo` is true, independently of message visibility, and blocks dismissal while unsaved.

### Private simulator pairing

`LocalAssistantPairing.consume() throws -> LocalMusicAssistant.Pairing?` reads only the simulator app's `Documents/loopa-assistant-pair.json`; missing file returns nil, invalid input throws a fixed safe error, and the physical-device default returns nil without reading Documents. The internal `consume(directory:now:beforeUnlink:)` seam is for disposable fixtures.

| JSON key | Required value |
|----------|----------------|
| `version` | Numeric `1`, not Bool |
| `endpoint` | Exactly `http://127.0.0.1:<port>/`, port `1024...65535` |
| `capability` | 32 random bytes encoded as canonical unpadded base64url, 43 ASCII characters |
| `expires_at` | Integer Unix milliseconds, positive remaining lifetime at load of at most 900 seconds |

These are the only keys; duplicate keys are rejected. The file is at most 2,048 bytes, owned by the current user, regular, singly linked, mode `0600`, with no extended ACL. Symlinks, unsafe directories, broad access, malformed/truncated data and expired pairings fail closed. The loader pins directory/file descriptors and verifies identity/metadata before unlinking; the trusted launcher must serialize publication and consumption because POSIX does not offer conditional unlink by inode. Only the in-memory capability is retained; OAuth tokens never enter the pairing file.

`LocalMusicAssistant.Pairing` maps these fields to `endpoint: URL`, `capability: String`, `expiresAt: Date`. The client returns typed status/models or `[MusicEdit]`, allows one active request, uses a maximum 45-second deadline and 262,144-byte response, and rechecks pairing/generation after awaits. Redirects, cookies, cached credentials, proxies and response caching are disabled. `cancel()` invalidates locally immediately and sends best-effort remote cancellation without refunding usage.

### Paired loopback HTTP contract

Every route requires the local capability as `Authorization: Bearer <capability>`, the exact loopback Host and a live pairing. OAuth credentials are never accepted or returned here. Browser Origin/cookie/fetch headers, duplicate headers, queries and unsupported routes fail closed. One normal operation is active at a time; a matching cancellation route can interrupt it.

| Route | Request / successful JSON |
|-------|---------------------------|
| `GET /v1/status` | `{version:1,status,sharing}`; status is `connected`, `disconnected`, `connecting`, `reconnect_required` or `usage_unavailable` |
| `GET /v1/models` | `{version:1,models:[{slug,display_name}]}`; only visible models |
| `POST /v1/proposals` | Body `{request_id,user_text,model,project}`; result `{version:1,request_id,proposal:{operations:[{kind:"gain",track_id,value}]}}` |
| `DELETE /v1/proposals/<request UUID>` | `{version:1,cancelled:Bool}`; never refunds a request |

The project object is exactly `{version:1,request_id,tempo_bpm,loop_beats,track,capabilities:["gain"]}`; `track` has exactly `{id,kind,instrument,volume,muted,solo,length_beats,audible}`. Bounds include tempo `(0,1000]`, loop beats `(0,64]`, track length `(0,1024]`, finite gain `0...1`, request body 16,384 bytes, headers 8,192 bytes and reply 262,144 bytes. Repeated request IDs are denied; the server retains at most 256 IDs per pairing lifetime. Errors use bounded `{version:1,error,message}` with fixed safe text, never upstream bodies.

### Mac identity, storage and plan usage

`createSIWCGrant({repository,hostId,...}).start({profileId?,signal?,port?})` returns a cancellable grant handle with `authorizationUrl`, `redirectUri` and `completion`. It enforces OAuth state/nonce/PKCE and an exact `127.0.0.1` callback, persists the registered client before exchange, and verifies the RS256 ID token using bounded official-origin discovery/JWKS. An identity grant alone does not authorize inference: provider access requires both `resource.invoke` and `chatgpt.tokens.use.direct` plus a fresh active credential with enough remaining lifetime. Tokens are delivered only to the protected repository; refresh is not implemented.

`createCredentialRepository({helperPath})` exposes `initialize`, `getRegistration`, `savePendingRegistration`, `activateVerified`, `getActiveSession`, `reserveRequest`, `disconnect` and `reconcile`. The whole stored envelope is `{version:1,payload:{hostId,registrations,sessions,requests}}`, with at most four registrations/sessions and **one durable Responses-request reservation**. Activation follows a confirmed verified-record write and signal/epoch checks. Restart/reconcile keeps persisted sessions inactive. Disconnect, reconnect, cancellation and failed inference never reset/refund the reservation. Busy operations fail without a queue; uncertain writes deactivate and latch reconciliation rather than assuming rollback.

The native helper has fixed service `Loopa ChatGPT Local`, account `state-v1`, nonsynchronizable storage and noninteractive access to one captured macOS default Keychain. It accepts one compact JSON line plus EOF over private child pipes or anonymous Unix socketpairs: `{op:"read"}`, `{op:"replace",record}` or `{op:"delete"}`. Success is `{ok:true,record}` for read and `{ok:true}` otherwise; failure is a fixed `{ok:false,error}`. Limits are 65,536 stored-record bytes, 66,560 input bytes and 65,664 output bytes. The trusted launcher must own the process lock and serialize read/modify/write; whole-blob update is atomic, but the sequence is not compare-and-swap. Killing the helper is not rollback. Tokens travel through pipes, never arguments, logs or simulator files.

### Provider, stream and runtime

`createMusicProvider({getActiveSession,reserveRequest,readProposal,...})` exposes `listModels({signal})`, `proposeGain({requestId,userText,project,model,signal})` and `cancel()`. It uses only `https://api.openai.com/v1/models` and `/v1/responses`, preserves the visible catalog, requires explicit model choice and writes the durable reservation before POST. A response request uses `store:false`, `stream:true` and one strict namespace function, `loopa_music.propose_gain({track_id,gain})`; it does not send unsupported `max_output_tokens` or `temperature` controls. No automatic retry, token refresh, alternate model, arbitrary URL/file/shell tools, tool-result loop or paid API fallback is present.

`readMusicProposal(body,{signal,expectedTrackId,...})` returns only `{operations:[{kind:"gain",track_id,value}]}` after a completed-status terminal response and clean EOF. It validates UTF-8, JSON, selected UUID/range and response/item/output-index/call correlation; reconciles redundant final representations; tolerates bounded reasoning/text; and rejects unsupported calls, refusals, failed/incomplete progress, conflicts, truncation or unexpected trailing terminal data. Caps: 262,144 wire bytes, 32,768 event bytes, 4,096 argument bytes, 256 events, one function, 15-second idle and 45-second total duration. Failure yields no proposal and never executes an edit.

`startLocalAssistant({helperPath,pairingFile,...})` obtains a private process lock before protected-store initialization, composes the default modules and exclusively writes the mode-0600 pairing. It returns only `{status,connect,stop,pairingExpiresAt}`. `connect({profileId?})` fences previous-account work before a fresh grant and returns safe status/sharing only. `stop()` cancels grant/provider work, waits for bounded cleanup, removes owned pairing/lock state and retains the lock on uncertain credential activity. Pairing lasts at most 900 seconds; expiring credentials require reconnect, not implicit refresh.

The pending launcher command is `node mac-bridge/local-pilot.mjs --helper <absolute executable> --pairing-file <absolute path to Documents/loopa-assistant-pair.json>`. It accepts only those two flags, starts the runtime and interactive connection, and requires sharing. Startup is bounded to 15 seconds, connect to 180 seconds, lifetime to 900 seconds and cleanup to 15 seconds. SIGINT/SIGTERM trigger cleanup. Fixed `LOOPA_PILOT_*` messages contain no secret/authorization URL. Exit codes: `0` lifetime expiry, `2` invalid arguments, `3` start/connect/sharing failure, `4` deadline, `5` uncertain cleanup, `130` SIGINT, `143` SIGTERM; cleanup uncertainty takes precedence. It does not remove retained locks or reset the allowance.

Bridge composition has passed synthetic offline checks, including restart without automatic activation or allowance reset. Real account sign-in/usage consent, one real permitted request, listening quality and the final combined iOS UI/save/reopen/export journey remain separate verification. This local personal contract makes no public/commercial eligibility claim; audio input remains deferred.
