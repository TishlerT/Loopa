import XCTest
@testable import Loopa

final class MusicAssistantProtocolTests: XCTestCase {
    private func fixture() -> (MusicalSnapshot, Track) {
        let notes = [MidiNote(pitch: 36, velocity: 100, startBeat: 0, durationBeats: 0.25),
                     MidiNote(pitch: 42, velocity: 80, startBeat: 0.5, durationBeats: 0.25),
                     MidiNote(pitch: 42, velocity: 70, startBeat: 1, durationBeats: 0.25)]
        let track = Track(instrumentName: "Drums", instrumentProgram: 0, isDrumKit: true,
                          notes: notes, volume: 0.5)
        let vocal = Track(audioFileName: "private-unreleased-take.m4a", volume: 0.4)
        return (MusicalSnapshot(token: MusicalToken(sessionID: UUID(), revision: 7),
                                tracks: [track, vocal], bpm: 120, barCount: .four), track)
    }

    private func context(_ snapshot: MusicalSnapshot, _ track: Track, midi: Bool = true) throws -> MusicAssistantContext {
        try MusicAssistantContext(snapshot: snapshot, trackID: track.id,
            region: midi ? .init(startBeat: 0, endBeat: 4, selection: .pitches([42])) : nil)
    }

    private func data(_ operations: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["operations": operations], options: [.sortedKeys])
    }

    private func gain(_ track: Track, _ value: Any = 0.7) -> [String: Any] {
        ["kind": "gain", "track_id": track.id.uuidString, "value": value]
    }

    private func note(_ original: MidiNote, pitch: Any = 42, start: Any = 0.5) -> [String: Any] {
        ["id": original.id.uuidString, "pitch": pitch, "velocity": 80,
         "start_beat": start, "duration_beats": 0.25]
    }

    private func bytes(_ tracks: [Track]) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return try encoder.encode(tracks)
    }

    func testContextIncludesMusicalStateButNeverAudioPathsOrUnselectedTracks() throws {
        let (snapshot, track) = fixture()
        let payload = try context(snapshot, track).encodedProject()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        XCTAssertEqual(object["tempo_bpm"] as? Double, 120)
        XCTAssertEqual((object["track"] as? [String: Any])?["id"] as? String, track.id.uuidString)
        XCTAssertEqual((object["notes"] as? [[String: Any]])?.count, 3)
        let text = String(decoding: payload, as: UTF8.self)
        XCTAssertFalse(text.contains("private-unreleased"))
        XCTAssertFalse(text.contains(snapshot.tracks[1].id.uuidString))
        XCTAssertFalse(text.contains("audioFileName"))
        XCTAssertFalse(text.contains("recordedAt"))
    }

    func testGainUsesCapturedBeforeValueAndPreservesEveryOtherField() throws {
        let (snapshot, track) = fixture(), original = try bytes(snapshot.tracks)
        let edits = try context(snapshot, track).decodeProposal(data([gain(track)]))
        let result = try MusicEdit.apply(edits, to: snapshot.tracks)
        var expected = snapshot.tracks; expected[0].volume = 0.7
        XCTAssertEqual(try bytes(result.tracks), try bytes(expected))
        XCTAssertEqual(try bytes(snapshot.tracks), original)
        XCTAssertEqual(try bytes(result.inverse.apply(to: result.tracks)), original)
    }

    func testHatReplacementPreservesKickAndOtherTrack() throws {
        let (snapshot, track) = fixture()
        let proposal: [[String: Any]] = [["kind": "midi_region", "track_id": track.id.uuidString,
                                          "notes": [note(track.notes[1])]]]
        let result = try MusicEdit.apply(context(snapshot, track).decodeProposal(data(proposal)), to: snapshot.tracks)
        XCTAssertEqual(result.tracks[0].notes, [track.notes[0], track.notes[1]])
        XCTAssertEqual(try bytes([result.tracks[1]]), try bytes([snapshot.tracks[1]]))
    }

    func testNewNotesReceiveStableLocalIDsAcrossIdenticalResponseDelivery() throws {
        let (snapshot, track) = fixture(); let request = try context(snapshot, track)
        let new: [String: Any] = ["pitch": 42, "velocity": 90, "start_beat": 2, "duration_beats": 0.25]
        let payload = try data([["kind": "midi_region", "track_id": track.id.uuidString, "notes": [new]]])
        let a = try MusicEdit.apply(request.decodeProposal(payload), to: snapshot.tracks)
        let b = try MusicEdit.apply(request.decodeProposal(payload), to: snapshot.tracks)
        XCTAssertEqual(a.tracks[0].notes, b.tracks[0].notes)
        XCTAssertFalse(Set(track.notes.map(\.id)).contains(a.tracks[0].notes.last!.id))
    }

    func testResponseCannotChooseOtherTracksOrInventBeforeValues() throws {
        let (snapshot, track) = fixture(); let request = try context(snapshot, track)
        XCTAssertThrowsError(try request.decodeProposal(data([gain(snapshot.tracks[1])])))
        var operation = gain(track); operation["before"] = 0.1
        XCTAssertThrowsError(try request.decodeProposal(data([operation])))
    }

    func testUnknownOperationsAndExtraKeysReject() throws {
        let (snapshot, track) = fixture(); let request = try context(snapshot, track)
        for kind in ["shell", "delete_track", "open_url", "set_tempo"] {
            XCTAssertThrowsError(try request.decodeProposal(data([["kind": kind, "track_id": track.id.uuidString]])))
        }
        let payload = try JSONSerialization.data(withJSONObject: ["operations": [gain(track)], "summary": "trust me"])
        XCTAssertThrowsError(try request.decodeProposal(payload))
    }

    func testBooleanStringNonfiniteAndOutOfRangeGainsReject() throws {
        let (snapshot, track) = fixture(); let request = try context(snapshot, track)
        for value in [true, "0.7", -0.1, 1.1] as [Any] {
            XCTAssertThrowsError(try request.decodeProposal(data([gain(track, value)])))
        }
        let raw = "{\"operations\":[{\"kind\":\"gain\",\"track_id\":\"\(track.id)\",\"value\":1e400}]}"
        XCTAssertThrowsError(try request.decodeProposal(Data(raw.utf8)))
    }

    func testFractionalPitchesAndBooleansNeverCoerceIntoMIDIValues() throws {
        let (snapshot, track) = fixture(); let request = try context(snapshot, track)
        for pitch in [true, 42.5, -1, 128] as [Any] {
            let payload = try data([["kind": "midi_region", "track_id": track.id.uuidString,
                                    "notes": [note(track.notes[1], pitch: pitch)]]])
            XCTAssertThrowsError(try request.decodeProposal(payload))
        }
    }

    func testModelCannotExpandRegionOrChangeProtectedKick() throws {
        let (snapshot, track) = fixture(); let request = try context(snapshot, track)
        for changed in [note(track.notes[0], pitch: 36), note(track.notes[1], start: 4)] {
            XCTAssertThrowsError(try request.decodeProposal(data([["kind": "midi_region", "track_id": track.id.uuidString,
                                                                  "notes": [changed]]])))
        }
        var op: [String: Any] = ["kind": "midi_region", "track_id": track.id.uuidString, "notes": []]
        op["end_beat"] = 16
        XCTAssertThrowsError(try request.decodeProposal(data([op])))
    }

    func testGainOnlyContextRejectsNotesAndNoOpGain() throws {
        let (snapshot, track) = fixture(); let request = try context(snapshot, track, midi: false)
        XCTAssertThrowsError(try request.decodeProposal(data([gain(track, 0.5)])))
        XCTAssertThrowsError(try request.decodeProposal(data([["kind": "midi_region", "track_id": track.id.uuidString, "notes": []]])))
    }

    func testDuplicateKindsEmptyAndOversizedOperationsReject() throws {
        let (snapshot, track) = fixture(); let request = try context(snapshot, track)
        for operations in [[], [gain(track), gain(track, 0.8)], Array(repeating: gain(track), count: 17)] {
            XCTAssertThrowsError(try request.decodeProposal(data(operations)))
        }
    }

    func testMalformedAndOversizedResponsesReject() throws {
        let (snapshot, track) = fixture(); let request = try context(snapshot, track)
        for value in ["```json\n{}\n```", "[]", "null", "{", String(repeating: " ", count: 131073)] {
            XCTAssertThrowsError(try request.decodeProposal(Data(value.utf8)))
        }
    }

    func testExistingNoteIdentityCannotBeForgedOrDuplicated() throws {
        let (snapshot, track) = fixture(); let request = try context(snapshot, track)
        var forged = note(track.notes[1]); forged["id"] = UUID().uuidString
        for notes in [[forged], [note(track.notes[1]), note(track.notes[1])]] {
            XCTAssertThrowsError(try request.decodeProposal(data([["kind": "midi_region", "track_id": track.id.uuidString, "notes": notes]])))
        }
    }

    func testInvalidOrCrossingLocalSelectionsRejectBeforeSendingContext() throws {
        let (snapshot, track) = fixture()
        for region in [MusicAssistantContext.Region(startBeat: 0, endBeat: 17, selection: .pitches([42])),
                       .init(startBeat: 0.6, endBeat: 4, selection: .pitches([42])),
                       .init(startBeat: 0, endBeat: 4, selection: .pitches([])),
                       .init(startBeat: 0, endBeat: 4, selection: .noteIDs([UUID()]))] {
            XCTAssertThrowsError(try MusicAssistantContext(snapshot: snapshot, trackID: track.id, region: region))
        }
    }

    func testExplicitNoteSelectionCannotInsertOrChangeAnotherNote() throws {
        let (snapshot, track) = fixture()
        let request = try MusicAssistantContext(snapshot: snapshot, trackID: track.id,
            region: .init(startBeat: 0, endBeat: 4, selection: .noteIDs([track.notes[1].id])))
        let allowed = try data([["kind": "midi_region", "track_id": track.id.uuidString, "notes": [note(track.notes[1], pitch: 46)]]])
        XCTAssertNoThrow(try request.decodeProposal(allowed))
        let disallowed = try data([["kind": "midi_region", "track_id": track.id.uuidString, "notes": [note(track.notes[2])]]])
        XCTAssertThrowsError(try request.decodeProposal(disallowed))
    }

    func testProtectedNotesRejectRemovalThroughDecoder() throws {
        let (snapshot, track) = fixture()
        let request = try MusicAssistantContext(snapshot: snapshot, trackID: track.id,
            region: .init(startBeat: 0, endBeat: 4, selection: .pitches([42])), protectedNoteIDs: [track.notes[1].id])
        XCTAssertThrowsError(try request.decodeProposal(data([["kind": "midi_region", "track_id": track.id.uuidString, "notes": []]])))
    }
}
