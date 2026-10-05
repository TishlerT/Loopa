import Foundation
import CoreFoundation

enum MusicAssistantProtocolError: Error, Equatable {
    case invalidContext, malformedResponse, payloadTooLarge, unsupportedOperation, outsideSelection
    case invalidProposal(MusicEditError)
}

/// A captured local request. This is the only source of before-values and edit
/// authority; provider output cannot choose its own project, region or revision.
struct MusicAssistantContext {
    struct Region {
        let startBeat: Double
        let endBeat: Double
        let selection: MusicNoteSelection
    }

    static let maximumPayloadBytes = 131_072
    let requestID: UUID
    let snapshot: MusicalSnapshot
    let trackID: UUID
    let region: Region?
    let protectedNoteIDs: Set<UUID>
    private let selectedTrack: Track
    private let selectedNotes: [MidiNote]
    // Stable across retries of this request; new identities are assigned locally.
    private let newNoteIDs: [UUID]

    init(requestID: UUID = UUID(), snapshot: MusicalSnapshot, trackID: UUID,
         region: Region? = nil, protectedNoteIDs: Set<UUID> = []) throws {
        guard !snapshot.tracks.isEmpty, snapshot.tracks.count <= 64,
              Set(snapshot.tracks.map(\.id)).count == snapshot.tracks.count,
              snapshot.bpm.isFinite, snapshot.bpm > 0,
              let track = snapshot.tracks.first(where: { $0.id == trackID }),
              track.volume.isFinite, (0...1).contains(track.volume),
              track.recordedLengthBeats.isFinite, track.recordedLengthBeats > 0,
              track.notes.count <= MusicEdit.maximumNotesPerTrack else {
            throw MusicAssistantProtocolError.invalidContext
        }
        self.requestID = requestID; self.snapshot = snapshot; self.trackID = trackID
        self.region = region; self.protectedNoteIDs = protectedNoteIDs; self.selectedTrack = track
        self.newNoteIDs = (0..<MusicEdit.maximumNotesPerRegion).map { _ in UUID() }
        if let region {
            guard track.trackType == .midi,
                  region.startBeat.isFinite, region.endBeat.isFinite,
                  region.startBeat >= 0, region.endBeat > region.startBeat,
                  region.endBeat - region.startBeat <= MusicEdit.maximumRegionBeats,
                  region.endBeat <= track.recordedLengthBeats else {
                throw MusicAssistantProtocolError.invalidContext
            }
            switch region.selection {
            case .pitches(let pitches):
                guard !pitches.isEmpty, pitches.allSatisfy({ (0...127).contains($0) }) else {
                    throw MusicAssistantProtocolError.invalidContext
                }
            case .noteIDs(let ids):
                guard !ids.isEmpty, ids.isSubset(of: Set(track.notes.map(\.id))) else {
                    throw MusicAssistantProtocolError.invalidContext
                }
            }
            let selected = track.notes.filter { Self.matches($0, region.selection) }
            guard selected.allSatisfy({ note in
                let overlaps = note.startBeat < region.endBeat && note.endBeat > region.startBeat
                return !overlaps || (note.startBeat >= region.startBeat && note.endBeat <= region.endBeat)
            }) else { throw MusicAssistantProtocolError.invalidContext }
            self.selectedNotes = selected.filter { $0.startBeat >= region.startBeat && $0.startBeat < region.endBeat }
            if case .noteIDs(let ids) = region.selection,
               ids != Set(selectedNotes.map(\.id)) { throw MusicAssistantProtocolError.invalidContext }
            guard selectedNotes.count <= MusicEdit.maximumNotesPerRegion,
                  Set(track.notes.map(\.id)).count == track.notes.count,
                  track.notes.allSatisfy({ $0.startBeat.isFinite && $0.startBeat >= 0 &&
                      $0.durationBeats.isFinite && $0.durationBeats >= 0.0625 && $0.endBeat.isFinite }) else {
                throw MusicAssistantProtocolError.invalidContext
            }
        } else {
            self.selectedNotes = []
        }
    }

    /// Compact musical context only. Source filenames, recordings, dates and
    /// other tracks' content never enter this payload. Labels are known enums.
    func encodedProject() throws -> Data {
        var object: [String: Any] = [
            "version": 1, "request_id": requestID.uuidString, "tempo_bpm": snapshot.bpm,
            "loop_beats": snapshot.barCount.rawValue * 4,
            "track": ["id": trackID.uuidString, "kind": selectedTrack.trackType.rawValue,
                      "instrument": selectedTrack.isVocal ? "Vocals" : (selectedTrack.instrument?.rawValue ?? "Instrument"),
                      "volume": selectedTrack.volume, "muted": selectedTrack.isMuted,
                      "solo": selectedTrack.isSolo, "length_beats": selectedTrack.recordedLengthBeats,
                      "audible": selectedTrack.isAudible(anyTrackSoloed: snapshot.tracks.contains(where: \.isSolo))],
            "capabilities": region == nil ? ["gain"] : ["gain", "midi_region"]
        ]
        if let region {
            var selection: [String: Any] = ["start_beat": region.startBeat, "end_beat": region.endBeat]
            switch region.selection {
            case .pitches(let pitches): selection["pitches"] = pitches.sorted()
            case .noteIDs(let ids): selection["note_ids"] = ids.map(\.uuidString).sorted()
            }
            object["selection"] = selection
            // Include protected musical context within the same selected region
            // so a hat edit can follow the kick, without granting edit authority.
            let notes = selectedTrack.notes.filter { $0.startBeat < region.endBeat && $0.endBeat > region.startBeat }
            guard notes.count <= MusicEdit.maximumNotesPerRegion else { throw MusicAssistantProtocolError.payloadTooLarge }
            object["notes"] = notes.map { note in
                ["id": note.id.uuidString, "pitch": Int(note.pitch), "velocity": Int(note.velocity),
                 "start_beat": note.startBeat, "duration_beats": note.durationBeats,
                 "editable": selectedNotes.contains(where: { $0.id == note.id }) && !protectedNoteIDs.contains(note.id)] as [String: Any]
            }
        }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard data.count <= Self.maximumPayloadBytes else { throw MusicAssistantProtocolError.payloadTooLarge }
        return data
    }

