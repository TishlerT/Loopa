import Foundation
import Combine
import AVFoundation
import Darwin

/// A renderer transfers ownership of a NEW direct M4A file in a NEW
/// temporaryDirectory/LoopaExport-<UUID> directory. It must use the supplied name.
/// Returning borrowed media, a source vocal, or a caller's saved export is invalid.
@MainActor
protocol MusicPreviewRendering {
    func render(snapshot: MusicalSnapshot, loopLengthBeats: Double,
                soundFontURL: URL, name: String) async throws -> URL
}

@MainActor
protocol MusicPreviewPlaying: AnyObject {
    var currentTime: TimeInterval { get set }
    var duration: TimeInterval { get }
    var isPlaying: Bool { get }
    var onFinish: ((Bool) -> Void)? { get set }
    func prepareToPlay() -> Bool
    func play() -> Bool
    func pause()
    func stop()
}

/// Session-local Original/Change comparison. No canonical mutation, persistence,
/// Keep, Undo, microphone access, or automatic playback is performed here.
///
/// HOST CONTRACT: pause canonical playback and drain its queued audio callbacks
/// before preparing/playing. The required predicate must report that real audio
/// transport AND recording are stopped. Call stop on dismissal, manual edit,
/// recording, session replacement, background/interruption, Keep, or Reject.
/// This adapter does not implement production transport cutover or audio parity.
@MainActor
final class MusicPreview: ObservableObject {
    enum Side: String, CaseIterable { case original, change }

    enum State: Equatable {
        case idle
        case preparing(UUID)
        case prepared(Side)
        case playing(Side)
        case failed(Failure)
    }

    enum Failure: Error, Equatable, LocalizedError {
        case busy, hostPlaybackActive, invalidSnapshot, proposalUnavailable
        case renderFailed, invalidOutput, playerFailed
        case proposal(MusicProposalSession.Failure)

        var errorDescription: String? {
            switch self {
            case .busy: return "Another audio preparation is still finishing. Try again shortly."
            case .hostPlaybackActive: return "Pause playback and recording before comparing this change."
            case .invalidSnapshot: return "This project cannot be prepared for comparison."
            case .proposalUnavailable: return "Prepare a current change before listening."
            case .renderFailed: return "The comparison audio could not be created."
            case .invalidOutput: return "The comparison audio is missing or invalid."
            case .playerFailed: return "The comparison audio could not be played."
            case .proposal: return "This change is no longer available. Request a new change."
            }
        }
    }

    /// Return a fresh player/delegate for each call; playback callbacks belong
    /// to that one playback attempt, including any delayed delegate actor hop.
    typealias PlayerFactory = @MainActor (URL) throws -> MusicPreviewPlaying
    static let maximumDuration: TimeInterval = 30

    @Published private(set) var state: State = .idle
    private(set) var duration: TimeInterval = 0

    var currentTime: TimeInterval {
        guard let player, player.currentTime.isFinite else { return 0 }
        return min(max(player.currentTime, 0), duration)
    }

    private let session: MusicProposalSession
    private let soundFontURL: URL
    private let canonicalPlaybackIsStopped: @MainActor () -> Bool
    private let renderer: MusicPreviewRendering
    private let makePlayer: PlayerFactory
    private var requestID: UUID?
    private var generation = UUID()
    private var playerGeneration = UUID()
    private var isPreparing = false
    private var publishing = false
    private var stopAfterPublication = false
    private var outputs: [Side: OwnedOutput] = [:]
    private var player: MusicPreviewPlaying?
    private var playerSide: Side?

    /// The injection arguments are the same entry point used by production.
    /// Defaults render through AudioExporter.shared and play with AVAudioPlayer.
    init(session: MusicProposalSession, soundFontURL: URL,
         canonicalPlaybackIsStopped: @escaping @MainActor () -> Bool,
         renderer: MusicPreviewRendering? = nil, makePlayer: PlayerFactory? = nil) {
        self.session = session
        self.soundFontURL = soundFontURL
        self.canonicalPlaybackIsStopped = canonicalPlaybackIsStopped
        self.renderer = renderer ?? ExportRenderer()
        self.makePlayer = makePlayer ?? { try SystemPlayer(url: $0) }
    }

