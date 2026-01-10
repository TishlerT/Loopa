import SwiftUI

/// Real-time waveform visualization for vocal recording mode
/// Displays a rolling waveform that responds to microphone input levels
struct VocalWaveformView: View {
	/// Current audio input level (0.0 to 1.0)
	let audioLevel: Float
	
	/// Whether currently recording
	let isRecording: Bool
	
	/// Whether currently counting in
	let isCountingIn: Bool
	
	/// Count-in beat number (4, 3, 2, 1)
	let countInBeat: Int
	
	/// Number of bars in the waveform display
	private let barCount = 64
	
	/// Rolling buffer of recent audio levels
	@State private var levelHistory: [Float] = []
	
	/// Animation phase for idle breathing effect
	@State private var breathePhase: Double = 0
	
	/// Timer for idle animation
	@State private var breatheTimer: Timer?
	
	@Environment(\.horizontalSizeClass) private var sizeClass
	
	private var isIPad: Bool { sizeClass == .regular }
	
	var body: some View {
		GeometryReader { geo in
			ZStack {
				// Background gradient
				RoundedRectangle(cornerRadius: isIPad ? 20 : 12)
					.fill(
						LinearGradient(
							colors: [Color(hex: "0D0D1A"), Color(hex: "1A1A2E")],
							startPoint: .top,
							endPoint: .bottom
						)
					)
				
				// Waveform visualization
				waveformBars(size: geo.size)
				
				// Center line glow
				centerLineGlow(width: geo.size.width)
				
				// Mic icon with pulse effect
				microphoneOverlay(size: geo.size)
			}
		}
		.clipShape(RoundedRectangle(cornerRadius: isIPad ? 20 : 12))
		.onChange(of: audioLevel) { _, newLevel in
			updateLevelHistory(newLevel)
		}
		.onAppear {
			initializeLevelHistory()
			startBreathingAnimation()
		}
		.onDisappear {
			breatheTimer?.invalidate()
		}
	}
	
	// MARK: - Waveform Bars
	
	private func waveformBars(size: CGSize) -> some View {
		let barWidth = size.width / CGFloat(barCount)
		let maxBarHeight = size.height * 0.8
		let centerY = size.height / 2
		
		return Canvas { context, canvasSize in
			for i in 0..<barCount {
				let level = i < levelHistory.count ? levelHistory[i] : 0
				
				// Add subtle idle animation when not recording
				let idleOffset: Float = isRecording ? 0 : Float(sin(breathePhase + Double(i) * 0.1)) * 0.03
				let effectiveLevel = max(0.02, level + idleOffset) // Minimum bar height for visibility
				
				let barHeight = CGFloat(effectiveLevel) * maxBarHeight
				let x = CGFloat(i) * barWidth + barWidth / 2
				
				// Draw bar (mirrored around center)
				let topRect = CGRect(
					x: x - barWidth * 0.35,
					y: centerY - barHeight / 2,
					width: barWidth * 0.7,
					height: barHeight
				)
				
				// Gradient color based on position (creates wave effect)
				let progress = CGFloat(i) / CGFloat(barCount)
				let color = barColor(progress: progress, level: effectiveLevel)
				
				let path = RoundedRectangle(cornerRadius: 2)
					.path(in: topRect)
				
				context.fill(path, with: .color(color))
			}
		}
	}
	
	private func barColor(progress: CGFloat, level: Float) -> Color {
		// Gradient from cyan to blue, with intensity based on level
		let baseColor: Color
		if progress < 0.5 {
			baseColor = Color(hex: "00FFCC")
		} else {
			baseColor = Color(hex: "00CCFF")
		}
		
		// Brighter when level is higher
		let opacity = 0.4 + Double(level) * 0.6
		return baseColor.opacity(opacity)
	}
	
	// MARK: - Center Line Glow
	
	private func centerLineGlow(width: CGFloat) -> some View {
		Rectangle()
			.fill(
				LinearGradient(
					colors: [
						Color(hex: "00FFCC").opacity(0),
						Color(hex: "00FFCC").opacity(isRecording ? 0.6 : 0.2),
						Color(hex: "00FFCC").opacity(0)
					],
					startPoint: .leading,
					endPoint: .trailing
				)
			)
			.frame(height: 2)
			.blur(radius: isRecording ? 4 : 2)
	}
	
	// MARK: - Microphone Overlay
	
	private func microphoneOverlay(size: CGSize) -> some View {
		let iconSize: CGFloat = isIPad ? 80 : 50
		let pulseScale = isRecording ? 1.0 + Double(audioLevel) * 0.3 : 1.0
		
		return ZStack {
			// Glow ring (pulses with audio)
			if isRecording || isCountingIn {
				Circle()
					.stroke(
						Color(hex: isCountingIn ? "FF9500" : "FF3B30").opacity(0.3),
						lineWidth: isIPad ? 4 : 2
					)
					.frame(width: iconSize * 1.8, height: iconSize * 1.8)
					.scaleEffect(pulseScale)
					.blur(radius: 8)
					.animation(.easeOut(duration: 0.1), value: audioLevel)
			}
			
			// Background circle
			Circle()
				.fill(Color(hex: "2A2A4A").opacity(0.8))
				.frame(width: iconSize * 1.4, height: iconSize * 1.4)
			
			// Count-in display or mic icon
			if isCountingIn {
				Text("\(countInBeat)")
					.font(.system(size: isIPad ? 48 : 32, weight: .bold, design: .rounded))
					.foregroundColor(Color(hex: "FF9500"))
			} else {
				// Mic icon
				Image(systemName: isRecording ? "mic.fill" : "mic")
					.font(.system(size: isIPad ? 36 : 24, weight: .medium))
					.foregroundColor(isRecording ? Color(hex: "FF3B30") : Color(hex: "00FFCC"))
					.scaleEffect(isRecording ? 1.0 + CGFloat(audioLevel) * 0.2 : 1.0)
					.animation(.easeOut(duration: 0.1), value: audioLevel)
			}
			
			// Recording indicator ring
			if isRecording {
				Circle()
					.stroke(Color(hex: "FF3B30"), lineWidth: isIPad ? 3 : 2)
					.frame(width: iconSize * 1.4, height: iconSize * 1.4)
			}
		}
	}
	
	// MARK: - Level History Management
	
	private func initializeLevelHistory() {
		levelHistory = Array(repeating: 0, count: barCount)
	}
	
	private func updateLevelHistory(_ newLevel: Float) {
		// Shift history left and add new level at the end (creates scrolling effect)
		var history = levelHistory
		if history.count > 0 {
			history.removeFirst()
			history.append(newLevel)
			levelHistory = history
		}
	}
	
	private func startBreathingAnimation() {
		breatheTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { _ in
			breathePhase += 0.05
			if breathePhase > .pi * 2 {
				breathePhase -= .pi * 2
			}
		}
	}
}

// MARK: - Preview

#Preview {
	VStack(spacing: 20) {
		// Idle state
		VocalWaveformView(
			audioLevel: 0.1,
			isRecording: false,
			isCountingIn: false,
			countInBeat: 0
		)
		.frame(height: 200)
		
		// Recording state
		VocalWaveformView(
			audioLevel: 0.6,
			isRecording: true,
			isCountingIn: false,
			countInBeat: 0
		)
		.frame(height: 200)
	}
	.padding()
	.background(Color(hex: "0D0D1A"))
}

