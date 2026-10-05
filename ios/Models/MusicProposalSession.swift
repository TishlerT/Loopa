import Foundation
import Combine

/// Owns one in-flight proposal, never the project's tracks, audio, or storage.
/// Model replies remain untrusted until scope and the captured canonical token pass.
@MainActor
final class MusicProposalSession: ObservableObject {
    struct Region {
        let startBeat: Double
        let endBeat: Double
        let selection: MusicNoteSelection
    }

    /// Authority is assigned locally before requesting a proposal. One existing
    /// track and at most four bars are supported; permission is never model supplied.
    struct Scope {
        let trackID: UUID
        let allowsGain: Bool
        let midiRegion: Region?
        let protectedTrackIDs: Set<UUID>
        let protectedNoteIDs: Set<UUID>

        init(trackID: UUID, allowsGain: Bool = false, midiRegion: Region? = nil,
             protectedTrackIDs: Set<UUID> = [], protectedNoteIDs: Set<UUID> = []) {
            self.trackID = trackID
            self.allowsGain = allowsGain
            self.midiRegion = midiRegion
            self.protectedTrackIDs = protectedTrackIDs
            self.protectedNoteIDs = protectedNoteIDs
        }
    }

    struct Request {
        let id: UUID
        let snapshot: MusicalSnapshot
        let scope: Scope
    }

    /// A historical acknowledgement, not authority for another commit. Retrying
    /// Keep returns this same value even after Undo or later manual work.
    struct Receipt: Equatable {
        let requestID: UUID
        let beforeToken: MusicalToken
        let committedToken: MusicalToken
    }

    enum Phase: Equatable {
        case idle
        case requesting(UUID), ready(UUID), kept(UUID)
        case cancelled(UUID), rejected(UUID), invalidated(UUID), undone(UUID)
    }

    enum Failure: Error, Equatable {
        case busy, stale, unknownRequest, requestInvalidated, proposalUnavailable
        case payloadChanged, invalidScope, outsideScope
        case invalidEdit(MusicEditError)
    }

    @Published private(set) var phase: Phase = .idle
    private(set) var currentRequest: Request?

    /// A value-copy preview for display. Its token names the ORIGINAL snapshot;
    /// the candidate is not committed state. Audio adapters must call candidate(for:)
    /// immediately before using it so manual edits invalidate a cached preview.
    private(set) var candidateSnapshot: MusicalSnapshot?

    /// Bounded, session-local receipts. Evicted IDs fail closed, never reapply.
    /// Neither proposals nor Undo are durable across a new instance/app restart.
    static let maximumRetainedReceipts = 50

    private struct CommitRecord {
        let receipt: Receipt
        let inverse: MusicEditInverse
        var undoneToken: MusicalToken?
    }

    private let looper: MultiTrackLooper
    private var frozenEdits: [MusicEdit]?
    private var commits: [UUID: CommitRecord] = [:]
    private var commitOrder: [UUID] = []
    // Combine publications can synchronously call back into this MainActor class.
    private var isMutating = false

    init(looper: MultiTrackLooper) {
        self.looper = looper
    }

    @discardableResult
    func beginRequest(scope: Scope) throws -> Request {
        try enter(); defer { isMutating = false }
        switch phase {
        case .requesting, .ready: throw Failure.busy
        default: break
        }
        let snapshot = try canonicalSnapshot()
        try validate(scope, in: snapshot)
        let request = Request(id: UUID(), snapshot: snapshot, scope: scope)
        currentRequest = request
        frozenEdits = nil
        candidateSnapshot = nil
        phase = .requesting(request.id)
        return request
    }

    /// Validates a typed model response without mutating canonical tracks. Once
    /// ready, byte-value-equivalent retries are accepted; a changed payload fails.
    @discardableResult
    func receive(_ edits: [MusicEdit], for requestID: UUID) throws -> MusicalSnapshot {
        try enter(); defer { isMutating = false }
        let request = try activeRequest(requestID)
        if let frozenEdits {
            guard Self.sameEdits(frozenEdits, edits) else { throw Failure.payloadChanged }
        }
        guard phase == .requesting(requestID) || phase == .ready(requestID) else {
            throw Failure.proposalUnavailable
        }
        try checkCurrent(request)
        if let candidateSnapshot { return candidateSnapshot }
        try validate(edits, scope: request.scope)
        let result: MusicEditResult
        do {
            result = try MusicEdit.apply(edits, to: request.snapshot.tracks,
                                         protectedTrackIDs: request.scope.protectedTrackIDs,
                                         protectedNoteIDs: request.scope.protectedNoteIDs)
        } catch let error as MusicEditError {
            throw Failure.invalidEdit(error)
        }
        // A second check also fences a concurrent legacy looper mutation during
        // pure validation. Any later change is checked again by candidate/Keep.
        try checkCurrent(request)
        let candidate = MusicalSnapshot(token: request.snapshot.token, tracks: result.tracks,
                                        bpm: request.snapshot.bpm, barCount: request.snapshot.barCount)
        frozenEdits = edits
        candidateSnapshot = candidate
        phase = .ready(requestID)
        return candidate
    }