    /// Serial, bounded rendering of the original and validated value-copy change.
    /// A cancelled exporter may finish; generation fences discard and delete its
    /// late output. A second prepare is busy until that first renderer returns.
    func prepare(requestID: UUID) async throws {
        guard !isPreparing, !publishing else { throw Failure.busy }
        stop()
        isPreparing = true
        defer { isPreparing = false }
        let preparingGeneration = generation
        self.requestID = requestID
        publish(.preparing(requestID))

        do {
            let candidate = try checkCandidate(requestID)
            guard let request = session.currentRequest, request.id == requestID else {
                throw Failure.proposalUnavailable
            }
            let original = request.snapshot
            let extent = try Self.extent(of: original)
            for (side, snapshot) in [(Side.original, original), (.change, candidate)] {
                try checkPreparation(preparingGeneration, requestID: requestID)
                let name = "Preview-\(UUID().uuidString)-\(side.rawValue)"
                let url = try await renderer.render(snapshot: snapshot, loopLengthBeats: extent.beats,
                                                    soundFontURL: soundFontURL, name: name)
                // Establish ownership BEFORE observing cancellation, so late valid
                // output is also removed. Invalid/borrowed paths are never deleted.
                let output = try OwnedOutput(url: url, expectedName: name + ".m4a")
                do {
                    try checkPreparation(preparingGeneration, requestID: requestID)
                } catch {
                    output.remove()
                    throw error
                }
                outputs[side] = output
            }
            try checkPreparation(preparingGeneration, requestID: requestID)
            duration = extent.seconds
            try preparePlayer(.original, position: 0, requestID: requestID)
            try checkPreparation(preparingGeneration, requestID: requestID)
            publish(.prepared(.original))
        } catch {
            if generation == preparingGeneration {
                clearAudio()
                self.requestID = nil
                if error is CancellationError { publish(.idle) }
                else { publish(.failed(Self.failure(error))) }
            }
            throw error
        }
    }

    /// Explicit playback only. Every attempt gets a fresh player/delegate and
    /// completion generation, including replay of the same side after pausing
    /// or finishing. Stop the old player before starting at the same timestamp.
    func play(_ side: Side) throws {
        guard !isPreparing, !publishing else { throw Failure.busy }
        let playingGeneration = generation
        do {
            guard let requestID else { throw Failure.proposalUnavailable }
            _ = try checkCandidate(requestID)
            guard let output = outputs[side] else { throw Failure.proposalUnavailable }
            try output.validate()
            let position = currentTime
            try preparePlayer(side, position: position, requestID: requestID)
            _ = try checkCandidate(requestID)
            guard let player else { throw Failure.playerFailed }
            // A completed comparison restarts both choices at zero on next Play.
            if player.currentTime >= min(duration, player.duration) { player.currentTime = 0 }
            guard player.play() else { throw Failure.playerFailed }
            _ = try checkCandidate(requestID)
            publish(.playing(side))
        } catch {
            if generation == playingGeneration {
                clearAudio()
                requestID = nil
                publish(.failed(Self.failure(error)))
            }
            throw error
        }
    }

    /// Pause retains prepared files and comparison position. Stop discards them.
    func pause() {
        guard !publishing else { return }
        player?.pause()
        if let playerSide { publish(.prepared(playerSide)) }
    }

    func stop() {
        generation = UUID()
        // Published emits synchronously before assigning. Defer the final idle
        // publication so an observer's cancellation cannot be overwritten.
        if publishing { stopAfterPublication = true; return }
        requestID = nil
        clearAudio()
        publish(.idle)
    }

    private func checkCandidate(_ requestID: UUID) throws -> MusicalSnapshot {
        guard self.requestID == requestID else { throw CancellationError() }
        guard canonicalPlaybackIsStopped() else { throw Failure.hostPlaybackActive }
        guard self.requestID == requestID else { throw CancellationError() }
        do { return try session.candidate(for: requestID) }
        catch let error as MusicProposalSession.Failure { throw Failure.proposal(error) }
    }

    private func publish(_ value: State) {
        guard state != value else { return }
        publishing = true
        state = value
        publishing = false
        if stopAfterPublication {
            stopAfterPublication = false
            stop()
        }
    }

    private func checkPreparation(_ expected: UUID, requestID: UUID) throws {
        try Task.checkCancellation()
        guard generation == expected else { throw CancellationError() }
        _ = try checkCandidate(requestID)
    }

    private func preparePlayer(_ side: Side, position: TimeInterval, requestID: UUID) throws {
        guard let output = outputs[side] else { throw Failure.proposalUnavailable }
        playerGeneration = UUID()
        player?.onFinish = nil
        player?.stop()
        player = nil
        playerSide = nil
        try output.validate()
        _ = try checkCandidate(requestID)
        let next: MusicPreviewPlaying
        do { next = try makePlayer(output.url) }
        catch { throw Failure.playerFailed }
        // Factories are injectable and may invoke synchronous callbacks. Never
        // let a cached snapshot bypass a fresh validation before audio use.
        do { _ = try checkCandidate(requestID) }
        catch { next.stop(); throw error }
        player = next
        guard next.prepareToPlay(), next.duration.isFinite, next.duration > 0 else {
            throw Failure.playerFailed
        }
        _ = try checkCandidate(requestID)
        next.currentTime = min(max(position, 0), min(duration, next.duration))
        playerSide = side
        let expectedPlayer = playerGeneration
        next.onFinish = { [weak self] success in
            guard let self, self.playerGeneration == expectedPlayer,
                  self.state == .playing(side) else { return }
            if success { self.publish(.prepared(side)) }
            else {
                self.clearAudio()
                self.requestID = nil
                self.publish(.failed(.playerFailed))
            }
        }
    }

    private func clearAudio() {
        playerGeneration = UUID()
        player?.onFinish = nil
        player?.stop()
        player = nil
        playerSide = nil
        outputs.values.forEach { $0.remove() }
        outputs.removeAll()
        duration = 0
    }

