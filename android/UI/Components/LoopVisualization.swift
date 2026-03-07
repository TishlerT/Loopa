import SwiftUI
import Combine

/// Visual representation of the loop with playhead and events
struct LoopVisualization: View {
	@ObservedObject var vm: TishViewModel
	
	@State private var playheadPosition: Double = 0
	@State private var timer: AnyCancellable?
	
	var body: some View {
		GeometryReader { geo in
			let width = geo.size.width
			let height = geo.size.height
			
			ZStack(alignment: .leading) {
				// Background track
				RoundedRectangle(cornerRadius: TishRadius.sm)
					.fill(Color.tishSurface)
				
				// Grid lines (beat markers)
				if vm.looper.loopLength > 0 {
					beatMarkers(width: width, height: height)
				}
				
				// Event blocks
				if !vm.looper.events.isEmpty {
					eventBlocks(width: width, height: height)
				}
				
				// Playhead
				if vm.isPlaying || vm.isRecording {
					playhead(width: width, height: height)
				}
				
				// Empty state
				if vm.looper.loopLength == 0 && !vm.isRecording {
					emptyState
				}
				
				// Recording indicator
				if vm.isRecording {
					recordingOverlay(width: width)
				}
			}
		}
		.frame(height: 48)
		.onAppear { startPlayheadTimer() }
		.onDisappear { stopPlayheadTimer() }
		.onChange(of: vm.isPlaying) { _, isPlaying in
			if isPlaying {
				startPlayheadTimer()
			} else {
				stopPlayheadTimer()
			}
		}
	}
	
	// MARK: - Beat Markers
	
	private func beatMarkers(width: CGFloat, height: CGFloat) -> some View {
		let secondsPerBeat = 60.0 / vm.bpm
		let beatCount = Int(vm.looper.loopLength / secondsPerBeat)
		
		return ForEach(0..<max(1, beatCount), id: \.self) { beat in
			let x = (CGFloat(beat) * secondsPerBeat / vm.looper.loopLength) * width
			let isDownbeat = beat % Int(vm.metro.beatsPerBar) == 0
			
			Rectangle()
				.fill(isDownbeat ? Color.tishTextSecondary.opacity(0.4) : Color.tishTextTertiary.opacity(0.2))
				.frame(width: isDownbeat ? 2 : 1, height: height)
				.position(x: x, y: height / 2)
		}
	}
	
	// MARK: - Event Blocks
	
	private func eventBlocks(width: CGFloat, height: CGFloat) -> some View {
		let noteOnEvents = vm.looper.events.filter { $0.isNoteOn }
		
		// Group by note to create blocks
		return ForEach(noteOnEvents.indices, id: \.self) { index in
			let event = noteOnEvents[index]
			let x = (event.time / vm.looper.loopLength) * width
			let color = event.isLeft ? Color.tishAccent : Color.tishAccentSecondary
			
			// Find corresponding note off to determine duration
			let noteOff = vm.looper.events.first { off in
				!off.isNoteOn &&
				off.note == event.note &&
				off.isLeft == event.isLeft &&
				off.time > event.time
			}
			
			let duration: CGFloat = noteOff.map { CGFloat(($0.time - event.time) / vm.looper.loopLength) * width } ?? 8
			let blockWidth = max(4, min(duration, width - x))
			
			// Velocity affects height
			let velocityNorm = CGFloat(event.velocity) / 127.0
			let blockHeight = 4 + (velocityNorm * 12)
			
			RoundedRectangle(cornerRadius: 2)
				.fill(color.opacity(0.6 + velocityNorm * 0.4))
				.frame(width: blockWidth, height: blockHeight)
				.position(x: x + blockWidth / 2, y: height / 2)
		}
	}
	
	// MARK: - Playhead
	
	private func playhead(width: CGFloat, height: CGFloat) -> some View {
		let x = playheadPosition * width
		
		return ZStack {
			// Glow
			Rectangle()
				.fill(Color.tishAccent.opacity(0.3))
				.frame(width: 8, height: height)
				.blur(radius: 4)
			
			// Line
			Rectangle()
				.fill(Color.tishAccent)
				.frame(width: 2, height: height)
		}
		.position(x: x, y: height / 2)
	}
	
	// MARK: - Empty State
	
