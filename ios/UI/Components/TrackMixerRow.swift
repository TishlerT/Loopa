import SwiftUI

/// A single track row in the Tracks mixer with M/S/Q/L buttons, volume, and instrument
struct TrackMixerRow: View {
    let track: Track
    let anyTrackSoloed: Bool
    
    // Actions
    let onTap: () -> Void
    let onToggleMute: () -> Void
    let onToggleSolo: () -> Void
    let onToggleLoop: () -> Void
    let onQuantize: () -> Void
    let onVolumeChange: (Float) -> Void
    let onInstrumentTap: () -> Void
    let onDelete: () -> Void
    
    @State private var volume: Float
    @State private var isDraggingVolume = false
    
    // iPad detection
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var isIPad: Bool { sizeClass == .regular }
    
    // iPad-specific sizing - Enlarged for better visibility/touch
    private var iconCircleSize: CGFloat { isIPad ? 88 : 56 }
    private var iconSize: CGFloat { isIPad ? 36 : 22 }
    private var trackNameSize: CGFloat { isIPad ? 22 : 15 }
    private var trackSubtitleSize: CGFloat { isIPad ? 16 : 11 }
    private var msqButtonSize: CGFloat { isIPad ? 44 : 28 }
    private var msqFontSize: CGFloat { isIPad ? 18 : 12 }
    private var deleteButtonSize: CGFloat { isIPad ? 44 : 28 }
    private var deleteFontSize: CGFloat { isIPad ? 20 : 14 }
    private var sliderWidth: CGFloat { isIPad ? 120 : 80 }
    private var sliderHeight: CGFloat { isIPad ? 8 : 6 }
    private var thumbSize: CGFloat { isIPad ? 28 : 20 }
    private var rowPaddingH: CGFloat { isIPad ? 24 : 12 }
    private var rowPaddingV: CGFloat { isIPad ? 14 : 10 }
    
    init(
        track: Track,
        anyTrackSoloed: Bool,
        onTap: @escaping () -> Void,
        onToggleMute: @escaping () -> Void,
        onToggleSolo: @escaping () -> Void,
        onToggleLoop: @escaping () -> Void,
        onQuantize: @escaping () -> Void,
        onVolumeChange: @escaping (Float) -> Void,
        onInstrumentTap: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.track = track
        self.anyTrackSoloed = anyTrackSoloed
        self.onTap = onTap
        self.onToggleMute = onToggleMute
        self.onToggleSolo = onToggleSolo
        self.onToggleLoop = onToggleLoop
        self.onQuantize = onQuantize
        self.onVolumeChange = onVolumeChange
        self.onInstrumentTap = onInstrumentTap
        self.onDelete = onDelete
        self._volume = State(initialValue: track.volume)
    }
    
    private var isAudible: Bool {
        track.isAudible(anyTrackSoloed: anyTrackSoloed)
    }
    
    private var trackColor: Color {
        if track.isVocal {
            return Color(hex: "FF9500")
        } else {
            return Color(hex: "00FFCC")
        }
    }
    
