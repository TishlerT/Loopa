import SwiftUI

/// A small local pilot: one selected track, one volume proposal, explicit listening and Keep.
struct MusicAssistantPanel: View {
    @ObservedObject var controller: MusicAssistantController
    @ObservedObject var viewModel: LooperViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var operation: Task<Void, Never>?
    @FocusState private var promptFocused: Bool
    private let mint = Color(hex: "00FFCC")

    private var busy: Bool { [.discovering, .requesting, .preparing].contains(controller.state.phase) }
    private var unsaved: Bool { controller.state.saveState == .unsaved }
    private var previewReady: Bool {
        switch controller.state.previewState {
        case .prepared, .playing: return true
        default: return false
        }
    }
    private var canRequest: Bool {
        !busy && !unsaved && controller.state.connection == .connected && controller.state.sharing &&
        controller.state.selectedModel != nil && controller.state.selectedTrackID != nil &&
        !controller.state.userText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        controller.state.userText.utf8.count <= 2_048
    }
    private var connectionTitle: String {
        switch controller.state.connection {
        case .connected: return controller.state.sharing ? "ChatGPT connected" : "Allow ChatGPT usage on your Mac"
        case .connecting: return "Finish connecting on your Mac"
        case .reconnect_required: return "Reconnect ChatGPT on your Mac"
        case .usage_unavailable: return "ChatGPT usage unavailable"
        case .disconnected: return "Connect ChatGPT on your Mac"
        }
    }
    var body: some View {
        NavigationStack {
            Form {
                connectionSection
                requestSection
                comparisonSection
                resultSection
                privacySection
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollContentBackground(.hidden).background(Color(hex: "0D0D1A"))
            .navigationTitle("Shape your sound").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { operation?.cancel(); controller.dismiss(); dismiss() }
                        .disabled(unsaved).accessibilityIdentifier("assistantCloseButton")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done typing") { promptFocused = false }
                        .accessibilityIdentifier("assistantKeyboardDoneButton")
                }
            }
        }
        .tint(mint).preferredColorScheme(.dark)
        .interactiveDismissDisabled(unsaved)
        .task {
            if controller.state.selectedTrackID == nil { controller.selectTrack(viewModel.tracks.first?.id) }
            await controller.discover()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { operation?.cancel(); controller.backgrounded() }
        }
        .onDisappear { operation?.cancel(); controller.dismiss() }
    }
    @ViewBuilder private var connectionSection: some View {
        Section {
            Text("Describe a volume change. Hear both versions, then decide.")
                .font(.body).foregroundStyle(.secondary)
            HStack {
                Label(connectionTitle, systemImage: "sparkles")
                    .accessibilityIdentifier("assistantConnectionStatus")
                Spacer()
                Button("Refresh") { operation = Task { await controller.discover() } }
                    .disabled(busy || unsaved).accessibilityIdentifier("assistantRefreshButton")
            }
            if !controller.state.models.isEmpty {
                Picker("Model", selection: Binding(get: { controller.state.selectedModel }, set: { if let value = $0 { controller.selectModel(value) } })) {
                    ForEach(controller.state.models, id: \.slug) { model in
                        Text(model.displayName).tag(Optional(model.slug))
                    }
                }
                .disabled(busy || unsaved).accessibilityIdentifier("assistantModelPicker")
            }
        } header: { Text("Local preview") }
    }

    @ViewBuilder private var requestSection: some View {
        Section {
            trackSelector
            promptField
            requestButton
            if busy {
                Button("Cancel request") { operation?.cancel(); controller.discard() }
                    .accessibilityIdentifier("assistantCancelButton")
            }
        } header: { Text("Your idea") }
    }

    private func trackTitle(_ track: Track) -> String {
        let index = (viewModel.tracks.firstIndex(where: { $0.id == track.id }) ?? 0) + 1
        return "\(index). \(track.instrumentName)"
    }

    @ViewBuilder private var trackSelector: some View {
        if viewModel.tracks.isEmpty {
            Text("Record a track to get started.")
                .foregroundStyle(.secondary).accessibilityIdentifier("assistantEmptyState")
        } else {
            Picker("Track", selection: Binding<UUID?>(get: { controller.state.selectedTrackID }, set: { controller.selectTrack($0) })) {
                Text("Choose a track").tag(Optional<UUID>.none)
                ForEach(viewModel.tracks) { track in
                    Text(trackTitle(track)).tag(Optional<UUID>(track.id))
                }
            }
            .disabled(busy || unsaved).accessibilityIdentifier("assistantTrackPicker")
        }
    }

    @ViewBuilder private var promptField: some View {
        TextField("Try “make this track a little louder”", text: Binding<String>(get: { controller.state.userText }, set: { controller.setUserText($0) }), axis: .vertical)
            .lineLimit(2...4).focused($promptFocused)
            .disabled(busy || unsaved).accessibilityIdentifier("assistantPromptField")
    }

    @ViewBuilder private var requestButton: some View {
        Button {
            promptFocused = false
            operation = Task {
                await controller.requestGain()
                if !Task.isCancelled, controller.state.phase == .ready { await controller.preparePreview() }
            }
        } label: {
            HStack {
                Text("Suggest a change").fontWeight(.semibold)
                Spacer()
                if busy { ProgressView() } else { Image(systemName: "arrow.up") }
            }
        }
        .disabled(!canRequest).accessibilityIdentifier("assistantRequestButton")
    }

    @ViewBuilder private var comparisonSection: some View {
        if controller.state.phase == .ready {
            Section {
                HStack {
                    Button("Original", systemImage: "play.fill") { controller.playOriginal() }
                        .accessibilityIdentifier("assistantOriginalButton")
                    Spacer()
                    Button("Change", systemImage: "play.fill") { controller.playChange() }
                        .accessibilityIdentifier("assistantChangeButton")
                    Spacer()
                    Button("Pause", systemImage: "pause.fill") { controller.pausePreview() }
                        .accessibilityIdentifier("assistantPauseButton")
                }
                .buttonStyle(.bordered).disabled(!previewReady)
                HStack {
                    Button("Discard") { operation?.cancel(); controller.discard() }
                        .accessibilityIdentifier("assistantDiscardButton")
                    Spacer()
                    Button("Keep change") { controller.keep() }
                        .buttonStyle(.borderedProminent).tint(mint).foregroundStyle(.black)
                        .disabled(!previewReady).accessibilityIdentifier("assistantKeepButton")
                }
            } header: { Text("Listen and decide") }
    }
    }

    @ViewBuilder private var resultSection: some View {
        if controller.state.message != nil || controller.state.canUndo {
            Section {
                if let message = controller.state.message {
                    Text(message).foregroundStyle(unsaved ? Color.orange : Color.secondary)
                        .accessibilityIdentifier("assistantMessage")
                }
                if unsaved {
                    Button("Retry saving") { controller.retrySave() }
                        .accessibilityIdentifier("assistantRetrySaveButton")
                }
                if controller.state.canUndo {
                    Button("Undo change") { controller.undo() }
                        .disabled(busy).accessibilityIdentifier("assistantUndoButton")
                }
            }
    }
    }

    @ViewBuilder private var privacySection: some View {
        Section {
            DisclosureGroup {
                Text(controller.inputSharingSummary + " Requests use the connected ChatGPT account’s allowance.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("assistantSharingSummary")
            } label: {
                Text("What is shared")
                    .accessibilityIdentifier("assistantSharingDisclosure")
            }
    }
    }

}
