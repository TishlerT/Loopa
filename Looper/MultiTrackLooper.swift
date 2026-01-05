import Foundation
import QuartzCore

/// Multi-track looper with bar-based recording
final class MultiTrackLooper: ObservableObject {
	
	// MARK: - Published State
	
	@Published private(set) var tracks: [Track] = []
	@Published private(set) var isRecording = false
	@Published private(set) var isPlaying = false
	@Published var barCount: BarCount = .four
	@Published var bpm: Double = 100 {
		didSet { recalculateLoopLength() }
	}
	
	// MARK: - Loop Timing
	
	/// Total loop length in seconds (calculated from bars and BPM)
	private(set) var loopLength: Double = 0
	
	/// Recording loop length in beats (based on barCount setting)
	var recordingLoopLengthBeats: Double {
		Double(barCount.rawValue) * 4.0
	}
	
	/// Effective loop length in beats (longest track's recorded length, or barCount if no tracks)
	var loopLengthBeats: Double {
		if tracks.isEmpty {
			return recordingLoopLengthBeats
		}
		return tracks.map { $0.recordedLengthBeats }.max() ?? recordingLoopLengthBeats
	}
	
	/// Current playback position (0 to loopLength)
	@Published private(set) var currentPosition: Double = 0
	
	/// Current beat within the loop (for UI)
	@Published private(set) var currentBeat: Int = 0
	
	/// Recording progress (0.0 to 1.0) - fills based on barCount, not global loop
	@Published private(set) var recordingProgress: Double = 0
	
	// MARK: - Recording State
	
	private var recordingEvents: [MidiEvent] = []
	private var recordStartTime: TimeInterval = 0
	private var recordingInstrument: Instrument = .piano
	
	/// Track ID to punch into (when recording from non-zero position with same instrument)
	private var punchInTrackId: UUID? = nil
	
	/// Position where punch-in recording started (notes before this are preserved)
	private var punchInPosition: Double = 0
	
	// MARK: - Quantization
	
	/// Quantizer for snapping MIDI events to the beat grid
	var quantizer: Quantizer?
	
	// MARK: - Playback State
	
	private var playStartTime: TimeInterval = 0
	private var timer: DispatchSourceTimer?
	private var lastTickPosition: Double = 0
	private var currentLoopCycle: Int = 0
	private var dispatchedThisCycle: Set<String> = []
	
	/// Position saved when pausing (for resume functionality)
	private var pausedPosition: Double = 0
	
	/// Whether playback was paused (vs stopped)
	@Published private(set) var isPaused: Bool = false
	
	/// Total elapsed playback time since start (doesn't wrap around like position)
	var playbackElapsedTime: TimeInterval {
		guard isPlaying else { return 0 }
		return CACurrentMediaTime() - playStartTime
	}
	
	/// Current playback position calculated identically to tick() for UI synchronization
	/// This is the single source of truth for both audio dispatch and visual display
	var synchronizedPlaybackPosition: Double {
		guard isPlaying, loopLength > 0 else {
			// When paused, return the paused position
			if isPaused { return pausedPosition }
			return 0
		}
		let now = CACurrentMediaTime()
		let elapsed = now - playStartTime
		return fmod(elapsed, loopLength)
	}
	
	/// Current playback fraction (0.0 to 1.0) for UI display
	/// Calculated identically to tick() to ensure audio-visual sync
	var synchronizedPlaybackFraction: Double {
		guard loopLength > 0 else { return 0 }
		return synchronizedPlaybackPosition / loopLength
	}
	
	/// Currently active notes (for note-off tracking)
	private var activeNotes: [String: (note: MidiNote, track: Track)] = [:]
	
	// MARK: - Solo/Mute
	
	/// Whether any track has solo enabled
	var anyTrackSoloed: Bool {
		tracks.contains { $0.isSolo }
	}
	
	// MARK: - Callbacks
	
	/// Called when a MIDI event should be played
	var onPlayEvent: ((MidiEvent, Track) -> Void)?
	
