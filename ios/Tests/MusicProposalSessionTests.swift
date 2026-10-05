import XCTest
import Combine
@testable import Loopa

@MainActor
final class MusicProposalSessionTests: XCTestCase {
    private func fixture() -> (MultiTrackLooper, MusicProposalSession, Track, Track) {
        let selected = Track(instrumentName: "Drums", instrumentProgram: 0, isDrumKit: true,
                             notes: [MidiNote(pitch: 36, velocity: 100, startBeat: 0, durationBeats: 0.25),
                                     MidiNote(pitch: 42, velocity: 80, startBeat: 0, durationBeats: 0.25),
                                     MidiNote(pitch: 42, velocity: 70, startBeat: 1, durationBeats: 0.25)],
                             recordedAt: Date(timeIntervalSince1970: 100),
                             isMuted: false, isSolo: true, volume: 0.5,
                             recordedLengthBeats: 16, isLooping: false)
        let other = Track(audioFileName: "untouched.caf", recordedAt: Date(timeIntervalSince1970: 200),
                          isMuted: true, volume: 0.3, recordedLengthBeats: 8)
        let looper = MultiTrackLooper()
        looper.loadTracks([selected, other])
        return (looper, MusicProposalSession(looper: looper), selected, other)
    }

    private func gainScope(_ track: Track) -> MusicProposalSession.Scope {
        .init(trackID: track.id, allowsGain: true)
    }

    private func hatScope(_ track: Track, protectedNotes: Set<UUID> = []) -> MusicProposalSession.Scope {
        .init(trackID: track.id,
              midiRegion: .init(startBeat: 0, endBeat: 4, selection: .pitches([42, 46])),
              protectedNoteIDs: protectedNotes)
    }

    private func gain(_ track: Track, after: Float = 0.7) -> [MusicEdit] {
        [.gain(trackID: track.id, before: track.volume, after: after)]
    }

    private func thinHats(_ track: Track) -> [MusicEdit] {
        let hats = track.notes.filter { $0.pitch == 42 }
        return [.midiRegion(trackID: track.id, startBeat: 0, endBeat: 4,
                            selection: .pitches([42]), before: hats,
                            after: [MusicNoteInput(hats[0])])]
    }

    private func bytes(_ tracks: [Track]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(tracks)
    }

