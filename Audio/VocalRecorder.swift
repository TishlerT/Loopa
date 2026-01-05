import Foundation
import AVFoundation

/// Handles recording and playback of vocal audio tracks
final class VocalRecorder: ObservableObject {
	
	// MARK: - State
	
	@Published private(set) var isRecording = false
	@Published private(set) var hasPermission = false
	@Published var permissionDenied = false
	
	// MARK: - Audio Components
	
	private var audioRecorder: AVAudioRecorder?
	private var audioPlayers: [UUID: AVAudioPlayer] = [:]
	
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
}

