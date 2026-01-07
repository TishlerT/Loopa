import SwiftUI
import Combine
import QuartzCore
import Foundation

/// ViewModel for the multi-track looper
@MainActor
final class LooperViewModel: ObservableObject {
	
	// MARK: - Published State
	
	@Published var currentInstrument: Instrument = .piano
	@Published var barCount: BarCount = .four
	@Published var bpm: Double = 100 {
		didSet {
			looper.bpm = bpm
		}
	}
	@Published var isMetronomeOn: Bool = false
	@Published var audioError: String? = nil
	@Published var quantizeDivision: QuantizeDivision = .off {
		didSet { updateQuantizer() }
	}
	
	// MARK: - Pause State
	
	/// Whether playback is paused (vs stopped)
	@Published private(set) var isPaused = false
	
	// MARK: - Count-In State
	
	/// Whether we're counting in before recording
	@Published private(set) var isCountingIn = false
	
	/// Current count-in beat (4, 3, 2, 1) - displays to user
	@Published private(set) var countInBeat: Int = 0
	
	/// Number of beats for count-in
	let countInBeats: Int = 4
	
	/// Timer for count-in
	private var countInTimer: Timer?
	
	// MARK: - Looper State (forwarded)
	
	@Published private(set) var tracks: [Track] = []
	@Published private(set) var isRecording = false
	@Published private(set) var isPlaying = false
	@Published private(set) var currentPosition: Double = 0
	@Published private(set) var currentBeat: Int = 0
	@Published private(set) var recordingProgress: Double = 0  // 0.0 to 1.0 during recording
	
	// MARK: - DisplayLink for Audio-Visual Sync
	
	/// DisplayLink wrapper for screen-synced UI updates
	private var displayLink: CADisplayLink?
	
	/// Synchronized playback position read directly from looper (bypasses Combine latency)
	/// This is the single source of truth for UI display - use this instead of currentPosition for visuals
	var synchronizedPosition: Double {
		looper.synchronizedPlaybackPosition
	}
	
	/// Synchronized playback fraction (0.0 to 1.0) for progress bar display
	/// Uses same calculation as audio dispatch to guarantee sync
	var synchronizedProgressFraction: Double {
		guard looper.loopLength > 0 else { return 0 }
		
		// During recording, use recording progress (fills based on barCount)
		if isRecording {
			return recordingProgress
		}
		
		// Use the synchronized position from the looper
		let position = looper.synchronizedPlaybackPosition
		
		// Wrap to bar cycle for display consistency
		let barCycleBeats = Double(barCount.rawValue) * 4.0
		let secondsPerBeat = 60.0 / bpm
		let barCycleSeconds = barCycleBeats * secondsPerBeat
		
		guard barCycleSeconds > 0 else { return 0 }
		let positionInCycle = position.truncatingRemainder(dividingBy: barCycleSeconds)
		return positionInCycle / barCycleSeconds
	}
	
	/// Synchronized beat number for beat indicator display
	var synchronizedBeat: Int {
		// During recording, derive beat from recordingProgress to stay in sync with progress bar
		// This ensures beat indicator and progress bar use the same timing source (barCount-based)
		if isRecording {
			let totalBeatsInRecording = Double(barCount.rawValue) * 4.0
			return Int(recordingProgress * totalBeatsInRecording)
		}
		
		// During playback, use synchronized position
		let secondsPerBeat = 60.0 / bpm
		guard secondsPerBeat > 0 else { return 0 }
		let position = looper.synchronizedPlaybackPosition
		let rawBeat = Int(position / secondsPerBeat)
		return totalBeats > 0 ? rawBeat % totalBeats : 0
	}
	
	// MARK: - Session State
	
	@Published var savedSessions: [SavedSession] = []
	@Published var currentSessionName: String = ""
	@Published var showingSaveSheet = false
	@Published var showingLoadSheet = false
	@Published var showingSettings = false
	private var currentSessionId: UUID?
	
	// MARK: - Tracks Screen State
	
	@Published var showingTracksSheet = false
	@Published var showingBPMEditor = false
	@Published var selectedTrackForFocus: Track? = nil
	
	// MARK: - Components
	
	let audio = LooperAudioEngine()
	let looper = MultiTrackLooper()
	let vocalRecorder = VocalRecorder()
	
	// MARK: - Vocal Recording State
	
	@Published var isRecordingVocals = false
	@Published var showMicPermissionAlert = false
	@Published var isVocalMode = false
	private var currentVocalFilename: String?
	
	/// Whether the headphone recommendation has been shown this session
	private var hasShownHeadphoneRecommendation = false
	
