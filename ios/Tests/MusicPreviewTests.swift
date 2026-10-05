import XCTest
import AVFoundation
import Combine
@testable import Loopa

@MainActor
final class MusicPreviewTests: XCTestCase {
    private final class Renderer: MusicPreviewRendering {
        var calls: [(MusicalSnapshot, Double, String)] = []
        var action: ((Int, String) async throws -> URL)?
        var outputs: [URL] = []

        func render(snapshot: MusicalSnapshot, loopLengthBeats: Double,
                    soundFontURL: URL, name: String) async throws -> URL {
            calls.append((snapshot, loopLengthBeats, name))
            let url = try await action?(calls.count, name) ?? Self.output(name)
            outputs.append(url)
            return url
        }

        static func output(_ name: String) throws -> URL {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("LoopaExport-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            let url = directory.appendingPathComponent(name + ".m4a")
            try Data([1, 2, 3]).write(to: url)
            return url
        }
    }

    private final class Player: MusicPreviewPlaying {
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 10
        var isPlaying = false
        var onFinish: ((Bool) -> Void)?
        var prepareSucceeds = true
        var playSucceeds = true
        var events: [String] = []
        var onPlay: (() -> Void)?
        func prepareToPlay() -> Bool { events.append("prepare"); return prepareSucceeds }
        func play() -> Bool {
            events.append("play")
            onPlay?()
            isPlaying = playSucceeds
            return playSucceeds
        }
        func pause() { events.append("pause"); isPlaying = false }
        func stop() { events.append("stop"); isPlaying = false }
    }

    private func fixture(length: Double = 16) throws -> (MultiTrackLooper, MusicProposalSession, UUID) {
        let track = Track(instrumentName: "Piano", instrumentProgram: 0, isDrumKit: false,
                          notes: [MidiNote(pitch: 60, velocity: 80, startBeat: 0, durationBeats: 0.25)],
                          volume: 0.2, recordedLengthBeats: length)
        let looper = MultiTrackLooper()
        looper.loadTracks([track])
        looper.bpm = 120
        let session = MusicProposalSession(looper: looper)
        let request = try session.beginRequest(scope: .init(trackID: track.id, allowsGain: true))
        try session.receive([.gain(trackID: track.id, before: 0.2, after: 0.4)], for: request.id)
        return (looper, session, request.id)
    }

    private func controller(_ session: MusicProposalSession, renderer: Renderer,
                            stopped: @escaping () -> Bool = { true },
                            factory: @escaping MusicPreview.PlayerFactory = { _ in Player() }) -> MusicPreview {
        MusicPreview(session: session, soundFontURL: URL(fileURLWithPath: "/unused.sf2"),
                     canonicalPlaybackIsStopped: stopped, renderer: renderer, makePlayer: factory)
    }

    private func bytes(_ tracks: [Track]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(tracks)
    }

    func testPrepareUsesOriginalAndCandidateWithoutPlayingOrMutatingCanonical() async throws {
        let (looper, session, id) = try fixture()
        let before = try bytes(looper.tracks)
        let token = looper.musicalToken
        let renderer = Renderer()
        let player = Player()
        let preview = controller(session, renderer: renderer, factory: { _ in player })
        defer { preview.stop() }
        try await preview.prepare(requestID: id)
        XCTAssertEqual(renderer.calls.count, 2)
        XCTAssertEqual(renderer.calls[0].0.tracks[0].volume, 0.2)
        XCTAssertEqual(renderer.calls[1].0.tracks[0].volume, 0.4)
        XCTAssertEqual(renderer.calls[0].0.token, renderer.calls[1].0.token)
        XCTAssertEqual(renderer.calls[0].1, 16)
        XCTAssertEqual(preview.duration, 8)
        XCTAssertEqual(preview.state, .prepared(.original))
        XCTAssertEqual(player.events, ["prepare"])
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(try bytes(looper.tracks), before)
        XCTAssertEqual(looper.musicalToken, token)
    }

    func testDurationUsesLongestRecordedTrackAndIsCappedAtThirtySeconds() async throws {
        let (_, session, id) = try fixture(length: 160)
        let renderer = Renderer()
        let preview = controller(session, renderer: renderer)
        defer { preview.stop() }
        try await preview.prepare(requestID: id)
        XCTAssertEqual(preview.duration, 30)
        XCTAssertEqual(renderer.calls.map { $0.1 }, [60, 60])
    }

