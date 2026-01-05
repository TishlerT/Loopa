import SwiftUI
import Combine

/// ViewModel for the Tracks mixer screen
/// Acts as a lightweight wrapper around LooperViewModel for track-specific operations
@MainActor
final class TracksViewModel: ObservableObject {
    
    // MARK: - Dependencies
    
    private let looperVM: LooperViewModel
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Published State
    
    @Published private(set) var tracks: [Track] = []
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var isPaused: Bool = false
    @Published private(set) var currentPosition: Double = 0
    @Published var selectedTrackId: UUID? = nil
    @Published var showingQuantizeSheet = false
    @Published var trackToQuantize: Track? = nil
    @Published var showingInstrumentPicker = false
    @Published var trackToChangeInstrument: Track? = nil
    @Published var selectedTrackForFocus: Track? = nil  // For presenting MIDI editor
    
    // MARK: - Computed Properties
    
    var anyTrackSoloed: Bool {
        looperVM.anyTrackSoloed
    }
    
    var loopLengthBeats: Double {
        looperVM.loopLengthBeats
    }
    
    var bpm: Double {
        looperVM.bpm
    }
    
    // MARK: - Initialization
    
    init(looperVM: LooperViewModel) {
        self.looperVM = looperVM
        
        // Forward tracks from looperVM
        looperVM.$tracks
            .receive(on: DispatchQueue.main)
            .assign(to: &$tracks)
        
        // Forward isPlaying
        looperVM.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playing in
                self?.isPlaying = playing
            }
            .store(in: &cancellables)
        
        // Forward isPaused
        looperVM.$isPaused
            .receive(on: DispatchQueue.main)
            .sink { [weak self] paused in
                self?.isPaused = paused
            }
            .store(in: &cancellables)
        
        // Forward currentPosition for progress bar
        looperVM.$currentPosition
            .receive(on: DispatchQueue.main)
            .sink { [weak self] position in
                self?.currentPosition = position
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Track Operations
    
    func toggleMute(_ track: Track) {
        looperVM.toggleMute(track)
    }
    
    func toggleSolo(_ track: Track) {
        looperVM.toggleSolo(track)
    }
    
    func toggleLoop(_ track: Track) {
        looperVM.toggleLoop(track)
    }
    
    func setVolume(_ track: Track, volume: Float) {
        looperVM.setTrackVolume(track, volume: volume)
    }
    
    func setInstrument(_ track: Track, instrument: Instrument) {
        looperVM.setTrackInstrument(track, instrument: instrument)
    }
    
    func deleteTrack(_ track: Track) {
        looperVM.deleteTrack(track)
    }
    
    func quantizeTrack(_ track: Track, division: QuantizeDivision) {
        looperVM.quantizeTrack(track, division: division)
    }
    
    // MARK: - Quantize Flow
    
    func requestQuantize(_ track: Track) {
        trackToQuantize = track
        showingQuantizeSheet = true
    }
    
    func applyQuantize(division: QuantizeDivision) {
        guard let track = trackToQuantize else { return }
        quantizeTrack(track, division: division)
        showingQuantizeSheet = false
        trackToQuantize = nil
    }
    
    func cancelQuantize() {
        showingQuantizeSheet = false
        trackToQuantize = nil
    }
    
    // MARK: - Instrument Change Flow
    
    func requestInstrumentChange(_ track: Track) {
        trackToChangeInstrument = track
        showingInstrumentPicker = true
    }
    
    func applyInstrumentChange(instrument: Instrument) {
        guard let track = trackToChangeInstrument else { return }
        setInstrument(track, instrument: instrument)
        showingInstrumentPicker = false
        trackToChangeInstrument = nil
    }
    
    func cancelInstrumentChange() {
        showingInstrumentPicker = false
        trackToChangeInstrument = nil
    }
    
    // MARK: - Track Focus Navigation
    
    func selectTrackForFocus(_ track: Track) {
        selectedTrackForFocus = track
    }
    
    func closeTrackFocus() {
        selectedTrackForFocus = nil
    }
    
    var looperViewModel: LooperViewModel {
        looperVM
    }
    
    func getTrack(withId id: UUID) -> Track? {
        tracks.first { $0.id == id }
    }
}