	/// Controls the headphone recommendation alert
	@Published var showHeadphoneRecommendation = false
	
	// MARK: - Keyboard Config
	
	/// Keyboard range: 2 octaves (25 keys) - easier to play chords
	let keyCount: Int = 25 // 2 octaves + 1
	
	/// Current octave offset (0 = middle, -1 = down, +1 = up)
	@Published var octaveOffset: Int = 0
	
	/// Base starting note (C3 = 48, adjustable by octave)
	var startNote: UInt8 {
		let base: Int = 48 + (octaveOffset * 12)
		return UInt8(max(24, min(84, base))) // Clamp between C1 and C6
	}
	
	/// Current octave name for display (shows the middle octave of the keyboard, which is C4 by default)
	var currentOctaveName: String {
		let octave = 4 + octaveOffset  // Middle of keyboard is C4 (MIDI 60) at offset 0
		return "C\(octave)"
	}
	
	// Drum mapping for drum kit (25 pads)
	private let drumMap: [UInt8] = [
		36, 38, 42, 46, 39,  // Row 1: Kick, Snare, HH Closed, HH Open, Clap
		41, 43, 45, 47, 49,  // Row 2: Low Tom, Mid Tom, Hi Tom, Crash, Ride
		51, 53, 55, 57, 59,  // Row 3: More cymbals/percussion
		60, 62, 64, 65, 67,  // Row 4: Bongos, congas
		68, 69, 70, 71, 72   // Row 5: More percussion
	]
	
	// MARK: - Octave Control
	
	func octaveUp() {
		if octaveOffset < 2 {
			octaveOffset += 1
			HapticManager.shared.selectionChanged()
		}
	}
	
	func octaveDown() {
		if octaveOffset > -2 {
			octaveOffset -= 1
			HapticManager.shared.selectionChanged()
		}
	}
	
	private var cancellables = Set<AnyCancellable>()
	
	/// Track IDs that have already been prepared (to avoid redundant player/sampler creation)
	private var preparedTrackIds = Set<UUID>()
	
	// MARK: - DisplayLink Target (must be non-isolated for CADisplayLink callback)
	
	/// Wrapper object to handle DisplayLink callbacks (CADisplayLink requires @objc target)
	private var displayLinkTarget: DisplayLinkTarget?
	
	// MARK: - Initialization
	
	init() {
		setupAudio()
		setupBindings()
		setupDisplayLink()
	}
	
	deinit {
		displayLink?.invalidate()
	}
	
