import Foundation
import AVFoundation

/// Handles recording and playback of vocal audio tracks
final class VocalRecorder: ObservableObject {
	
	// MARK: - State
	
	@Published private(set) var isRecording = false
	@Published private(set) var hasPermission = false
	@Published var permissionDenied = false
	
	/// Current audio input level (0.0 to 1.0) for waveform visualization
	@Published private(set) var currentLevel: Float = 0
	
	/// Whether input monitoring is active (for waveform display when not recording)
	@Published private(set) var isMonitoring = false
	
	// MARK: - Audio Components
	
	private var audioRecorder: AVAudioRecorder?
	private var audioPlayers: [UUID: AVAudioPlayer] = [:]
	
	// MARK: - Input Monitoring (for waveform when not recording)
	
	private var monitoringEngine: AVAudioEngine?
	private var meteringTimer: Timer?
	
	// MARK: - File Management
	
	private var documentsURL: URL {
		FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
	}
	
	private var vocalsDirectory: URL {
		documentsURL.appendingPathComponent("Vocals", isDirectory: true)
	}
	
	init() {
		createVocalsDirectory()
		checkPermission()
	}
	
	private func createVocalsDirectory() {
		try? FileManager.default.createDirectory(at: vocalsDirectory, withIntermediateDirectories: true)
	}
	
	// MARK: - Permissions
	
	func checkPermission() {
		switch AVAudioApplication.shared.recordPermission {
		case .granted:
			hasPermission = true
			permissionDenied = false
		case .denied:
			hasPermission = false
			permissionDenied = true
		case .undetermined:
			hasPermission = false
			permissionDenied = false
		@unknown default:
			hasPermission = false
		}
	}
	
	func requestPermission() async -> Bool {
		let granted = await AVAudioApplication.requestRecordPermission()
		await MainActor.run {
			hasPermission = granted
			permissionDenied = !granted
		}
		return granted
	}
	
	// MARK: - Recording
	
	/// Whether the audio session has been pre-configured for recording
	private var sessionPreparedForRecording = false
	
	/// Pre-configure audio session for recording (call during count-in to avoid glitch)
	/// This changes the session category BEFORE playback starts, preventing audio interruption
	func prepareSessionForRecording() {
		guard !sessionPreparedForRecording else { return }
		
		do {
			let session = AVAudioSession.sharedInstance()
			// Use .default mode instead of .voiceChat - voiceChat reduces playback volume
			try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
			try session.setActive(true)
			sessionPreparedForRecording = true
			print("✓ Audio session pre-configured for vocal recording")
		} catch {
			print("⚠️ Failed to pre-configure audio session: \(error)")
		}
	}
	
	/// Start recording vocals, returns the filename
	func startRecording() -> String? {
		guard hasPermission else {
			print("❌ No microphone permission")
			return nil
		}
		
		// Stop monitoring if it was running (we'll use recorder metering instead)
		if isMonitoring {
			stopMonitoring()
		}
		
		// Generate unique filename
		let filename = "vocal_\(UUID().uuidString).m4a"
		let fileURL = vocalsDirectory.appendingPathComponent(filename)
		
		// Configure audio session for recording (skip if already prepared during count-in)
		if !sessionPreparedForRecording {
			do {
				let session = AVAudioSession.sharedInstance()
				// Use .default mode instead of .voiceChat - voiceChat reduces playback volume
				try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
				try session.setActive(true)
			} catch {
				print("❌ Failed to configure audio session: \(error)")
				return nil
			}
		}
		
		// Recording settings
		let settings: [String: Any] = [
			AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
			AVSampleRateKey: 44100.0,
			AVNumberOfChannelsKey: 1,
			AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
		]
		
		do {
			audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
			audioRecorder?.prepareToRecord()
			audioRecorder?.record()
			isRecording = true
			
			// Start metering for waveform visualization
			startMeteringTimer()
			
			print("🎤 Started recording: \(filename)")
			return filename
		} catch {
			print("❌ Failed to start recording: \(error)")
			return nil
		}
	}
	
	/// Stop recording and return success
	func stopRecording() -> Bool {
		guard isRecording, let recorder = audioRecorder else { return false }
		
		// Stop metering timer
		stopMeteringTimer()
		
		recorder.stop()
		isRecording = false
		sessionPreparedForRecording = false  // Reset for next recording session
		
		// Reset audio session back to playback only
		do {
			let session = AVAudioSession.sharedInstance()
			try session.setCategory(.playback, mode: .default)
			try session.setActive(true)
		} catch {
			print("⚠️ Failed to reset audio session: \(error)")
		}
		
		print("🎤 Stopped recording")
		return true
	}
	
	// MARK: - Playback
	
	/// Get the URL for a vocal file
	func getAudioURL(for filename: String) -> URL {
		vocalsDirectory.appendingPathComponent(filename)
	}
	
	/// Prepare audio player for a track (idempotent - safe to call multiple times)
	/// If a player already exists for this track, just updates volume without replacing it
	func preparePlayer(for trackId: UUID, filename: String, volume: Float) -> Bool {
		// If player already exists, just update volume and return (don't replace playing player!)
		if let existingPlayer = audioPlayers[trackId] {
			existingPlayer.volume = volume
			return true
		}
		
		let url = getAudioURL(for: filename)
		
		guard FileManager.default.fileExists(atPath: url.path) else {
			print("❌ Audio file not found: \(filename)")
			return false
		}
		
		do {
			let player = try AVAudioPlayer(contentsOf: url)
			player.volume = volume
			player.prepareToPlay()
			player.numberOfLoops = -1  // Loop indefinitely
			audioPlayers[trackId] = player
			print("✓ Prepared player for \(filename)")
			return true
		} catch {
			print("❌ Failed to create player: \(error)")
			return false
		}
	}
	