	/// Called on each beat (for metronome/UI)
	var onBeat: ((Int, Bool) -> Void)? // (beatNumber, isDownbeat)
	
	/// Called when recording auto-stops at loop wrap (so ViewModel can pause)
	var onRecordingAutoStop: (() -> Void)?
	
	// MARK: - Initialization
	
	init() {
		recalculateLoopLength()
	}
	
	// MARK: - Loop Length
	
	private func recalculateLoopLength() {
		let secondsPerBeat = 60.0 / bpm
		// Use effective loop length (based on longest track, or barCount if no tracks)
		loopLength = loopLengthBeats * secondsPerBeat
	}
	
	func setBarCount(_ count: BarCount) {
		barCount = count
		recalculateLoopLength()
	}
	
	// MARK: - Recording
	
	/// Start recording from a specific position
	/// - Parameters:
	///   - instrument: The instrument to record
	///   - fromPosition: Position to start from (nil = start from 0, resetting playback)
	func startRecording(instrument: Instrument, fromPosition: Double? = nil) {
		guard !isRecording else { return }
		
		recordingEvents.removeAll()
		recordingInstrument = instrument
		recordStartTime = CACurrentMediaTime()
		isRecording = true
		
		// Determine start position
		let startPos = fromPosition ?? 0
		punchInPosition = startPos
		punchInTrackId = nil
		
		// If starting from non-zero, check for existing track to punch into
		if startPos > 0 {
			if let existingTrack = tracks.last(where: { $0.instrumentName == instrument.rawValue && !$0.isVocal }) {
				punchInTrackId = existingTrack.id
			}
		}
		
		// If not already playing, start playback
		if !isPlaying {
			if startPos > 0 {
				// Resume from the specified position
				pausedPosition = startPos
				isPaused = true
				resumePlayback()
			} else {
				startPlayback()
			}
		}
	}
	
	func addLiveEvent(note: UInt8, velocity: UInt8, isNoteOn: Bool) {
		guard isRecording else { return }
		
		let now = CACurrentMediaTime()
		let elapsed = now - playStartTime
		let time = fmod(elapsed, loopLength)
		
		let event = MidiEvent(
			time: time,
			note: note,
			velocity: velocity,
			isNoteOn: isNoteOn,
			isLeft: false // Not used in new architecture
		)
		recordingEvents.append(event)
	}
	
	func stopRecording() {
		guard isRecording else { return }
		isRecording = false
		
		// Create track from recorded events
		if !recordingEvents.isEmpty {
			// Apply quantization to events if enabled
			var finalEvents = recordingEvents
			if let quantizer = quantizer {
				finalEvents = quantizer.quantize(events: recordingEvents, loopLength: loopLength)
				finalEvents.sort { $0.time < $1.time }
			}
			
			// Convert events to notes (pair note-on/off)
			var notes = MidiNote.fromEvents(finalEvents, bpm: bpm, loopLengthBeats: loopLengthBeats)
			
			// ALWAYS quantize drums to 16th notes for step sequencer visibility
			// This ensures every drum hit snaps to a visible grid cell, even if global quantize is off
			if recordingInstrument.isDrumKit {
				let drumQuantizer = Quantizer(bpm: bpm, division: .sixteenth)
				notes = drumQuantizer.quantize(notes: notes, loopLengthBeats: loopLengthBeats)
			}
			
			// Check if we're punching into an existing track
			if let punchTrackId = punchInTrackId,
			   let trackIndex = tracks.firstIndex(where: { $0.id == punchTrackId }) {
				// Punch-in: remove notes that start at or after punch-in position, then add new notes
				let punchInBeat = punchInPosition / (60.0 / bpm)
				var existingNotes = tracks[trackIndex].notes
				existingNotes.removeAll { $0.startBeat >= punchInBeat }
				existingNotes.append(contentsOf: notes)
				existingNotes.sort { $0.startBeat < $1.startBeat }
				tracks[trackIndex].notes = existingNotes
			} else {
				// Normal recording: create new track with its recorded length (based on barCount setting)
				let track = Track(
					instrumentName: recordingInstrument.rawValue,
					instrumentProgram: recordingInstrument.programNumber,
					isDrumKit: recordingInstrument.isDrumKit,
					notes: notes,
					recordedLengthBeats: recordingLoopLengthBeats,  // Use the barCount-based length, not global loop length
					isLooping: true  // Default to looping enabled
				)
				tracks.append(track)
			}
		}
		
		recordingEvents.removeAll()
		punchInTrackId = nil
		punchInPosition = 0
		recordingProgress = 0  // Reset progress for next recording
	}
	
