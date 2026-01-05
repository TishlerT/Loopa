import Foundation
import AVFoundation

/// Audio engine for the multi-track looper
/// Single live sampler + multiple playback samplers for layered tracks
final class LooperAudioEngine {
	let engine = AVAudioEngine()
	
	/// Live playing sampler (what the user plays in real-time)
	let liveSampler = KeyboardSampler()
	
	/// Pre-allocated pool of samplers for track playback (avoid runtime allocation)
	private var samplerPool: [KeyboardSampler] = []
	private var trackSamplerMap: [UUID: Int] = [:] // Track ID -> pool index
	private let maxTracks = 16
	
	/// Metronome click sampler
	let clickSampler = KeyboardSampler()
	
	/// Reverb effect
	let reverb = AVAudioUnitReverb()
	
	/// Master volume (1.0 = normal, 2.0 = 2x louder)
	var masterVolume: Float = 1.5 {
		didSet {
			engine.mainMixerNode.outputVolume = masterVolume
		}
	}
	
	/// Minimum velocity for consistent volume
	private let minVelocity: UInt8 = 80
	
	private(set) var soundFontURL: URL?
	private(set) var currentInstrument: Instrument = .piano
	
	init() {
		setupAudioGraph()
	}
	
	private func setupAudioGraph() {
		print("🔧 Setting up audio graph...")
		
		// Attach nodes first
		engine.attach(liveSampler.sampler)
		engine.attach(clickSampler.sampler)
		
		// Use nil format - let AVAudioEngine figure out the best format
		// This is often more reliable than specifying a format explicitly
		print("🔧 Connecting with nil format (auto-negotiated)")
		
		// Connect samplers directly to mixer (simpler routing)
		engine.connect(liveSampler.sampler, to: engine.mainMixerNode, format: nil)
		engine.connect(clickSampler.sampler, to: engine.mainMixerNode, format: nil)
		
		// Pre-allocate sampler pool for tracks (prevents crashes from runtime allocation)
		for i in 0..<maxTracks {
			let sampler = KeyboardSampler()
			engine.attach(sampler.sampler)
			engine.connect(sampler.sampler, to: engine.mainMixerNode, format: nil)
			samplerPool.append(sampler)
			print("🔧 Sampler \(i) attached")
		}
		
		// Set master volume boost
		engine.mainMixerNode.outputVolume = masterVolume
		
		print("✅ Audio graph initialized with \(maxTracks) pre-allocated samplers")
	}
	
	// MARK: - Session Configuration
	
	func configureSession() throws {
		let session = AVAudioSession.sharedInstance()
		
		// Simple playback category
		try session.setCategory(.playback, mode: .default)
		try session.setPreferredIOBufferDuration(0.005)
		try session.setActive(true)
		
		setupInterruptionHandling()
		
		print("✓ Audio session: category=\(session.category.rawValue)")
		print("✓ Output route: \(session.currentRoute.outputs.map { $0.portName })")
	}
	
	private func setupInterruptionHandling() {
		NotificationCenter.default.addObserver(
			forName: AVAudioSession.interruptionNotification,
			object: nil,
			queue: .main
		) { [weak self] notification in
			guard let self = self,
				  let userInfo = notification.userInfo,
				  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
				  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
			
			if type == .ended {
				try? AVAudioSession.sharedInstance().setActive(true)
				try? self.engine.start()
			}
		}
	}
	
	func start() throws {
		if !engine.isRunning {
			// Prepare the engine (allocates resources)
			engine.prepare()
			print("✓ Audio engine prepared")
			
			try engine.start()
			print("✓ Audio engine started, running: \(engine.isRunning)")
			
			// Debug: print output format
			let outputFormat = engine.outputNode.outputFormat(forBus: 0)
			print("🔊 Output format: \(outputFormat)")
			print("🔊 Output volume: \(engine.mainMixerNode.outputVolume)")
			print("🔊 Live sampler volume: \(liveSampler.sampler.volume)")
			
			// Verify connections
			print("🔊 Live sampler connections: \(liveSampler.sampler.numberOfInputs) in, \(liveSampler.sampler.numberOfOutputs) out")
		} else {
			print("ℹ️ Audio engine already running")
		}
	}
	
