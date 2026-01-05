import SwiftUI

/// Tracks mixer screen showing all tracks with M/S/Q, volume, and instrument controls
struct TracksView: View {
    @ObservedObject var vm: TracksViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showingDeleteConfirmation = false
    @State private var trackToDelete: Track? = nil
    
    // MARK: - iPad Detection & Sizing - Enlarged for better visibility/touch
    
    private var isIPad: Bool { sizeClass == .regular }
    private var headerPadH: CGFloat { isIPad ? 32 : 16 }
    private var headerPadV: CGFloat { isIPad ? 24 : 12 }
    private var doneTextSize: CGFloat { isIPad ? 26 : 16 }
    private var transportSize: CGFloat { isIPad ? 72 : 40 }
    private var transportIconSize: CGFloat { isIPad ? 28 : 16 }
    private var transportPauseW: CGFloat { isIPad ? 10 : 4 }
    private var transportPauseH: CGFloat { isIPad ? 32 : 14 }
    private var logoMainSize: CGFloat { isIPad ? 40 : 20 }
    private var logoInfinitySize: CGFloat { isIPad ? 52 : 26 }
    private var emptyIconSize: CGFloat { isIPad ? 96 : 48 }
    private var emptyTitleSize: CGFloat { isIPad ? 36 : 20 }
    private var emptySubtitleSize: CGFloat { isIPad ? 22 : 14 }
    private var listPadH: CGFloat { isIPad ? 40 : 16 }
    private var listSpacing: CGFloat { isIPad ? 20 : 12 }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Custom header with logo and transport
                headerBar
                
                // Progress bar showing current position in loop
                progressBar
                