    var body: some View {
        HStack(spacing: isIPad ? 16 : 12) {
            // Delete button (trash icon)
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: deleteFontSize))
                    .foregroundColor(.red.opacity(0.7))
                    .frame(width: deleteButtonSize, height: deleteButtonSize)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(isIPad ? 8 : 6)
            }
            .accessibilityIdentifier("deleteButton_\(track.id)")
            
            // TAPPABLE AREA: Track icon + name → opens MIDI editor (only for non-vocal)
            Button(action: onTap) {
                HStack(spacing: isIPad ? 16 : 12) {
                    // Track icon (large, easy to tap)
                    ZStack {
                        Circle()
                            .fill(trackColor.opacity(isAudible ? 0.2 : 0.05))
                            .frame(width: iconCircleSize, height: iconCircleSize)
                        
                        if track.isVocal {
                            Image(systemName: "mic.fill")
                                .font(.system(size: iconSize))
                                .foregroundColor(isAudible ? trackColor : .white.opacity(0.3))
                        } else if let instrument = track.instrument {
                            Image(systemName: instrument.icon)
                                .font(.system(size: iconSize))
                                .foregroundColor(isAudible ? trackColor : .white.opacity(0.3))
                        }
                    }
                    
                    // Track name
                    VStack(alignment: .leading, spacing: isIPad ? 3 : 2) {
                        Text(track.instrumentName)
                            .font(.system(size: trackNameSize, weight: .semibold))
                            .foregroundColor(isAudible ? .white : .white.opacity(0.4))
                        
                        if track.isVocal {
                            Text("Audio track")
                                .font(.system(size: trackSubtitleSize))
                                .foregroundColor(.white.opacity(0.4))
                        } else {
                            Text("\(track.notes.count) notes")
                                .font(.system(size: trackSubtitleSize))
                                .foregroundColor(.white.opacity(0.4))
                        }
                    }
                    
                    Spacer(minLength: 0)
                    
                    // Arrow indicator (only for MIDI tracks, not vocals)
                    if !track.isVocal {
                        Image(systemName: "chevron.right")
                            .font(.system(size: isIPad ? 14 : 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.3))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(track.isVocal) // Disable tapping for vocal tracks
            
            // M S Q L buttons (horizontal row)
            HStack(spacing: isIPad ? 8 : 6) {
                msqButton(
                    label: "M",
                    isActive: track.isMuted,
                    activeColor: Color.red,
                    action: onToggleMute
                )
                .accessibilityIdentifier("muteButton_\(track.id)")
                
                msqButton(
                    label: "S",
                    isActive: track.isSolo,
                    activeColor: Color.yellow,
                    action: onToggleSolo
                )
                .accessibilityIdentifier("soloButton_\(track.id)")
                
                if !track.isVocal {
                    msqButton(
                        label: "Q",
                        isActive: false,
                        activeColor: Color(hex: "00FFCC"),
                        action: onQuantize
                    )
                    .accessibilityIdentifier("quantizeButton_\(track.id)")
                }
                
                // L (Loop) button with red strikethrough when off
                loopButton
                    .accessibilityIdentifier("loopButton_\(track.id)")
            }
            
            // Horizontal volume slider (inline after M/S/Q/L buttons)
            horizontalVolumeSlider
                .accessibilityIdentifier("volumeSlider_\(track.id)")
            
            // Instrument button (only for melodic MIDI tracks - not vocals or drums)
            if !track.isVocal && !track.isDrumKit {
                Button(action: onInstrumentTap) {
                    HStack(spacing: isIPad ? 6 : 4) {
                        if let instrument = track.instrument {
                            Image(systemName: instrument.icon)
                                .font(.system(size: isIPad ? 15 : 12))
                        }
                        Image(systemName: "chevron.down")
                            .font(.system(size: isIPad ? 10 : 8))
                    }
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, isIPad ? 14 : 10)
                    .padding(.vertical, isIPad ? 10 : 8)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(isIPad ? 8 : 6)
                }
                .accessibilityIdentifier("instrumentButton_\(track.id)")
            }
        }
        .padding(.horizontal, rowPaddingH)
        .padding(.vertical, rowPaddingV)
        .background(
            RoundedRectangle(cornerRadius: isIPad ? 16 : 12)
                .fill(Color.white.opacity(isAudible ? 0.05 : 0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: isIPad ? 16 : 12)
                        .stroke(track.isSolo ? Color.yellow.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        )
        .onChange(of: track.volume) { _, newValue in
            if !isDraggingVolume {
                volume = newValue
            }
        }
    }
    
    // MARK: - Horizontal Volume Slider (inline)
    
    private var horizontalVolumeSlider: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: isIPad ? 4 : 3)
                    .fill(Color.white.opacity(0.15))
                    .frame(height: sliderHeight)
                
                // Filled track
                RoundedRectangle(cornerRadius: isIPad ? 4 : 3)
                    .fill(trackColor)
                    .frame(width: max(0, geo.size.width * CGFloat(volume)), height: sliderHeight)
                
                // Thumb
                Circle()
                    .fill(Color.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                    .offset(x: max(0, min(geo.size.width - thumbSize, geo.size.width * CGFloat(volume) - thumbSize/2)))
            }
            .frame(height: thumbSize)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDraggingVolume = true
                        let newVolume = Float(max(0, min(1, value.location.x / geo.size.width)))
                        volume = newVolume
                        onVolumeChange(newVolume)
                    }
                    .onEnded { value in
                        isDraggingVolume = false
                        let newVolume = Float(max(0, min(1, value.location.x / geo.size.width)))
                        volume = newVolume
                        onVolumeChange(volume)
                    }
            )
        }
        .frame(width: sliderWidth, height: thumbSize)
    }
    
    // MARK: - Components
    
    private func msqButton(
        label: String,
        isActive: Bool,
        activeColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: msqFontSize, weight: .bold))
                .foregroundColor(isActive ? .black : .white.opacity(0.6))
                .frame(width: msqButtonSize, height: msqButtonSize)
                .background(isActive ? activeColor : Color.white.opacity(0.1))
                .cornerRadius(isIPad ? 8 : 6)
        }
    }
    
    /// Loop button with red strikethrough when looping is OFF
    private var loopButton: some View {
        Button(action: onToggleLoop) {
            ZStack {
                Text("L")
                    .font(.system(size: msqFontSize, weight: .bold))
                    .foregroundColor(track.isLooping ? .white.opacity(0.6) : .white.opacity(0.4))
                
                // Red strikethrough when looping is OFF
                if !track.isLooping {
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: isIPad ? 26 : 20, height: isIPad ? 3 : 2)
                        .rotationEffect(.degrees(-45))
                }
            }
            .frame(width: msqButtonSize, height: msqButtonSize)
            .background(track.isLooping ? Color.white.opacity(0.1) : Color.red.opacity(0.15))
            .cornerRadius(isIPad ? 8 : 6)
        }
    }
}

