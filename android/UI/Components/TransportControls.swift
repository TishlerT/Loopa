import SwiftUI

/// Professional transport bar with iconic buttons
struct TransportControls: View {
	@ObservedObject var vm: TishViewModel
	
	var body: some View {
		HStack(spacing: TishSpacing.lg) {
			// Metronome section
			metronomeSection
			
			Spacer()
			
			// Transport buttons
			transportButtons
			
			Spacer()
			
			// Loop info
			loopInfoSection
		}
		.padding(.horizontal, TishSpacing.lg)
		.padding(.vertical, TishSpacing.sm)
		.background(Color.tishSurface)
	}
	
	// MARK: - Metronome Section
	
	private var metronomeSection: some View {
		HStack(spacing: TishSpacing.md) {
			// Metronome toggle
			Button {
				vm.toggleMetronome()
			} label: {
				Image(systemName: vm.isMetronomeOn ? "metronome.fill" : "metronome")
					.font(.system(size: 20))
			}
			.buttonStyle(TishTransportButtonStyle(
				isActive: vm.isMetronomeOn,
				activeColor: .tishAccent
			))
			
			// BPM display and controls
			HStack(spacing: TishSpacing.xs) {
				Button {
					vm.bpm = max(40, vm.bpm - 1)
					vm.metro.bpm = vm.bpm
				} label: {
					Image(systemName: "minus")
						.font(.system(size: 12, weight: .bold))
				}
				.buttonStyle(BPMButtonStyle())
				
				Text("\(Int(vm.bpm))")
					.font(.tishMonoLarge)
					.foregroundColor(.tishTextPrimary)
					.frame(minWidth: 50)
				
				Button {
					vm.bpm = min(200, vm.bpm + 1)
					vm.metro.bpm = vm.bpm
				} label: {
					Image(systemName: "plus")
						.font(.system(size: 12, weight: .bold))
				}
				.buttonStyle(BPMButtonStyle())
			}
			
			Text("BPM")
				.font(.tishCaption)
				.foregroundColor(.tishTextSecondary)
			
			// Quantize picker
			Menu {
				ForEach(QuantizeDivision.allCases) { division in
					Button(division.rawValue) {
						vm.quantizeDivision = division
					}
				}
			} label: {
				HStack(spacing: 4) {
					Image(systemName: "squareshape.split.3x3")
						.font(.system(size: 14))
					Text(vm.quantizeDivision.rawValue)
						.font(.tishCaption)
				}
				.foregroundColor(.tishTextSecondary)
				.padding(.horizontal, TishSpacing.sm)
				.padding(.vertical, TishSpacing.xs)
				.background(Color.tishElevated)
				.cornerRadius(TishRadius.sm)
			}
		}
	}
	
	// MARK: - Transport Buttons
	