	// MARK: - SoundFont Loading
	
	func loadSoundFont() throws {
		guard let url = Bundle.main.url(forResource: "GM", withExtension: "sf2") else {
			throw NSError(domain: "Tish88", code: -1,
						  userInfo: [NSLocalizedDescriptionKey: "GM.sf2 not found"])
		}
		soundFontURL = url
		print("✓ Found GM.sf2 at: \(url.path)")
		
		// Load click sounds
		try clickSampler.loadDrumKit(soundFontURL: url)
		print("✓ Click sampler loaded")
		
		// Load default instrument into live sampler
		try setInstrument(.piano)
		print("✓ Live sampler loaded with Piano")
	}
	
	// MARK: - Instrument Selection
	
	func setInstrument(_ instrument: Instrument) throws {
		guard let url = soundFontURL else {
			throw NSError(domain: "Tish88", code: -2,
						  userInfo: [NSLocalizedDescriptionKey: "SoundFont not loaded"])
		}
		
		liveSampler.stopAll()
		
		if instrument.isDrumKit {
			try liveSampler.loadDrumKit(soundFontURL: url)
		} else {
			try liveSampler.loadProgram(instrument.programNumber, soundFontURL: url)
		}
		
		currentInstrument = instrument
		print("✓ Instrument set to: \(instrument.rawValue)")
	}
	
	// MARK: - Track Samplers (Pool-based)
	
	/// Get a sampler from the pool for a track, loading the instrument if needed
	private func getSampler(for trackId: UUID, instrument: Instrument) -> KeyboardSampler? {
		// Check if already assigned
		if let index = trackSamplerMap[trackId], index < samplerPool.count {
			return samplerPool[index]
		}
		
		// Find next available slot
		let usedIndices = Set(trackSamplerMap.values)
		guard let nextIndex = (0..<maxTracks).first(where: { !usedIndices.contains($0) }) else {
			print("⚠️ No available samplers in pool")
			return nil
		}
		
		let sampler = samplerPool[nextIndex]
		trackSamplerMap[trackId] = nextIndex
		
		// Load the instrument for this track (safe - sampler already attached)
		if let url = soundFontURL {
			do {
				if instrument.isDrumKit {
					try sampler.loadDrumKit(soundFontURL: url)
				} else {
					try sampler.loadProgram(instrument.programNumber, soundFontURL: url)
				}
				print("✓ Loaded \(instrument.rawValue) for track")
			} catch {
				print("⚠️ Failed to load track sampler: \(error)")
			}
		}
		
		return sampler
	}
	
	func removeSampler(for trackId: UUID) {
		guard let index = trackSamplerMap[trackId], index < samplerPool.count else { return }
		samplerPool[index].stopAll()
		trackSamplerMap.removeValue(forKey: trackId)
	}
	
	func clearAllTrackSamplers() {
		for sampler in samplerPool {
			sampler.stopAll()
		}
		trackSamplerMap.removeAll()
	}
	
	// MARK: - Live Note Playing
	
	func playNote(_ note: UInt8, velocity: UInt8) {
		print("🎹 playNote called: note=\(note), vel=\(velocity), engine.isRunning=\(engine.isRunning)")
		
		// Ensure engine is running
		if !engine.isRunning {
			print("⚠️ Engine not running, starting...")
			do {
				try start()
			} catch {
				print("❌ Failed to start engine: \(error)")
				return
			}
		}
		
		// Boost quiet velocities for more consistent volume
		let boostedVelocity = max(velocity, minVelocity)
		print("🎹 Sending noteOn: \(note), velocity: \(boostedVelocity)")
		liveSampler.send(noteOn: note, velocity: boostedVelocity)
	}
	
	func stopNote(_ note: UInt8) {
		liveSampler.send(noteOff: note)
	}
	
