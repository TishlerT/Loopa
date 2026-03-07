import SwiftUI

/// Drum sound mapping using General MIDI standard
struct DrumSound: Identifiable {
    let id = UUID()
    let name: String
    let shortName: String
    let pitch: UInt8
    let icon: String
    
    static let standardDrums: [DrumSound] = [
        DrumSound(name: "Kick", shortName: "KCK", pitch: 36, icon: "circle.fill"),
        DrumSound(name: "Snare", shortName: "SNR", pitch: 38, icon: "circle.inset.filled"),
        DrumSound(name: "Closed Hi-Hat", shortName: "CHH", pitch: 42, icon: "xmark"),
        DrumSound(name: "Open Hi-Hat", shortName: "OHH", pitch: 46, icon: "circle"),
        DrumSound(name: "Low Tom", shortName: "LTM", pitch: 45, icon: "rectangle.fill"),
        DrumSound(name: "Mid Tom", shortName: "MTM", pitch: 47, icon: "rectangle.fill"),
        DrumSound(name: "High Tom", shortName: "HTM", pitch: 50, icon: "rectangle.fill"),
        DrumSound(name: "Crash", shortName: "CRS", pitch: 49, icon: "star.fill"),
        DrumSound(name: "Ride", shortName: "RDE", pitch: 51, icon: "star"),
        DrumSound(name: "Clap", shortName: "CLP", pitch: 39, icon: "hand.raised.fill"),
        DrumSound(name: "Rim", shortName: "RIM", pitch: 37, icon: "square"),
        DrumSound(name: "Cowbell", shortName: "CBL", pitch: 56, icon: "bell.fill"),
    ]
}

/// Step sequencer grid view for drum tracks
struct DrumGridView: View {
    @ObservedObject var vm: TrackFocusViewModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    
    private var isIPad: Bool { sizeClass == .regular }
    
    // Layout constants - scale up for iPad
    private var rowHeight: CGFloat { isIPad ? 56 : 44 }
    private var cellWidth: CGFloat { isIPad ? 48 : 36 }
    private var labelWidth: CGFloat { isIPad ? 80 : 60 }
    private var iconSize: CGFloat { isIPad ? 16 : 12 }
    private var labelFontSize: CGFloat { isIPad ? 14 : 11 }
    private var stepFontSize: CGFloat { isIPad ? 13 : 10 }
    private var noteIconSize: CGFloat { isIPad ? 18 : 14 }
    
    // Filtered drum sounds that have notes or are standard
    private var activeDrumSounds: [DrumSound] {
        // Start with standard drums
        var sounds = DrumSound.standardDrums
        
        // Add any custom pitches from the track
        let existingPitches = Set(sounds.map(\.pitch))
        let trackPitches = Set(vm.track.notes.map(\.pitch))
        
        for pitch in trackPitches.sorted() {
            if !existingPitches.contains(pitch) {
                sounds.append(DrumSound(
                    name: "Drum \(pitch)",
                    shortName: "D\(pitch)",
                    pitch: pitch,
                    icon: "circle.dashed"
                ))
            }
        }
        
        return sounds
    }
    
    // Visible drum sounds (filtered when hideEmptyDrumRows is on)
    private var visibleDrumSounds: [DrumSound] {
        if vm.hideEmptyDrumRows {
            // Only show drums that have at least one note
            return activeDrumSounds.filter { drum in
                vm.track.notes.contains { $0.pitch == drum.pitch }
            }
        }
        return activeDrumSounds
    }
    
