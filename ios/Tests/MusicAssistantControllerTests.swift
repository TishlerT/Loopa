import XCTest
import Combine
@testable import Loopa

@MainActor
final class MusicAssistantControllerTests: XCTestCase {
    private final class Gate<T> {
        var continuation: CheckedContinuation<T, Never>?
        private var completed: T?
        func wait() async -> T {
            if let completed { return completed }
            return await withCheckedContinuation { continuation = $0 }
        }
        func finish(_ value: T) { completed = value; let pending = continuation; continuation = nil; pending?.resume(returning: value) }
    }
    private final class Renderer: MusicPreviewRendering {
        var calls = 0
        var outputs: [URL] = []
        var beforeRender: (() async -> Void)?
        var event: (String) -> Void = { _ in }
        func render(snapshot: MusicalSnapshot, loopLengthBeats: Double, soundFontURL: URL, name: String) async throws -> URL {
            calls += 1; event("render")
            await beforeRender?()
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LoopaExport-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            let url = directory.appendingPathComponent(name + ".m4a")
            try Data([1, 2, 3]).write(to: url); outputs.append(url)
            return url
        }
    }
    private final class Player: MusicPreviewPlaying {
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 8
        var isPlaying = false
        var onFinish: ((Bool) -> Void)?
        var event: (String) -> Void = { _ in }
        func prepareToPlay() -> Bool { event("prepare"); return true }
        func play() -> Bool { event("play"); isPlaying = true; return true }
        func pause() { event("pause"); isPlaying = false }
        func stop() { event("stop"); isPlaying = false }
    }
    @MainActor
    private final class Fixture {
        let looper = MultiTrackLooper()
        let track = Track(instrumentName: "Piano", instrumentProgram: 0, isDrumKit: false,
                          notes: [MidiNote(pitch: 60, velocity: 80, startBeat: 0, durationBeats: 1)],
                          volume: 0.2, recordedLengthBeats: 16)
        let other = Track(audioFileName: "private-recording.caf", volume: 0.5, recordedLengthBeats: 16)
        let renderer = Renderer()
        var controller: MusicAssistantController!
        var status = LocalMusicAssistant.Status(connection: .connected, sharing: true)
        var models = [LocalMusicAssistant.Model(slug: "second", displayName: "Second"), .init(slug: "first", displayName: "First")]
        var statusAction: (() async throws -> LocalMusicAssistant.Status)?
        var modelsAction: (() async throws -> [LocalMusicAssistant.Model])?
        var proposeAction: ((MusicAssistantContext) async throws -> [MusicEdit])?
        var beginAction: (() async throws -> MusicAssistantController.AudioLease)?
        var saveAction: (() -> Bool)?
        var endAction: (() -> Void)?
        var contexts: [MusicAssistantContext] = []
        var texts: [String] = []
        var chosenModels: [String] = []
        var modelCalls = 0, cancelCalls = 0, saveCalls = 0, beginCalls = 0
        var savedVolumes: [Float] = []
        var events: [String] = []
        var owned = false
        var players: [Player] = []
        init() {
            looper.loadTracks([track, other]); looper.bpm = 120
            renderer.event = { [weak self] in self?.events.append($0) }
            controller = MusicAssistantController(looper: looper,
                client: .init(status: { [unowned self] in try await statusAction?() ?? status },
                    models: { [unowned self] in modelCalls += 1; return try await modelsAction?() ?? models },
                    propose: { [unowned self] context, text, model in
                        contexts.append(context); texts.append(text); chosenModels.append(model)
                        return try await proposeAction?(context) ?? [.gain(trackID: context.trackID, before: context.snapshot.tracks[0].volume, after: 0.4)]
                    }, cancel: { [unowned self] in cancelCalls += 1 }),
                soundFontURL: URL(fileURLWithPath: "/synthetic-unused.sf2"),
                host: .init(begin: { [unowned self] in
                    beginCalls += 1; events.append("acquire"); owned = true
                    return try await beginAction?() ?? lease()
                }, cancelPending: { [unowned self] in events.append("cancelPending") },
                    save: { [unowned self] in
                        saveCalls += 1; events.append("save"); savedVolumes.append(looper.tracks[0].volume)
                        return saveAction?() ?? true
                    }), renderer: renderer,
                makePlayer: { [unowned self] _ in
                    let player = Player(); player.event = { [weak self] in self?.events.append($0) }
                    players.append(player); return player
                })
        }
        func lease() -> MusicAssistantController.AudioLease {
            .init(isStopped: { [unowned self] in owned }, end: { [unowned self] in
                XCTAssertFalse(players.contains(where: \.isPlaying)); events.append("release"); owned = false; endAction?()
            })
        }
        func connect() async {
            await controller.discover(); controller.selectTrack(track.id); controller.setUserText("Make this quieter")
        }
        func ready() async { await connect(); await controller.requestGain() }
        func close() { controller.dismiss(); renderer.outputs.forEach { try? FileManager.default.removeItem(at: $0.deletingLastPathComponent()) } }
    }
    private func waitUntil(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<500 { if predicate() { return }; await Task.yield() }
        XCTFail("Expected async boundary was not reached", file: file, line: line)
    }

