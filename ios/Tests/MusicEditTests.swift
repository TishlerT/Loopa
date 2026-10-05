import XCTest
@testable import Loopa

final class MusicEditTests: XCTestCase {
    private func note(_ pitch: UInt8 = 42, _ beat: Double = 0, id: UUID = UUID()) -> MidiNote {
        MidiNote(id: id, pitch: pitch, velocity: 90, startBeat: beat, durationBeats: 0.25)
    }

    private func track(_ notes: [MidiNote] = []) -> Track {
        Track(instrumentName: "Drums", instrumentProgram: 0, isDrumKit: true,
              notes: notes, recordedAt: Date(timeIntervalSince1970: 123),
              isMuted: true, isSolo: true, volume: 0.5, recordedLengthBeats: 16, isLooping: false)
    }

    private func raw(_ note: MidiNote, pitch: Int? = nil, velocity: Int? = nil,
                     start: Double? = nil, duration: Double? = nil) -> MusicNoteInput {
        MusicNoteInput(id: note.id, pitch: pitch ?? Int(note.pitch),
                       velocity: velocity ?? Int(note.velocity), startBeat: start ?? note.startBeat,
                       durationBeats: duration ?? note.durationBeats)
    }

    private func region(_ track: Track, before: [MidiNote], after: [MusicNoteInput],
                        start: Double = 0, end: Double = 4,
                        selection: MusicNoteSelection = .pitches([42, 46])) -> MusicEdit {
        .midiRegion(trackID: track.id, startBeat: start, endBeat: end,
                    selection: selection, before: before, after: after)
    }

    private func bytes(_ tracks: [Track]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(tracks)
    }

    private func rejects(_ edits: [MusicEdit], tracks: [Track], _ expected: MusicEditError,
                         protectedTracks: Set<UUID> = [], protectedNotes: Set<UUID> = [],
                         file: StaticString = #filePath, line: UInt = #line) {
        let snapshot = try? bytes(tracks)
        XCTAssertThrowsError(try MusicEdit.apply(edits, to: tracks,
                                                protectedTrackIDs: protectedTracks,
                                                protectedNoteIDs: protectedNotes), file: file, line: line) {
            XCTAssertEqual($0 as? MusicEditError, expected, file: file, line: line)
        }
        XCTAssertEqual(try? bytes(tracks), snapshot, "Rejected input changed", file: file, line: line)
    }

    func testAbsoluteVocalGainPreservesAllOtherFieldsAndTracks() throws {
        let vocal = Track(audioFileName: "private-take.caf", isMuted: true, isSolo: true,
                          volume: 0.5, recordedLengthBeats: 8, isLooping: false)
        let original = [track([note(36)]), vocal]
        let result = try MusicEdit.apply([.gain(trackID: vocal.id, before: 0.5, after: 0.7)], to: original)
        var expected = original
        expected[1].volume = 0.7
        XCTAssertEqual(try bytes(result.tracks), try bytes(expected))
        XCTAssertEqual(try bytes(original), try bytes([original[0], vocal]))
        XCTAssertEqual(try bytes(result.inverse.apply(to: result.tracks)), try bytes(original))
    }

    func testHatThinningPreservesKickMelodyAndEveryOtherField() throws {
        let kick = note(36), hat = note(42, 0.5), otherHat = note(46, 1), later = note(42, 4)
        let drums = track([kick, hat, otherHat, later])
        let melody = track([note(60)])
        let original = [drums, melody]
        let result = try MusicEdit.apply([region(drums, before: [hat, otherHat], after: [raw(hat)])],
                                        to: original, protectedTrackIDs: [melody.id], protectedNoteIDs: [kick.id])
        var expected = original
        expected[0].notes = [kick, hat, later]
        XCTAssertEqual(try bytes(result.tracks), try bytes(expected))
        XCTAssertEqual(try bytes(result.inverse.apply(to: result.tracks)), try bytes(original))
    }

