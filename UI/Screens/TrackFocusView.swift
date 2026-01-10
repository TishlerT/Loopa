import SwiftUI

/// Wrapper that creates and retains the TrackFocusViewModel as a @StateObject
/// This prevents the VM from being recreated on parent re-renders
struct TrackFocusViewWrapper: View {
    @StateObject private var vm: TrackFocusViewModel
    
    init(track: Track, looperVM: LooperViewModel) {
        _vm = StateObject(wrappedValue: TrackFocusViewModel(track: track, looperVM: looperVM))
    }
    
    var body: some View {
        TrackFocusView(vm: vm)
    }
}

/// Full-screen piano roll editor for a single track
struct TrackFocusView: View {
    @ObservedObject var vm: TrackFocusViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    
    @State private var showingInstrumentPicker = false
    
    // MARK: - iPad Detection & Sizing
    
    private var isIPad: Bool { sizeClass == .regular }
    
    // Header bar sizing - further enlarged for iPad visibility/touch
    private var headerPadH: CGFloat { isIPad ? 36 : 12 }
    private var headerPadV: CGFloat { isIPad ? 10 : 8 }  // Reduced vertical padding for more editor space
    private var closeTextSize: CGFloat { isIPad ? 26 : 14 }
    private var headerTransportSize: CGFloat { isIPad ? 68 : 34 }
    private var headerTransportIconSize: CGFloat { isIPad ? 28 : 14 }
    private var headerPauseW: CGFloat { isIPad ? 10 : 3 }
    private var headerPauseH: CGFloat { isIPad ? 30 : 12 }
    private var beatIndicatorSize: CGFloat { isIPad ? 20 : 10 }
    private var headerLogoMainSize: CGFloat { isIPad ? 36 : 16 }
    private var headerLogoInfinitySize: CGFloat { isIPad ? 46 : 20 }
    
    // Toolbar sizing - further enlarged for iPad visibility/touch
    private var toolbarPadH: CGFloat { isIPad ? 32 : 10 }
    private var toolbarPadV: CGFloat { isIPad ? 6 : 6 }  // Reduced vertical padding for more editor space
    private var toolbarButtonSize: CGFloat { isIPad ? 56 : 28 }
    private var toolbarIconSize: CGFloat { isIPad ? 26 : 14 }
    private var toolbarSmallIconSize: CGFloat { isIPad ? 24 : 12 }
    private var toolbarCornerRadius: CGFloat { isIPad ? 12 : 5 }
    private var toolbarSpacing: CGFloat { isIPad ? 18 : 8 }
    private var toolbarModeSpacing: CGFloat { isIPad ? 10 : 4 }
    
    // Helper bar sizing - further enlarged for iPad visibility/touch
    private var helperPadH: CGFloat { isIPad ? 40 : 16 }
    private var helperPadV: CGFloat { isIPad ? 14 : 10 }
    private var helperIconSize: CGFloat { isIPad ? 24 : 12 }
    private var helperTextSize: CGFloat { isIPad ? 20 : 11 }
    private var helperSpacing: CGFloat { isIPad ? 40 : 16 }
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom header with logo, transport, and controls
            headerBar
            
            // Toolbar with editing controls
            toolbarBar
            
            // Piano roll or Drum grid based on track type
            if vm.track.isDrumKit {
                DrumGridView(vm: vm)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                PianoRollCanvasView(vm: vm)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            // Helper text
            helperBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Color(hex: "1A1A2E"), Color(hex: "0D0D1A")],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .sheet(isPresented: $showingInstrumentPicker) {
            InstrumentPickerSheet(
                currentInstrument: vm.track.instrument,
                onSelect: { instrument in
                    vm.setInstrument(instrument)
                    showingInstrumentPicker = false
                },
                onCancel: {
                    showingInstrumentPicker = false
                }
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $vm.showingQuantizeSheet) {
            QuantizeOptionsSheet(
                trackName: vm.track.instrumentName,
                onSelect: { division in
                    vm.quantizeTrack(division: division)
                    vm.showingQuantizeSheet = false
                },
                onCancel: {
                    vm.showingQuantizeSheet = false
                }
            )
            .presentationDetents([.medium])
        }
    }
    
    // MARK: - Header Bar (with logo, transport, and close)
    