    func candidate(for requestID: UUID) throws -> MusicalSnapshot {
        try enter(); defer { isMutating = false }
        let request = try activeRequest(requestID)
        guard phase == .ready(requestID), let candidateSnapshot else {
            throw Failure.proposalUnavailable
        }
        try checkCurrent(request)
        return candidateSnapshot
    }

    /// The only acceptance route. The looper revalidates against canonical state
    /// and refuses playing/recording. This is a model-only commit, not audio cutover
    /// or durable save; those remain the calling adapter's responsibilities.
    @discardableResult
    func keep(requestID: UUID) throws -> Receipt {
        try enter(); defer { isMutating = false }
        if let record = commits[requestID] { return record.receipt }
        let request = try activeRequest(requestID)
        guard phase == .ready(requestID), let frozenEdits else { throw Failure.proposalUnavailable }
        try validate(frozenEdits, scope: request.scope)
        let commit: MusicalEditCommit
        do {
            commit = try looper.applyMusicEdits(frozenEdits, expectedToken: request.snapshot.token,
                                                protectedTrackIDs: request.scope.protectedTrackIDs,
                                                protectedNoteIDs: request.scope.protectedNoteIDs)
        } catch let error as MusicalCommitError {
            if error == .stale { invalidate(requestID) }
            throw Self.failure(error)
        }
        let receipt = Receipt(requestID: requestID, beforeToken: request.snapshot.token,
                              committedToken: commit.token)
        commits[requestID] = CommitRecord(receipt: receipt, inverse: commit.inverse)
        commitOrder.append(requestID)
        if commitOrder.count > Self.maximumRetainedReceipts {
            commits.removeValue(forKey: commitOrder.removeFirst())
        }
        candidateSnapshot = nil
        phase = .kept(requestID)
        return receipt
    }

    func cancel(requestID: UUID) throws {
        try finish(requestID, as: .cancelled(requestID))
    }

    func reject(requestID: UUID) throws {
        try finish(requestID, as: .rejected(requestID))
    }

    /// Undo is an exact inverse checked against its post-commit token. It never
    /// restores an old whole session over newer manual edits. A retry is idempotent.
    @discardableResult
    func undo(requestID: UUID) throws -> MusicalToken {
        try enter(); defer { isMutating = false }
        guard var record = commits[requestID] else { throw Failure.unknownRequest }
        if let undoneToken = record.undoneToken { return undoneToken }
        let token: MusicalToken
        do {
            token = try looper.applyMusicInverse(record.inverse, expectedToken: record.receipt.committedToken)
        } catch let error as MusicalCommitError {
            throw Self.failure(error)
        }
        record.undoneToken = token
        commits[requestID] = record
        // An Undo can arrive while a newer request is pending. Its old snapshot
        // must not remain eligible; late replies will fail the request-ID check.
        if currentRequest?.id != requestID { currentRequest = nil }
        candidateSnapshot = nil
        frozenEdits = nil
        phase = .undone(requestID)
        return token
    }

    private func enter() throws {
        guard !isMutating else { throw Failure.busy }
        isMutating = true
    }

    private func activeRequest(_ id: UUID) throws -> Request {
        guard let request = currentRequest, request.id == id else { throw Failure.unknownRequest }
        switch phase {
        case .cancelled, .rejected, .invalidated: throw Failure.requestInvalidated
        default: return request
        }
    }

    private func finish(_ id: UUID, as terminal: Phase) throws {
        try enter(); defer { isMutating = false }
        _ = try activeRequest(id)
        guard phase == .requesting(id) || phase == .ready(id) else { throw Failure.proposalUnavailable }
        frozenEdits = nil
        candidateSnapshot = nil
        phase = terminal
    }

