import Foundation
import Combine
import UIKit
import AVFoundation

/// Owns the panel workflow, never provider credentials. Keep/Undo receipts last
/// only for this controller's lifetime; saving persists music, not Undo history.
@MainActor
final class MusicAssistantController: ObservableObject {
    enum Phase: Equatable { case idle, discovering, requesting, ready, preparing, kept, undone }
    enum SaveState: Equatable { case notNeeded, saved, unsaved }
    struct State: Equatable {
        var phase: Phase = .idle
        var connection: LocalMusicAssistant.Connection = .disconnected
        var sharing = false
        var models: [LocalMusicAssistant.Model] = []
        var selectedModel: String?
        var selectedTrackID: UUID?
        var userText = ""
        var message: String?
        var saveState: SaveState = .notNeeded
        var previewState: MusicPreview.State = .idle
        var canUndo = false
    }
    /// Only these in-process seams are replaceable in offline tests.
    struct Client {
        var status: () async throws -> LocalMusicAssistant.Status
        var models: () async throws -> [LocalMusicAssistant.Model]
        var propose: (MusicAssistantContext, String, String) async throws -> [MusicEdit]
        var cancel: () -> Void
    }
    struct AudioLease {
        var isStopped: () -> Bool
        var end: () -> Void
    }
    struct Host {
        var begin: () async throws -> AudioLease
        var cancelPending: () -> Void
        var save: () -> Bool
    }
    @Published private(set) var state = State()
    let inputSharingSummary = "Sends your text, selected model, project tempo and loop length, and the selected track's ID, instrument, volume, mute, solo, length and audibility. No recordings, audio files, MIDI notes or other tracks' content are sent."
    private let looper: MultiTrackLooper
    private let session: MusicProposalSession
    private var client: Client
    private let host: Host
    private let soundFontURL: URL?
    private let renderer: MusicPreviewRendering?
    private let playerFactory: MusicPreview.PlayerFactory?
    private var epoch = UUID()
    private var request: MusicProposalSession.Request?
    private var lastOutcome: Phase = .idle
    private var keptID: UUID?
    private var keptToken: MusicalToken?
    private var unsavedSessionID: UUID?
    private var preview: MusicPreview?
    private var lease: AudioLease?
    private var changing = false
    private var terminating = false
    private var deferredInvalidation: String?
    private var observations = Set<AnyCancellable>()
    private var previewObservation: AnyCancellable?