	private func setupDisplayLink() {
		// Create a target object for DisplayLink callback
		displayLinkTarget = DisplayLinkTarget { [weak self] in
			Task { @MainActor in
				self?.onDisplayLinkTick()
			}
		}
		
		displayLink = CADisplayLink(target: displayLinkTarget!, selector: #selector(DisplayLinkTarget.tick))
		displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
		displayLink?.add(to: .main, forMode: .common)
		displayLink?.isPaused = true // Start paused, activate when playing
	}
	
	/// Called on each display refresh when playing - triggers UI update
	private func onDisplayLinkTick() {
		// Force SwiftUI to re-read synchronizedProgressFraction and synchronizedBeat
		// by publishing a change notification
		objectWillChange.send()
	}
	
	private func startDisplayLink() {
		displayLink?.isPaused = false
	}
	
	private func stopDisplayLink() {
		displayLink?.isPaused = true
	}
	
	private func setupAudio() {
		do {
			try audio.configureSession()
			try audio.loadSoundFont()
			try audio.start()
			try audio.setInstrument(.piano)
			audioError = nil
			print("✅ Audio initialized successfully!")
			
			// Removed test tones - audio should be ready immediately
		} catch {
			audioError = error.localizedDescription
			print("❌ Audio error: \(error)")
		}
	}
	
	private func setupBindings() {
		// Initialize quantizer
		updateQuantizer()
		
		// Forward looper state and prepare samplers/players for NEW tracks only
		// (Avoid re-preparing existing tracks, which would stop vocal playback)
		looper.$tracks
			.receive(on: DispatchQueue.main)
			.sink { [weak self] newTracks in
				guard let self = self else { return }
				self.tracks = newTracks
				
				// Only prepare NEW tracks (ones we haven't seen before)
				for track in newTracks {
					guard !self.preparedTrackIds.contains(track.id) else { continue }
					self.preparedTrackIds.insert(track.id)
					
					if track.isVocal {
						if let filename = track.audioFileName {
							_ = self.vocalRecorder.preparePlayer(for: track.id, filename: filename, volume: track.volume)
						}
					} else if let instrument = Instrument(rawValue: track.instrumentName) {
						self.audio.prepareSampler(for: track.id, instrument: instrument)
					}
				}
				
				// Clean up preparedTrackIds for deleted tracks
				let currentTrackIds = Set(newTracks.map { $0.id })
				self.preparedTrackIds = self.preparedTrackIds.intersection(currentTrackIds)
			}
			.store(in: &cancellables)
		
		looper.$isRecording
			.receive(on: DispatchQueue.main)
			.assign(to: &$isRecording)
		
		looper.$isPlaying
			.receive(on: DispatchQueue.main)
			.sink { [weak self] playing in
				guard let self = self else { return }
				self.isPlaying = playing
				// Start/stop DisplayLink for synchronized UI updates
				if playing {
					self.startDisplayLink()
				} else {
					self.stopDisplayLink()
				}
				// Start/stop vocal playback with loop
				self.handlePlaybackStateChange(isPlaying: playing)
			}
			.store(in: &cancellables)
		
		looper.$currentPosition
			.receive(on: DispatchQueue.main)
			.sink { [weak self] pos in
				guard let self = self else { return }
				self.currentPosition = pos
				
				// Auto-stop vocal recording when allotted bars are complete
				if self.isRecordingVocals {
					self.checkVocalRecordingAutoStop(currentPosition: pos)
				}
			}
			.store(in: &cancellables)
		
		looper.$currentBeat
			.receive(on: DispatchQueue.main)
			.assign(to: &$currentBeat)
		
		looper.$recordingProgress
			.receive(on: DispatchQueue.main)
			.assign(to: &$recordingProgress)
		
		// Handle playback events (on main thread for safety)
		looper.onPlayEvent = { [weak self] event, track in
			DispatchQueue.main.async {
				self?.handlePlaybackEvent(event, track: track)
			}
		}
		
		// Handle beats
		looper.onBeat = { [weak self] beat, isDownbeat in
			DispatchQueue.main.async {
				self?.handleBeat(beat, isDownbeat: isDownbeat)
			}
		}
		
		// Handle recording auto-stop (at loop wrap) - should pause at position 0
		looper.onRecordingAutoStop = { [weak self] in
			guard let self = self else { return }
			self.looper.pausePlayback()
			self.audio.stopAllNotes()
			self.vocalRecorder.stopAll()
			self.isPaused = true
			// Reset to beginning after completing full recording
			// (prevents small offset from tick timing)
			self.looper.seekTo(position: 0)
			HapticManager.shared.loopSet()
		}
		
		// Sync BPM
		looper.bpm = bpm
	}
	
	private func handlePlaybackStateChange(isPlaying: Bool) {
		if isPlaying {
			// Start audible vocal tracks (respecting solo/mute)
			let soloActive = anyTrackSoloed
			for track in tracks where track.isVocal && track.isAudible(anyTrackSoloed: soloActive) {
				vocalRecorder.play(trackId: track.id, at: currentPosition)
			}
		} else {
			// Stop all vocal tracks
			vocalRecorder.stopAll()
		}
	}
	
	// MARK: - Instrument Selection
	
	func selectInstrument(_ instrument: Instrument) {
		// Prevent changing instruments while recording to avoid mixing instruments on one track
		guard !isRecording else { return }
		
		currentInstrument = instrument
		isVocalMode = false // Exit vocal mode when selecting an instrument
		HapticManager.shared.selectionChanged()
		
		do {
			try audio.setInstrument(instrument)
		} catch {
			audioError = error.localizedDescription
		}
	}
	
	func enableVocalMode() {
		guard !isRecording && !isRecordingVocals else { return }
		isVocalMode = true
		HapticManager.shared.selectionChanged()
	}
	
	// MARK: - Loop Controls
	
	func setBarCount(_ count: BarCount) {
		barCount = count
		looper.setBarCount(count)
		HapticManager.shared.selectionChanged()
	}
	
	func startRecording() {
		looper.setBarCount(barCount)
		looper.startRecording(instrument: currentInstrument)
		HapticManager.shared.recordingStarted()
	}
	
	func stopRecording() {
		looper.stopRecording()
		HapticManager.shared.loopSet()
	}
	
	/// Toggle recording with smart resume behavior:
	/// - Always does a count-in before recording starts
	/// - If paused: resume playback after count-in
	/// - If recording: stop recording and pause playback
	/// - If counting in: cancel the count-in
	func toggleRecordingWithResume() {
		if isRecording {
			// Stop recording and pause playback
			looper.stopRecording()
			looper.pausePlayback()
			audio.stopAllNotes()
			vocalRecorder.stopAll()
			isPaused = true
			HapticManager.shared.loopSet()
		} else if isCountingIn {
			// Cancel count-in
			cancelCountIn()
		} else {
			// Start count-in before recording
			startCountIn()
		}
	}
	
	// MARK: - Count-In Logic
	
	/// Position captured when count-in starts (for recording from that position)
	private var countInStartPosition: Double = 0
	
	private func startCountIn() {
		isCountingIn = true
		countInBeat = countInBeats // Start at 4
		
		// Capture current position for recording start (supports punch-in from non-zero position)
		countInStartPosition = currentPosition
		
		// Don't start looper playback during count-in - keep position where it is
		// The count-in clicks are played via audio.clickBeat() independently
		
		// Calculate interval between beats
		let beatInterval = 60.0 / bpm
		
		// Play first count-in beat immediately
		HapticManager.shared.metronomeDownbeat()
		audio.clickBeat(isDownbeat: true)
		
		// Schedule the countdown beats
		scheduleNextCountInBeat(beatInterval: beatInterval)
	}
	
	private func scheduleNextCountInBeat(beatInterval: Double) {
		countInTimer = Timer.scheduledTimer(withTimeInterval: beatInterval, repeats: false) { [weak self] _ in
			DispatchQueue.main.async {
				guard let self = self, self.isCountingIn else { return }
				
				self.countInBeat -= 1
				
				if self.countInBeat > 0 {
					// Still counting - play click and schedule next
					HapticManager.shared.metronomeBeat()
					self.audio.clickBeat(isDownbeat: false)
					self.scheduleNextCountInBeat(beatInterval: beatInterval)
				} else {
					// Count-in complete! Start recording from captured position
					self.countInTimer = nil
					self.isCountingIn = false
					
					// Start recording from the position that was set before count-in
					self.looper.setBarCount(self.barCount)
					self.looper.startRecording(instrument: self.currentInstrument, fromPosition: self.countInStartPosition)
					HapticManager.shared.recordingStarted()
				}
			}
		}
	}
	
	private func cancelCountIn() {
		countInTimer?.invalidate()
		countInTimer = nil
		isCountingIn = false
		countInBeat = 0
		HapticManager.shared.selectionChanged()
	}
	
	/// Toggle vocal recording with smart resume behavior
	func toggleVocalRecordingWithResume() {
		if isRecordingVocals {
			stopVocalRecording()
		} else if isCountingIn {
			// Cancel count-in
			cancelCountIn()
		} else {
			// Show headphone recommendation on first vocal recording this session
			if !hasShownHeadphoneRecommendation {
				hasShownHeadphoneRecommendation = true
				showHeadphoneRecommendation = true
				return  // User will tap "Continue" to proceed
			}
			
			// Start count-in before vocal recording
			startVocalCountIn()
		}
	}
	
	private func startVocalCountIn() {
		isCountingIn = true
		countInBeat = countInBeats
		
		// Capture current position for recording start
		countInStartPosition = currentPosition
		
		// PRE-CONFIGURE audio session for recording DURING count-in (before playback starts)
		// This prevents the audio glitch that occurs when changing session category during playback
		vocalRecorder.prepareSessionForRecording()
		
		// Ensure engine is still running after session change (category change can stop it)
		audio.ensureRunning()
		
		// Don't start looper playback during count-in - keep position where it is
		// The count-in clicks are played via audio.clickBeat() independently
		
		let beatInterval = 60.0 / bpm
		
		// Play first count-in beat
		HapticManager.shared.metronomeDownbeat()
		audio.clickBeat(isDownbeat: true)
		
		// Schedule the countdown beats
		scheduleNextVocalCountInBeat(beatInterval: beatInterval)
	}
	
	private func scheduleNextVocalCountInBeat(beatInterval: Double) {
		countInTimer = Timer.scheduledTimer(withTimeInterval: beatInterval, repeats: false) { [weak self] _ in
			DispatchQueue.main.async {
				guard let self = self, self.isCountingIn else { return }
				
				self.countInBeat -= 1
				
				if self.countInBeat > 0 {
					// Still counting
					HapticManager.shared.metronomeBeat()
					self.audio.clickBeat(isDownbeat: false)
					self.scheduleNextVocalCountInBeat(beatInterval: beatInterval)
				} else {
					// Count-in complete! Start vocal recording from captured position
					self.countInTimer = nil
					self.isCountingIn = false
					// Start playback from captured position for vocal recording
					if self.countInStartPosition > 0 {
						self.looper.seekTo(position: self.countInStartPosition)
						self.looper.resumePlayback()
					} else {
						self.looper.startPlayback()
					}
					self.startVocalRecording()
				}
			}
		}
	}
	
	/// Simple play/pause toggle - pauses preserving position, or resumes from where paused
	/// If recording, also stops the recording
	func togglePlayPause() {
		if isPlaying {
			// If recording, stop recording first
			if isRecording {
				looper.stopRecording()
				HapticManager.shared.loopSet()
			}
			if isRecordingVocals {
				stopVocalRecording()
			}
			// Cancel count-in if active
			if isCountingIn {
				cancelCountIn()
			}
			
			// Pause (preserves position)
			looper.pausePlayback()
			audio.stopAllNotes()
			vocalRecorder.stopAll()
			isPaused = true
		} else if isPaused {
			// Resume from where we paused
			looper.resumePlayback()
			isPaused = false
		} else {
			// Start fresh
			looper.startPlayback()
			isPaused = false
		}
		HapticManager.shared.selectionChanged()
	}
	
	func togglePlayback() {
		looper.togglePlayback()
		isPaused = false
		HapticManager.shared.selectionChanged()
	}
	
	func pausePlayback() {
		if isPlaying {
			looper.pausePlayback()
			audio.stopAllNotes()
			vocalRecorder.stopAll()
			isPaused = true
			HapticManager.shared.selectionChanged()
		}
	}
	
	func restartPlayback() {
		// Remember if we were paused
		let wasPaused = isPaused
		
		// Stop everything
		looper.stopPlayback()
		audio.stopAllNotes()
		vocalRecorder.stopAll()
		
		// If we were paused, stay paused at the beginning
		// Otherwise, start playing from the beginning
		if wasPaused {
			isPaused = true
			// Position is already reset to 0 by stopPlayback
		} else {
			isPaused = false
			// Start fresh from the beginning
			looper.startPlayback()
		}
		HapticManager.shared.selectionChanged()
	}
	
	/// Seek to a specific position in the loop (from tap gesture)
	func seekToPosition(_ position: Double) {
		// Ignore during recording or count-in
		guard !isRecording && !isRecordingVocals && !isCountingIn else { return }
		
		looper.seekTo(position: position)
		
		// Seek vocal players if playing
		if isPlaying {
			for track in tracks where track.isVocal && !track.isMuted {
				vocalRecorder.seek(trackId: track.id, to: position)
			}
		}
		
		HapticManager.shared.selectionChanged()
	}
	
	func resumePlayback() {
		// Resume from paused state
		if isPaused {
			looper.resumePlayback()
			isPaused = false
			HapticManager.shared.selectionChanged()
		}
	}
	
	func stopPlayback() {
		looper.stopPlayback()
		audio.stopAllNotes()
		vocalRecorder.stopAll()
		isPaused = false
	}
	
	func clearAll() {
		looper.clearAllTracks()
		audio.clearAllTrackSamplers()
		audio.stopAllNotes()
		vocalRecorder.stopAll()
		preparedTrackIds.removeAll()
		HapticManager.shared.warning()
	}
	
	func undoLastTrack() {
		if let lastTrack = tracks.last {
			if lastTrack.isVocal {
				vocalRecorder.removePlayer(for: lastTrack.id)
				if let filename = lastTrack.audioFileName {
					vocalRecorder.deleteAudioFile(filename)
				}
			} else {
				audio.removeSampler(for: lastTrack.id)
			}
		}
		looper.undoLastTrack()
		HapticManager.shared.selectionChanged()
	}
	
	func deleteTrack(_ track: Track) {
		if track.isVocal {
			vocalRecorder.removePlayer(for: track.id)
			if let filename = track.audioFileName {
				vocalRecorder.deleteAudioFile(filename)
			}
		} else {
			audio.removeSampler(for: track.id)
		}
		looper.deleteTrack(track)
	}
	
	func toggleMute(_ track: Track) {
		looper.toggleMute(track)
		// Update vocal playback based on new audibility state
		if isPlaying {
			updateVocalPlaybackStates()
		}
	}
	
	func toggleSolo(_ track: Track) {
		looper.toggleSolo(track)
		// Update vocal playback based on new audibility state
		if isPlaying {
			updateVocalPlaybackStates()
		}
		HapticManager.shared.selectionChanged()
	}
	
	func toggleLoop(_ track: Track) {
		looper.toggleLoop(track)
		HapticManager.shared.selectionChanged()
	}
	
	/// Update vocal track playback based on current mute/solo states
	/// Call this after any mute/solo change during playback
	/// Uses looper.tracks directly (not self.tracks) because self.tracks is updated async via Combine
	private func updateVocalPlaybackStates() {
		let soloActive = looper.anyTrackSoloed
		for track in looper.tracks where track.isVocal {
			if track.isAudible(anyTrackSoloed: soloActive) {
				// Track should be playing - start if not already
				vocalRecorder.play(trackId: track.id, at: synchronizedPosition)
			} else {
				// Track should be silent - pause it
				vocalRecorder.pause(trackId: track.id)
			}
		}
	}
	
	func setTrackVolume(_ track: Track, volume: Float) {
		looper.setTrackVolume(track.id, volume: volume)
		// Also update the sampler/player volume for immediate effect
		if track.isVocal {
			vocalRecorder.setVolume(track.id, volume: volume)
		} else if let instrument = Instrument(rawValue: track.instrumentName) {
			audio.setTrackVolume(track.id, volume: volume, instrument: instrument)
		}
	}
	
	func setTrackInstrument(_ track: Track, instrument: Instrument) {
		looper.setTrackInstrument(track.id, instrument: instrument)
		// Update the sampler for this track
		audio.removeSampler(for: track.id)
		audio.prepareSampler(for: track.id, instrument: instrument)
		HapticManager.shared.selectionChanged()
	}
	
	/// Quantize all notes in a track to the specified grid
	func quantizeTrack(_ track: Track, division: QuantizeDivision) {
		guard !track.isVocal else { return } // Can't quantize audio tracks
		looper.quantizeTrack(track.id, division: division)
		HapticManager.shared.selectionChanged()
	}
	
	/// Get a track by ID
	func track(withId id: UUID) -> Track? {
		tracks.first { $0.id == id }
	}
	
	/// Update a track (for note editing from TrackFocusView)
	func updateTrack(_ track: Track) {
		looper.updateTrack(track)
	}
	
	/// Whether any track has solo enabled
	var anyTrackSoloed: Bool {
		looper.anyTrackSoloed
	}
	
	/// Loop length in beats
	var loopLengthBeats: Double {
		looper.loopLengthBeats
	}
	
	// MARK: - Vocal Recording
	
	/// Normal master volume level (saved before vocal recording)
	private var normalMasterVolume: Float = 1.5
	
	/// Volume multiplier during vocal recording (75% to reduce mic bleed while staying audible)
	private let vocalRecordingVolumeMultiplier: Float = 0.75
	
	/// Looper elapsed time when vocal recording started (for auto-stop calculation)
	private var vocalRecordingStartElapsed: Double = 0
	
	func startVocalRecording() {
		proceedWithVocalRecording()
	}
	
	/// Called after user dismisses the headphone recommendation
	func continueVocalRecordingAfterRecommendation() {
		showHeadphoneRecommendation = false
		// Now start the count-in (which leads to recording)
		startVocalCountIn()
	}
	
	/// Proceeds with actual vocal recording (after recommendation or on subsequent recordings)
	private func proceedWithVocalRecording() {
		// If permission already granted, start immediately (no async delay)
		if vocalRecorder.hasPermission {
			beginVocalRecordingImmediately()
		} else {
			// Need to request permission asynchronously
			Task {
				let granted = await vocalRecorder.requestPermission()
				if granted {
					beginVocalRecordingImmediately()
				} else {
					showMicPermissionAlert = true
				}
			}
		}
	}
	
	/// Actually starts vocal recording - called synchronously when permission is already granted
	private func beginVocalRecordingImmediately() {
		// Reduce volume of other tracks to prevent mic bleed (happens immediately)
		normalMasterVolume = audio.masterVolume
		audio.masterVolume = normalMasterVolume * vocalRecordingVolumeMultiplier
		
		// Start the loop if not playing
		// CRITICAL: Check looper.isPlaying (authoritative) NOT self.isPlaying (async-updated via Combine)
		// The Combine publisher uses .receive(on: DispatchQueue.main) which delays updates,
		// causing self.isPlaying to be stale when called immediately after looper.startPlayback()
		if !looper.isPlaying {
			looper.startPlayback()
		}
		
		// Track looper's elapsed time when recording started (synced with playback)
		vocalRecordingStartElapsed = looper.playbackElapsedTime
		
		// Start recording
		if let filename = vocalRecorder.startRecording() {
			currentVocalFilename = filename
			isRecordingVocals = true
			HapticManager.shared.recordingStarted()
		}
	}
	
	func stopVocalRecording() {
		guard isRecordingVocals else { return }
		
		// Restore normal volume
		audio.masterVolume = normalMasterVolume
		
		// Pause playback immediately when stopping vocal recording
		looper.pausePlayback()
		isPaused = true
		
		if vocalRecorder.stopRecording(), let filename = currentVocalFilename {
			// Create audio track
			let track = Track(audioFileName: filename)
			looper.addAudioTrack(track)
			
			// Prepare player for this track
			_ = vocalRecorder.preparePlayer(for: track.id, filename: filename, volume: track.volume)
			
			HapticManager.shared.loopSet()
		}
		
		isRecordingVocals = false
		currentVocalFilename = nil
	}
	
	/// Check if vocal recording should auto-stop based on allotted bars
	private func checkVocalRecordingAutoStop(currentPosition: Double) {
		let secondsPerBeat = 60.0 / bpm
		let recordingLengthBeats = Double(barCount.rawValue * 4)
		let maxRecordingDuration = recordingLengthBeats * secondsPerBeat
		
		// Use looper's elapsed time (synced with playback) to avoid timing drift
		let recordingElapsed = looper.playbackElapsedTime - vocalRecordingStartElapsed
		
		// Auto-stop if we've exceeded the allotted recording time
		if recordingElapsed >= maxRecordingDuration {
			stopVocalRecording()
			// Reset to beginning after completing full recording
			// (prevents small offset from tick timing)
			looper.seekTo(position: 0)
		}
	}
	
	func toggleVocalRecording() {
		if isRecordingVocals {
			stopVocalRecording()
		} else {
			startVocalRecording()
		}
	}
	
	// MARK: - Save/Load Sessions
	
	func loadSavedSessions() {
		savedSessions = SessionStorage.shared.loadSessions()
	}
	
	func saveCurrentSession(name: String) {
		guard !tracks.isEmpty else { return }
		
		let session = SavedSession(
			id: currentSessionId ?? UUID(),
			name: name,
			bpm: bpm,
			barCount: barCount.rawValue,
			tracks: tracks
		)
		
		SessionStorage.shared.saveSession(session)
		currentSessionId = session.id
		currentSessionName = name
		loadSavedSessions()
		HapticManager.shared.loopSet()
	}
	
	func loadSession(_ session: SavedSession) {
		// Stop current playback
		stopPlayback()
		clearAll()
		
		// Load session settings
		bpm = session.bpm
		if let bc = BarCount(rawValue: session.barCount) {
			barCount = bc
			looper.setBarCount(bc)
		}
		
		// Load tracks into looper
		looper.loadTracks(session.tracks)
		
		// Prepare samplers for all tracks
		for track in session.tracks {
			if let instrument = Instrument(rawValue: track.instrumentName) {
				audio.prepareSampler(for: track.id, instrument: instrument)
				audio.setTrackVolume(track.id, volume: track.volume, instrument: instrument)
			}
		}
		
		currentSessionId = session.id
		currentSessionName = session.name
		HapticManager.shared.selectionChanged()
	}
	
	func deleteSession(_ session: SavedSession) {
		SessionStorage.shared.deleteSession(session)
		loadSavedSessions()
	}
	
	// MARK: - Share & Export
	
	/// Whether audio export is in progress
	@Published var isExporting = false
	
	/// Share the current session as an audio file (M4A)
	func shareCurrentSession() {
		// Sharing now exports audio instead of .loopa project files
		// so recipients can actually listen to the beat
		exportToAudio()
	}
	
	/// Export the current session to an M4A audio file
	func exportToAudio() {
		guard !tracks.isEmpty else { return }
		guard let soundFontURL = audio.soundFontURL else {
			print("❌ SoundFont not loaded")
			return
		}
		
		isExporting = true
		
		Task {
			let sessionName = currentSessionName.isEmpty ? "My Beat" : currentSessionName
			
			let url = await AudioExporter.shared.exportToM4A(
				tracks: tracks,
				bpm: bpm,
				loopLengthBeats: looper.loopLengthBeats,
				sessionName: sessionName,
				soundFontURL: soundFontURL
			)
			
			await MainActor.run {
				isExporting = false
				
				if let url = url {
					AudioExporter.shared.shareAudio(at: url)
					HapticManager.shared.loopSet()
				}
			}
		}
	}
	
	/// Load an imported session (from .loopa file)
	func loadImportedSession(_ session: SavedSession) {
		// Save the imported session first
		SessionStorage.shared.saveSession(session)
		loadSavedSessions()
		
		// Then load it into the app
		loadSession(session)
		
		// Update session name
		currentSessionName = session.name
		currentSessionId = session.id
		
		print("✓ Loaded imported session: \(session.name)")
	}
	
	// MARK: - Metronome
	
	func toggleMetronome() {
		isMetronomeOn.toggle()
		HapticManager.shared.selectionChanged()
	}
	
	// MARK: - Quantization
	
	private func updateQuantizer() {
		if quantizeDivision == .off {
			looper.quantizer = nil
		} else {
			looper.quantizer = Quantizer(bpm: bpm, division: quantizeDivision)
		}
	}
	
	func cycleQuantization() {
		// Cycle through: 1/16 -> 1/8 -> 1/4 -> Off -> 1/16
		switch quantizeDivision {
		case .sixteenth:
			quantizeDivision = .eighth
		case .eighth:
			quantizeDivision = .quarter
		case .quarter:
			quantizeDivision = .off
		case .off:
			quantizeDivision = .sixteenth
		case .thirtysecond:
			quantizeDivision = .sixteenth
		}
		HapticManager.shared.selectionChanged()
	}
	
	// MARK: - Note Playing
	
	func noteOn(_ note: UInt8, velocity: UInt8) {
		let effectiveNote = currentInstrument.isDrumKit ? mapToDrum(note) : note
		
		audio.playNote(effectiveNote, velocity: velocity)
		looper.addLiveEvent(note: effectiveNote, velocity: velocity, isNoteOn: true)
		
		HapticManager.shared.keyPressed(velocity: Double(velocity) / 127.0)
	}
	
	func noteOff(_ note: UInt8) {
		let effectiveNote = currentInstrument.isDrumKit ? mapToDrum(note) : note
		
		audio.stopNote(effectiveNote)
		looper.addLiveEvent(note: effectiveNote, velocity: 0, isNoteOn: false)
	}
	
	private func mapToDrum(_ note: UInt8) -> UInt8 {
		let index = Int(note) - Int(startNote)
		guard index >= 0 && index < drumMap.count else {
			return 36 // Default to kick
		}
		return drumMap[index]
	}
	
	// MARK: - Note Preview (Editor Feedback)
	
	/// Play a short preview of a note (for editor feedback when adding notes)
	func previewNote(pitch: UInt8, velocity: UInt8, trackId: UUID, duration: TimeInterval = 0.15) {
		guard let track = track(withId: trackId),
			  let instrument = Instrument(rawValue: track.instrumentName) else { return }
		
		audio.playTrackNote(pitch, velocity: velocity, trackId: trackId, instrument: instrument, volume: track.volume)
		
		// Auto-stop after short duration
		DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
			self?.audio.stopTrackNote(pitch, trackId: trackId, instrument: instrument)
		}
	}
	
