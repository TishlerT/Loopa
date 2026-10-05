import Foundation

/// Untrusted note values. Validate these before using MidiNote's clamping initializer.
/// A caller assigns IDs to new notes; existing notes retain their IDs.
struct MusicNoteInput: Equatable {
    let id: UUID
    let pitch: Int
    let velocity: Int
    let startBeat: Double
    let durationBeats: Double

    init(id: UUID, pitch: Int, velocity: Int, startBeat: Double, durationBeats: Double) {
        self.id = id
        self.pitch = pitch
        self.velocity = velocity
        self.startBeat = startBeat
        self.durationBeats = durationBeats
    }

    init(_ note: MidiNote) {
        self.init(id: note.id, pitch: Int(note.pitch), velocity: Int(note.velocity),
                  startBeat: note.startBeat, durationBeats: note.durationBeats)
    }

    fileprivate func validatedNote() throws -> MidiNote {
        let endBeat = startBeat + durationBeats
        guard (0...127).contains(pitch), (1...127).contains(velocity),
              startBeat.isFinite, startBeat >= 0,
              durationBeats.isFinite, durationBeats >= 0.0625,
              endBeat.isFinite, endBeat > startBeat else {
            throw MusicEditError.invalidNote
        }
        return MidiNote(id: id, pitch: UInt8(pitch), velocity: UInt8(velocity),
                        startBeat: startBeat, durationBeats: durationBeats)
    }
}

/// Pitch selection can insert new notes in those lanes. ID selection can only
/// change or remove the specified existing notes, including changing their pitch.
enum MusicNoteSelection {
    case pitches(Set<Int>)
    case noteIDs(Set<UUID>)
}

enum MusicEditError: Error, Equatable {
    case missingTrack, wrongTrackKind, missingNote
    case duplicateTrackID, duplicateNoteID
    case invalidGain, invalidNote, invalidScope, invalidSelection
    case tooManyNotes, tooManyOperations
    case outsideScope, protectedTrack, protectedNote
    case staleBefore, noChange
}

/// Only musical values are changed. This pure foundation does not own session
/// revisions, persistence, playback, async requests, or duplicate-request receipts.
enum MusicEdit {
    /// Linear whole-track gain, never an implicit unmute or relative adjustment.
    case gain(trackID: UUID, before: Float, after: Float)
    /// Half-open [startBeat, endBeat), limited to four 4/4 bars. `before` is the
    /// exact selected notes in current array order. Crossing notes are rejected.
    case midiRegion(trackID: UUID, startBeat: Double, endBeat: Double,
                    selection: MusicNoteSelection, before: [MidiNote], after: [MusicNoteInput])

    static let maximumOperations = 16
    static let maximumNotesPerRegion = 512
    static let maximumNotesPerTrack = 4096
    static let maximumRegionBeats: Double = 16