    private var headerBar: some View {
        HStack(spacing: isIPad ? 16 : 10) {
            // Close button
            Button {
                dismiss()
            } label: {
                Text("Close")
                    .font(.system(size: closeTextSize, weight: .semibold))
                    .foregroundColor(Color(hex: "00FFCC"))
            }
            
            Spacer()
            
            // Transport controls (matching Page 1 style, smaller) with beat indicator below
            VStack(spacing: isIPad ? 6 : 4) {
                HStack(spacing: isIPad ? 16 : 12) {
                    // Restart button
                    Button {
                        vm.restart()
                    } label: {
                        ZStack {
                            Circle()
                                .stroke(Color(hex: "00CCFF"), lineWidth: isIPad ? 3 : 2)
                                .frame(width: headerTransportSize, height: headerTransportSize)
                            
                            Circle()
                                .fill(Color(hex: "00CCFF").opacity(0.2))
                                .frame(width: headerTransportSize, height: headerTransportSize)
                            
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: headerTransportIconSize, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    
                    // Play/Pause button
                    Button {
                        vm.togglePlayback()
                    } label: {
                        ZStack {
                            Circle()
                                .stroke(vm.isPlaying ? Color(hex: "34C759") : Color(hex: "4A4A6A"), lineWidth: isIPad ? 3 : 2)
                                .frame(width: headerTransportSize, height: headerTransportSize)
                            
                            Circle()
                                .fill(vm.isPlaying ? Color(hex: "34C759").opacity(0.2) : Color(hex: "2A2A4A"))
                                .frame(width: headerTransportSize, height: headerTransportSize)
                            
                            if vm.isPlaying {
                                HStack(spacing: isIPad ? 5 : 3) {
                                    RoundedRectangle(cornerRadius: isIPad ? 2 : 1)
                                        .fill(Color.white)
                                        .frame(width: headerPauseW, height: headerPauseH)
                                    RoundedRectangle(cornerRadius: isIPad ? 2 : 1)
                                        .fill(Color.white)
                                        .frame(width: headerPauseW, height: headerPauseH)
                                }
                            } else {
                                Image(systemName: "play.fill")
                                    .font(.system(size: isIPad ? 26 : 12))
                                    .foregroundColor(.white)
                                    .offset(x: isIPad ? 3 : 1)
                            }
                        }
                    }
                }
                
                // Beat position indicator (centered under transport)
                Text(String(format: "%.1f / %.0f", vm.currentBeat, vm.loopLengthBeats))
                    .font(.system(size: beatIndicatorSize, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            // Logo "L∞PA" (smaller)
            HStack(spacing: 0) {
                Text("L")
                    .font(.system(size: headerLogoMainSize, weight: .black, design: .rounded))
                Text("∞")
                    .font(.system(size: headerLogoInfinitySize, weight: .black))
                    .baselineOffset(isIPad ? 2 : 1)
                Text("PA")
                    .font(.system(size: headerLogoMainSize, weight: .black, design: .rounded))
            }
            .foregroundColor(.white)
        }
        .padding(.horizontal, headerPadH)
        .padding(.vertical, headerPadV)
        .background(Color(hex: "1A1A30"))
    }
    
    // MARK: - Toolbar Bar (with editing controls)
    
    private var toolbarBar: some View {
        HStack(spacing: toolbarSpacing) {
            // Track/instrument selector button
            trackInfoButton
            
            // Mode toggle buttons
            HStack(spacing: toolbarModeSpacing) {
                // Multi-select mode
                multiSelectModeButton
                
                // Add note mode
                addNoteModeButton
                
                // Delete mode
                deleteNoteModeButton
                
                // Copy/Paste buttons (visible when relevant)
                if vm.isMultiSelectMode {
                    copyButton
                    pasteButton
                }
            }
            
            Spacer()
            
            // Editing controls (fixed size to prevent compression)
            HStack(spacing: toolbarModeSpacing) {
                // Hide empty rows toggle (drums only)
                if vm.track.isDrumKit {
                    hideEmptyRowsButton
                }
                zoomControls
                undoButton
                quantizeButton
                gridStepMenu
            }
            .fixedSize()
        }
        .padding(.horizontal, toolbarPadH)
        .padding(.vertical, toolbarPadV)
        .background(Color(hex: "1A1A30").opacity(0.7))
    }
    
    // MARK: - Add Note Mode Button
    
    private var addNoteModeButton: some View {
        Button {
            vm.toggleAddNoteMode()
        } label: {
            Image(systemName: vm.isAddNoteMode ? "plus.circle.fill" : "plus.circle")
                .font(.system(size: toolbarIconSize, weight: .medium))
                .foregroundColor(vm.isAddNoteMode ? Color(hex: "00FFCC") : .white.opacity(0.6))
                .frame(width: toolbarButtonSize, height: toolbarButtonSize)
                .background(vm.isAddNoteMode ? Color(hex: "00FFCC").opacity(0.2) : Color(hex: "2A2A4A"))
                .cornerRadius(toolbarCornerRadius)
        }
    }
    
    // MARK: - Delete Note Mode Button
    
    private var deleteNoteModeButton: some View {
        Button {
            vm.toggleDeleteMode()
        } label: {
            Image(systemName: vm.isDeleteMode ? "trash.circle.fill" : "trash.circle")
                .font(.system(size: toolbarIconSize, weight: .medium))
                .foregroundColor(vm.isDeleteMode ? Color.red : .white.opacity(0.6))
                .frame(width: toolbarButtonSize, height: toolbarButtonSize)
                .background(vm.isDeleteMode ? Color.red.opacity(0.2) : Color(hex: "2A2A4A"))
                .cornerRadius(toolbarCornerRadius)
        }
    }
    
    // MARK: - Multi-Select Mode Button
    
    private var multiSelectModeButton: some View {
        Button {
            vm.toggleMultiSelectMode()
        } label: {
            Image(systemName: vm.isMultiSelectMode ? "checkmark.rectangle.stack.fill" : "rectangle.stack")
                .font(.system(size: toolbarSmallIconSize, weight: .medium))
                .foregroundColor(vm.isMultiSelectMode ? Color(hex: "FFD700") : .white.opacity(0.6))
                .frame(width: toolbarButtonSize, height: toolbarButtonSize)
                .background(vm.isMultiSelectMode ? Color(hex: "FFD700").opacity(0.2) : Color(hex: "2A2A4A"))
                .cornerRadius(toolbarCornerRadius)
        }
    }
    
    // MARK: - Copy Button
    
    private var copyButton: some View {
        Button {
            vm.copySelectedNotes()
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.system(size: toolbarSmallIconSize, weight: .medium))
                .foregroundColor(vm.canCopy ? .white : .white.opacity(0.3))
                .frame(width: toolbarButtonSize, height: toolbarButtonSize)
                .background(Color(hex: "2A2A4A"))
                .cornerRadius(toolbarCornerRadius)
        }
        .disabled(!vm.canCopy)
    }
    
    // MARK: - Paste Button
    
    private var pasteButton: some View {
        Button {
            vm.pasteNotes()
        } label: {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: toolbarSmallIconSize, weight: .medium))
                .foregroundColor(vm.canPaste ? Color(hex: "00FFCC") : .white.opacity(0.3))
                .frame(width: toolbarButtonSize, height: toolbarButtonSize)
                .background(vm.canPaste ? Color(hex: "00FFCC").opacity(0.2) : Color(hex: "2A2A4A"))
                .cornerRadius(toolbarCornerRadius)
        }
        .disabled(!vm.canPaste)
    }
    
    // MARK: - Zoom Controls
    
    private var zoomControls: some View {
        // Use toolbarButtonSize for height to match other buttons
        let zoomButtonW: CGFloat = isIPad ? 40 : 24
        let zoomResetW: CGFloat = isIPad ? 28 : 16
        let zoomIconSize: CGFloat = isIPad ? 18 : 10
        let zoomLabelSize: CGFloat = isIPad ? 16 : 9
        
        return HStack(spacing: toolbarModeSpacing) {
            // Horizontal zoom
            HStack(spacing: 1) {
                Button {
                    vm.zoomOut()
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: zoomIconSize, weight: .medium))
                        .foregroundColor(vm.zoomLevel > vm.minZoom ? .white : .white.opacity(0.3))
                        .frame(width: zoomButtonW, height: toolbarButtonSize)
                }
                .disabled(vm.zoomLevel <= vm.minZoom)
                
                Button {
                    vm.resetZoom()
                } label: {
                    Text("H")
                        .font(.system(size: zoomLabelSize, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: zoomResetW, height: toolbarButtonSize)
                }
                
                Button {
                    vm.zoomIn()
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: zoomIconSize, weight: .medium))
                        .foregroundColor(vm.zoomLevel < vm.maxZoom ? .white : .white.opacity(0.3))
                        .frame(width: zoomButtonW, height: toolbarButtonSize)
                }
                .disabled(vm.zoomLevel >= vm.maxZoom)
            }
            .background(Color(hex: "2A2A4A"))
            .cornerRadius(toolbarCornerRadius)
            
            // Vertical zoom
            HStack(spacing: 1) {
                Button {
                    vm.zoomOutVertical()
                } label: {
                    Image(systemName: "arrow.down.left.and.arrow.up.right")
                        .font(.system(size: isIPad ? 16 : 9, weight: .medium))
                        .foregroundColor(vm.verticalZoomLevel > vm.minVerticalZoom ? .white : .white.opacity(0.3))
                        .frame(width: zoomButtonW, height: toolbarButtonSize)
                }
                .disabled(vm.verticalZoomLevel <= vm.minVerticalZoom)
                
                Button {
                    vm.resetZoom()
                } label: {
                    Text("V")
                        .font(.system(size: zoomLabelSize, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: zoomResetW, height: toolbarButtonSize)
                }
                
                Button {
                    vm.zoomInVertical()
                } label: {
                    Image(systemName: "arrow.up.right.and.arrow.down.left")
                        .font(.system(size: isIPad ? 16 : 9, weight: .medium))
                        .foregroundColor(vm.verticalZoomLevel < vm.maxVerticalZoom ? .white : .white.opacity(0.3))
                        .frame(width: zoomButtonW, height: toolbarButtonSize)
                }
                .disabled(vm.verticalZoomLevel >= vm.maxVerticalZoom)
            }
            .background(Color(hex: "2A2A4A"))
            .cornerRadius(toolbarCornerRadius)
        }
    }
    