    /// Accept only a completed provider response. This returns checked values;
    /// it never changes a session or starts playback. The lifecycle owner must
    /// additionally recheck request identity and current session revision.
    func decodeProposal(_ data: Data) throws -> [MusicEdit] {
        guard data.count <= Self.maximumPayloadBytes else { throw MusicAssistantProtocolError.payloadTooLarge }
        guard let root = try? JSONSerialization.jsonObject(with: data),
              let object = root as? [String: Any], Set(object.keys) == ["operations"],
              let operations = object["operations"] as? [[String: Any]],
              !operations.isEmpty, operations.count <= 2 else {
            throw MusicAssistantProtocolError.malformedResponse
        }
        var edits: [MusicEdit] = []; var kinds = Set<String>()
        for operation in operations {
            guard let kind = operation["kind"] as? String,
                  let idText = operation["track_id"] as? String, let id = UUID(uuidString: idText),
                  kinds.insert(kind).inserted else { throw MusicAssistantProtocolError.malformedResponse }
            guard id == trackID else { throw MusicAssistantProtocolError.outsideSelection }
            switch kind {
            case "gain":
                guard Set(operation.keys) == ["kind", "track_id", "value"] else {
                    throw MusicAssistantProtocolError.malformedResponse
                }
                let value = try Self.number(operation["value"])
                guard (0...1).contains(value) else { throw MusicAssistantProtocolError.malformedResponse }
                edits.append(.gain(trackID: trackID, before: selectedTrack.volume, after: Float(value)))
            case "midi_region":
                guard let region else { throw MusicAssistantProtocolError.outsideSelection }
                guard Set(operation.keys) == ["kind", "track_id", "notes"],
                      let notes = operation["notes"] as? [[String: Any]],
                      notes.count <= MusicEdit.maximumNotesPerRegion else { throw MusicAssistantProtocolError.malformedResponse }
                let allowedIDs = Set(selectedNotes.map(\.id))
                let after: [MusicNoteInput] = try notes.enumerated().map { index, note in
                    let required: Set<String> = ["pitch", "velocity", "start_beat", "duration_beats"]
                    guard required.isSubset(of: Set(note.keys)), Set(note.keys).isSubset(of: required.union(["id"])) else {
                        throw MusicAssistantProtocolError.malformedResponse
                    }
                    let noteID: UUID
                    if let rawID = note["id"] {
                        guard let string = rawID as? String, let parsed = UUID(uuidString: string), allowedIDs.contains(parsed) else {
                            throw MusicAssistantProtocolError.outsideSelection
                        }
                        noteID = parsed
                    } else {
                        noteID = newNoteIDs[index]
                    }
                    return MusicNoteInput(id: noteID, pitch: try Self.integer(note["pitch"], in: 0...127),
                        velocity: try Self.integer(note["velocity"], in: 1...127),
                        startBeat: try Self.number(note["start_beat"]), durationBeats: try Self.number(note["duration_beats"]))
                }
                edits.append(.midiRegion(trackID: trackID, startBeat: region.startBeat, endBeat: region.endBeat,
                                        selection: region.selection, before: selectedNotes, after: after))
            default: throw MusicAssistantProtocolError.unsupportedOperation
            }
        }
        do {
            _ = try MusicEdit.apply(edits, to: snapshot.tracks,
                                    protectedTrackIDs: Set(snapshot.tracks.map(\.id)).subtracting([trackID]),
                                    protectedNoteIDs: protectedNoteIDs)
        } catch let error as MusicEditError { throw MusicAssistantProtocolError.invalidProposal(error) }
        return edits
    }

    private static func matches(_ note: MidiNote, _ selection: MusicNoteSelection) -> Bool {
        switch selection {
        case .pitches(let pitches): return pitches.contains(Int(note.pitch))
        case .noteIDs(let ids): return ids.contains(note.id)
        }
    }

    private static func number(_ value: Any?) throws -> Double {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else {
            throw MusicAssistantProtocolError.malformedResponse
        }
        return value.doubleValue
    }

    private static func integer(_ value: Any?, in bounds: ClosedRange<Int>) throws -> Int {
        let value = try number(value)
        guard value.rounded(.towardZero) == value, value >= Double(bounds.lowerBound), value <= Double(bounds.upperBound) else {
            throw MusicAssistantProtocolError.malformedResponse
        }
        return Int(value)
    }
}