    private func fails<T>(_ expected: MusicProposalSession.Failure, _ action: @autoclosure () throws -> T,
                          file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try action(), file: file, line: line) {
            XCTAssertEqual($0 as? MusicProposalSession.Failure, expected, file: file, line: line)
        }
    }

    func testRequestCapturesCanonicalSnapshotAndUniqueIdentity() throws {
        let (looper, session, track, _) = fixture()
        looper.bpm = 123
        looper.barCount = .two
        let request = try session.beginRequest(scope: gainScope(track))
        XCTAssertEqual(session.phase, .requesting(request.id))
        XCTAssertEqual(request.snapshot.token, looper.musicalToken)
        XCTAssertEqual(request.snapshot.bpm, 123)
        XCTAssertEqual(request.snapshot.barCount, .two)
        XCTAssertEqual(try bytes(request.snapshot.tracks), try bytes(looper.tracks))
        try session.cancel(requestID: request.id)
        let next = try session.beginRequest(scope: gainScope(track))
        XCTAssertNotEqual(next.id, request.id)
    }

    func testGainCandidateNeverMutatesCanonicalAndKeepPreservesOtherFields() throws {
        let (looper, session, track, _) = fixture()
        let before = try looper.musicSnapshot()
        let request = try session.beginRequest(scope: gainScope(track))
        let candidate = try session.receive(gain(track), for: request.id)
        XCTAssertEqual(candidate.tracks[0].volume, 0.7)
        XCTAssertEqual(candidate.token, before.token)
        XCTAssertEqual(candidate.bpm, before.bpm)
        XCTAssertEqual(candidate.barCount, before.barCount)
        XCTAssertEqual(try bytes(looper.tracks), try bytes(before.tracks))
        XCTAssertEqual(looper.musicalToken, before.token)
        let receipt = try session.keep(requestID: request.id)
        XCTAssertEqual(receipt.requestID, request.id)
        XCTAssertEqual(receipt.beforeToken, before.token)
        XCTAssertEqual(receipt.committedToken, looper.musicalToken)
        XCTAssertEqual(receipt.committedToken.revision, before.token.revision + 1)
        var expected = before.tracks
        expected[0].volume = 0.7
        XCTAssertEqual(try bytes(looper.tracks), try bytes(expected))
        XCTAssertEqual(session.phase, .kept(request.id))
    }

    func testMIDICandidateKeepAndUndoPreserveKickOtherTrackAndMetadata() throws {
        let (looper, session, track, _) = fixture()
        let original = try bytes(looper.tracks)
        let request = try session.beginRequest(scope: hatScope(track, protectedNotes: [track.notes[0].id]))
        let candidate = try session.receive(thinHats(track), for: request.id)
        XCTAssertEqual(candidate.tracks[0].notes, [track.notes[0], track.notes[1]])
        XCTAssertEqual(try bytes(looper.tracks), original)
        let receipt = try session.keep(requestID: request.id)
        var expected = [track, looper.tracks[1]]
        expected[0].notes = [track.notes[0], track.notes[1]]
        XCTAssertEqual(try bytes(looper.tracks), try bytes(expected))
        let undone = try session.undo(requestID: request.id)
        XCTAssertEqual(try bytes(looper.tracks), original)
        XCTAssertEqual(undone.revision, receipt.committedToken.revision + 1)
        XCTAssertEqual(session.phase, .undone(request.id))
    }

    func testCancelDuringGenerationRejectsLateReplyAndKeep() throws {
        let (looper, session, track, _) = fixture()
        let request = try session.beginRequest(scope: gainScope(track))
        try session.cancel(requestID: request.id)
        fails(.requestInvalidated, try session.receive(gain(track), for: request.id))
        fails(.requestInvalidated, try session.keep(requestID: request.id))
        XCTAssertNil(session.candidateSnapshot)
        XCTAssertEqual(looper.musicalToken, request.snapshot.token)
        XCTAssertEqual(session.phase, .cancelled(request.id))
    }

    func testRejectReadyProposalDiscardsCandidateAndInvalidatesLateReply() throws {
        let (looper, session, track, _) = fixture()
        let request = try session.beginRequest(scope: gainScope(track))
        _ = try session.receive(gain(track), for: request.id)
        try session.reject(requestID: request.id)
        fails(.requestInvalidated, try session.receive(gain(track), for: request.id))
        fails(.requestInvalidated, try session.candidate(for: request.id))
        XCTAssertNil(session.candidateSnapshot)
        XCTAssertEqual(looper.tracks[0].volume, 0.5)
        XCTAssertEqual(looper.musicalToken, request.snapshot.token)
    }

    func testOldReplyCannotAttachToNewRequest() throws {
        let (_, session, track, _) = fixture()
        let old = try session.beginRequest(scope: gainScope(track))
        try session.cancel(requestID: old.id)
        let current = try session.beginRequest(scope: gainScope(track))
        fails(.unknownRequest, try session.receive(gain(track), for: old.id))
        XCTAssertEqual(session.phase, .requesting(current.id))
        XCTAssertNoThrow(try session.receive(gain(track), for: current.id))
    }

    func testManualEditWhileGeneratingInvalidatesResponse() throws {
        let (looper, session, track, other) = fixture()
        let request = try session.beginRequest(scope: gainScope(track))
        looper.toggleMute(other)
        let newer = try bytes(looper.tracks)
        fails(.stale, try session.receive(gain(track), for: request.id))
        XCTAssertEqual(try bytes(looper.tracks), newer)
        XCTAssertEqual(session.phase, .invalidated(request.id))
    }

    func testNewProjectWithSameContentsInvalidatesResponse() throws {
        let (looper, session, track, _) = fixture()
        let request = try session.beginRequest(scope: gainScope(track))
        looper.loadTracks(looper.tracks)
        fails(.stale, try session.receive(gain(track), for: request.id))
        XCTAssertNotEqual(looper.musicalToken.sessionID, request.snapshot.token.sessionID)
        XCTAssertEqual(looper.tracks[0].volume, track.volume)
    }

    func testNewEmptyProjectInvalidatesReadyProposal() throws {
        let (looper, session, track, _) = fixture()
        let request = try session.beginRequest(scope: gainScope(track))
        _ = try session.receive(gain(track), for: request.id)
        looper.clearAllTracks()
        fails(.stale, try session.keep(requestID: request.id))
        XCTAssertTrue(looper.tracks.isEmpty)
        XCTAssertNil(session.candidateSnapshot)
    }

    func testManualEditAfterPreviewBlocksCandidateAndKeep() throws {
        let (looper, session, track, _) = fixture()
        let request = try session.beginRequest(scope: gainScope(track))
        _ = try session.receive(gain(track), for: request.id)
        looper.bpm = 125
        fails(.stale, try session.candidate(for: request.id))
        fails(.requestInvalidated, try session.keep(requestID: request.id))
        XCTAssertEqual(looper.tracks[0].volume, 0.5)
        XCTAssertEqual(looper.bpm, 125)
    }

    func testDuplicateReplyReturnsFrozenCandidateButChangedPayloadRejects() throws {
        let (looper, session, track, _) = fixture()
        let request = try session.beginRequest(scope: gainScope(track))
        let first = try session.receive(gain(track), for: request.id)
        let retry = try session.receive(gain(track), for: request.id)
        XCTAssertEqual(try bytes(first.tracks), try bytes(retry.tracks))
        fails(.payloadChanged, try session.receive(gain(track, after: 0.9), for: request.id))
        XCTAssertEqual(session.candidateSnapshot?.tracks[0].volume, 0.7)
        _ = try session.keep(requestID: request.id)
        XCTAssertEqual(looper.tracks[0].volume, 0.7)
        fails(.payloadChanged, try session.receive(gain(track, after: 0.9), for: request.id))
    }

    func testDuplicateKeepIsStableAfterManualWorkUndoAndNextRequest() throws {
        let (looper, session, track, _) = fixture()
        let request = try session.beginRequest(scope: gainScope(track))
        _ = try session.receive(gain(track), for: request.id)
        let receipt = try session.keep(requestID: request.id)
        XCTAssertEqual(try session.keep(requestID: request.id), receipt)
        XCTAssertEqual(looper.musicalToken, receipt.committedToken)
        let undone = try session.undo(requestID: request.id)
        XCTAssertEqual(try session.keep(requestID: request.id), receipt)
        XCTAssertEqual(looper.musicalToken, undone)
        looper.toggleMute(track)
        let newer = looper.musicalToken
        _ = try session.beginRequest(scope: gainScope(track))
        XCTAssertEqual(try session.keep(requestID: request.id), receipt)
        XCTAssertEqual(looper.musicalToken, newer)
        XCTAssertEqual(looper.tracks[0].volume, 0.5)
    }

    func testChangedMIDISelectionCannotReplaceFrozenPayload() throws {
        let (_, session, track, _) = fixture()
        let request = try session.beginRequest(scope: hatScope(track))
        _ = try session.receive(thinHats(track), for: request.id)
        let hats = track.notes.filter { $0.pitch == 42 }
        let changed: [MusicEdit] = [.midiRegion(trackID: track.id, startBeat: 0, endBeat: 4,
                                               selection: .pitches([42, 46]), before: hats,
                                               after: [MusicNoteInput(hats[0])])]
        fails(.payloadChanged, try session.receive(changed, for: request.id))
    }

    func testTrackOutsideScopeAndUnpermittedOperationReject() throws {
        let (looper, session, track, other) = fixture()
        let request = try session.beginRequest(scope: gainScope(track))
        fails(.outsideScope, try session.receive(gain(other), for: request.id))
        fails(.outsideScope, try session.receive(thinHats(track), for: request.id))
        XCTAssertEqual(looper.musicalToken, request.snapshot.token)
        XCTAssertNil(session.candidateSnapshot)
    }

    func testMIDIRegionCannotWidenTimePitchesOrSwitchSelectionKind() throws {
        let (_, session, track, _) = fixture()
        let request = try session.beginRequest(scope: hatScope(track))
        let hats = track.notes.filter { $0.pitch == 42 }
        let attempts: [MusicEdit] = [
            .midiRegion(trackID: track.id, startBeat: 0, endBeat: 8,
                        selection: .pitches([42]), before: hats, after: []),
            .midiRegion(trackID: track.id, startBeat: 0, endBeat: 4,
                        selection: .pitches([36, 42]), before: track.notes, after: []),
            .midiRegion(trackID: track.id, startBeat: 0, endBeat: 4,
                        selection: .noteIDs(Set(hats.map(\.id))), before: hats, after: [])
        ]
        for edit in attempts { fails(.outsideScope, try session.receive([edit], for: request.id)) }
    }

    func testNoteIDScopeAllowsOnlySelectedExistingNotes() throws {
        let (_, session, track, _) = fixture()
        let hat = track.notes[1]
        let request = try session.beginRequest(scope: .init(trackID: track.id,
            midiRegion: .init(startBeat: 0, endBeat: 4, selection: .noteIDs([hat.id]))))
        let changed = MusicNoteInput(id: hat.id, pitch: 46, velocity: 81, startBeat: 0.5, durationBeats: 0.25)
        let edit: MusicEdit = .midiRegion(trackID: track.id, startBeat: 0, endBeat: 2,
                                        selection: .noteIDs([hat.id]), before: [hat], after: [changed])
        let candidate = try session.receive([edit], for: request.id)
        XCTAssertEqual(candidate.tracks[0].notes[1].pitch, 46)
        XCTAssertEqual(candidate.tracks[0].notes[0], track.notes[0])
        XCTAssertEqual(candidate.tracks[0].notes[2], track.notes[2])
    }

    func testProtectedTrackAndNoteRejectWithoutMutation() throws {
        let (looper, session, track, _) = fixture()
        let blocked = try session.beginRequest(scope: .init(trackID: track.id, allowsGain: true,
                                                            protectedTrackIDs: [track.id]))
        fails(.invalidEdit(.protectedTrack), try session.receive(gain(track), for: blocked.id))
        try session.cancel(requestID: blocked.id)
        let request = try session.beginRequest(scope: hatScope(track, protectedNotes: [track.notes[2].id]))
        fails(.invalidEdit(.protectedNote), try session.receive(thinHats(track), for: request.id))
        XCTAssertEqual(try bytes(looper.tracks), try bytes(request.snapshot.tracks))
        XCTAssertEqual(looper.musicalToken, request.snapshot.token)
    }

    func testMalformedGainNoOpAndOversizedBatchRemainErrors() throws {
        let (looper, session, track, _) = fixture()
        let request = try session.beginRequest(scope: gainScope(track))
        fails(.invalidEdit(.invalidGain), try session.receive(gain(track, after: .nan), for: request.id))
        fails(.invalidEdit(.invalidGain), try session.receive(gain(track, after: 1.1), for: request.id))
        fails(.invalidEdit(.noChange), try session.receive(gain(track, after: 0.5), for: request.id))
        fails(.invalidEdit(.noChange), try session.receive([], for: request.id))
        fails(.invalidEdit(.tooManyOperations), try session.receive(Array(repeating: gain(track)[0], count: 17), for: request.id))
        XCTAssertEqual(looper.musicalToken, request.snapshot.token)
        XCTAssertNil(session.candidateSnapshot)
    }

    func testMalformedNoteAndPartialBatchAreRejectedAtomically() throws {
        let (looper, session, track, _) = fixture()
        let request = try session.beginRequest(scope: .init(trackID: track.id, allowsGain: true,
            midiRegion: .init(startBeat: 0, endBeat: 4, selection: .pitches([42]))))
        let hats = track.notes.filter { $0.pitch == 42 }
        let invalid = MusicNoteInput(id: hats[0].id, pitch: 42, velocity: 200, startBeat: 0, durationBeats: 0.25)
        let edit: MusicEdit = .midiRegion(trackID: track.id, startBeat: 0, endBeat: 4,
                                        selection: .pitches([42]), before: hats, after: [invalid])
        fails(.invalidEdit(.invalidNote), try session.receive(gain(track) + [edit], for: request.id))
        XCTAssertEqual(try bytes(looper.tracks), try bytes(request.snapshot.tracks))
        XCTAssertNil(session.candidateSnapshot)
    }

    func testInvalidScopeNeverCreatesRequest() {
        let (_, session, track, other) = fixture()
        let scopes: [MusicProposalSession.Scope] = [
            .init(trackID: UUID(), allowsGain: true),
            .init(trackID: track.id),
            .init(trackID: other.id, midiRegion: .init(startBeat: 0, endBeat: 4, selection: .pitches([42]))),
            .init(trackID: track.id, midiRegion: .init(startBeat: 0, endBeat: 17, selection: .pitches([42]))),
            .init(trackID: track.id, midiRegion: .init(startBeat: .nan, endBeat: 4, selection: .pitches([42]))),
            .init(trackID: track.id, midiRegion: .init(startBeat: 0, endBeat: 4, selection: .pitches([]))),
            .init(trackID: track.id, midiRegion: .init(startBeat: 0, endBeat: 4, selection: .noteIDs([UUID()])))
        ]
        for scope in scopes { fails(.invalidScope, try session.beginRequest(scope: scope)) }
        XCTAssertEqual(session.phase, .idle)
        XCTAssertNil(session.currentRequest)
    }

    func testConcurrentRequestAndKeepBeforeProposalReject() throws {
        let (_, session, track, _) = fixture()
        let request = try session.beginRequest(scope: gainScope(track))
        fails(.busy, try session.beginRequest(scope: gainScope(track)))
        fails(.proposalUnavailable, try session.keep(requestID: request.id))
        _ = try session.receive(gain(track), for: request.id)
        fails(.busy, try session.beginRequest(scope: gainScope(track)))
    }

    func testKeepDuringPlaybackIsBusyAndCanRetryAfterStop() throws {
        let (looper, session, track, _) = fixture()
        defer { looper.stopPlayback() }
        let request = try session.beginRequest(scope: gainScope(track))
        _ = try session.receive(gain(track), for: request.id)
        looper.startPlayback()
        fails(.busy, try session.keep(requestID: request.id))
        XCTAssertEqual(session.phase, .ready(request.id))
        XCTAssertEqual(looper.musicalToken, request.snapshot.token)
        looper.stopPlayback()
        XCTAssertNoThrow(try session.keep(requestID: request.id))
    }

    func testRecordingInvalidatesOutstandingRequestAndBusyCommitNeverMutates() throws {
        let (looper, session, track, _) = fixture()
        defer { looper.stopPlayback() }
        let request = try session.beginRequest(scope: gainScope(track))
        _ = try session.receive(gain(track), for: request.id)
        looper.startRecording(instrument: .piano)
        fails(.busy, try session.keep(requestID: request.id))
        XCTAssertEqual(looper.tracks[0].volume, track.volume)
        looper.stopRecording()
        looper.stopPlayback()
        fails(.stale, try session.keep(requestID: request.id))
    }

    func testUndoRejectsNewerManualRevisionEvenWhenEditedFieldStillMatches() throws {
        let (looper, session, track, other) = fixture()
        let request = try session.beginRequest(scope: gainScope(track))
        _ = try session.receive(gain(track), for: request.id)
        _ = try session.keep(requestID: request.id)
        looper.toggleMute(other)
        let newer = try bytes(looper.tracks)
        let token = looper.musicalToken
        fails(.stale, try session.undo(requestID: request.id))
        XCTAssertEqual(try bytes(looper.tracks), newer)
        XCTAssertEqual(looper.musicalToken, token)
    }

    func testUndoIsBusyDuringPlaybackThenRestoresExactlyOnce() throws {
        let (looper, session, track, _) = fixture()
        defer { looper.stopPlayback() }
        let request = try session.beginRequest(scope: gainScope(track))
        _ = try session.receive(gain(track), for: request.id)
        _ = try session.keep(requestID: request.id)
        looper.startPlayback()
        fails(.busy, try session.undo(requestID: request.id))
        XCTAssertEqual(looper.tracks[0].volume, 0.7)
        looper.stopPlayback()
        let undone = try session.undo(requestID: request.id)
        XCTAssertEqual(try session.undo(requestID: request.id), undone)
        XCTAssertEqual(looper.musicalToken, undone)
        XCTAssertEqual(looper.tracks[0].volume, 0.5)
    }

    func testUndoRejectsSameContentSessionReplacement() throws {
        let (looper, session, track, _) = fixture()
        let request = try session.beginRequest(scope: gainScope(track))
        _ = try session.receive(gain(track), for: request.id)
        _ = try session.keep(requestID: request.id)
        looper.loadTracks(looper.tracks)
        let replacement = try bytes(looper.tracks)
        fails(.stale, try session.undo(requestID: request.id))
        XCTAssertEqual(try bytes(looper.tracks), replacement)
    }

    func testUndoInvalidatesNewPendingRequestWithoutApplyingItsReply() throws {
        let (looper, session, track, _) = fixture()
        let first = try session.beginRequest(scope: gainScope(track))
        _ = try session.receive(gain(track), for: first.id)
        _ = try session.keep(requestID: first.id)
        let newerTrack = looper.tracks[0]
        let next = try session.beginRequest(scope: gainScope(newerTrack))
        _ = try session.undo(requestID: first.id)
        fails(.unknownRequest, try session.receive(gain(newerTrack, after: 0.9), for: next.id))
        XCTAssertEqual(looper.tracks[0].volume, 0.5)
        XCTAssertNil(session.currentRequest)
    }

    func testEvictedReceiptCannotBeAppliedAgain() throws {
        let (looper, session, track, _) = fixture()
        var firstID: UUID?
        for index in 0...MusicProposalSession.maximumRetainedReceipts {
            let current = looper.tracks[0]
            let request = try session.beginRequest(scope: gainScope(track))
            if firstID == nil { firstID = request.id }
            _ = try session.receive(gain(current, after: index.isMultiple(of: 2) ? 0.7 : 0.5), for: request.id)
            _ = try session.keep(requestID: request.id)
        }
        let current = looper.musicalToken
        fails(.unknownRequest, try session.keep(requestID: XCTUnwrap(firstID)))
        XCTAssertEqual(looper.musicalToken, current)
    }

    func testRequestDuringCanonicalPublicationFailsBusyWithoutPartialState() {
        let (looper, session, track, _) = fixture()
        let scope = gainScope(track)
        let subscription = looper.$tracks.dropFirst().sink { _ in
            do {
                _ = try session.beginRequest(scope: scope)
                XCTFail("Request cannot capture a half-published canonical state")
            } catch {
                XCTAssertEqual(error as? MusicProposalSession.Failure, .busy)
            }
        }
        looper.setTrackVolume(track.id, volume: 0.6)
        XCTAssertEqual(session.phase, .idle)
        XCTAssertNil(session.currentRequest)
        withExtendedLifetime(subscription) {}
    }

    func testCrossingNoteCannotBeSilentlyCutByAllowedRegion() throws {
        let (looper, session, track, _) = fixture()
        var changed = track
        changed.notes.append(MidiNote(pitch: 42, startBeat: 3.5, durationBeats: 1))
        looper.updateTrack(changed)
        let request = try session.beginRequest(scope: hatScope(changed))
        let hats = changed.notes.filter { $0.pitch == 42 }
        let edit: MusicEdit = .midiRegion(trackID: track.id, startBeat: 0, endBeat: 4,
                                        selection: .pitches([42]), before: hats, after: [])
        fails(.invalidEdit(.outsideScope), try session.receive([edit], for: request.id))
        XCTAssertEqual(looper.tracks[0].notes, changed.notes)
    }

    func testForgedBeforeValueDoesNotBecomeAProposal() throws {
        let (looper, session, track, _) = fixture()
        let request = try session.beginRequest(scope: gainScope(track))
        let edit: MusicEdit = .gain(trackID: track.id, before: 0.2, after: 0.7)
        fails(.invalidEdit(.staleBefore), try session.receive([edit], for: request.id))
        XCTAssertNil(session.candidateSnapshot)
        XCTAssertEqual(looper.musicalToken, request.snapshot.token)
    }

    func testLooperPublicationReentryCannotCommitTwice() throws {
        let (looper, session, track, _) = fixture()
        let request = try session.beginRequest(scope: gainScope(track))
        _ = try session.receive(gain(track), for: request.id)
        var callbacks = 0
        let subscription = looper.$tracks.dropFirst().sink { _ in
            callbacks += 1
            do {
                _ = try session.keep(requestID: request.id)
                XCTFail("Reentrant Keep must fail")
            } catch {
                XCTAssertEqual(error as? MusicProposalSession.Failure, .busy)
            }
        }
        let receipt = try session.keep(requestID: request.id)
        XCTAssertEqual(callbacks, 1)
        XCTAssertEqual(receipt.committedToken.revision, request.snapshot.token.revision + 1)
        withExtendedLifetime(subscription) {}
    }

    func testPhasePublicationReentryCannotReplaceOrKeepHalfPublishedProposal() throws {
        let (looper, session, track, _) = fixture()
        let request = try session.beginRequest(scope: gainScope(track))
        let subscription = session.$phase.dropFirst().sink { phase in
            if phase == .ready(request.id) {
                do {
                    _ = try session.keep(requestID: request.id)
                    XCTFail("Cannot keep a half-published proposal")
                } catch {
                    XCTAssertEqual(error as? MusicProposalSession.Failure, .busy)
                }
                do {
                    try session.cancel(requestID: request.id)
                    XCTFail("Cannot cancel a half-published proposal")
                } catch {
                    XCTAssertEqual(error as? MusicProposalSession.Failure, .busy)
                }
            }
        }
        _ = try session.receive(gain(track), for: request.id)
        XCTAssertEqual(looper.musicalToken, request.snapshot.token)
        XCTAssertEqual(session.phase, .ready(request.id))
        withExtendedLifetime(subscription) {}
    }
}