    private func canonicalSnapshot() throws -> MusicalSnapshot {
        do { return try looper.musicSnapshot() }
        catch let error as MusicalCommitError { throw Self.failure(error) }
    }

    private func checkCurrent(_ request: Request) throws {
        guard try canonicalSnapshot().token == request.snapshot.token else {
            invalidate(request.id)
            throw Failure.stale
        }
    }

    private func invalidate(_ id: UUID) {
        frozenEdits = nil
        candidateSnapshot = nil
        phase = .invalidated(id)
    }

    private static func failure(_ error: MusicalCommitError) -> Failure {
        switch error {
        case .busy: return .busy
        case .stale: return .stale
        case let .invalidEdit(error): return .invalidEdit(error)
        }
    }

    private func validate(_ scope: Scope, in snapshot: MusicalSnapshot) throws {
        guard scope.allowsGain || scope.midiRegion != nil,
              let track = snapshot.tracks.first(where: { $0.id == scope.trackID }) else {
            throw Failure.invalidScope
        }
        guard let region = scope.midiRegion else { return }
        guard track.trackType == .midi,
              region.startBeat.isFinite, region.endBeat.isFinite,
              region.startBeat >= 0, region.endBeat > region.startBeat,
              region.endBeat - region.startBeat <= MusicEdit.maximumRegionBeats,
              track.recordedLengthBeats.isFinite, region.endBeat <= track.recordedLengthBeats else {
            throw Failure.invalidScope
        }
        switch region.selection {
        case let .pitches(pitches):
            guard !pitches.isEmpty, pitches.allSatisfy({ (0...127).contains($0) }) else {
                throw Failure.invalidScope
            }
        case let .noteIDs(ids):
            let notes = track.notes.filter { ids.contains($0.id) }
            guard !ids.isEmpty, ids.count <= MusicEdit.maximumNotesPerRegion,
                  notes.count == ids.count,
                  notes.allSatisfy({ $0.startBeat >= region.startBeat && $0.endBeat <= region.endBeat }) else {
                throw Failure.invalidScope
            }
        }
    }

    private func validate(_ edits: [MusicEdit], scope: Scope) throws {
        guard !edits.isEmpty else { throw Failure.invalidEdit(.noChange) }
        guard edits.count <= MusicEdit.maximumOperations else { throw Failure.invalidEdit(.tooManyOperations) }
        for edit in edits {
            switch edit {
            case let .gain(trackID, _, _):
                guard trackID == scope.trackID, scope.allowsGain else { throw Failure.outsideScope }
            case let .midiRegion(trackID, start, end, selection, _, _):
                guard trackID == scope.trackID, let region = scope.midiRegion,
                      start.isFinite, end.isFinite,
                      start >= region.startBeat, end <= region.endBeat,
                      Self.isSubset(selection, of: region.selection) else { throw Failure.outsideScope }
            }
        }
    }

    private static func isSubset(_ selected: MusicNoteSelection, of allowed: MusicNoteSelection) -> Bool {
        switch (selected, allowed) {
        case let (.pitches(selected), .pitches(allowed)): return selected.isSubset(of: allowed)
        case let (.noteIDs(selected), .noteIDs(allowed)): return selected.isSubset(of: allowed)
        default: return false // Never translate authority between lanes and IDs implicitly.
        }
    }

    private static func sameSelection(_ lhs: MusicNoteSelection, _ rhs: MusicNoteSelection) -> Bool {
        switch (lhs, rhs) {
        case let (.pitches(a), .pitches(b)): return a == b
        case let (.noteIDs(a), .noteIDs(b)): return a == b
        default: return false
        }
    }

    private static func sameEdits(_ lhs: [MusicEdit], _ rhs: [MusicEdit]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { first, second in
            switch (first, second) {
            case let (.gain(aID, aBefore, aAfter), .gain(bID, bBefore, bAfter)):
                return aID == bID && aBefore.bitPattern == bBefore.bitPattern && aAfter.bitPattern == bAfter.bitPattern
            case let (.midiRegion(aID, aStart, aEnd, aSelection, aBefore, aAfter),
                      .midiRegion(bID, bStart, bEnd, bSelection, bBefore, bAfter)):
                return aID == bID && aStart.bitPattern == bStart.bitPattern && aEnd.bitPattern == bEnd.bitPattern &&
                    sameSelection(aSelection, bSelection) && aBefore == bBefore && aAfter == bAfter
            default: return false
            }
        }
    }
}