    var body: some View {
        GeometryReader { geo in
            // Use track's own recorded length, not global loop length
            let stepsCount = Int(vm.trackLengthBeats * 4)  // 16th note steps
            let gridWidth = CGFloat(stepsCount) * cellWidth
            
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                VStack(spacing: 0) {
                    // Step number header
                    stepHeader(stepsCount: stepsCount)
                    
                    // Drum rows (filtered when hideEmptyDrumRows is on)
                    ForEach(visibleDrumSounds) { drum in
                        drumRow(drum: drum, stepsCount: stepsCount)
                    }
                }
                .frame(width: labelWidth + gridWidth)
            }
        }
        .background(Color(hex: "0D0D1A"))
    }
    
    // MARK: - Step Header
    
    private func stepHeader(stepsCount: Int) -> some View {
        HStack(spacing: 0) {
            // Empty corner
            Text("")
                .frame(width: labelWidth, height: isIPad ? 30 : 24)
                .background(Color(hex: "1A1A30"))
            
            // Step numbers
            ForEach(0..<stepsCount, id: \.self) { step in
                let isDownbeat = step % 4 == 0
                let beat = step / 4 + 1
                
                Text(isDownbeat ? "\(beat)" : "")
                    .font(.system(size: stepFontSize, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(width: cellWidth, height: isIPad ? 30 : 24)
                    .background(isDownbeat ? Color.white.opacity(0.05) : Color.clear)
            }
        }
        .background(Color(hex: "1A1A30"))
    }
    
    // MARK: - Drum Row
    
    private func drumRow(drum: DrumSound, stepsCount: Int) -> some View {
        HStack(spacing: 0) {
            // Drum label
            HStack(spacing: isIPad ? 8 : 6) {
                Image(systemName: drum.icon)
                    .font(.system(size: iconSize))
                    .foregroundColor(Color(hex: "FF9500"))
                
                Text(drum.shortName)
                    .font(.system(size: labelFontSize, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
            }
            .frame(width: labelWidth, height: rowHeight)
            .background(Color(hex: "1A1A30"))
            
            // Step cells
            ForEach(0..<stepsCount, id: \.self) { step in
                stepCell(drum: drum, step: step, stepsCount: stepsCount)
            }
        }
        .background(Color(hex: "0D0D1A"))
    }
    
    // MARK: - Step Cell
    
    private func stepCell(drum: DrumSound, step: Int, stepsCount: Int) -> some View {
        let stepBeat = Double(step) / 4.0  // Convert step to beat (16th notes)
        let hasNote = noteAt(pitch: drum.pitch, beat: stepBeat) != nil
        let isDownbeat = step % 4 == 0
        let isCurrentStep = isStepActive(step: step, stepsCount: stepsCount)
        
        return Button {
            toggleNote(pitch: drum.pitch, beat: stepBeat)
        } label: {
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(cellBackgroundColor(hasNote: hasNote, isDownbeat: isDownbeat, isActive: isCurrentStep))
                    .frame(width: cellWidth - 2, height: rowHeight - 4)
                
                // Note indicator
                if hasNote {
                    let note = noteAt(pitch: drum.pitch, beat: stepBeat)
                    let velocity = Double(note?.velocity ?? 100) / 127.0
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: "FF9500").opacity(0.3 + velocity * 0.7))
                        .frame(width: cellWidth - 6, height: rowHeight - 8)
                    
                    Image(systemName: drum.icon)
                        .font(.system(size: noteIconSize))
                        .foregroundColor(.white)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: cellWidth, height: rowHeight)
    }
    
    // MARK: - Helpers
    
    private func cellBackgroundColor(hasNote: Bool, isDownbeat: Bool, isActive: Bool) -> Color {
        if isActive {
            return Color(hex: "00FFCC").opacity(0.3)
        } else if hasNote {
            return Color(hex: "2A2A4A")
        } else if isDownbeat {
            return Color.white.opacity(0.08)
        } else {
            return Color.white.opacity(0.04)
        }
    }
    
    private func isStepActive(step: Int, stepsCount: Int) -> Bool {
        let stepBeat = Double(step) / 4.0
        let nextStepBeat = Double(step + 1) / 4.0
        // Wrap currentBeat within track's own length for proper sync
        let trackLength = vm.trackLengthBeats
        let wrappedBeat = trackLength > 0 ? vm.currentBeat.truncatingRemainder(dividingBy: trackLength) : vm.currentBeat
        return wrappedBeat >= stepBeat && wrappedBeat < nextStepBeat
    }
    
    private func noteAt(pitch: UInt8, beat: Double) -> MidiNote? {
        // Look for note at this exact beat (within tolerance)
        let tolerance = 0.125 / 2  // Half of a 32nd note
        return vm.track.notes.first { note in
            note.pitch == pitch && abs(note.startBeat - beat) < tolerance
        }
    }
    
    private func toggleNote(pitch: UInt8, beat: Double) {
        if let existingNote = noteAt(pitch: pitch, beat: beat) {
            // Delete existing note
            vm.deleteNote(existingNote.id)
        } else {
            // Add new note (short duration for drums - 1/16 note)
            vm.addNote(pitch: pitch, startBeat: beat, duration: 0.25, velocity: 100)
        }
    }
}

#Preview {
    let looperVM = LooperViewModel()
    let track = Track(
        instrumentName: "Drums",
        instrumentProgram: 0,
        isDrumKit: true,
        notes: [
            MidiNote(pitch: 36, velocity: 100, startBeat: 0, durationBeats: 0.25),
            MidiNote(pitch: 36, velocity: 100, startBeat: 1, durationBeats: 0.25),
            MidiNote(pitch: 38, velocity: 90, startBeat: 1, durationBeats: 0.25),
            MidiNote(pitch: 42, velocity: 80, startBeat: 0.5, durationBeats: 0.25),
            MidiNote(pitch: 42, velocity: 80, startBeat: 1.5, durationBeats: 0.25)
        ]
    )
    let focusVM = TrackFocusViewModel(track: track, looperVM: looperVM)
    
    return DrumGridView(vm: focusVM)
        .frame(height: 400)
}