    func testExplicitNoteIDsAllowOnlySelectedNotesToMove() throws {
        let a = note(), b = note(42, 1)
        let t = track([a, b])
        let edit = region(t, before: [a], after: [raw(a, pitch: 46, start: 2)], selection: .noteIDs([a.id]))
        let result = try MusicEdit.apply([edit], to: [t])
        XCTAssertEqual(result.tracks[0].notes[0].pitch, 46)
        XCTAssertEqual(result.tracks[0].notes[0].startBeat, 2)
        XCTAssertEqual(result.tracks[0].notes[1], b)
        XCTAssertEqual(try result.inverse.apply(to: result.tracks)[0].notes, t.notes)
    }

    func testPitchSelectionCanInsertNewLocalNoteAndUndoOriginalOrder() throws {
        let outside = note(36, 3), hat = note(42, 1), earlier = note(38, 0)
        let t = track([outside, hat, earlier]) // Deliberately not sorted.
        let newNote = note(46, 2)
        let result = try MusicEdit.apply([region(t, before: [hat], after: [raw(newNote), raw(hat)])], to: [t])
        XCTAssertEqual(result.tracks[0].notes, [outside, newNote, hat, earlier])
        XCTAssertEqual(try result.inverse.apply(to: result.tracks)[0].notes, t.notes)
    }

    func testEmptyPitchRegionCanInsertAndUndo() throws {
        let t = track([note(36)])
        let inserted = note(42, 2)
        let result = try MusicEdit.apply([region(t, before: [], after: [raw(inserted)])], to: [t])
        XCTAssertEqual(result.tracks[0].notes, t.notes + [inserted])
        XCTAssertEqual(try result.inverse.apply(to: result.tracks)[0].notes, t.notes)
    }

    func testStaleGainAndStaleNotesRejectWithoutChangingInput() {
        let hat = note(), t = track([hat])
        rejects([.gain(trackID: t.id, before: 0.4, after: 0.7)], tracks: [t], .staleBefore)
        var stale = hat
        stale.velocity = 80
        rejects([region(t, before: [stale], after: [])], tracks: [t], .staleBefore)
    }

    func testGainRejectsNonfiniteAndOutOfRangeBeforeOrAfter() {
        let t = track()
        for value in [Float.nan, .infinity, -.infinity, -0.01, 1.01] {
            rejects([.gain(trackID: t.id, before: 0.5, after: value)], tracks: [t], .invalidGain)
            rejects([.gain(trackID: t.id, before: value, after: 0.6)], tracks: [t], .invalidGain)
        }
    }

    func testGainEndpointsAreValid() throws {
        let t = track()
        for value in [Float(0), 1] {
            let result = try MusicEdit.apply([.gain(trackID: t.id, before: 0.5, after: value)], to: [t])
            XCTAssertEqual(result.tracks[0].volume, value)
            XCTAssertEqual(try result.inverse.apply(to: result.tracks)[0].volume, 0.5)
        }
    }

    func testUnknownTrackAndVocalNoteEditingReject() {
        let t = track(), vocal = Track(audioFileName: "take.caf")
        rejects([.gain(trackID: UUID(), before: 0.5, after: 0.7)], tracks: [t], .missingTrack)
        rejects([region(vocal, before: [], after: [raw(note())])], tracks: [vocal], .wrongTrackKind)
    }

    func testMissingExplicitNoteRejects() {
        let t = track([note()])
        rejects([region(t, before: [], after: [], selection: .noteIDs([UUID()]))], tracks: [t], .missingNote)
    }

    func testInvalidSelectionsReject() {
        let t = track([note()])
        for selection in [MusicNoteSelection.pitches([]), .pitches([-1]), .pitches([128]), .noteIDs([])] {
            rejects([region(t, before: [], after: [], selection: selection)], tracks: [t], .invalidSelection)
        }
    }

    func testInvalidScopeAndOversizedRegionReject() {
        let t = track([note()])
        for (start, end) in [(Double.nan, 4.0), (0, Double.infinity), (-1, 4), (4, 4), (5, 4), (0, 17), (15, 17)] {
            rejects([region(t, before: [], after: [], start: start, end: end)], tracks: [t], .invalidScope)
        }
    }