    private static func extent(of snapshot: MusicalSnapshot) throws -> (beats: Double, seconds: Double) {
        guard !snapshot.tracks.isEmpty, snapshot.tracks.count <= 64,
              snapshot.bpm.isFinite, snapshot.bpm > 0,
              snapshot.tracks.allSatisfy({ $0.recordedLengthBeats.isFinite && $0.recordedLengthBeats > 0 }),
              let beats = snapshot.tracks.map(\.recordedLengthBeats).max() else {
            throw Failure.invalidSnapshot
        }
        // Match MultiTrackLooper's actual extent (longest track), not the bar
        // selector, which describes the length of the NEXT recording.
        let secondsPerBeat = 60 / snapshot.bpm
        let fullDuration = beats * secondsPerBeat
        guard secondsPerBeat.isFinite, secondsPerBeat > 0,
              fullDuration.isFinite, fullDuration >= 1 / 44_100 else { throw Failure.invalidSnapshot }
        let seconds = min(fullDuration, maximumDuration)
        let boundedBeats = seconds / secondsPerBeat
        guard boundedBeats.isFinite, boundedBeats > 0 else { throw Failure.invalidSnapshot }
        return (boundedBeats, seconds)
    }

    private static func failure(_ error: Error) -> Failure {
        (error as? Failure) ?? .renderFailed
    }

    /// Deletes only the exact returned file, and removes its parent only with
    /// rmdir (which refuses nonempty directories). Never recursively remove an
    /// export directory: it could contain another owner's file.
    private final class OwnedOutput {
        let url: URL
        private let expectedName: String

        init(url: URL, expectedName: String) throws {
            self.url = url
            self.expectedName = expectedName
            try validate()
        }

        func validate() throws {
            let fm = FileManager.default
            let root = fm.temporaryDirectory.standardizedFileURL
            let directory = url.deletingLastPathComponent()
            let directoryName = directory.lastPathComponent
            guard url.isFileURL, url == url.standardizedFileURL,
                  url.lastPathComponent == expectedName,
                  directory.deletingLastPathComponent().standardizedFileURL == root,
                  directoryName.hasPrefix("LoopaExport-"),
                  UUID(uuidString: String(directoryName.dropFirst("LoopaExport-".count))) != nil else {
                throw Failure.invalidOutput
            }
            do {
                let parent = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                let file = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                let resolved = root.resolvingSymlinksInPath().appendingPathComponent(directoryName, isDirectory: true)
                    .appendingPathComponent(expectedName).standardizedFileURL
                guard parent.isDirectory == true, parent.isSymbolicLink != true,
                      file.isRegularFile == true, file.isSymbolicLink != true,
                      (file.fileSize ?? 0) > 0,
                      url.resolvingSymlinksInPath().standardizedFileURL == resolved else {
                    throw Failure.invalidOutput
                }
            } catch { throw Failure.invalidOutput }
        }

        func remove() {
            guard (try? validate()) != nil else { return }
            try? FileManager.default.removeItem(at: url)
            // rmdir cannot erase another file added to this directory.
            _ = url.deletingLastPathComponent().path.withCString { rmdir($0) }
        }

        deinit { remove() }
    }

    @MainActor
    private final class ExportRenderer: MusicPreviewRendering {
        // Covers preview calls while the exporter runs off the main executor.
        // AudioExporter's own atomic lease also excludes ordinary Share exports.
        private static var rendering = false

        func render(snapshot: MusicalSnapshot, loopLengthBeats: Double,
                    soundFontURL: URL, name: String) async throws -> URL {
            guard !Self.rendering, !AudioExporter.shared.isExporting else { throw Failure.busy }
            Self.rendering = true
            defer { Self.rendering = false }
            guard let output = await AudioExporter.shared.exportToM4A(
                tracks: snapshot.tracks, bpm: snapshot.bpm, loopLengthBeats: loopLengthBeats,
                sessionName: name, soundFontURL: soundFontURL
            ) else {
                try Task.checkCancellation()
                throw Failure.renderFailed
            }
            return output
        }
    }

    @MainActor
    private final class SystemPlayer: NSObject, MusicPreviewPlaying, AVAudioPlayerDelegate {
        private let audio: AVAudioPlayer
        var onFinish: ((Bool) -> Void)?
        var currentTime: TimeInterval {
            get { audio.currentTime }
            set { audio.currentTime = newValue }
        }
        var duration: TimeInterval { audio.duration }
        var isPlaying: Bool { audio.isPlaying }

        init(url: URL) throws {
            audio = try AVAudioPlayer(contentsOf: url)
            super.init()
            audio.numberOfLoops = 0
            audio.delegate = self
        }

        func prepareToPlay() -> Bool { audio.prepareToPlay() }
        func play() -> Bool { audio.play() }
        func pause() { audio.pause() }
        func stop() { audio.stop() }

        nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            // This SystemPlayer is never reused for a subsequent playback.
            // Its callback is cleared when retired; the actor hop therefore
            // cannot look up a newer attempt's callback on this instance.
            Task { @MainActor [weak self] in self?.onFinish?(flag) }
        }

        nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
            Task { @MainActor [weak self] in self?.onFinish?(false) }
        }
    }
}