	// MARK: - Playback
	
	func startPlayback() {
		guard !isPlaying else { return }
		
		recalculateLoopLength()
		guard loopLength > 0 else { return }
		
		isPlaying = true
		isPaused = false
		pausedPosition = 0
		playStartTime = CACurrentMediaTime()
		resetPlaybackState()
		scheduleTimer()
	}
	
	func stopPlayback() {
		isPlaying = false
		isRecording = false
		isPaused = false
		timer?.cancel()
		timer = nil
		
		// Send noteOff for any notes that might still be playing
		sendAllNotesOff()
		
		resetPlaybackState()
		pausedPosition = 0
	}
	
	/// Pause playback, preserving the current position for later resume
	func pausePlayback() {
		guard isPlaying else { return }
		
		// Save current position before stopping
		pausedPosition = currentPosition
		isPaused = true
		isPlaying = false
		timer?.cancel()
		timer = nil
		
		// Send noteOff for any notes that might still be playing
		sendAllNotesOff()
	}
	
	/// Resume playback from where it was paused
	func resumePlayback() {
		guard isPaused, loopLength > 0 else {
			// If not paused, just start from beginning
			startPlayback()
			return
		}
		
		isPlaying = true
		isPaused = false
		
		// Calculate playStartTime so that current position matches pausedPosition
		playStartTime = CACurrentMediaTime() - pausedPosition
		
		// Reset dispatch tracking but preserve position-related state
		lastTickPosition = pausedPosition
		currentLoopCycle = 0
		dispatchedThisCycle.removeAll()
		activeNotes.removeAll()
		
		// Calculate current beat from paused position
		let secondsPerBeat = 60.0 / bpm
		currentBeat = Int(pausedPosition / secondsPerBeat)
		
		scheduleTimer()
	}
	
	func togglePlayback() {
		if isPlaying {
			stopPlayback()
		} else {
			startPlayback()
		}
	}
	
	/// Seek to a specific position in the loop
	func seekTo(position: Double) {
		let clampedPosition = max(0, min(position, loopLength))
		
		// Send noteOff for all notes to prevent stuck notes
		sendAllNotesOff()
		
		// Update position
		currentPosition = clampedPosition
		pausedPosition = clampedPosition
		
		// Recalculate beat
		let secondsPerBeat = 60.0 / bpm
		currentBeat = Int(clampedPosition / secondsPerBeat)
		
		// Reset dispatch tracking
		dispatchedThisCycle.removeAll()
		activeNotes.removeAll()
		lastTickPosition = clampedPosition
		
		// If playing, adjust playStartTime so elapsed calculation is correct
		if isPlaying {
			playStartTime = CACurrentMediaTime() - clampedPosition
		}
	}
	
	/// Send noteOff for all notes that might be playing (prevents stuck notes)
	private func sendAllNotesOff() {
		for (_, activeNote) in activeNotes {
			let noteOff = MidiEvent(
				time: 0,
				note: activeNote.note.pitch,
				velocity: 0,
				isNoteOn: false,
				isLeft: false
			)
			onPlayEvent?(noteOff, activeNote.track)
		}
		activeNotes.removeAll()
		
		// Also send note-off for all notes in all tracks (safety)
		for track in tracks {
			for note in track.notes {
				let noteOff = MidiEvent(
					time: 0,
					note: note.pitch,
					velocity: 0,
					isNoteOn: false,
					isLeft: false
				)
				onPlayEvent?(noteOff, track)
			}
		}
	}
	