    func testSwitchStopsOldPlayerBeforeNewPlayerStartsAtSamePosition() async throws {
        let (looper, session, id) = try fixture()
        let before = try bytes(looper.tracks)
        let renderer = Renderer()
        var players: [Player] = []
        let preview = controller(session, renderer: renderer, factory: { _ in
            let player = Player()
            player.onPlay = { XCTAssertFalse(players.contains { $0 !== player && $0.isPlaying }) }
            players.append(player)
            return player
        })
        defer { preview.stop() }
        try await preview.prepare(requestID: id)
        try preview.play(.original)
        players[1].currentTime = 2.75
        try preview.play(.change)
        XCTAssertEqual(players.count, 3)
        XCTAssertEqual(players[2].currentTime, 2.75)
        XCTAssertEqual(players[1].events.last, "stop")
        XCTAssertEqual(preview.state, .playing(.change))
        preview.pause()
        XCTAssertEqual(preview.state, .prepared(.change))
        try preview.play(.original)
        XCTAssertEqual(players[3].currentTime, 2.75)
        XCTAssertEqual(try bytes(looper.tracks), before)
    }

    func testStopDeletesOnlyReturnedFilesAndPreservesSiblingFiles() async throws {
        let (_, session, id) = try fixture()
        let renderer = Renderer()
        let preview = controller(session, renderer: renderer)
        try await preview.prepare(requestID: id)
        let first = try XCTUnwrap(renderer.outputs.first)
        let sibling = first.deletingLastPathComponent().appendingPathComponent("unrelated.caf")
        try Data([9]).write(to: sibling)
        defer { try? FileManager.default.removeItem(at: first.deletingLastPathComponent()) }
        preview.stop()
        XCTAssertEqual(preview.state, .idle)
        XCTAssertTrue(renderer.outputs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        XCTAssertEqual(try Data(contentsOf: sibling), Data([9]))
    }

    func testCancelDuringFirstRenderDeletesLateOutputAndNeverPreparesOrPlays() async throws {
        let (_, session, id) = try fixture()
        let entered = expectation(description: "first render entered")
        var continuation: CheckedContinuation<URL, Error>?
        let renderer = Renderer()
        renderer.action = { _, _ in
            try await withCheckedThrowingContinuation { continuation = $0; entered.fulfill() }
        }
        var playerCalls = 0
        let preview = controller(session, renderer: renderer, factory: { _ in playerCalls += 1; return Player() })
        let task = Task { try await preview.prepare(requestID: id) }
        await fulfillment(of: [entered], timeout: 2)
        preview.stop()
        let late = try Renderer.output(try XCTUnwrap(renderer.calls.first?.2))
        continuation?.resume(returning: late)
        do { try await task.value; XCTFail("Cancelled work must reject") } catch is CancellationError {} catch { XCTFail("\(error)") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: late.path))
        XCTAssertEqual(renderer.calls.count, 1)
        XCTAssertEqual(playerCalls, 0)
        XCTAssertEqual(preview.state, .idle)
    }