	private var emptyState: some View {
		HStack {
			Spacer()
			Text("Tap Record to start")
				.font(.tishCaption)
				.foregroundColor(.tishTextTertiary)
			Spacer()
		}
	}
	
	// MARK: - Recording Overlay
	
	private func recordingOverlay(width: CGFloat) -> some View {
		// Animated recording bar
		Rectangle()
			.fill(
				LinearGradient(
					colors: [Color.tishRecording.opacity(0.3), Color.tishRecording.opacity(0.1)],
					startPoint: .leading,
					endPoint: .trailing
				)
			)
			.frame(width: playheadPosition * width)
			.animation(.linear(duration: 0.1), value: playheadPosition)
	}
	
	// MARK: - Timer
	
	private func startPlayheadTimer() {
		stopPlayheadTimer()
		
		timer = Timer.publish(every: 0.016, on: .main, in: .common)
			.autoconnect()
			.sink { [self] _ in
				updatePlayhead()
			}
	}
	
	private func stopPlayheadTimer() {
		timer?.cancel()
		timer = nil
	}
	
	private func updatePlayhead() {
		if vm.isRecording {
			// During recording, show elapsed time as fraction of expected loop
			let elapsed = vm.looper.currentRecordingElapsed()
			let secondsPerBeat = 60.0 / vm.bpm
			// Assume 4 beats for visualization during recording
			let expectedLength = secondsPerBeat * 4
			playheadPosition = min(1.0, elapsed / expectedLength)
		} else if vm.isPlaying, vm.looper.loopLength > 0 {
			// During playback, calculate position in loop
			let now = CACurrentMediaTime()
			// We need to track when playback started - for now, estimate
			playheadPosition = fmod(now, vm.looper.loopLength) / vm.looper.loopLength
		} else {
			playheadPosition = 0
		}
	}
}

// MARK: - Circular Loop Indicator (Alternative)

struct CircularLoopIndicator: View {
	@ObservedObject var vm: TishViewModel
	
	@State private var progress: Double = 0
	@State private var timer: AnyCancellable?
	
	var body: some View {
		ZStack {
			// Background circle
			Circle()
				.stroke(Color.tishSurface, lineWidth: 4)
			
			// Progress arc
			Circle()
				.trim(from: 0, to: progress)
				.stroke(
					vm.isRecording ? Color.tishRecording :
					vm.isOverdubbing ? Color.tishOverdub :
					Color.tishPlaying,
					style: StrokeStyle(lineWidth: 4, lineCap: .round)
				)
				.rotationEffect(.degrees(-90))
				.animation(.linear(duration: 0.1), value: progress)
			
			// Event dots
			eventDots
			
			// Center icon
			Image(systemName: vm.isRecording ? "record.circle" :
				  vm.isPlaying ? "play.fill" : "circle")
				.font(.system(size: 16))
				.foregroundColor(
					vm.isRecording ? .tishRecording :
					vm.isPlaying ? .tishPlaying :
					.tishTextTertiary
				)
		}
		.frame(width: 48, height: 48)
		.onAppear { startTimer() }
		.onDisappear { stopTimer() }
	}
	
	private var eventDots: some View {
		ForEach(vm.looper.events.filter { $0.isNoteOn }.prefix(20), id: \.id) { event in
			let angle = (event.time / max(0.1, vm.looper.loopLength)) * 360 - 90
			let color = event.isLeft ? Color.tishAccent : Color.tishAccentSecondary
			
			Circle()
				.fill(color)
				.frame(width: 4, height: 4)
				.offset(y: -18)
				.rotationEffect(.degrees(angle))
		}
	}
	
	private func startTimer() {
		timer = Timer.publish(every: 0.016, on: .main, in: .common)
			.autoconnect()
			.sink { _ in
				updateProgress()
			}
	}
	
	private func stopTimer() {
		timer?.cancel()
		timer = nil
	}
	
	private func updateProgress() {
		guard vm.looper.loopLength > 0 else {
			progress = 0
			return
		}
		
		if vm.isPlaying {
			let now = CACurrentMediaTime()
			progress = fmod(now, vm.looper.loopLength) / vm.looper.loopLength
		} else {
			progress = 0
		}
	}
}

// MARK: - Preview

#Preview {
	VStack(spacing: 20) {
		LoopVisualization(vm: TishViewModel())
			.padding()
		
		CircularLoopIndicator(vm: TishViewModel())
	}
	.background(Color.tishBackground)
}