    func testScopeIsHalfOpenAndAllowsNotesEndingExactlyAtBoundary() throws {
        let inside = note(42, 3.75), boundary = note(42, 4)
        let t = track([inside, boundary])
        let result = try MusicEdit.apply([region(t, before: [inside], after: [])], to: [t])
        XCTAssertEqual(result.tracks[0].notes, [boundary])
    }

    func testNotesCrossingEitherRegionEdgeReject() {
        for beat in [0.875, 3.875] {
            let crossing = note(42, beat), t = track([crossing])
            rejects([region(t, before: [crossing], after: [], start: 1, end: 4)], tracks: [t], .outsideScope)
        }
    }

    func testExplicitIDOutsideRegionAndReplacementOutsideScopeReject() {
        let hat = note(42, 1), outside = note(42, 4), t = track([hat, outside])
        rejects([region(t, before: [outside], after: [], selection: .noteIDs([outside.id]))], tracks: [t], .outsideScope)
        for input in [raw(hat, start: 4), raw(hat, start: 3.9), raw(hat, pitch: 36)] {
            rejects([region(t, before: [hat], after: [input])], tracks: [t], .outsideScope)
        }
    }

    func testRawInvalidNotesRejectBeforeMidiNoteCanClamp() {
        let hat = note(), t = track([hat])
        let invalid = [raw(hat, pitch: -1), raw(hat, pitch: 128), raw(hat, pitch: Int.max),
                       raw(hat, velocity: 0), raw(hat, velocity: 128), raw(hat, velocity: -1),
                       raw(hat, start: -1), raw(hat, start: .nan), raw(hat, start: .infinity),
                       raw(hat, duration: 0), raw(hat, duration: 0.01), raw(hat, duration: -.infinity),
                       raw(hat, duration: .nan), raw(hat, duration: .infinity),
                       raw(hat, start: Double.greatestFiniteMagnitude, duration: Double.greatestFiniteMagnitude)]
        for input in invalid {
            rejects([region(t, before: [hat], after: [input])], tracks: [t], .invalidNote)
        }
    }

    func testMalformedExistingNotesReject() {
        var bad = note()
        bad.durationBeats = .nan
        let t = track([bad])
        rejects([region(t, before: [bad], after: [])], tracks: [t], .invalidNote)
    }

    func testDuplicateTrackAndNoteIDsReject() {
        let hat = note(), t = track([hat])
        rejects([.gain(trackID: t.id, before: 0.5, after: 0.6)], tracks: [t, t], .duplicateTrackID)
        let duplicate = track([hat, hat])
        rejects([region(duplicate, before: [hat, hat], after: [])], tracks: [duplicate], .duplicateNoteID)
        rejects([region(t, before: [hat], after: [raw(hat), raw(hat)])], tracks: [t], .duplicateNoteID)
        rejects([region(t, before: [hat, hat], after: [])], tracks: [t], .duplicateNoteID)
        rejects([region(t, before: [hat], after: [])], tracks: [t, track([hat])], .duplicateNoteID)
    }

    func testNewNoteCannotStealIDFromUnselectedOrOtherTrackNote() {
        let hat = note(), kick = note(36), t = track([hat, kick]), melody = track([note(60)])
        for stolen in [kick, melody.notes[0]] {
            let replacement = MusicNoteInput(id: stolen.id, pitch: 42, velocity: 90, startBeat: 1, durationBeats: 0.25)
            rejects([region(t, before: [hat], after: [replacement])], tracks: [t, melody], .duplicateNoteID)
        }
    }

    func testExplicitIDSelectionCannotInsertAnotherID() {
        let hat = note(), t = track([hat])
        rejects([region(t, before: [hat], after: [raw(note())], selection: .noteIDs([hat.id]))],
                tracks: [t], .outsideScope)
    }