    func testCancelDuringSecondRenderCleansBothOutputs() async throws {
        let (_, session, id) = try fixture()
        let entered = expectation(description: "second render entered")
        var continuation: CheckedContinuation<URL, Error>?
        let renderer = Renderer()
        renderer.action = { index, name in
            if index == 1 { return try Renderer.output(name) }
            return try await withCheckedThrowingContinuation { continuation = $0; entered.fulfill() }
        }
        let preview = controller(session, renderer: renderer)
        let task = Task { try await preview.prepare(requestID: id) }
        await fulfillment(of: [entered], timeout: 2)
        let first = try XCTUnwrap(renderer.outputs.first)
        preview.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        let late = try Renderer.output(try XCTUnwrap(renderer.calls.last?.2))
        continuation?.resume(returning: late)
        do { try await task.value; XCTFail("Cancelled work must reject") } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: late.path))
        XCTAssertEqual(preview.state, .idle)
    }

    func testCallerCancellationAlsoCleansLateRender() async throws {
        let (_, session, id) = try fixture()
        let entered = expectation(description: "render entered")
        var continuation: CheckedContinuation<URL, Error>?
        let renderer = Renderer()
        renderer.action = { _, _ in try await withCheckedThrowingContinuation { continuation = $0; entered.fulfill() } }
        let preview = controller(session, renderer: renderer)
        let task = Task { try await preview.prepare(requestID: id) }
        await fulfillment(of: [entered], timeout: 2)
        task.cancel()
        let late = try Renderer.output(try XCTUnwrap(renderer.calls.first?.2))
        continuation?.resume(returning: late)
        do { try await task.value; XCTFail("Cancellation must propagate") } catch is CancellationError {} catch { XCTFail("\(error)") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: late.path))
        XCTAssertEqual(preview.state, .idle)
    }

    func testSecondRenderFailureRemovesFirstOutput() async throws {
        let (_, session, id) = try fixture()
        let renderer = Renderer()
        renderer.action = { index, name in
            if index == 2 { throw MusicPreview.Failure.renderFailed }
            return try Renderer.output(name)
        }
        let preview = controller(session, renderer: renderer)
        do { try await preview.prepare(requestID: id); XCTFail("Expected render failure") } catch {}
        XCTAssertEqual(preview.state, .failed(.renderFailed))
        XCTAssertTrue(renderer.outputs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    func testManualEditDuringRenderRejectsStaleCandidateAndCleansOutput() async throws {
        let (looper, session, id) = try fixture()
        let renderer = Renderer()
        renderer.action = { _, name in looper.bpm = 121; return try Renderer.output(name) }
        let preview = controller(session, renderer: renderer)
        do { try await preview.prepare(requestID: id); XCTFail("Stale snapshot must reject") } catch {}
        XCTAssertEqual(renderer.calls.count, 1)
        XCTAssertEqual(preview.state, .failed(.proposal(.stale)))
        XCTAssertTrue(renderer.outputs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        XCTAssertEqual(looper.bpm, 121)
    }

    func testManualEditAfterPreparationPreventsPlayback() async throws {
        let (looper, session, id) = try fixture()
        let renderer = Renderer()
        let player = Player()
        let preview = controller(session, renderer: renderer, factory: { _ in player })
        try await preview.prepare(requestID: id)
        looper.bpm = 121
        XCTAssertThrowsError(try preview.play(.original))
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(preview.state, .failed(.proposal(.stale)))
        XCTAssertTrue(renderer.outputs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    func testCandidateIsRevalidatedAfterPlayerFactoryBeforePrepare() async throws {
        let (looper, session, id) = try fixture()
        let renderer = Renderer()
        let player = Player()
        let preview = controller(session, renderer: renderer, factory: { _ in looper.bpm = 121; return player })
        do { try await preview.prepare(requestID: id); XCTFail("Stale factory result must reject") } catch {}
        XCTAssertFalse(player.events.contains("prepare"))
        XCTAssertEqual(preview.state, .failed(.proposal(.stale)))
    }

    func testHostMustPauseCanonicalPlaybackBeforeRenderAndBeforePlay() async throws {
        let (_, session, id) = try fixture()
        let renderer = Renderer()
        var stopped = false
        let preview = controller(session, renderer: renderer, stopped: { stopped })
        do { try await preview.prepare(requestID: id); XCTFail("Host must pause") } catch {}
        XCTAssertTrue(renderer.calls.isEmpty)
        stopped = true
        try await preview.prepare(requestID: id)
        stopped = false
        XCTAssertThrowsError(try preview.play(.original))
        XCTAssertEqual(preview.state, .failed(.hostPlaybackActive))
    }

    func testPreparationFailureCleansBothOutputs() async throws {
        let (_, session, id) = try fixture()
        let renderer = Renderer()
        let player = Player()
        player.prepareSucceeds = false
        let preview = controller(session, renderer: renderer, factory: { _ in player })
        do { try await preview.prepare(requestID: id); XCTFail("Prepare must fail") } catch {}
        XCTAssertEqual(preview.state, .failed(.playerFailed))
        XCTAssertTrue(renderer.outputs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    func testMissingOutputFailsBeforePlayerCreation() async throws {
        let (_, session, id) = try fixture()
        let renderer = Renderer()
        renderer.action = { _, name in
            let output = try Renderer.output(name)
            try FileManager.default.removeItem(at: output)
            return output
        }
        let preview = controller(session, renderer: renderer, factory: { _ in XCTFail("Missing audio must not be prepared"); return Player() })
        do { try await preview.prepare(requestID: id); XCTFail("Missing output must reject") } catch {}
        XCTAssertEqual(preview.state, .failed(.invalidOutput))
        for output in renderer.outputs { try? FileManager.default.removeItem(at: output.deletingLastPathComponent()) }
    }

    func testUnownedOutputIsRejectedWithoutDeletingIt() async throws {
        let (_, session, id) = try fixture()
        let userFile = FileManager.default.temporaryDirectory.appendingPathComponent("Vocal-\(UUID()).m4a")
        try Data([42]).write(to: userFile)
        defer { try? FileManager.default.removeItem(at: userFile) }
        let renderer = Renderer()
        renderer.action = { _, _ in userFile }
        let preview = controller(session, renderer: renderer)
        do { try await preview.prepare(requestID: id); XCTFail("Unowned path must reject") } catch {}
        preview.stop()
        XCTAssertEqual(try Data(contentsOf: userFile), Data([42]))
        XCTAssertEqual(renderer.calls.count, 1)
    }

    func testSymbolicLinkOutputDoesNotDeleteUserTarget() async throws {
        let (_, session, id) = try fixture()
        let userFile = FileManager.default.temporaryDirectory.appendingPathComponent("Vocal-\(UUID()).caf")
        try Data([42]).write(to: userFile)
        defer { try? FileManager.default.removeItem(at: userFile) }
        let renderer = Renderer()
        renderer.action = { _, name in
            let output = try Renderer.output(name)
            try FileManager.default.removeItem(at: output)
            try FileManager.default.createSymbolicLink(at: output, withDestinationURL: userFile)
            return output
        }
        let preview = controller(session, renderer: renderer)
        do { try await preview.prepare(requestID: id); XCTFail("Symlink must reject") } catch {}
        XCTAssertEqual(try Data(contentsOf: userFile), Data([42]))
        for output in renderer.outputs { try? FileManager.default.removeItem(at: output.deletingLastPathComponent()) }
    }

    func testPlaybackCompletionAndStaleCompletionHaveCorrectState() async throws {
        let (_, session, id) = try fixture()
        let renderer = Renderer()
        let player = Player()
        let preview = controller(session, renderer: renderer, factory: { _ in player })
        try await preview.prepare(requestID: id)
        try preview.play(.original)
        let completion = player.onFinish
        completion?(true)
        XCTAssertEqual(preview.state, .prepared(.original))
        preview.stop()
        completion?(false)
        XCTAssertEqual(preview.state, .idle)
    }

    func testConcurrentPreparationFailsBusyWithoutStartingAnotherRender() async throws {
        let (_, session, id) = try fixture()
        let entered = expectation(description: "render entered")
        var continuation: CheckedContinuation<URL, Error>?
        let renderer = Renderer()
        renderer.action = { _, _ in try await withCheckedThrowingContinuation { continuation = $0; entered.fulfill() } }
        let preview = controller(session, renderer: renderer)
        let task = Task { try await preview.prepare(requestID: id) }
        await fulfillment(of: [entered], timeout: 2)
        do { try await preview.prepare(requestID: id); XCTFail("Concurrent prepare must fail") }
        catch { XCTAssertEqual(error as? MusicPreview.Failure, .busy) }
        preview.stop()
        continuation?.resume(throwing: CancellationError())
        _ = try? await task.value
        XCTAssertEqual(renderer.calls.count, 1)
    }

    func testProductionRendererAndPlayerPrepareRealAudioWithoutAutoplay() async throws {
        let (_, session, id) = try fixture(length: 1)
        let soundFont = try XCTUnwrap(Bundle.main.url(forResource: "GM", withExtension: "sf2"))
        let preview = MusicPreview(session: session, soundFontURL: soundFont,
                                   canonicalPlaybackIsStopped: { true })
        defer { preview.stop() }
        try await preview.prepare(requestID: id)
        XCTAssertEqual(preview.state, .prepared(.original))
        XCTAssertEqual(preview.currentTime, 0, accuracy: 0.001)
        XCTAssertEqual(preview.duration, 0.5)
    }

    func testCancellationFromPreparingPublicationStaysIdleAndNeverRenders() async throws {
        let (_, session, id) = try fixture()
        let renderer = Renderer()
        let preview = controller(session, renderer: renderer)
        let subscription = preview.$state.sink { state in
            if case .preparing = state { preview.stop() }
        }
        do { try await preview.prepare(requestID: id); XCTFail("Observer cancelled preparation") }
        catch is CancellationError {} catch { XCTFail("\(error)") }
        XCTAssertTrue(renderer.calls.isEmpty)
        XCTAssertEqual(preview.state, .idle)
        withExtendedLifetime(subscription) {}
    }

    func testStopFromPlayingPublicationCannotLeavePlayingStatus() async throws {
        let (_, session, id) = try fixture()
        let renderer = Renderer()
        let player = Player()
        let preview = controller(session, renderer: renderer, factory: { _ in player })
        try await preview.prepare(requestID: id)
        let subscription = preview.$state.sink { state in
            if case .playing = state { preview.stop() }
        }
        try preview.play(.original)
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(preview.state, .idle)
        XCTAssertTrue(renderer.outputs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        withExtendedLifetime(subscription) {}
    }

    func testCancellationInsideFactoryNeverPreparesPlayer() async throws {
        let (_, session, id) = try fixture()
        let renderer = Renderer()
        let player = Player()
        var preview: MusicPreview!
        preview = controller(session, renderer: renderer, factory: { _ in preview.stop(); return player })
        do { try await preview.prepare(requestID: id); XCTFail("Factory cancelled preparation") }
        catch is CancellationError {} catch { XCTFail("\(error)") }
        XCTAssertFalse(player.events.contains("prepare"))
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(preview.state, .idle)
        // Release the test's factory closure cycle.
        preview = nil
    }

    func testPlaybackFailureStopsComparisonAndCleansBothOutputs() async throws {
        let (_, session, id) = try fixture()
        let renderer = Renderer()
        let player = Player()
        player.playSucceeds = false
        let preview = controller(session, renderer: renderer, factory: { _ in player })
        try await preview.prepare(requestID: id)
        XCTAssertThrowsError(try preview.play(.original))
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(preview.state, .failed(.playerFailed))
        XCTAssertTrue(renderer.outputs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    private func assertLateCompletionCannotAffectReplay(naturalFinish: Bool, lateSuccess: Bool,
                                                       file: StaticString = #filePath, line: UInt = #line) async throws {
        let (_, session, id) = try fixture()
        let renderer = Renderer()
        var players: [Player] = []
        let preview = controller(session, renderer: renderer, factory: { _ in
            let player = Player()
            player.onPlay = { XCTAssertFalse(players.contains { $0 !== player && $0.isPlaying }, file: file, line: line) }
            players.append(player)
            return player
        })
        defer { preview.stop() }
        try await preview.prepare(requestID: id)
        try preview.play(.original)
        let old = try XCTUnwrap(players.last)
        let oldCompletion = try XCTUnwrap(old.onFinish)
        old.currentTime = 2.25
        if naturalFinish {
            old.isPlaying = false
            old.currentTime = preview.duration
            oldCompletion(true)
        } else {
            preview.pause()
        }
        XCTAssertEqual(preview.state, .prepared(.original), file: file, line: line)
        try preview.play(.original)
        let replay = try XCTUnwrap(players.last)
        XCTAssertFalse(old === replay, file: file, line: line)
        XCTAssertNil(old.onFinish, "Retired delegate must not retain a live callback", file: file, line: line)
        XCTAssertEqual(replay.currentTime, naturalFinish ? 0 : 2.25, file: file, line: line)
        oldCompletion(lateSuccess)
        XCTAssertEqual(preview.state, .playing(.original), file: file, line: line)
        XCTAssertTrue(replay.isPlaying, file: file, line: line)
        XCTAssertTrue(renderer.outputs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }, file: file, line: line)
    }

    func testOldSuccessAfterPauseAndSameSideReplayCannotChangeCurrentPlayback() async throws {
        try await assertLateCompletionCannotAffectReplay(naturalFinish: false, lateSuccess: true)
    }

    func testOldFailureAfterPauseAndSameSideReplayCannotStopCurrentPlayback() async throws {
        try await assertLateCompletionCannotAffectReplay(naturalFinish: false, lateSuccess: false)
    }

    func testOldSuccessAfterNaturalFinishAndReplayCannotChangeCurrentPlayback() async throws {
        try await assertLateCompletionCannotAffectReplay(naturalFinish: true, lateSuccess: true)
    }

    func testOldFailureAfterNaturalFinishAndReplayCannotStopCurrentPlayback() async throws {
        try await assertLateCompletionCannotAffectReplay(naturalFinish: true, lateSuccess: false)
    }
}
