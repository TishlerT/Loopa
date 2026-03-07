import Foundation
import QuartzCore

/// MIDI loop recorder and player with precise timing and undo support
final class MidiLooper {
	private(set) var isRecording = false
	private(set) var isPlaying = false
	private(set) var isOverdubbing = false
	private(set) var loopLength: Double = 0 // seconds
	
	// Events storage - internal access for testing
	private(set) var events: [MidiEvent] = []
	
	private var playStartTime: TimeInterval = 0
	private var recordStartTime: TimeInterval = 0
	private var timer: DispatchSourceTimer?
	
	// Timing: track the last position we processed to avoid double-firing
	// and correctly handle loop wrap-around
	private var lastTickPosition: Double = 0
	private var currentLoopCycle: Int = 0
	private var dispatchedThisCycle: Set<String> = []
	
	// Quantization
	var quantizer: Quantizer?
	
	// Undo support: track layers of overdubs
	private var overdubLayers: [[MidiEvent]] = [] // Stack of overdub layers
	private var currentOverdubEvents: [MidiEvent] = [] // Events being recorded in current overdub
	
	/// Number of undo steps available
	var undoCount: Int { overdubLayers.count }
	
	/// Whether undo is available
	var canUndo: Bool { !overdubLayers.isEmpty }
	
	var onDispatch: ((MidiEvent) -> Void)?
	
	// MARK: - Public API
	
	func clear() {
		stop()
		events.removeAll()
		overdubLayers.removeAll()
		currentOverdubEvents.removeAll()
		loopLength = 0
		resetPlaybackState()
	}
	
	func startRecording() {
		isRecording = true
		isPlaying = false
		isOverdubbing = false
		events.removeAll()
		overdubLayers.removeAll()
		currentOverdubEvents.removeAll()
		recordStartTime = CACurrentMediaTime()
		resetPlaybackState()
	}
	
	/// Current elapsed time since recording started, or 0 if not recording
	func currentRecordingElapsed() -> Double {
		guard isRecording else { return 0 }
		return CACurrentMediaTime() - recordStartTime
	}
	
	func finalizeLoop(lengthSeconds: Double) {
		isRecording = false
		loopLength = max(0.1, lengthSeconds)
		
		// Normalize all event times to be within loop bounds
		events = events.map { event in
			let normalizedTime = min(event.time, loopLength)
			return MidiEvent(
				time: normalizedTime,
				note: event.note,
				velocity: event.velocity,
				isNoteOn: event.isNoteOn,
				isLeft: event.isLeft
			)
		}
		
		// Apply quantization if enabled
		if let quantizer = quantizer {
			events = quantizer.quantize(events: events, loopLength: loopLength)
		}
		
		// Sort events by time for efficient playback
		events.sort { $0.time < $1.time }
		
		startPlayback()
	}
	
	func startPlayback() {
		guard loopLength > 0 else { return }
		isPlaying = true
		isOverdubbing = false
		playStartTime = CACurrentMediaTime()
		resetPlaybackState()
		scheduleTimer()
	}
	
	func startOverdub() {
		guard loopLength > 0 else { return }
		isOverdubbing = true
		isPlaying = true
		currentOverdubEvents.removeAll() // Start fresh for this overdub pass
		if timer == nil {
			playStartTime = CACurrentMediaTime()
			resetPlaybackState()
			scheduleTimer()
		}
	}
	
	/// Stop overdubbing and finalize the current overdub layer
	func stopOverdub() {
		guard isOverdubbing else { return }
		isOverdubbing = false
		
		// If we recorded any events in this overdub, save them as a layer
		if !currentOverdubEvents.isEmpty {
			// Apply quantization to overdub events
			var layerEvents = currentOverdubEvents
			if let quantizer = quantizer {
				layerEvents = quantizer.quantize(events: layerEvents, loopLength: loopLength)
			}
			overdubLayers.append(layerEvents)
			currentOverdubEvents.removeAll()
		}
	}
	
	func stop() {
		// If we were overdubbing, finalize the layer first
		if isOverdubbing {
			stopOverdub()
		}
		
		isRecording = false
		isPlaying = false
		isOverdubbing = false
		timer?.cancel()
		timer = nil
		resetPlaybackState()
	}
	
	/// Undo the last overdub layer
	func undo() {
		guard !overdubLayers.isEmpty else { return }
		
		// Remove the last layer
		let removedLayer = overdubLayers.removeLast()
		
		// Remove those events from the main event list
		let removedIds = Set(removedLayer.map { $0.id })
		events.removeAll { removedIds.contains($0.id) }
	}
	
	/// Redo is not supported in this simple implementation
	/// (would require storing removed layers)
	
	func addLiveEvent(note: UInt8, velocity: UInt8, isNoteOn: Bool, isLeft: Bool) {
		let now = CACurrentMediaTime()
		if isRecording {
			let t = now - recordStartTime
			events.append(MidiEvent(time: t, note: note, velocity: velocity, isNoteOn: isNoteOn, isLeft: isLeft))
		} else if isOverdubbing, loopLength > 0 {
			let t = fmod(now - playStartTime, loopLength)
			let event = MidiEvent(time: t, note: note, velocity: velocity, isNoteOn: isNoteOn, isLeft: isLeft)
			
			// Add to both current overdub layer tracking AND main events list
			currentOverdubEvents.append(event)
			events.append(event)
			
			// Re-sort after adding overdub event
			events.sort { $0.time < $1.time }
		}
	}
	
	// MARK: - Private
	
	private func resetPlaybackState() {
		lastTickPosition = 0
		currentLoopCycle = 0
		dispatchedThisCycle.removeAll()
	}
	
	private func scheduleTimer() {
		timer?.cancel()
		let source = DispatchSource.makeTimerSource(queue: .global(qos: .userInteractive))
		// Use 2ms interval for tighter timing
		let interval = 0.002
		source.schedule(deadline: .now(), repeating: interval, leeway: .microseconds(500))
		source.setEventHandler { [weak self] in self?.tick() }
		source.resume()
		timer = source
	}
	
	private func tick() {
		guard isPlaying, loopLength > 0 else { return }
		
		let now = CACurrentMediaTime()
		let elapsed = now - playStartTime
		let currentPos = fmod(elapsed, loopLength)
		let newCycle = Int(elapsed / loopLength)
		
		// Detect loop wrap-around
		if newCycle > currentLoopCycle {
			currentLoopCycle = newCycle
			dispatchedThisCycle.removeAll()
			lastTickPosition = 0
		}
		
		// Find events that should fire between lastTickPosition and currentPos
		let eventsToDispatch: [MidiEvent]
		
		if currentPos >= lastTickPosition {
			// Normal case: no wrap within this tick
			eventsToDispatch = events.filter { event in
				event.time >= lastTickPosition &&
				event.time < currentPos &&
				!dispatchedThisCycle.contains(event.id)
			}
		} else {
			// Wrap-around case (shouldn't happen often with cycle tracking, but handle it)
			eventsToDispatch = events.filter { event in
				(event.time >= lastTickPosition || event.time < currentPos) &&
				!dispatchedThisCycle.contains(event.id)
			}
		}
		
		// Dispatch events in time order
		for event in eventsToDispatch.sorted(by: { $0.time < $1.time }) {
			dispatchedThisCycle.insert(event.id)
			onDispatch?(event)
		}
		
		lastTickPosition = currentPos
	}
}