    func testProtectedTrackAndProtectedNoteChangesReject() {
        let a = note(), b = note(42, 1), t = track([a, b])
        rejects([.gain(trackID: t.id, before: 0.5, after: 0.6)], tracks: [t], .protectedTrack, protectedTracks: [t.id])
        rejects([region(t, before: [a, b], after: [])], tracks: [t], .protectedTrack, protectedTracks: [t.id])
        rejects([region(t, before: [a, b], after: [raw(b)])], tracks: [t], .protectedNote, protectedNotes: [a.id])
        rejects([region(t, before: [a, b], after: [raw(a, velocity: 50), raw(b)])],
                tracks: [t], .protectedNote, protectedNotes: [a.id])
    }

    func testProtectedSelectedNoteMayRemainExactlyUnchanged() throws {
        let a = note(), b = note(42, 1), t = track([a, b])
        let result = try MusicEdit.apply([region(t, before: [a, b], after: [raw(a)])],
                                        to: [t], protectedNoteIDs: [a.id])
        XCTAssertEqual(result.tracks[0].notes, [a])
    }

    func testOversizedBeforeAfterAndBatchReject() {
        let hat = note(), t = track([hat])
        let many = (0...MusicEdit.maximumNotesPerRegion).map { _ in note() }
        rejects([region(t, before: [hat], after: many.map { raw($0) })], tracks: [t], .tooManyNotes)
        rejects([region(t, before: many, after: [])], tracks: [t], .tooManyNotes)
        let tooManyIDs = Set((0...MusicEdit.maximumNotesPerRegion).map { _ in UUID() })
        rejects([region(t, before: [], after: [], selection: .noteIDs(tooManyIDs))], tracks: [t], .tooManyNotes)
        let edits = (0...MusicEdit.maximumOperations).map { _ in MusicEdit.gain(trackID: t.id, before: 0.5, after: 0.6) }
        rejects(edits, tracks: [t], .tooManyOperations)
    }

    func testEmptyUnchangedAndReorderOnlyProposalsReject() {
        let a = note(), b = note(42, 1), t = track([a, b])
        rejects([], tracks: [t], .noChange)
        rejects([.gain(trackID: t.id, before: 0.5, after: 0.5)], tracks: [t], .noChange)
        rejects([region(t, before: [a, b], after: [raw(a), raw(b)])], tracks: [t], .noChange)
        rejects([region(t, before: [a, b], after: [raw(b), raw(a)])], tracks: [t], .noChange)
        rejects([region(t, before: [], after: [], start: 2, end: 4)], tracks: [t], .noChange)
    }

    func testCompositeFailureIsAtomic() {
        let a = note(), t = track([a])
        rejects([.gain(trackID: t.id, before: 0.5, after: 0.7), region(t, before: [], after: [])],
                tracks: [t], .staleBefore)
    }

    func testCompositeInverseRestoresExactValuesIDsAndOrder() throws {
        let a = note(), kick = note(36), b = note(46, 2), t = track([a, kick, b])
        let original = [t, track([note(60)])]
        let edits: [MusicEdit] = [.gain(trackID: t.id, before: 0.5, after: 0.8),
                                 region(t, before: [a, b], after: [raw(a, start: 1)]),
                                 .gain(trackID: t.id, before: 0.8, after: 0.9)]
        let result = try MusicEdit.apply(edits, to: original)
        XCTAssertEqual(try bytes(result.inverse.apply(to: result.tracks)), try bytes(original))
    }

    func testNetZeroCompositeRejects() {
        let t = track()
        rejects([.gain(trackID: t.id, before: 0.5, after: 0.8), .gain(trackID: t.id, before: 0.8, after: 0.5)],
                tracks: [t], .noChange)
    }

    func testInversePreservesUnrelatedNewerFields() throws {
        let a = note(), t = track([a])
        let result = try MusicEdit.apply([region(t, before: [a], after: [])], to: [t])
        var newer = result.tracks
        newer[0].volume = 0.9
        newer[0].isMuted = false
        newer[0].instrumentName = "Changed instrument"
        var expected = newer
        expected[0].notes = t.notes
        XCTAssertEqual(try bytes(result.inverse.apply(to: newer)), try bytes(expected))
    }