// MARK: - Quantize Options Sheet

struct QuantizeOptionsSheet: View {
    let trackName: String
    let onSelect: (QuantizeDivision) -> Void
    let onCancel: () -> Void
    
    private let options: [(QuantizeDivision, String)] = [
        (.off, "Off - No quantization"),
        (.quarter, "1/4 - Quarter notes"),
        (.eighth, "1/8 - Eighth notes"),
        (.sixteenth, "1/16 - Sixteenth notes"),
        (.thirtysecond, "1/32 - Thirty-second notes")
    ]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Text("Quantize \"\(trackName)\"")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                
                Text("Snap all notes to the selected grid")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.bottom, 20)
                
                ForEach(options, id: \.0) { division, label in
                    Button {
                        onSelect(division)
                    } label: {
                        HStack {
                            Text(label)
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                            Spacer()
                            if division == .off {
                                Text("Default")
                                    .font(.system(size: 12))
                                    .foregroundColor(Color(hex: "00FFCC"))
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.05))
                    }
                    
                    if division != .thirtysecond {
                        Divider()
                            .background(Color.white.opacity(0.1))
                    }
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(hex: "1A1A2E"))
            .navigationTitle("Quantize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }
}

// MARK: - Instrument Picker Sheet

struct InstrumentPickerSheet: View {
    let currentInstrument: Instrument?
    let onSelect: (Instrument) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(Instrument.allCases) { instrument in
                        Button {
                            onSelect(instrument)
                        } label: {
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(currentInstrument == instrument
                                              ? Color(hex: "00FFCC").opacity(0.2)
                                              : Color.white.opacity(0.1))
                                        .frame(width: 56, height: 56)
                                    
                                    Image(systemName: instrument.icon)
                                        .font(.system(size: 22))
                                        .foregroundColor(currentInstrument == instrument
                                                         ? Color(hex: "00FFCC")
                                                         : .white)
                                }
                                
                                Text(instrument.rawValue)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(currentInstrument == instrument
                                                     ? Color(hex: "00FFCC")
                                                     : .white.opacity(0.8))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(currentInstrument == instrument
                                            ? Color(hex: "00FFCC").opacity(0.5)
                                            : Color.clear, lineWidth: 1)
                            )
                        }
                    }
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(hex: "1A1A2E"))
            .navigationTitle("Instrument")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        TrackMixerRow(
            track: Track(
                instrumentName: "Piano",
                instrumentProgram: 0,
                isDrumKit: false,
                notes: [
                    MidiNote(pitch: 60, startBeat: 0, durationBeats: 1),
                    MidiNote(pitch: 64, startBeat: 1, durationBeats: 1)
                ]
            ),
            anyTrackSoloed: false,
            onTap: {},
            onToggleMute: {},
            onToggleSolo: {},
            onToggleLoop: {},
            onQuantize: {},
            onVolumeChange: { _ in },
            onInstrumentTap: {},
            onDelete: {}
        )
        
        TrackMixerRow(
            track: Track(audioFileName: "vocals.m4a"),
            anyTrackSoloed: false,
            onTap: {},
            onToggleMute: {},
            onToggleSolo: {},
            onToggleLoop: {},
            onQuantize: {},
            onVolumeChange: { _ in },
            onInstrumentTap: {},
            onDelete: {}
        )
    }
    .padding()
    .background(Color(hex: "0D0D1A"))
}