	// MARK: - Track Management
	
	func deleteTrack(_ track: Track) {
		tracks.removeAll { $0.id == track.id }
	}
	
	func toggleMute(_ track: Track) {
		if let index = tracks.firstIndex(where: { $0.id == track.id }) {
			tracks[index].isMuted.toggle()
		}
	}
	
	func toggleSolo(_ track: Track) {
		if let index = tracks.firstIndex(where: { $0.id == track.id }) {
			tracks[index].isSolo.toggle()
		}
	}
	
	func toggleLoop(_ track: Track) {
		if let index = tracks.firstIndex(where: { $0.id == track.id }) {
			tracks[index].isLooping.toggle()
		}
	}
	
	func setTrackSolo(_ trackId: UUID, solo: Bool) {
		if let index = tracks.firstIndex(where: { $0.id == trackId }) {
			tracks[index].isSolo = solo
		}
	}
	
	func clearAllTracks() {
		stopPlayback()
		tracks.removeAll()
	}
	
	func undoLastTrack() {
		guard !tracks.isEmpty else { return }
		tracks.removeLast()
	}
	
	func setTrackVolume(_ trackId: UUID, volume: Float) {
		if let index = tracks.firstIndex(where: { $0.id == trackId }) {
			tracks[index].volume = max(0, min(1, volume))
		}
	}
	
	func setTrackInstrument(_ trackId: UUID, instrument: Instrument) {
		if let index = tracks.firstIndex(where: { $0.id == trackId }) {
			tracks[index].instrumentName = instrument.rawValue
			tracks[index].instrumentProgram = instrument.programNumber
		}
	}
	
	func loadTracks(_ newTracks: [Track]) {
		tracks = newTracks
	}
	
	func addAudioTrack(_ track: Track) {
		tracks.append(track)
	}
	
	/// Update a specific track (for note editing)
	func updateTrack(_ track: Track) {
		if let index = tracks.firstIndex(where: { $0.id == track.id }) {
			tracks[index] = track
		}
	}
	
	/// Get a track by ID
	func track(withId id: UUID) -> Track? {
		tracks.first { $0.id == id }
	}
	
	/// Quantize all notes in a track
	func quantizeTrack(_ trackId: UUID, division: QuantizeDivision) {
		guard let index = tracks.firstIndex(where: { $0.id == trackId }) else { return }
		
		let quantizer = Quantizer(bpm: bpm, division: division)
		tracks[index].notes = quantizer.quantize(notes: tracks[index].notes, loopLengthBeats: loopLengthBeats)
	}
	
	// MARK: - Private Playback
	
	private func resetPlaybackState() {
		lastTickPosition = 0
		currentLoopCycle = 0
		currentPosition = 0
		currentBeat = 0
		dispatchedThisCycle.removeAll()
		activeNotes.removeAll()
	}
	
