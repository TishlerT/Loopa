import UIKit
import CoreHaptics

/// Manages haptic feedback throughout the app
final class HapticManager {
	
	static let shared = HapticManager()
	
	private var engine: CHHapticEngine?
	private var supportsHaptics: Bool = false
	
	// MARK: - Initialization
	
	private init() {
		setupHapticEngine()
	}
	
	private func setupHapticEngine() {
		guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
			supportsHaptics = false
			return
		}
		
		supportsHaptics = true
		
		do {
			engine = try CHHapticEngine()
			engine?.playsHapticsOnly = true
			
			// Handle engine reset
			engine?.resetHandler = { [weak self] in
				do {
					try self?.engine?.start()
				} catch {
					print("Haptic engine reset failed: \(error)")
				}
			}
			
			// Start engine
			try engine?.start()
		} catch {
			print("Haptic engine creation failed: \(error)")
			supportsHaptics = false
		}
	}
	
	// MARK: - Key Press Haptics
	
	/// Light haptic for key press
	func keyPressed(velocity: Double = 0.5) {
		guard supportsHaptics else {
			// Fallback to UIKit haptics
			let generator = UIImpactFeedbackGenerator(style: .light)
			generator.impactOccurred(intensity: velocity)
			return
		}
		
		playHaptic(intensity: Float(0.4 + (velocity * 0.3)), sharpness: 0.7)
	}
	
	/// Softer haptic for key release (optional)
	func keyReleased() {
		guard supportsHaptics else { return }
		playHaptic(intensity: 0.15, sharpness: 0.3)
	}
	
	// MARK: - Metronome Haptics
	
	/// Medium haptic for downbeat
	func metronomeDownbeat() {
		guard supportsHaptics else {
			let generator = UIImpactFeedbackGenerator(style: .medium)
			generator.impactOccurred()
			return
		}
		
		playHaptic(intensity: 0.8, sharpness: 0.9)
	}
	
	/// Soft haptic for regular beats
	func metronomeBeat() {
		guard supportsHaptics else {
			let generator = UIImpactFeedbackGenerator(style: .light)
			generator.impactOccurred(intensity: 0.5)
			return
		}
		
		playHaptic(intensity: 0.3, sharpness: 0.5)
	}
	
	// MARK: - Action Haptics
	
	/// Success haptic for completing actions (loop set, etc.)
	func success() {
		let generator = UINotificationFeedbackGenerator()
		generator.notificationOccurred(.success)
	}
	
	/// Warning haptic
	func warning() {
		let generator = UINotificationFeedbackGenerator()
		generator.notificationOccurred(.warning)
	}
	
	/// Error haptic
	func error() {
		let generator = UINotificationFeedbackGenerator()
		generator.notificationOccurred(.error)
	}
	
	/// Selection changed haptic
	func selectionChanged() {
		let generator = UISelectionFeedbackGenerator()
		generator.selectionChanged()
	}
	
	// MARK: - Recording Haptics
	
	/// Haptic pulse when recording starts
	func recordingStarted() {
		playHapticPattern([
			(intensity: 0.6, sharpness: 0.8, time: 0),
			(intensity: 0.4, sharpness: 0.6, time: 0.1)
		])
	}
	
	/// Haptic pulse when loop is set
	func loopSet() {
		playHapticPattern([
			(intensity: 0.7, sharpness: 0.9, time: 0),
			(intensity: 0.5, sharpness: 0.7, time: 0.08),
			(intensity: 0.3, sharpness: 0.5, time: 0.16)
		])
	}
	
	// MARK: - Private Helpers
	
	private func playHaptic(intensity: Float, sharpness: Float) {
		guard supportsHaptics, let engine = engine else { return }
		
		let event = CHHapticEvent(
			eventType: .hapticTransient,
			parameters: [
				CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
				CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
			],
			relativeTime: 0
		)
		
		do {
			let pattern = try CHHapticPattern(events: [event], parameters: [])
			let player = try engine.makePlayer(with: pattern)
			try player.start(atTime: CHHapticTimeImmediate)
		} catch {
			print("Haptic playback failed: \(error)")
		}
	}
	
	private func playHapticPattern(_ events: [(intensity: Float, sharpness: Float, time: TimeInterval)]) {
		guard supportsHaptics, let engine = engine else {
			success() // Fallback
			return
		}
		
		let hapticEvents = events.map { event in
			CHHapticEvent(
				eventType: .hapticTransient,
				parameters: [
					CHHapticEventParameter(parameterID: .hapticIntensity, value: event.intensity),
					CHHapticEventParameter(parameterID: .hapticSharpness, value: event.sharpness)
				],
				relativeTime: event.time
			)
		}
		
		do {
			let pattern = try CHHapticPattern(events: hapticEvents, parameters: [])
			let player = try engine.makePlayer(with: pattern)
			try player.start(atTime: CHHapticTimeImmediate)
		} catch {
			print("Haptic pattern playback failed: \(error)")
		}
	}
}