	private var transportButtons: some View {
		HStack(spacing: TishSpacing.md) {
			// Record / Set Loop button
			Button {
				if vm.isRecording {
					vm.setLoopNow()
				} else {
					vm.startRecord()
				}
			} label: {
				ZStack {
					if vm.isRecording {
						// Pulsing record indicator
						Circle()
							.fill(Color.tishRecording.opacity(0.3))
							.frame(width: 44, height: 44)
						
						// Square = "Set Loop"
						RoundedRectangle(cornerRadius: 4)
							.fill(Color.tishRecording)
							.frame(width: 16, height: 16)
					} else {
						// Record dot
						Circle()
							.fill(Color.tishRecording)
							.frame(width: 14, height: 14)
					}
				}
			}
			.buttonStyle(TishTransportButtonStyle(
				isActive: vm.isRecording,
				activeColor: .tishRecording
			))
			.animation(.easeInOut(duration: 0.3).repeatForever(autoreverses: true), value: vm.isRecording)
			
			// Overdub button
			Button {
				if vm.isOverdubbing {
					vm.looper.stopOverdub()
					vm.isOverdubbing = false
				} else {
					vm.startOverdub()
				}
			} label: {
				Image(systemName: "plus.circle")
					.font(.system(size: 20))
			}
			.buttonStyle(TishTransportButtonStyle(
				isActive: vm.isOverdubbing,
				activeColor: .tishOverdub
			))
			.disabled(vm.isRecording || vm.looper.loopLength == 0)
			.opacity(vm.isRecording || vm.looper.loopLength == 0 ? 0.4 : 1)
			
			// Play/Stop button
			Button {
				if vm.isPlaying {
					vm.stopAll()
				} else if vm.looper.loopLength > 0 {
					vm.looper.startPlayback()
					vm.isPlaying = true
				}
			} label: {
				Image(systemName: vm.isPlaying ? "stop.fill" : "play.fill")
					.font(.system(size: 20))
			}
			.buttonStyle(TishTransportButtonStyle(
				isActive: vm.isPlaying,
				activeColor: .tishPlaying
			))
			.disabled(vm.looper.loopLength == 0 && !vm.isRecording)
			.opacity(vm.looper.loopLength == 0 && !vm.isRecording ? 0.4 : 1)
			
			// Undo button
			Button {
				vm.looper.undo()
			} label: {
				Image(systemName: "arrow.uturn.backward")
					.font(.system(size: 18))
			}
			.buttonStyle(TishTransportButtonStyle(
				isActive: false,
				activeColor: .tishAccent
			))
			.disabled(!vm.looper.canUndo)
			.opacity(vm.looper.canUndo ? 1 : 0.4)
			
			// Clear button
			Button {
				vm.clearLoop()
			} label: {
				Image(systemName: "trash")
					.font(.system(size: 18))
			}
			.buttonStyle(TishTransportButtonStyle(
				isActive: false,
				activeColor: .tishAccentTertiary
			))
			.disabled(vm.looper.loopLength == 0)
			.opacity(vm.looper.loopLength == 0 ? 0.4 : 1)
		}
	}
	
	// MARK: - Loop Info Section
	
	private var loopInfoSection: some View {
		HStack(spacing: TishSpacing.sm) {
			// Loop length display
			if vm.looper.loopLength > 0 {
				VStack(alignment: .trailing, spacing: 2) {
					Text(formatTime(vm.looper.loopLength))
						.font(.tishMono)
						.foregroundColor(.tishTextPrimary)
					
					Text("\(vm.looper.events.count) events")
						.font(.tishCaption)
						.foregroundColor(.tishTextSecondary)
				}
			} else if vm.isRecording {
				Text("Recording...")
					.font(.tishCaption)
					.foregroundColor(.tishRecording)
			} else {
				Text("No loop")
					.font(.tishCaption)
					.foregroundColor(.tishTextTertiary)
			}
			
			// Undo count badge
			if vm.looper.undoCount > 0 {
				Text("\(vm.looper.undoCount)")
					.font(.tishCaption)
					.foregroundColor(.tishBackground)
					.padding(.horizontal, 6)
					.padding(.vertical, 2)
					.background(Color.tishAccent)
					.cornerRadius(TishRadius.full)
			}
		}
	}
	
	// MARK: - Helpers
	
	private func formatTime(_ seconds: Double) -> String {
		let mins = Int(seconds) / 60
		let secs = Int(seconds) % 60
		let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 100)
		if mins > 0 {
			return String(format: "%d:%02d.%02d", mins, secs, ms)
		}
		return String(format: "%d.%02d", secs, ms)
	}
}

// MARK: - BPM Button Style

struct BPMButtonStyle: ButtonStyle {
	func makeBody(configuration: Configuration) -> some View {
		configuration.label
			.foregroundColor(.tishTextSecondary)
			.frame(width: 24, height: 24)
			.background(Color.tishElevated)
			.cornerRadius(TishRadius.sm)
			.scaleEffect(configuration.isPressed ? 0.9 : 1)
	}
}

// MARK: - Preview

#Preview {
	TransportControls(vm: TishViewModel())
		.background(Color.tishBackground)
}