    func testInverseRejectsStaleAfterValuesAndIsAtomic() throws {
        let a = note(), t = track([a])
        let result = try MusicEdit.apply([.gain(trackID: t.id, before: 0.5, after: 0.8),
                                         region(t, before: [a], after: [])], to: [t])
        var newer = result.tracks
        newer[0].volume = 0.9
        let originalBytes = try bytes(newer)
        XCTAssertThrowsError(try result.inverse.apply(to: newer)) {
            XCTAssertEqual($0 as? MusicEditError, .staleBefore)
        }
        XCTAssertEqual(try bytes(newer), originalBytes)
        let restored = try result.inverse.apply(to: result.tracks)
        XCTAssertThrowsError(try result.inverse.apply(to: restored))
    }

    func testReplacingOnlyNoteIDsIsNotAMusicalChange() {
        let hat = note(), t = track([hat])
        let clone = note(42, 0)
        rejects([region(t, before: [hat], after: [raw(clone)])], tracks: [t], .noChange)
    }

    func testGainInverseCapturesActualOriginalSignedZero() throws {
        var t = track()
        t.volume = -Float.zero
        let result = try MusicEdit.apply([.gain(trackID: t.id, before: 0, after: 0.5)], to: [t])
        XCTAssertEqual(try result.inverse.apply(to: result.tracks)[0].volume.bitPattern, t.volume.bitPattern)
    }

    func testRemovingOneOfTwoCoincidentNotesIsAChange() throws {
        let a = note(), b = note(), t = track([a, b])
        let result = try MusicEdit.apply([region(t, before: [a, b], after: [raw(a)])], to: [t])
        XCTAssertEqual(result.tracks[0].notes, [a])
        XCTAssertEqual(try result.inverse.apply(to: result.tracks)[0].notes, t.notes)
    }

    func testRawValidPitchVelocityAndDurationBoundariesStayExact() throws {
        let t = track()
        let a = MusicNoteInput(id: UUID(), pitch: 0, velocity: 1, startBeat: 0, durationBeats: 0.0625)
        let b = MusicNoteInput(id: UUID(), pitch: 127, velocity: 127, startBeat: 3.9375, durationBeats: 0.0625)
        let result = try MusicEdit.apply([region(t, before: [], after: [a, b], selection: .pitches([0, 127]))], to: [t])
        XCTAssertEqual(result.tracks[0].notes.map { MusicNoteInput($0) }, [a, b])
    }

    func testNoteCountBoundAcceptsLimitAndRejectsOversizedResult() throws {
        let notes = (0..<MusicEdit.maximumNotesPerRegion).map { _ in note() }
        let t = track(notes)
        let result = try MusicEdit.apply([region(t, before: notes, after: [])], to: [t])
        XCTAssertTrue(result.tracks[0].notes.isEmpty)
        XCTAssertEqual(try result.inverse.apply(to: result.tracks)[0].notes, notes)
        let full = track((0..<MusicEdit.maximumNotesPerTrack).map { _ in note(36) })
        rejects([region(full, before: [], after: [raw(note())])], tracks: [full], .tooManyNotes)
        let oversized = track(full.notes + [note(36)])
        rejects([.gain(trackID: oversized.id, before: 0.5, after: 0.6)], tracks: [oversized], .tooManyNotes)
    }

    func testInverseCannotReintroduceAnIDNowOwnedByAnotherTrack() throws {
        let hat = note(), t = track([hat]), other = track()
        let result = try MusicEdit.apply([region(t, before: [hat], after: [])], to: [t, other])
        var newer = result.tracks
        newer[1].notes = [hat]
        let snapshot = try bytes(newer)
        XCTAssertThrowsError(try result.inverse.apply(to: newer)) {
            XCTAssertEqual($0 as? MusicEditError, .duplicateNoteID)
        }
        XCTAssertEqual(try bytes(newer), snapshot)
    }

}