    // MARK: - Track Info Button
    
    private var trackInfoButton: some View {
        Button {
            // Don't allow instrument switching for drum tracks
            if !vm.track.isDrumKit {
                showingInstrumentPicker = true
            }
        } label: {
            HStack(spacing: isIPad ? 6 : 4) {
                if let instrument = vm.track.instrument {
                    Image(systemName: instrument.icon)
                        .font(.system(size: isIPad ? 20 : 12))
                }
                Text(vm.track.instrumentName)
                    .font(.system(size: isIPad ? 20 : 13, weight: .semibold))
                    .lineLimit(1)
                // Hide chevron for drums since they can't switch
                if !vm.track.isDrumKit {
                    Image(systemName: "chevron.down")
                        .font(.system(size: isIPad ? 12 : 8))
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, isIPad ? 16 : 8)
            .frame(height: toolbarButtonSize)
            .background(Color(hex: "2A2A4A"))
            .cornerRadius(toolbarCornerRadius)
            .fixedSize(horizontal: true, vertical: false)
            .opacity(vm.track.isDrumKit ? 0.7 : 1.0)
        }
        .disabled(vm.track.isDrumKit)
    }
    
    // MARK: - Hide Empty Rows Button (Drums only)
    
    private var hideEmptyRowsButton: some View {
        Button {
            vm.hideEmptyDrumRows.toggle()
        } label: {
            Image(systemName: vm.hideEmptyDrumRows ? "eye.slash" : "eye")
                .font(.system(size: toolbarSmallIconSize, weight: .semibold))
                .foregroundColor(vm.hideEmptyDrumRows ? Color(hex: "00FFCC") : .white.opacity(0.6))
                .frame(width: toolbarButtonSize, height: toolbarButtonSize)
                .background(Color(hex: "2A2A4A"))
                .cornerRadius(toolbarCornerRadius)
        }
    }
    
    // MARK: - Undo Button
    
    private var undoButton: some View {
        Button {
            vm.undo()
        } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: toolbarSmallIconSize, weight: .semibold))
                .foregroundColor(vm.canUndo ? .white : .white.opacity(0.3))
                .frame(width: toolbarButtonSize, height: toolbarButtonSize)
                .background(Color(hex: "2A2A4A"))
                .cornerRadius(toolbarCornerRadius)
        }
        .disabled(!vm.canUndo)
    }
    
    // MARK: - Quantize Button
    
    private var quantizeButton: some View {
        Button {
            vm.showingQuantizeSheet = true
        } label: {
            Text("Q")
                .font(.system(size: toolbarIconSize, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "00FFCC"))
                .frame(width: toolbarButtonSize, height: toolbarButtonSize)
                .background(Color(hex: "2A2A4A"))
                .cornerRadius(toolbarCornerRadius)
        }
    }
    
    // MARK: - Grid Step Menu
    
    private var gridStepMenu: some View {
        Menu {
            ForEach([QuantizeDivision.quarter, .eighth, .sixteenth, .thirtysecond], id: \.self) { division in
                Button {
                    vm.setGridStep(division)
                } label: {
                    HStack {
                        Text(division.rawValue)
                        if vm.gridStep == division.beatFraction {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: isIPad ? 6 : 3) {
                Image(systemName: "grid")
                    .font(.system(size: isIPad ? 18 : 10))
                Text(gridStepLabel)
                    .font(.system(size: isIPad ? 18 : 10, weight: .medium, design: .monospaced))
            }
            .foregroundColor(.white.opacity(0.7))
            .padding(.horizontal, isIPad ? 14 : 6)
            .frame(height: toolbarButtonSize)
            .background(Color(hex: "2A2A4A"))
            .cornerRadius(toolbarCornerRadius)
            .fixedSize()  // Prevent compression/wrapping
        }
    }
    
    private var gridStepLabel: String {
        switch vm.gridStep {
        case 1.0: return "1/4"
        case 0.5: return "1/8"
        case 0.25: return "1/16"
        case 0.125: return "1/32"
        default: return "1/16"
        }
    }
    
    // MARK: - Helper Bar
    
    private var helperBar: some View {
        HStack(spacing: helperSpacing) {
            if vm.isAddNoteMode {
                // Add note mode hints
                HStack(spacing: isIPad ? 8 : 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: helperIconSize))
                    Text("Tap to add note")
                        .font(.system(size: helperTextSize))
                }
                .foregroundColor(Color(hex: "00FFCC"))
                
                HStack(spacing: isIPad ? 8 : 6) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: helperIconSize))
                    Text("Tap + again to exit")
                        .font(.system(size: helperTextSize))
                }
            } else if vm.isDeleteMode {
                // Delete mode hints
                HStack(spacing: isIPad ? 8 : 6) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: helperIconSize))
                    Text("Tap notes to delete")
                        .font(.system(size: helperTextSize))
                }
                .foregroundColor(.red)
                
                HStack(spacing: isIPad ? 8 : 6) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: helperIconSize))
                    Text("Tap trash again to exit")
                        .font(.system(size: helperTextSize))
                }
            } else if vm.isResizeMode {
                // Resize mode hints
                HStack(spacing: isIPad ? 8 : 6) {
                    Image(systemName: "arrow.left.and.right")
                        .font(.system(size: helperIconSize))
                    Text("Drag to resize")
                        .font(.system(size: helperTextSize))
                }
                .foregroundColor(Color(hex: "FF9500"))
                
                HStack(spacing: isIPad ? 8 : 6) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: helperIconSize))
                    Text("Tap elsewhere to exit")
                        .font(.system(size: helperTextSize))
                }
            } else {
                // Normal mode hints
                HStack(spacing: isIPad ? 8 : 6) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: helperIconSize))
                    Text("Tap to select")
                        .font(.system(size: helperTextSize))
                }
                
                HStack(spacing: isIPad ? 8 : 6) {
                    Image(systemName: "arrow.left.and.right")
                        .font(.system(size: helperIconSize))
                    Text("Drag to move")
                        .font(.system(size: helperTextSize))
                }
                
                HStack(spacing: isIPad ? 8 : 6) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: helperIconSize))
                    Text("Double-tap to resize")
                        .font(.system(size: helperTextSize))
                }
            }
            
            Spacer()
            
            Text("\(vm.track.notes.count) notes")
                .font(.system(size: helperTextSize, weight: .medium))
                .foregroundColor(Color(hex: "00FFCC"))
        }
        .foregroundColor(.white.opacity(0.5))
        .padding(.horizontal, helperPadH)
        .padding(.vertical, helperPadV)
        .background(helperBarBackground)
        .animation(.easeInOut(duration: 0.2), value: vm.isResizeMode)
        .animation(.easeInOut(duration: 0.2), value: vm.isAddNoteMode)
        .animation(.easeInOut(duration: 0.2), value: vm.isDeleteMode)
    }
    
    private var helperBarBackground: Color {
        if vm.isDeleteMode {
            return Color(hex: "2A1010")
        } else if vm.isAddNoteMode {
            return Color(hex: "0A2A20")
        } else if vm.isResizeMode {
            return Color(hex: "2A1A10")
        } else {
            return Color(hex: "1A1A30")
        }
    }
}

#Preview {
    let looperVM = LooperViewModel()
    let track = Track(
        instrumentName: "Piano",
        instrumentProgram: 0,
        isDrumKit: false,
        notes: [
            MidiNote(pitch: 60, velocity: 100, startBeat: 0, durationBeats: 1),
            MidiNote(pitch: 64, velocity: 90, startBeat: 1, durationBeats: 0.5),
            MidiNote(pitch: 67, velocity: 80, startBeat: 2, durationBeats: 2)
        ]
    )
    let focusVM = TrackFocusViewModel(track: track, looperVM: looperVM)
    
    return TrackFocusView(vm: focusVM)
}