    /// Returns a value copy and an opaque exact inverse, or throws without
    /// changing the input. Operations in a batch see preceding operations' values.
    /// Protections are enforced for every operation, not just the final result.
    static func apply(_ edits: [MusicEdit], to tracks: [Track],
                      protectedTrackIDs: Set<UUID> = [],
                      protectedNoteIDs: Set<UUID> = []) throws -> MusicEditResult {
        guard !edits.isEmpty else { throw MusicEditError.noChange }
        guard edits.count <= maximumOperations else { throw MusicEditError.tooManyOperations }
        try validateTracks(tracks)
        var candidate = tracks
        var inverse: [MusicEditInverse.Step] = []
        for edit in edits {
            switch edit {
            case let .gain(trackID, before, after):
                let index = try trackIndex(trackID, in: candidate)
                guard !protectedTrackIDs.contains(trackID) else { throw MusicEditError.protectedTrack }
                guard validGain(before), validGain(after), validGain(candidate[index].volume) else {
                    throw MusicEditError.invalidGain
                }
                guard candidate[index].volume == before else { throw MusicEditError.staleBefore }
                guard before != after else { throw MusicEditError.noChange }
                let previous = candidate[index].volume
                candidate[index].volume = after
                inverse.append(.gain(trackID: trackID, expected: after, restored: previous))

            case let .midiRegion(trackID, start, end, selection, before, after):
                let index = try trackIndex(trackID, in: candidate)
                let track = candidate[index]
                guard !protectedTrackIDs.contains(trackID) else { throw MusicEditError.protectedTrack }
                guard track.trackType == .midi else { throw MusicEditError.wrongTrackKind }
                guard start.isFinite, end.isFinite, start >= 0, end > start,
                      end - start <= maximumRegionBeats,
                      track.recordedLengthBeats.isFinite, end <= track.recordedLengthBeats else {
                    throw MusicEditError.invalidScope
                }
                guard before.count <= maximumNotesPerRegion, after.count <= maximumNotesPerRegion else {
                    throw MusicEditError.tooManyNotes
                }
                try validateNoteIDs(before.map(\.id))
                try validateNoteIDs(after.map(\.id))
                for note in before { _ = try MusicNoteInput(note).validatedNote() }
                // Validate all raw fields before any UInt8 conversion or MidiNote construction.
                let replacement = try after.map { try $0.validatedNote() }
                let selected = try selectedNotes(in: track.notes, start: start, end: end, selection: selection)
                guard selected.count <= maximumNotesPerRegion else { throw MusicEditError.tooManyNotes }
                guard selected == before else { throw MusicEditError.staleBefore }
                let selectedIDs = Set(selected.map(\.id))
                let otherIDs = Set(candidate.flatMap { $0.notes }.map(\.id)).subtracting(selectedIDs)
                for note in replacement {
                    guard note.startBeat >= start, note.startBeat < end, note.endBeat <= end else {
                        throw MusicEditError.outsideScope
                    }
                    switch selection {
                    case let .pitches(pitches):
                        guard pitches.contains(Int(note.pitch)) else { throw MusicEditError.outsideScope }
                    case let .noteIDs(ids):
                        guard ids.contains(note.id) else { throw MusicEditError.outsideScope }
                    }
                    guard !otherIDs.contains(note.id) else { throw MusicEditError.duplicateNoteID }
                }
                let replacementByID = Dictionary(uniqueKeysWithValues: replacement.map { ($0.id, $0) })
                for note in selected where protectedNoteIDs.contains(note.id) {
                    guard replacementByID[note.id] == note else { throw MusicEditError.protectedNote }
                }
                // Array-order changes alone have no musical effect.
                guard musicalValues(selected) != musicalValues(replacement) else { throw MusicEditError.noChange }
                let resultingCount = track.notes.count - selected.count + replacement.count
                guard resultingCount <= maximumNotesPerTrack else { throw MusicEditError.tooManyNotes }
                var notes: [MidiNote] = []
                var inserted = false
                for note in track.notes {
                    if selectedIDs.contains(note.id) {
                        if !inserted { notes.append(contentsOf: replacement); inserted = true }
                    } else {
                        notes.append(note)
                    }
                }
                if !inserted { notes.append(contentsOf: replacement) }
                candidate[index].notes = notes
                inverse.append(.notes(trackID: trackID, expected: notes, restored: track.notes))
            }
        }
        guard zip(tracks, candidate).contains(where: { original, updated in
            (original.volume.bitPattern != updated.volume.bitPattern && original.volume != updated.volume)
                || musicalValues(original.notes) != musicalValues(updated.notes)
        }) else { throw MusicEditError.noChange }
        return MusicEditResult(tracks: candidate, inverse: MusicEditInverse(steps: Array(inverse.reversed())))
    }

    /// Ignore identity/order-only churn, but count coincident notes separately.
    private struct NoteValue: Hashable {
        let pitch: UInt8
        let velocity: UInt8
        let start: Double
        let duration: Double
    }

