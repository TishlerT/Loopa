import Foundation
import QuartzCore

/// A precise metronome using high-priority timer scheduling.
/// Fires beat callbacks at the specified BPM with downbeat detection.
final class Metronome {
	
	// MARK: - Configuration
	
	/// Beats per minute (40-300 range recommended)
	var bpm: Double = 120 {
		didSet {
			if isRunning {
				// Restart timer with new interval
				stop()
				start()
			}
		}
	}
	
	/// Number of beats per bar (for downbeat detection)
	var beatsPerBar: Int = 4
	
	// MARK: - Callbacks
	
	/// Called on each beat with the current beat number (0-indexed within the bar)
	var onBeat: ((Int) -> Void)?
	
	// MARK: - State
	
	private(set) var isRunning = false
	private var timer: DispatchSourceTimer?
	private var currentBeat: Int = 0
	private var startTime: TimeInterval = 0
	
	// MARK: - Computed Properties
	
	/// Seconds per beat based on current BPM
	var secondsPerBeat: Double {
		60.0 / bpm
	}
	
	// MARK: - Control
	
	/// Start the metronome. First beat fires immediately.
	func start() {
		guard !isRunning else { return }
		isRunning = true
		currentBeat = 0
		startTime = CACurrentMediaTime()
		
		// Fire first beat immediately
		onBeat?(currentBeat)
		currentBeat = 1
		
		// Schedule subsequent beats
		scheduleTimer()
	}
	
	/// Stop the metronome.
	func stop() {
		isRunning = false
		timer?.cancel()
		timer = nil
		currentBeat = 0
	}
	
	// MARK: - Private
	
	private func scheduleTimer() {
		timer?.cancel()
		
		let source = DispatchSource.makeTimerSource(queue: .global(qos: .userInteractive))
		let interval = secondsPerBeat
		
		// Schedule repeating timer
		source.schedule(
			deadline: .now() + interval,
			repeating: interval,
			leeway: .milliseconds(1)
		)
		
		source.setEventHandler { [weak self] in
			self?.tick()
		}
		
		source.resume()
		timer = source
	}
	
	private func tick() {
		guard isRunning else { return }
		
		// Calculate which beat we should be on based on elapsed time
		// This drift-corrects in case of timing jitter
		let elapsed = CACurrentMediaTime() - startTime
		let expectedBeat = Int(elapsed / secondsPerBeat)
		
		// Only fire if we haven't already fired this beat
		if expectedBeat >= currentBeat {
			let beatInBar = currentBeat % beatsPerBar
			onBeat?(beatInBar)
			currentBeat = expectedBeat + 1
		}
	}
}