                if vm.tracks.isEmpty {
                    emptyState
                } else {
                    tracksList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(
                    colors: [Color(hex: "1A1A2E"), Color(hex: "0D0D1A")],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .navigationBarHidden(true)
        }
        .alert("Delete Track?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                trackToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let track = trackToDelete {
                    vm.deleteTrack(track)
                }
                trackToDelete = nil
            }
        } message: {
            if let track = trackToDelete {
                Text("Are you sure you want to delete \"\(track.instrumentName)\"? This cannot be undone.")
            }
        }
        .sheet(isPresented: $vm.showingQuantizeSheet) {
            if let track = vm.trackToQuantize {
                QuantizeOptionsSheet(
                    trackName: track.instrumentName,
                    onSelect: { division in
                        vm.applyQuantize(division: division)
                    },
                    onCancel: {
                        vm.cancelQuantize()
                    }
                )
                .presentationDetents([.medium])
            }
        }
        .sheet(isPresented: $vm.showingInstrumentPicker) {
            if let track = vm.trackToChangeInstrument {
                InstrumentPickerSheet(
                    currentInstrument: track.instrument,
                    onSelect: { instrument in
                        vm.applyInstrumentChange(instrument: instrument)
                    },
                    onCancel: {
                        vm.cancelInstrumentChange()
                    }
                )
                .presentationDetents([.medium])
            }
        }
        .fullScreenCover(item: $vm.selectedTrackForFocus) { track in
            TrackFocusViewWrapper(track: track, looperVM: vm.looperViewModel)
        }
    }
    
    // MARK: - Header Bar
    
    private var headerBar: some View {
        HStack(spacing: isIPad ? 20 : 12) {
            // Done button
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.system(size: doneTextSize, weight: .semibold))
                    .foregroundColor(Color(hex: "00FFCC"))
            }
            
            Spacer()
            
            // Transport controls
            HStack(spacing: isIPad ? 20 : 16) {
                // Restart button
                Button {
                    vm.looperViewModel.restartPlayback()
                } label: {
                    ZStack {
                        Circle()
                            .stroke(Color(hex: "00CCFF"), lineWidth: isIPad ? 3 : 2)
                            .frame(width: transportSize, height: transportSize)
                        
                        Circle()
                            .fill(Color(hex: "00CCFF").opacity(0.2))
                            .frame(width: transportSize, height: transportSize)
                        
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: transportIconSize, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                
                // Play/Pause button
                Button {
                    vm.looperViewModel.togglePlayPause()
                } label: {
                    ZStack {
                        Circle()
                            .stroke(vm.isPlaying ? Color(hex: "34C759") : (vm.isPaused ? Color(hex: "FF9500") : Color(hex: "4A4A6A")), lineWidth: isIPad ? 3 : 2)
                            .frame(width: transportSize, height: transportSize)
                        
                        Circle()
                            .fill(vm.isPlaying ? Color(hex: "34C759").opacity(0.2) : (vm.isPaused ? Color(hex: "FF9500").opacity(0.2) : Color(hex: "2A2A4A")))
                            .frame(width: transportSize, height: transportSize)
                        
                        if vm.isPlaying {
                            HStack(spacing: isIPad ? 6 : 4) {
                                RoundedRectangle(cornerRadius: isIPad ? 2 : 1)
                                    .fill(Color.white)
                                    .frame(width: transportPauseW, height: transportPauseH)
                                RoundedRectangle(cornerRadius: isIPad ? 2 : 1)
                                    .fill(Color.white)
                                    .frame(width: transportPauseW, height: transportPauseH)
                            }
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: isIPad ? 28 : 14))
                                .foregroundColor(.white)
                                .offset(x: isIPad ? 3 : 1)
                        }
                    }
                }
            }
            
            Spacer()
            
            // Logo "L∞PA"
            HStack(spacing: 0) {
                Text("L")
                    .font(.system(size: logoMainSize, weight: .black, design: .rounded))
                Text("∞")
                    .font(.system(size: logoInfinitySize, weight: .black))
                    .baselineOffset(isIPad ? 3 : 2)
                Text("PA")
                    .font(.system(size: logoMainSize, weight: .black, design: .rounded))
            }
            .foregroundColor(.white)
        }
        .padding(.horizontal, headerPadH)
        .padding(.vertical, headerPadV)
        .background(Color(hex: "1A1A30"))
    }
    
    // MARK: - Progress Bar
    
    private var progressBar: some View {
        let barHeight: CGFloat = isIPad ? 10 : 4
        
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: isIPad ? 3 : 2)
                    .fill(Color.white.opacity(0.1))
                    .frame(height: barHeight)
                
                // Progress fill
                RoundedRectangle(cornerRadius: isIPad ? 3 : 2)
                    .fill(Color(hex: "00FFCC"))
                    .frame(width: progressWidth(totalWidth: geo.size.width), height: barHeight)
            }
        }
        .frame(height: barHeight)
        .padding(.horizontal, headerPadH)
        .padding(.vertical, isIPad ? 12 : 8)
        .background(Color(hex: "1A1A30").opacity(0.5))
    }
    
    private func progressWidth(totalWidth: CGFloat) -> CGFloat {
        guard vm.loopLengthBeats > 0 else { return 0 }
        let secondsPerBeat = 60.0 / vm.bpm
        let loopDuration = vm.loopLengthBeats * secondsPerBeat
        let progress = vm.currentPosition / loopDuration
        return max(0, min(totalWidth, CGFloat(progress) * totalWidth))
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: isIPad ? 24 : 16) {
            Spacer()
            
            Image(systemName: "music.note.list")
                .font(.system(size: emptyIconSize))
                .foregroundColor(.white.opacity(0.2))
            
            Text("No Tracks Yet")
                .font(.system(size: emptyTitleSize, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
            
            Text("Record some notes to create tracks")
                .font(.system(size: emptySubtitleSize))
                .foregroundColor(.white.opacity(0.4))
            
            Spacer()
        }
    }
    
    // MARK: - Tracks List
    
    private var tracksList: some View {
        ScrollView {
            LazyVStack(spacing: listSpacing) {
                ForEach(vm.tracks) { track in
                    TrackMixerRow(
                        track: track,
                        anyTrackSoloed: vm.anyTrackSoloed,
                        onTap: {
                            // Only allow opening MIDI editor for non-vocal tracks
                            if !track.isVocal {
                                vm.selectTrackForFocus(track)
                            }
                        },
                        onToggleMute: {
                            vm.toggleMute(track)
                        },
                        onToggleSolo: {
                            vm.toggleSolo(track)
                        },
                        onToggleLoop: {
                            vm.toggleLoop(track)
                        },
                        onQuantize: {
                            vm.requestQuantize(track)
                        },
                        onVolumeChange: { newVolume in
                            vm.setVolume(track, volume: newVolume)
                        },
                        onInstrumentTap: {
                            // Don't allow instrument switching for drum tracks
                            if !track.isDrumKit {
                                vm.requestInstrumentChange(track)
                            }
                        },
                        onDelete: {
                            trackToDelete = track
                            showingDeleteConfirmation = true
                        }
                    )
                }
            }
            .padding(.horizontal, listPadH)
            .padding(.vertical, isIPad ? 20 : 12)
        }
    }
}

#Preview {
    TracksView(vm: TracksViewModel(looperVM: LooperViewModel()))
}