    func testDiscoveryPreservesOrderAndSelectsFirstModel() async {
        let f = Fixture(); defer { f.close() }; await f.connect()
        XCTAssertEqual(f.controller.state.models.map(\.slug), ["second", "first"])
        XCTAssertEqual(f.controller.state.selectedModel, "second")
        f.controller.selectModel("first"); XCTAssertEqual(f.controller.state.selectedModel, "first")
        f.controller.selectModel("unknown"); XCTAssertEqual(f.controller.state.selectedModel, "first")
    }
    func testNoSharingDoesNotDiscoverModelsOrRequest() async {
        let f = Fixture(); defer { f.close() }; f.status = .init(connection: .connected, sharing: false)
        await f.connect(); await f.controller.requestGain()
        XCTAssertEqual(f.modelCalls, 0); XCTAssertTrue(f.contexts.isEmpty)
    }
    func testNilPairingRemainsDisabledWithoutNetwork() async {
        let f = Fixture(); defer { f.close() }; let local = LocalMusicAssistant()
        f.statusAction = { try await local.status() }; await f.connect()
        XCTAssertEqual(f.controller.state.connection, .disconnected)
        XCTAssertEqual(f.controller.state.message, LocalMusicAssistant.Failure.notPaired.errorDescription)
        XCTAssertTrue(f.controller.state.models.isEmpty)
    }
    func testDiscoveryErrorDoesNotExposeDependencyText() async {
        let f = Fixture(); defer { f.close() }
        f.statusAction = { throw NSError(domain: "SYNTHETIC_SECRET", code: 1) }; await f.connect()
        XCTAssertFalse(f.controller.state.message?.contains("SYNTHETIC") ?? true)
    }
    func testRequestCapturesActualSelectedGainContextWithoutAudioOrOtherTracks() async throws {
        let f = Fixture(); defer { f.close() }; await f.ready()
        let context = try XCTUnwrap(f.contexts.first)
        let bytes = try context.encodedProject(); let text = String(decoding: bytes, as: UTF8.self)
        XCTAssertEqual(context.trackID, f.track.id); XCTAssertNil(context.region)
        XCTAssertEqual(context.snapshot.token, f.looper.musicalToken)
        XCTAssertFalse(text.contains("private-recording")); XCTAssertFalse(text.contains(f.other.id.uuidString))
        XCTAssertFalse(text.contains("notes")); XCTAssertEqual(f.texts, ["Make this quieter"])
        XCTAssertEqual(f.chosenModels, ["second"])
        XCTAssertTrue(f.controller.inputSharingSummary.contains("No recordings"))
    }
    func testReadyProposalDoesNotMutateSaveOrAutoplay() async {
        let f = Fixture(); defer { f.close() }; await f.ready()
        XCTAssertEqual(f.controller.state.phase, .ready); XCTAssertEqual(f.looper.tracks[0].volume, 0.2)
        XCTAssertEqual(f.renderer.calls, 0); XCTAssertEqual(f.beginCalls, 0); XCTAssertEqual(f.saveCalls, 0)
    }
    func testOversizedUserTextDoesNotSendRequest() async {
        let f = Fixture(); defer { f.close() }; await f.connect()
        f.controller.setUserText(String(repeating: "é", count: 1025)); await f.controller.requestGain()
        XCTAssertTrue(f.contexts.isEmpty)
    }
    func testWrongTrackProposalCannotReachReadyOrMutate() async {
        let f = Fixture(); defer { f.close() }
        f.proposeAction = { _ in [.gain(trackID: f.other.id, before: 0.5, after: 0.6)] }
        await f.ready(); XCTAssertEqual(f.controller.state.phase, .idle)
        XCTAssertEqual(f.looper.tracks[1].volume, 0.5); XCTAssertEqual(f.saveCalls, 0)
    }
    func testManualRevisionDuringRequestRejectsLateProposal() async {
        let f = Fixture(); defer { f.close() }; let gate = Gate<[MusicEdit]>()
        f.proposeAction = { _ in await gate.wait() }; await f.connect()
        let task = Task { await f.controller.requestGain() }; await waitUntil { gate.continuation != nil }
        f.looper.toggleMute(f.other)
        gate.finish([.gain(trackID: f.track.id, before: 0.2, after: 0.4)]); await task.value
        XCTAssertNotEqual(f.controller.state.phase, .ready); XCTAssertEqual(f.looper.tracks[0].volume, 0.2)
    }
    func testSelectedTrackChangeCancelsPendingProposal() async {
        let f = Fixture(); defer { f.close() }; let gate = Gate<[MusicEdit]>()
        f.proposeAction = { _ in await gate.wait() }; await f.connect()
        let task = Task { await f.controller.requestGain() }; await waitUntil { gate.continuation != nil }
        let before = f.cancelCalls; f.controller.selectTrack(f.other.id)
        gate.finish([.gain(trackID: f.track.id, before: 0.2, after: 0.4)]); await task.value
        XCTAssertGreaterThan(f.cancelCalls, before); XCTAssertEqual(f.controller.state.selectedTrackID, f.other.id)
        XCTAssertEqual(f.controller.state.phase, .idle)
    }
    func testDismissPreventsLateProposal() async {
        let f = Fixture(); defer { f.close() }; let gate = Gate<[MusicEdit]>()
        f.proposeAction = { _ in await gate.wait() }; await f.connect()
        let task = Task { await f.controller.requestGain() }; await waitUntil { gate.continuation != nil }
        f.controller.dismiss(); gate.finish([.gain(trackID: f.track.id, before: 0.2, after: 0.4)]); await task.value
        XCTAssertEqual(f.controller.state.phase, .idle); XCTAssertEqual(f.saveCalls, 0)
    }
    func testTaskCancellationAtSuccessfulAwaitReleasesBusyState() async {
        let f = Fixture(); defer { f.close() }; let gate = Gate<[MusicEdit]>()
        f.proposeAction = { _ in await gate.wait() }; await f.connect()
        let task = Task { await f.controller.requestGain() }; await waitUntil { gate.continuation != nil }
        task.cancel(); gate.finish([.gain(trackID: f.track.id, before: 0.2, after: 0.4)]); await task.value
        XCTAssertEqual(f.controller.state.phase, .idle)
    }
    func testDismissPreventsLateCatalog() async {
        let f = Fixture(); defer { f.close() }; let gate = Gate<[LocalMusicAssistant.Model]>()
        f.modelsAction = { await gate.wait() }
        let task = Task { await f.controller.discover() }; await waitUntil { gate.continuation != nil }
        f.controller.dismiss(); gate.finish(f.models); await task.value
        XCTAssertTrue(f.controller.state.models.isEmpty); XCTAssertEqual(f.controller.state.phase, .idle)
    }
    func testReentrantReadyPublicationCancellationWins() async {
        let f = Fixture(); defer { f.close() }; await f.connect()
        let observer = f.controller.$state.sink { if $0.phase == .ready { f.controller.dismiss() } }
        await f.controller.requestGain(); withExtendedLifetime(observer) {}
        XCTAssertEqual(f.controller.state.phase, .idle); f.controller.keep(); XCTAssertEqual(f.saveCalls, 0)
    }
    func testPreviewAcquiresHostBeforeRenderingAndNeverAutoplays() async {
        let f = Fixture(); defer { f.close() }; await f.ready(); f.events = []
        await f.controller.preparePreview()
        XCTAssertEqual(f.events.first, "acquire"); XCTAssertEqual(f.renderer.calls, 2)
        XCTAssertFalse(f.events.contains("play")); XCTAssertTrue(f.owned)
        XCTAssertEqual(f.controller.state.previewState, .prepared(.original))
        f.controller.playOriginal(); XCTAssertTrue(f.players.last?.isPlaying ?? false)
        f.controller.playChange(); XCTAssertTrue(f.players.last?.isPlaying ?? false)
        XCTAssertEqual(f.looper.tracks[0].volume, 0.2)
    }
    func testDiscardStopsPlayerBeforeReleasingHost() async {
        let f = Fixture(); defer { f.close() }; await f.ready(); await f.controller.preparePreview(); f.controller.playChange()
        f.events = []; f.controller.discard()
        XCTAssertEqual(Array(f.events.prefix(2)), ["stop", "release"]); XCTAssertFalse(f.owned)
        XCTAssertEqual(f.looper.tracks[0].volume, 0.2)
    }
    func testBackgroundStopsAndReleasesWithoutSaving() async {
        let f = Fixture(); defer { f.close() }; await f.ready(); await f.controller.preparePreview(); f.controller.playChange()
        f.events = []; f.controller.backgrounded()
        XCTAssertEqual(Array(f.events.prefix(2)), ["stop", "release"]); XCTAssertEqual(f.saveCalls, 0)
    }
    func testInterruptionStopsAndReleasesWithoutSaving() async {
        let f = Fixture(); defer { f.close() }; await f.ready(); await f.controller.preparePreview(); f.controller.playOriginal()
        f.events = []; f.controller.interrupted()
        XCTAssertEqual(Array(f.events.prefix(2)), ["stop", "release"]); XCTAssertEqual(f.saveCalls, 0)
    }
    func testLateHostAcquisitionAfterDismissIsReleasedWithoutRendering() async {
        let f = Fixture(); defer { f.close() }; let gate = Gate<MusicAssistantController.AudioLease>()
        f.beginAction = { await gate.wait() }; await f.ready()
        let task = Task { await f.controller.preparePreview() }; await waitUntil { gate.continuation != nil }
        f.controller.dismiss(); gate.finish(f.lease()); await task.value
        XCTAssertFalse(f.owned); XCTAssertEqual(f.renderer.calls, 0); XCTAssertEqual(f.controller.state.phase, .idle)
    }
    func testLateRendererOutputAfterDiscardIsDeleted() async {
        let f = Fixture(); defer { f.close() }; let gate = Gate<Bool>()
        f.renderer.beforeRender = { _ = await gate.wait() }; await f.ready()
        let task = Task { await f.controller.preparePreview() }; await waitUntil { gate.continuation != nil }
        f.controller.discard(); gate.finish(true); await task.value
        XCTAssertEqual(f.renderer.calls, 1); XCTAssertFalse(f.owned)
        XCTAssertTrue(f.renderer.outputs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }
    func testKeepStopsPreviewCommitsThenSavesExactlyOnce() async {
        let f = Fixture(); defer { f.close() }; await f.ready(); await f.controller.preparePreview(); f.controller.playChange()
        f.events = []; f.controller.keep(); f.controller.keep()
        XCTAssertEqual(Array(f.events.prefix(2)), ["stop", "release"])
        XCTAssertEqual(f.savedVolumes, [0.4]); XCTAssertEqual(f.saveCalls, 1)
        XCTAssertEqual(f.controller.state.phase, .kept); XCTAssertEqual(f.controller.state.saveState, .saved)
        XCTAssertTrue(f.controller.state.canUndo)
    }
    func testFailedKeepSaveRetainsMusicAndBlocksFreshRequestUntilRetry() async {
        let f = Fixture(); defer { f.close() }; f.saveAction = { false }; await f.ready(); f.controller.keep()
        XCTAssertEqual(f.looper.tracks[0].volume, 0.4); XCTAssertEqual(f.controller.state.saveState, .unsaved)
        await f.controller.requestGain(); XCTAssertEqual(f.contexts.count, 1)
        f.saveAction = { true }; f.controller.retrySave()
        XCTAssertEqual(f.saveCalls, 2); XCTAssertEqual(f.controller.state.saveState, .saved)
        await f.controller.requestGain(); XCTAssertEqual(f.contexts.count, 2)
    }
    func testDismissDoesNotHideUnsavedKeepOrDiscardRecovery() async {
        let f = Fixture(); defer { f.close() }; f.saveAction = { false }; await f.ready(); f.controller.keep()
        let message = f.controller.state.message; f.controller.dismiss()
        XCTAssertEqual(f.controller.state.saveState, .unsaved); XCTAssertEqual(f.controller.state.message, message)
        XCTAssertEqual(f.looper.tracks[0].volume, 0.4); XCTAssertEqual(f.saveCalls, 1)
    }
    func testUndoRestoresThenSavesAndDoesNotRepeat() async {
        let f = Fixture(); defer { f.close() }; await f.ready(); f.controller.keep(); f.controller.undo(); f.controller.undo()
        XCTAssertEqual(f.savedVolumes, [0.4, 0.2]); XCTAssertEqual(f.controller.state.phase, .undone)
        XCTAssertFalse(f.controller.state.canUndo); XCTAssertEqual(f.controller.state.saveState, .saved)
    }
    func testUndoSaveFailureRetainsUndoneMusicAndCanRetry() async {
        let f = Fixture(); defer { f.close() }; await f.ready(); f.controller.keep(); f.saveAction = { false }; f.controller.undo()
        XCTAssertEqual(f.looper.tracks[0].volume, 0.2); XCTAssertEqual(f.controller.state.saveState, .unsaved)
        f.saveAction = { true }; f.controller.retrySave()
        XCTAssertEqual(f.savedVolumes, [0.4, 0.2, 0.2]); XCTAssertEqual(f.controller.state.saveState, .saved)
    }
    func testManualChangeAfterKeepCannotBeOverwrittenByUndo() async {
        let f = Fixture(); defer { f.close() }; await f.ready(); f.controller.keep(); f.looper.toggleMute(f.track)
        f.controller.undo(); XCTAssertTrue(f.looper.tracks[0].isMuted)
        XCTAssertEqual(f.looper.tracks[0].volume, 0.4); XCTAssertEqual(f.saveCalls, 1)
    }
    func testManualChangeImmediatelyBeforeKeepFailsClosed() async {
        let f = Fixture(); defer { f.close() }; await f.ready(); f.looper.bpm = 125; f.controller.keep()
        XCTAssertEqual(f.looper.tracks[0].volume, 0.2); XCTAssertEqual(f.saveCalls, 0)
    }
    func testUnsavedPreviousProjectCannotOverwriteRecoveryAfterReplacement() async {
        let f = Fixture(); defer { f.close() }; f.saveAction = { false }; await f.ready(); f.controller.keep()
        f.looper.loadTracks([f.other]); f.controller.retrySave()
        XCTAssertEqual(f.saveCalls, 1); XCTAssertEqual(f.controller.state.saveState, .unsaved)
    }
    func testSaveSuccessWithReentrantManualEditIsNotAdvertisedSaved() async {
        let f = Fixture(); defer { f.close() }; await f.ready()
        f.saveAction = { f.looper.toggleMute(f.track); return true }; f.controller.keep()
        XCTAssertEqual(f.controller.state.saveState, .unsaved)
        XCTAssertTrue(f.looper.tracks[0].isMuted)
    }
    func testReentrantDismissDuringSaveRetainsUnsavedState() async {
        let f = Fixture(); defer { f.close() }; await f.ready()
        f.saveAction = { f.controller.dismiss(); return false }; f.controller.keep()
        XCTAssertEqual(f.controller.state.saveState, .unsaved); XCTAssertEqual(f.looper.tracks[0].volume, 0.4)
    }

    func testPreviewPlayerFailureReleasesHost() async {
        let f = Fixture(); defer { f.close() }; await f.ready(); await f.controller.preparePreview(); f.controller.playChange()
        f.events = []; f.players.last?.onFinish?(false)
        await waitUntil { !f.owned }
        XCTAssertTrue(f.events.contains("release")); XCTAssertEqual(f.controller.state.phase, .idle)
    }
    func testManualRevisionDuringPlaybackStopsBeforeHostRelease() async {
        let f = Fixture(); defer { f.close() }; await f.ready(); await f.controller.preparePreview(); f.controller.playOriginal()
        f.events = []; f.looper.toggleMute(f.other)
        await waitUntil { !f.owned }
        XCTAssertEqual(Array(f.events.prefix(2)), ["stop", "release"]); XCTAssertEqual(f.saveCalls, 0)
    }
    func testReentrantDismissDuringHostReleasePreventsKeep() async {
        let f = Fixture(); defer { f.close() }; await f.ready(); await f.controller.preparePreview()
        f.endAction = { f.controller.dismiss() }; f.controller.keep()
        XCTAssertEqual(f.looper.tracks[0].volume, 0.2); XCTAssertEqual(f.saveCalls, 0)
        XCTAssertEqual(f.controller.state.phase, .idle)
    }
    func testRepeatedReentrantDismissDuringPublicationTerminates() async {
        let f = Fixture(); defer { f.close() }; await f.connect()
        let observer = f.controller.$state.sink { _ in f.controller.dismiss() }
        await f.controller.requestGain(); withExtendedLifetime(observer) {}
        XCTAssertEqual(f.controller.state.phase, .idle); XCTAssertTrue(f.contexts.isEmpty)
    }
    func testUnsavedKeepCannotBeHiddenByDiscovery() async {
        let f = Fixture(); defer { f.close() }; f.saveAction = { false }; await f.ready(); f.controller.keep()
        let calls = f.modelCalls; await f.controller.discover()
        XCTAssertEqual(f.modelCalls, calls); XCTAssertEqual(f.controller.state.saveState, .unsaved)
        XCTAssertEqual(f.controller.state.phase, .kept)
    }
    func testUndoCanRestoreUnsavedKeepThenPersistOriginal() async {
        let f = Fixture(); defer { f.close() }; f.saveAction = { false }; await f.ready(); f.controller.keep()
        f.saveAction = { true }; f.controller.undo()
        XCTAssertEqual(f.savedVolumes, [0.4, 0.2]); XCTAssertEqual(f.looper.tracks[0].volume, 0.2)
        XCTAssertEqual(f.controller.state.saveState, .saved); XCTAssertEqual(f.controller.state.message, "Music saved.")
    }
    func testHostAcquisitionFailureReturnsToIdleWithoutRender() async {
        let f = Fixture(); defer { f.close() }; await f.ready()
        f.beginAction = { f.owned = false; throw CancellationError() }
        await f.controller.preparePreview()
        XCTAssertFalse(f.owned); XCTAssertEqual(f.renderer.calls, 0); XCTAssertEqual(f.controller.state.phase, .idle)
    }
    func testCancelledDiscoverySuccessfulAwaitCannotLeaveBusyState() async {
        let f = Fixture(); defer { f.close() }; let gate = Gate<LocalMusicAssistant.Status>()
        f.statusAction = { await gate.wait() }
        let task = Task { await f.controller.discover() }; await waitUntil { gate.continuation != nil }
        task.cancel(); gate.finish(f.status); await task.value
        XCTAssertEqual(f.controller.state.phase, .idle); XCTAssertEqual(f.modelCalls, 0)
    }

    func testEditingPromptOrModelDiscardsOldReadyProposal() async {
        let f = Fixture(); defer { f.close() }; await f.ready()
        f.controller.setUserText("A different request"); f.controller.keep()
        XCTAssertEqual(f.controller.state.phase, .idle); XCTAssertEqual(f.saveCalls, 0)
        await f.controller.requestGain(); XCTAssertEqual(f.controller.state.phase, .ready)
        f.controller.selectModel("first"); f.controller.keep()
        XCTAssertEqual(f.controller.state.phase, .idle); XCTAssertEqual(f.saveCalls, 0)
    }
    private func replacementClient(_ f: Fixture) -> MusicAssistantController.Client {
        .init(status: { .init(connection: .connected, sharing: true) },
              models: { [.init(slug: "new-model", displayName: "New model")] },
              propose: { context, _, _ in [.gain(trackID: context.trackID, before: context.snapshot.tracks[0].volume, after: 0.1)] },
              cancel: {})
    }
    func testReplacementPreservesSavedMusicPromptAndUndoAcrossDiscovery() async {
        let f = Fixture(); defer { f.close() }; await f.ready(); f.controller.keep()
        XCTAssertTrue(f.controller.state.canUndo)
        let token = f.looper.musicalToken; let oldCancels = f.cancelCalls
        XCTAssertTrue(f.controller.replaceClient(replacementClient(f)))
        XCTAssertGreaterThan(f.cancelCalls, oldCancels)
        XCTAssertEqual(f.controller.state.connection, .disconnected)
        XCTAssertTrue(f.controller.state.models.isEmpty)
        XCTAssertEqual(f.controller.state.userText, "Make this quieter")
        XCTAssertEqual(f.controller.state.selectedTrackID, f.track.id)
        XCTAssertEqual(f.looper.musicalToken, token)
        await f.controller.discover()
        XCTAssertEqual(f.controller.state.selectedModel, "new-model")
        XCTAssertTrue(f.controller.state.canUndo)
        f.controller.undo()
        XCTAssertEqual(f.looper.tracks[0].volume, 0.2)
        XCTAssertEqual(f.controller.state.saveState, .saved)
    }
    func testUnsavedMusicRejectsReplacementUntilSaveSucceeds() async {
        let f = Fixture(); defer { f.close() }; f.saveAction = { false }; await f.ready(); f.controller.keep()
        let state = f.controller.state; let cancelCount = f.cancelCalls
        XCTAssertFalse(f.controller.canAcceptPairing)
        XCTAssertFalse(f.controller.replaceClient(replacementClient(f)))
        XCTAssertEqual(f.controller.state, state); XCTAssertEqual(f.cancelCalls, cancelCount)
        f.saveAction = { true }; f.controller.retrySave()
        XCTAssertTrue(f.controller.canAcceptPairing)
        XCTAssertTrue(f.controller.replaceClient(replacementClient(f)))
        XCTAssertTrue(f.controller.state.canUndo)
    }
    func testReplacementRejectsOldLateDiscovery() async {
        let f = Fixture(); defer { f.close() }; let gate = Gate<LocalMusicAssistant.Status>()
        f.statusAction = { await gate.wait() }
        let task = Task { await f.controller.discover() }; await waitUntil { gate.continuation != nil }
        XCTAssertTrue(f.controller.replaceClient(replacementClient(f)))
        await f.controller.discover()
        gate.finish(.init(connection: .usage_unavailable, sharing: false)); await task.value
        XCTAssertEqual(f.controller.state.connection, .connected)
        XCTAssertEqual(f.controller.state.models.map(\.slug), ["new-model"])
    }
    func testReplacementRejectsOldLateProposalWithoutMutation() async {
        let f = Fixture(); defer { f.close() }; let gate = Gate<[MusicEdit]>()
        f.proposeAction = { _ in await gate.wait() }; await f.connect()
        let task = Task { await f.controller.requestGain() }; await waitUntil { gate.continuation != nil }
        XCTAssertTrue(f.controller.replaceClient(replacementClient(f)))
        await f.controller.discover()
        gate.finish([.gain(trackID: f.track.id, before: 0.2, after: 0.8)]); await task.value
        XCTAssertEqual(f.controller.state.phase, .idle); XCTAssertEqual(f.looper.tracks[0].volume, 0.2)
        XCTAssertEqual(f.saveCalls, 0); XCTAssertEqual(f.controller.state.selectedModel, "new-model")
    }
    func testReplacementStopsPreviewBeforeReleasingAudioAndKeepsMusic() async {
        let f = Fixture(); defer { f.close() }; await f.ready(); await f.controller.preparePreview(); f.controller.playChange()
        XCTAssertTrue(f.players.contains(where: \.isPlaying)); let token = f.looper.musicalToken
        XCTAssertTrue(f.controller.replaceClient(replacementClient(f)))
        XCTAssertFalse(f.players.contains(where: \.isPlaying)); XCTAssertFalse(f.owned)
        XCTAssertEqual(f.looper.musicalToken, token); XCTAssertEqual(f.controller.state.previewState, .idle)
    }
    func testReentrantReplacementCannotOverrideCurrentReplacement() async {
        let f = Fixture(); defer { f.close() }; await f.connect()
        var attempted = false; var accepted = true
        let observation = f.controller.$state.sink { _ in
            if !attempted { attempted = true; return }
            accepted = f.controller.replaceClient(.init(status: { .init(connection: .disconnected, sharing: false) }, models: { [] }, propose: { _,_,_ in [] }, cancel: {}))
        }
        defer { observation.cancel() }
        XCTAssertTrue(f.controller.replaceClient(replacementClient(f)))
        XCTAssertFalse(accepted)
        await f.controller.discover()
        XCTAssertEqual(f.controller.state.connection, .connected)
    }

}