    private static func musicalValues(_ notes: [MidiNote]) -> [NoteValue: Int] {
        var counts: [NoteValue: Int] = [:]
        for note in notes {
            let value = NoteValue(pitch: note.pitch, velocity: note.velocity,
                                  start: note.startBeat, duration: note.durationBeats)
            counts[value, default: 0] += 1
        }
        return counts
    }

    fileprivate static func validGain(_ value: Float) -> Bool {
        value.isFinite && (0...1).contains(value)
    }

    fileprivate static func trackIndex(_ id: UUID, in tracks: [Track]) throws -> Int {
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { throw MusicEditError.missingTrack }
        return index
    }

    fileprivate static func validateNoteIDs(_ ids: [UUID]) throws {
        guard Set(ids).count == ids.count else { throw MusicEditError.duplicateNoteID }
    }

    fileprivate static func validateTracks(_ tracks: [Track]) throws {
        guard Set(tracks.map(\.id)).count == tracks.count else { throw MusicEditError.duplicateTrackID }
        var noteIDs = Set<UUID>()
        for track in tracks {
            guard track.notes.count <= maximumNotesPerTrack else { throw MusicEditError.tooManyNotes }
            for note in track.notes {
                guard noteIDs.insert(note.id).inserted else { throw MusicEditError.duplicateNoteID }
                _ = try MusicNoteInput(note).validatedNote()
            }
        }
    }

    private static func selectedNotes(in notes: [MidiNote], start: Double, end: Double,
                                      selection: MusicNoteSelection) throws -> [MidiNote] {
        switch selection {
        case let .pitches(pitches):
            guard !pitches.isEmpty, pitches.allSatisfy({ (0...127).contains($0) }) else {
                throw MusicEditError.invalidSelection
            }
            let intersecting = notes.filter {
                pitches.contains(Int($0.pitch)) && $0.startBeat < end && $0.endBeat > start
            }
            guard intersecting.allSatisfy({ $0.startBeat >= start && $0.endBeat <= end }) else {
                throw MusicEditError.outsideScope
            }
            return intersecting
        case let .noteIDs(ids):
            guard !ids.isEmpty else { throw MusicEditError.invalidSelection }
            guard ids.count <= maximumNotesPerRegion else { throw MusicEditError.tooManyNotes }
            let selected = notes.filter { ids.contains($0.id) }
            guard selected.count == ids.count else { throw MusicEditError.missingNote }
            guard selected.allSatisfy({ $0.startBeat >= start && $0.startBeat < end && $0.endBeat <= end }) else {
                throw MusicEditError.outsideScope
            }
            return selected
        }
    }
}

struct MusicEditResult {
    let tracks: [Track]
    let inverse: MusicEditInverse
}

/// Only apply() creates these receipts. They retain exact affected fields, including
/// note array order and IDs. An inverse cannot overwrite a newer value in that field.
/// Other fields stay current; session-level staleness remains the future owner's job.
struct MusicEditInverse {
    fileprivate enum Step {
        case gain(trackID: UUID, expected: Float, restored: Float)
        case notes(trackID: UUID, expected: [MidiNote], restored: [MidiNote])
    }
    fileprivate let steps: [Step]

    func apply(to tracks: [Track]) throws -> [Track] {
        try MusicEdit.validateTracks(tracks)
        var candidate = tracks
        for step in steps {
            switch step {
            case let .gain(trackID, expected, restored):
                let index = try MusicEdit.trackIndex(trackID, in: candidate)
                guard candidate[index].volume == expected else { throw MusicEditError.staleBefore }
                candidate[index].volume = restored
            case let .notes(trackID, expected, restored):
                let index = try MusicEdit.trackIndex(trackID, in: candidate)
                guard candidate[index].trackType == .midi else { throw MusicEditError.wrongTrackKind }
                guard candidate[index].notes == expected else { throw MusicEditError.staleBefore }
                candidate[index].notes = restored
            }
        }
        try MusicEdit.validateTracks(candidate)
        return candidate
    }
}