	private func scheduleTimer() {
		timer?.cancel()
		let source = DispatchSource.makeTimerSource(queue: .global(qos: .userInteractive))
		source.schedule(deadline: .now(), repeating: 0.002, leeway: .microseconds(500))
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
		
		// Convert position to beats
		let secondsPerBeat = 60.0 / bpm
		let currentBeatPos = currentPos / secondsPerBeat
		let lastBeatPos = lastTickPosition / secondsPerBeat
		
		// Update position synchronously so UI playhead stays in sync with audio
		currentPosition = currentPos
		
		// Calculate current beat
		let newBeat = Int(currentBeatPos)
		
		// Detect beat change
		if newBeat != currentBeat {
			let isDownbeat = (newBeat % 4) == 0
			DispatchQueue.main.async { [weak self] in
				self?.currentBeat = newBeat
				self?.onBeat?(newBeat, isDownbeat)
			}
		}
		
		// Detect loop wrap-around (for playback of existing tracks)
		if newCycle > currentLoopCycle {
			currentLoopCycle = newCycle
			dispatchedThisCycle.removeAll()
			activeNotes.removeAll()
			lastTickPosition = 0
		}
		
		// Auto-stop recording based on RECORDING loop length (barCount), not global loop length
		// This ensures 1-bar recording stops after 1 bar, even if existing tracks are longer
		if isRecording {
			let recordingElapsed = now - recordStartTime
			let recordingLoopSeconds = recordingLoopLengthBeats * secondsPerBeat
			
			// Update recording progress (0.0 to 1.0) for UI
			let progress = min(1.0, recordingElapsed / recordingLoopSeconds)
			if progress != recordingProgress {
				recordingProgress = progress
			}
			
			if recordingElapsed >= recordingLoopSeconds {
				DispatchQueue.main.async { [weak self] in
					self?.stopRecording()
					self?.onRecordingAutoStop?()
				}
			}
		}
		
		// Check for solo state
		let soloActive = anyTrackSoloed
		
		// Dispatch note-ons and note-offs from all audible tracks
		for track in tracks {
			// Check audibility using solo/mute logic
			let isAudible = track.isAudible(anyTrackSoloed: soloActive)
			
			// Skip audio tracks (handled separately)
			guard !track.isVocal else { continue }
			
			// Calculate this track's position within its own loop cycle
			let trackLength = track.recordedLengthBeats
			guard trackLength > 0 else { continue }
			
			// Which cycle of this track are we in?
			let trackCycle = Int(currentBeatPos / trackLength)
			
			// If track doesn't loop and we're past the first cycle, skip it
			if !track.isLooping && trackCycle > 0 {
				continue
			}
			
			// Position within this track's loop
			let trackBeatPos = currentBeatPos.truncatingRemainder(dividingBy: trackLength)
			let trackLastBeatPos = lastBeatPos.truncatingRemainder(dividingBy: trackLength)
			
			// Handle wrap-around within this track's loop
			let didTrackWrap = trackBeatPos < trackLastBeatPos
			
			for note in track.notes {
				// Include track cycle in key to allow notes to play multiple times per global cycle
				let noteKey = "\(track.id)-\(note.id)-c\(trackCycle)"
				
				// Check for note-on
				let shouldTriggerOn: Bool
				if didTrackWrap {
					// Track wrapped around - check if note is in first part OR if we passed it before wrap
					shouldTriggerOn = (note.startBeat >= 0 && note.startBeat < trackBeatPos) ||
									  (note.startBeat >= trackLastBeatPos && note.startBeat < trackLength)
				} else {
					shouldTriggerOn = note.startBeat >= trackLastBeatPos && note.startBeat < trackBeatPos
				}
				
				if shouldTriggerOn {
					if !dispatchedThisCycle.contains(noteKey + "-on") && isAudible {
						dispatchedThisCycle.insert(noteKey + "-on")
						
						let noteOnEvent = MidiEvent(
							time: note.startBeat * secondsPerBeat,
							note: note.pitch,
							velocity: note.velocity,
							isNoteOn: true,
							isLeft: false
						)
						activeNotes[noteKey] = (note: note, track: track)
						onPlayEvent?(noteOnEvent, track)
					}
				}
				
				// Check for note-off
				let shouldTriggerOff: Bool
				if didTrackWrap {
					shouldTriggerOff = (note.endBeat >= 0 && note.endBeat < trackBeatPos) ||
									   (note.endBeat >= trackLastBeatPos && note.endBeat < trackLength)
				} else {
					shouldTriggerOff = note.endBeat >= trackLastBeatPos && note.endBeat < trackBeatPos
				}
				
				if shouldTriggerOff {
					if !dispatchedThisCycle.contains(noteKey + "-off") {
						dispatchedThisCycle.insert(noteKey + "-off")
						activeNotes.removeValue(forKey: noteKey)
						
						// Send note-off even if track became inaudible (to prevent stuck notes)
						let noteOffEvent = MidiEvent(
							time: note.endBeat * secondsPerBeat,
							note: note.pitch,
							velocity: 0,
							isNoteOn: false,
							isLeft: false
						)
						onPlayEvent?(noteOffEvent, track)
					}
				}
			}
		}
		
		lastTickPosition = currentPos
	}
}