	func stopAllNotes() {
		liveSampler.stopAll()
		for sampler in samplerPool {
			sampler.stopAll()
		}
	}
	
	// MARK: - Track Playback
	
	func playTrackNote(_ note: UInt8, velocity: UInt8, trackId: UUID, instrument: Instrument, volume: Float = 1.0) {
		guard let sampler = getSampler(for: trackId, instrument: instrument) else {
			print("⚠️ No sampler for track \(trackId)")
			return
		}
		// Apply track volume to velocity (scale 0.0-1.0 to velocity adjustment)
		let scaledVelocity = UInt8(Float(velocity) * volume)
		let boostedVelocity = max(scaledVelocity, UInt8(Float(minVelocity) * volume))
		sampler.send(noteOn: note, velocity: boostedVelocity)
	}
	
	func stopTrackNote(_ note: UInt8, trackId: UUID, instrument: Instrument) {
		guard let sampler = getSampler(for: trackId, instrument: instrument) else { return }
		sampler.send(noteOff: note)
	}
	
	/// Set volume for a specific track's sampler
	func setTrackVolume(_ trackId: UUID, volume: Float, instrument: Instrument) {
		guard let sampler = getSampler(for: trackId, instrument: instrument) else { return }
		sampler.sampler.volume = volume
	}
	
	/// Prepare a sampler for a track before playback starts (call when track is created)
	func prepareSampler(for trackId: UUID, instrument: Instrument) {
		_ = getSampler(for: trackId, instrument: instrument)
	}
	
	// MARK: - Engine State
	
	/// Ensure engine is running (call after audio session changes)
	func ensureRunning() {
		if !engine.isRunning {
			do {
				try engine.start()
				print("✓ Audio engine restarted after session change")
			} catch {
				print("⚠️ Failed to restart engine: \(error)")
			}
		}
	}
	
	// MARK: - Metronome
	
	func clickBeat(isDownbeat: Bool) {
		let note: UInt8 = isDownbeat ? 76 : 77 // Hi wood block, Lo wood block
		let velocity: UInt8 = isDownbeat ? 110 : 80
		clickSampler.send(noteOn: note, velocity: velocity)
		
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
			self?.clickSampler.send(noteOff: note)
		}
	}
	
	// MARK: - Test
	
	/// Play a test note to verify audio is working
	func testBeep() {
		print("🔔 Playing test beep...")
		playNote(60, velocity: 100) // Middle C
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
			self?.stopNote(60)
			print("🔔 Test beep ended")
		}
	}
	
	/// Play a pure sine wave test tone to verify audio output works
	func testTone() {
		print("🔊 Playing pure sine wave test tone...")
		
		// Create a player node for test tone
		let playerNode = AVAudioPlayerNode()
		engine.attach(playerNode)
		
		// Use stereo format matching the mixer
		let sampleRate: Double = 48000
		let frequency: Double = 440 // A4
		let duration: Double = 0.5
		let frameCount = AVAudioFrameCount(sampleRate * duration)
		
		guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
			  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
			print("❌ Failed to create audio buffer")
			return
		}
		
		// Connect with the buffer's format
		engine.connect(playerNode, to: engine.mainMixerNode, format: format)
		
		buffer.frameLength = frameCount
		
		// Fill both channels with sine wave
		if let leftChannel = buffer.floatChannelData?[0],
		   let rightChannel = buffer.floatChannelData?[1] {
			for i in 0..<Int(frameCount) {
				let sample = sin(2 * .pi * frequency * Double(i) / sampleRate)
				leftChannel[i] = Float(sample) * 0.5 // 50% volume
				rightChannel[i] = Float(sample) * 0.5
			}
		}
		
		playerNode.play()
		playerNode.scheduleBuffer(buffer, at: nil, options: []) {
			print("🔊 Sine wave test tone completed")
			DispatchQueue.main.async { [weak self] in
				self?.engine.detach(playerNode)
			}
		}
	}
}