	/// Start playing a vocal track
	func play(trackId: UUID, at time: TimeInterval = 0) {
		guard let player = audioPlayers[trackId] else { return }
		player.currentTime = time
		player.play()
	}
	
	/// Pause a vocal track
	func pause(trackId: UUID) {
		audioPlayers[trackId]?.pause()
	}
	
	/// Stop a vocal track
	func stop(trackId: UUID) {
		audioPlayers[trackId]?.stop()
		audioPlayers[trackId]?.currentTime = 0
	}
	
	/// Stop all vocal tracks
	func stopAll() {
		for player in audioPlayers.values {
			player.stop()
			player.currentTime = 0
		}
	}
	
	/// Seek a vocal track to a specific position
	func seek(trackId: UUID, to position: TimeInterval) {
		guard let player = audioPlayers[trackId] else { return }
		let wasPlaying = player.isPlaying
		player.currentTime = position
		if wasPlaying {
			player.play()
		}
	}
	
	/// Set volume for a track
	func setVolume(_ trackId: UUID, volume: Float) {
		audioPlayers[trackId]?.volume = volume
	}
	
	/// Remove player for a track
	func removePlayer(for trackId: UUID) {
		audioPlayers[trackId]?.stop()
		audioPlayers.removeValue(forKey: trackId)
	}
	
	/// Delete audio file
	func deleteAudioFile(_ filename: String) {
		let url = getAudioURL(for: filename)
		try? FileManager.default.removeItem(at: url)
		print("🗑️ Deleted audio file: \(filename)")
	}
	
	/// Sync playback position with loop
	func syncToPosition(_ position: TimeInterval, loopLength: TimeInterval) {
		let normalizedPosition = position.truncatingRemainder(dividingBy: loopLength)
		for player in audioPlayers.values where player.isPlaying {
			// Only sync if significantly out of sync
			let diff = abs(player.currentTime - normalizedPosition)
			if diff > 0.1 {
				player.currentTime = normalizedPosition
			}
		}
	}
	
	// MARK: - Input Monitoring (Waveform Display)
	
	/// Start monitoring microphone input for waveform visualization
	/// Call this when entering vocal mode (before recording starts)
	func startMonitoring() {
		guard !isMonitoring && !isRecording else { return }
		guard hasPermission else {
			print("⚠️ Cannot monitor: no microphone permission")
			return
		}
		
		do {
			let session = AVAudioSession.sharedInstance()
			try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
			try session.setActive(true)
			
			monitoringEngine = AVAudioEngine()
			guard let engine = monitoringEngine else { return }
			
			let inputNode = engine.inputNode
			let format = inputNode.outputFormat(forBus: 0)
			
			// Install a tap on the input to measure levels
			inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
				self?.processAudioBuffer(buffer)
			}
			
			try engine.start()
			isMonitoring = true
			print("🎤 Started input monitoring for waveform")
		} catch {
			print("❌ Failed to start input monitoring: \(error)")
		}
	}
	
	/// Stop monitoring microphone input
	func stopMonitoring() {
		guard isMonitoring else { return }
		
		monitoringEngine?.inputNode.removeTap(onBus: 0)
		monitoringEngine?.stop()
		monitoringEngine = nil
		isMonitoring = false
		currentLevel = 0
		
		// Only reset audio session if not recording
		if !isRecording {
			do {
				let session = AVAudioSession.sharedInstance()
				try session.setCategory(.playback, mode: .default)
				try session.setActive(true)
			} catch {
				print("⚠️ Failed to reset audio session: \(error)")
			}
		}
		
		print("🎤 Stopped input monitoring")
	}
	
	/// Process audio buffer to extract level for visualization
	private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
		guard let channelData = buffer.floatChannelData?[0] else { return }
		let frameLength = Int(buffer.frameLength)
		
		// Calculate RMS (root mean square) for better level representation
		var sum: Float = 0
		for i in 0..<frameLength {
			let sample = channelData[i]
			sum += sample * sample
		}
		let rms = sqrt(sum / Float(frameLength))
		
		// Convert to 0-1 range with some amplification for visual impact
		// RMS values are typically quite small, so we amplify
		let normalizedLevel = min(1.0, rms * 5.0)
		
		DispatchQueue.main.async { [weak self] in
			// Smooth the level changes for better visual appearance
			let smoothing: Float = 0.3
			self?.currentLevel = (self?.currentLevel ?? 0) * (1 - smoothing) + normalizedLevel * smoothing
		}
	}
	
	/// Start metering timer for recording (uses AVAudioRecorder's built-in metering)
	private func startMeteringTimer() {
		audioRecorder?.isMeteringEnabled = true
		
		meteringTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
			self?.updateRecordingLevel()
		}
	}
	
	/// Stop metering timer
	private func stopMeteringTimer() {
		meteringTimer?.invalidate()
		meteringTimer = nil
		currentLevel = 0
	}
	
	/// Update level from AVAudioRecorder during recording
	private func updateRecordingLevel() {
		guard let recorder = audioRecorder, recorder.isRecording else { return }
		
		recorder.updateMeters()
		
		// Get average power in decibels (-160 to 0)
		let decibels = recorder.averagePower(forChannel: 0)
		
		// Convert decibels to linear scale (0.0 to 1.0)
		// -60 dB is effectively silence, 0 dB is max
		let minDb: Float = -60
		let normalizedLevel: Float
		if decibels < minDb {
			normalizedLevel = 0
		} else {
			normalizedLevel = (decibels - minDb) / abs(minDb)
		}
		
		DispatchQueue.main.async { [weak self] in
			self?.currentLevel = normalizedLevel
		}
	}
}