	// MARK: - Playback Handling
	
	private func handlePlaybackEvent(_ event: MidiEvent, track: Track) {
		guard let instrument = Instrument(rawValue: track.instrumentName) else { return }
		
		if event.isNoteOn {
			audio.playTrackNote(event.note, velocity: event.velocity, trackId: track.id, instrument: instrument, volume: track.volume)
		} else {
			audio.stopTrackNote(event.note, trackId: track.id, instrument: instrument)
		}
	}
	
	private func handleBeat(_ beat: Int, isDownbeat: Bool) {
		if isMetronomeOn {
			audio.clickBeat(isDownbeat: isDownbeat)
		}
		
		if isDownbeat {
			HapticManager.shared.metronomeDownbeat()
		} else if isMetronomeOn {
			HapticManager.shared.metronomeBeat()
		}
	}
	
	// MARK: - Computed Properties
	
	var loopLengthSeconds: Double {
		looper.loopLength
	}
	
	var totalBeats: Int {
		barCount.rawValue * 4
	}
	
	var progressFraction: Double {
		guard looper.loopLength > 0 else { return 0 }
		
		// FIX: Use barCount setting for progress cycle, not global loop length
		// This makes a 1-bar track cycle 4 times in a 4-bar global loop
		let barCycleBeats = Double(barCount.rawValue) * 4.0  // 1 bar = 4 beats
		let secondsPerBeat = 60.0 / bpm
		let barCycleSeconds = barCycleBeats * secondsPerBeat
		
		// Wrap position within the bar cycle
		let positionInCycle = currentPosition.truncatingRemainder(dividingBy: barCycleSeconds)
		return positionInCycle / barCycleSeconds
	}
}

// MARK: - DisplayLink Target Helper

/// Helper class for CADisplayLink callback (requires @objc selector target)
private final class DisplayLinkTarget {
	private let callback: () -> Void
	
	init(callback: @escaping () -> Void) {
		self.callback = callback
	}
	
	@objc func tick() {
		callback()
	}
}