    convenience init(viewModel: LooperViewModel, pairing: LocalMusicAssistant.Pairing? = nil) {
        self.init(looper: viewModel.looper, client: Self.localClient(pairing: pairing), soundFontURL: viewModel.audio.soundFontURL,
            host: Host(begin: {
                let token = try await viewModel.beginMusicPreviewAudio()
                return AudioLease(isStopped: { viewModel.musicPreviewAudioIsStopped(for: token) },
                                  end: { viewModel.endMusicPreviewAudio(token) })
            }, cancelPending: { viewModel.cancelMusicPreviewAudioPreparation() },
            save: { viewModel.saveWorkingSession() }))
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in Task { @MainActor in self?.backgrounded() } }.store(in: &observations)
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .sink { [weak self] _ in Task { @MainActor in self?.interrupted() } }.store(in: &observations)
    }

    init(looper: MultiTrackLooper, client: Client, soundFontURL: URL?, host: Host,
         renderer: MusicPreviewRendering? = nil, makePlayer: MusicPreview.PlayerFactory? = nil) {
        self.looper = looper; self.session = MusicProposalSession(looper: looper)
        self.client = client; self.soundFontURL = soundFontURL; self.host = host
        self.renderer = renderer; self.playerFactory = makePlayer
        // Looper publishers fire before assignment. Check the canonical token on
        // the next actor turn, and synchronously again before every authority use.
        looper.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.checkForManualChange() }
        }.store(in: &observations)
    }

    private static func localClient(pairing: LocalMusicAssistant.Pairing?) -> Client {
        let local = LocalMusicAssistant(pairing: pairing)
        return Client(status: { try await local.status() }, models: { try await local.models() },
            propose: { try await local.proposeGain(context: $0, userText: $1, model: $2) }, cancel: { local.cancel() })
    }

    /// Check before consuming a one-use pairing file; unsaved music must not lose its recovery state.
    var canAcceptPairing: Bool { !changing && unsavedSessionID == nil }
    @discardableResult
    func pair(_ pairing: LocalMusicAssistant.Pairing) -> Bool {
        replaceClient(Self.localClient(pairing: pairing))
    }
    /// Swaps only the connection, preserving the project, prompt and session-local Undo receipt.
    @discardableResult
    func replaceClient(_ replacement: Client) -> Bool {
        guard canAcceptPairing else { return false }
        mutate {
            terminate(nil) // Fence old completions and stop audio before changing the transport.
            client = replacement
            var next = state; next.connection = .disconnected; next.sharing = false
            next.models = []; next.selectedModel = nil
            publish(next)
        }
        return true
    }

    func selectTrack(_ id: UUID?) {
        guard !changing else { return }
        if state.selectedTrackID != id, request != nil { invalidate("Selection changed. Request a new change.") }
        mutate { var next = state; next.selectedTrackID = id; publish(next) }
    }
    func selectModel(_ slug: String) {
        guard !changing, state.models.contains(where: { $0.slug == slug }), !isBusy else { return }
        if state.selectedModel != slug, request != nil { invalidate(nil) }
        mutate { var next = state; next.selectedModel = slug; publish(next) }
    }
    func setUserText(_ text: String) {
        guard !changing, !isBusy else { return }
        if state.userText != text, request != nil { invalidate(nil) }
        mutate { var next = state; next.userText = text; publish(next) }
    }
    private var isBusy: Bool { [.discovering, .requesting, .preparing].contains(state.phase) }

    func discover() async {
        guard !changing, !isBusy else { return }
        guard unsavedSessionID == nil else { show("Save the kept or undone music before refreshing the connection."); return }
        invalidate(nil)
        let operation = epoch
        mutate { var next = state; next.phase = .discovering; next.message = nil
            next.models = []; next.selectedModel = nil; next.sharing = false; publish(next) }
        guard live(operation) else { return }
        do {
            let status = try await client.status()
            guard live(operation) else { return }
            var models: [LocalMusicAssistant.Model] = []
            if status.connection == .connected && status.sharing { models = try await client.models() }
            guard live(operation) else { return }
            mutate { var next = state; next.connection = status.connection; next.sharing = status.sharing
                next.models = models; next.selectedModel = models.first?.slug
                next.phase = restingPhase; next.message = status.sharing ? nil : "Enable ChatGPT usage sharing on the Mac to request a change."
                publish(next) }
        } catch { fail(operation, message: safeClientError(error)) }
    }

    func requestGain() async {
        guard !changing, !isBusy else { return }
        guard unsavedSessionID == nil else { show("Save the kept or undone music before requesting another change."); return }
        guard state.connection == .connected, state.sharing, let model = state.selectedModel,
              state.models.contains(where: { $0.slug == model }), let trackID = state.selectedTrackID,
              !state.userText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              state.userText.utf8.count <= 2_048 else { show("Connect, choose a model and track, then describe a volume change."); return }
        invalidate(nil)
        let operation = epoch
        let text = state.userText
        var context: MusicAssistantContext?
        mutate {
            do {
                let captured = try session.beginRequest(scope: .init(trackID: trackID, allowsGain: true))
                request = captured
                context = try MusicAssistantContext(requestID: captured.id, snapshot: captured.snapshot, trackID: trackID)
                var next = state; next.phase = .requesting; next.message = nil; publish(next)
            } catch { terminate("This track cannot accept a volume proposal right now.") }
        }
        guard live(operation), let context else { return }
        do {
            let edits = try await client.propose(context, text, model)
            guard live(operation) else { return }
            mutate {
                do { try validateRequest()
                    guard edits.count == 1, case .gain = edits[0] else { throw CancellationError() }
                    _ = try session.receive(edits, for: context.requestID)
                    guard live(operation) else { return }
                    var next = state; next.phase = .ready; next.message = "Listen to Original and Change, then choose Keep or Discard."; publish(next)
                } catch { terminate("The project changed. Request a new change.") }
            }
        } catch { fail(operation, message: safeClientError(error)) }
    }

    func preparePreview() async {
        guard !changing, state.phase == .ready, preview == nil else { return }
        guard let soundFontURL else { show("Comparison audio is unavailable because the instrument library is not loaded."); return }
        let operation = epoch
        var id: UUID?
        mutate {
            do { try validateRequest(); id = request?.id
                var next = state; next.phase = .preparing; next.message = nil; publish(next)
            } catch { terminate("The project changed. Request a new change.") }
        }
        guard live(operation), let id else { return }
        do {
            let acquired = try await host.begin()
            guard live(operation) else { acquired.end(); return }
            var audition: MusicPreview!
            mutate {
                lease = acquired
                audition = MusicPreview(session: session, soundFontURL: soundFontURL,
                    canonicalPlaybackIsStopped: { acquired.isStopped() }, renderer: renderer, makePlayer: playerFactory)
                preview = audition
                previewObservation = audition.$state.sink { [weak self, weak audition] _ in
                    Task { @MainActor in
                        guard let self, let audition, self.preview === audition else { return }
                        if case .failed = audition.state {
                            self.invalidate("The comparison stopped. Request a new change.")
                        } else {
                            self.mutate { var next = self.state; next.previewState = audition.state; self.publish(next) }
                        }
                    }
                }
            }
            guard live(operation) else { return }
            try await audition.prepare(requestID: id)
            guard live(operation) else { return }
            mutate {
                do { try validateRequest(); guard acquired.isStopped() else { throw CancellationError() }
                    var next = state; next.phase = .ready; next.previewState = audition.state; publish(next)
                } catch { terminate("The comparison is no longer current. Request a new change.") }
            }
        } catch { fail(operation, message: "The comparison could not be prepared. Pause recording and try a new change.") }
    }

    func playOriginal() { play(.original) }
    func playChange() { play(.change) }
    private func play(_ side: MusicPreview.Side) {
        guard !changing, state.phase == .ready, let preview else { return }
        mutate {
            do { try validateRequest(); try preview.play(side)
                var next = state; next.previewState = preview.state; publish(next)
            } catch { terminate("The comparison is no longer available. Request a new change.") }
        }
    }
    func pausePreview() {
        guard !changing else { return }
        mutate { preview?.pause(); var next = state; next.previewState = preview?.state ?? .idle; publish(next) }
    }

    func keep() {
        guard !changing, state.phase == .ready else { return }
        let operation = epoch
        mutate {
            do {
                try validateRequest(); guard let request else { return }
                stopAudio()
                guard live(operation) else { return }
                try validateRequest()
                let receipt = try session.keep(requestID: request.id)
                keptID = receipt.requestID; keptToken = receipt.committedToken; lastOutcome = .kept
                self.request = nil
                var next = state; next.phase = .kept; next.canUndo = true; next.previewState = .idle
                state = next
                persistCurrentMusic()
            } catch { terminate("The project changed or is playing. The change was not kept.") }
        }
    }
    func undo() {
        guard !changing, !isBusy, state.canUndo, let keptID, let keptToken,
              looper.musicalToken == keptToken else { return }
        let operation = epoch
        mutate {
            do {
                stopAudio()
                guard live(operation) else { return }
                _ = try session.undo(requestID: keptID)
                self.keptToken = nil; request = nil; lastOutcome = .undone
                var next = state; next.phase = .undone; next.canUndo = false; next.previewState = .idle
                state = next
                persistCurrentMusic()
            } catch { terminate("The project changed. Undo is no longer available.") }
        }
    }
    func retrySave() {
        guard !changing, let unsavedSessionID else { return }
        guard looper.musicalToken.sessionID == unsavedSessionID else { show("The unsaved project was replaced. Its recovery copy has not been overwritten."); return }
        mutate { persistCurrentMusic() }
    }
    private func persistCurrentMusic() {
        let token = looper.musicalToken
        // Mark unsaved before invoking a reentrant storage/UI adapter.
        unsavedSessionID = token.sessionID
        var next = state; next.saveState = .unsaved; next.message = "Music changed in memory. Saving a recovery copy…"; publish(next)
        let saved = host.save()
        let unchanged = looper.musicalToken == token
        if saved && unchanged { unsavedSessionID = nil }
        next = state; next.saveState = saved && unchanged ? .saved : .unsaved
        next.message = saved && unchanged
            ? (next.canUndo ? "Music saved. Undo is available only in this app session." : "Music saved.")
            : "Current music remains in memory but has not been saved. Keep this project open and retry saving."
        publish(next)
    }

    func discard() { invalidate(nil) }
    func dismiss() { invalidate(nil) }
    func backgrounded() { invalidate("Comparison stopped while the app is in the background.") }
    func interrupted() { invalidate("Comparison stopped because audio was interrupted.") }
    func invalidateForManualEdit() { invalidate("The project changed. Request a new change.") }

    private var restingPhase: Phase { lastOutcome }
    private func live(_ operation: UUID) -> Bool {
        guard operation == epoch else { return false }
        if Task.isCancelled { invalidate("The assistant request was cancelled."); return false }
        return true
    }
    private func validateRequest() throws {
        guard let request, state.selectedTrackID == request.scope.trackID,
              looper.musicalToken == request.snapshot.token else { throw CancellationError() }
    }
    private func checkForManualChange() {
        if let request, looper.musicalToken != request.snapshot.token { invalidateForManualEdit() }
        if let keptToken, looper.musicalToken != keptToken {
            mutate { self.keptToken = nil; keptID = nil; lastOutcome = .idle
                var next = state; next.canUndo = false
                if next.phase == .kept { next.phase = .idle }
                if unsavedSessionID == nil { next.saveState = .notNeeded; next.message = "The project changed. Request a new change." }
                publish(next) }
        }
    }
    private func stopAudio() {
        let oldPreview = preview; let oldLease = lease
        preview = nil; lease = nil; previewObservation = nil
        oldPreview?.stop() // MUST precede host release on every path.
        oldLease?.end()
        host.cancelPending()
    }
    private func invalidate(_ message: String?) {
        epoch = UUID()
        if changing {
            if !terminating { deferredInvalidation = message ?? "" }
            return
        }
        mutate { terminate(message) }
    }
    private func terminate(_ message: String?) {
        terminating = true; defer { terminating = false }
        epoch = UUID(); client.cancel(); stopAudio()
        if let request { try? session.cancel(requestID: request.id) }
        request = nil
        var next = state; next.phase = restingPhase; next.previewState = .idle
        // Dismissal/discovery/cancellation must not hide a failed save.
        if unsavedSessionID == nil { next.message = message }
        publish(next)
    }
    private func fail(_ operation: UUID, message: String) {
        guard operation == epoch else { return }
        mutate { terminate(Task.isCancelled ? "The assistant request was cancelled." : message) }
    }
    private func safeClientError(_ error: Error) -> String {
        (error as? LocalMusicAssistant.Failure)?.errorDescription ?? "The local assistant is unavailable. Your project is unchanged."
    }
    private func show(_ message: String) { mutate { var next = state; next.message = message; publish(next) } }
    private func publish(_ next: State) { if state != next { state = next } }
    private func mutate(_ body: () -> Void) {
        guard !changing else { return }
        changing = true; body(); changing = false
        if let deferred = deferredInvalidation { deferredInvalidation = nil; invalidate(deferred.isEmpty ? nil : deferred) }
    }
}
