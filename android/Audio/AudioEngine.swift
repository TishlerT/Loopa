import Foundation
import AVFoundation

/// Main audio engine for Tish88 - manages samplers, reverb, and audio routing
final class TishAudioEngine {
	let engine = AVAudioEngine()
	let left = KeyboardSampler()
	let right = KeyboardSampler()
	let click = KeyboardSampler()
	let reverb = AVAudioUnitReverb()
	
	private(set) var soundFontURL: URL?
	private(set) var soundFont808URL: URL?
	
	init() {
		reverb.loadFactoryPreset(.mediumHall)
		reverb.wetDryMix = 12
		
		// Attach all audio units to the engine
		engine.attach(left.sampler)
		engine.attach(right.sampler)
		engine.attach(click.sampler)
		engine.attach(reverb)
		
		// Use the main mixer's output format for connections
		// This ensures consistent audio format throughout the graph
		let format = engine.mainMixerNode.outputFormat(forBus: 0)
		
		// Connect left and right samplers through reverb
		engine.connect(left.sampler, to: reverb, format: format)
		engine.connect(right.sampler, to: reverb, format: format)
		
		// Connect click directly to mixer (no reverb on metronome)
		engine.connect(click.sampler, to: engine.mainMixerNode, format: format)
		
		// Connect reverb to main mixer
		engine.connect(reverb, to: engine.mainMixerNode, format: format)
		
		print("✓ Audio graph connected: L→reverb, R→reverb, click→mixer, reverb→mixer")
	}
	
	// MARK: - Session Configuration
	
	func configureSession() throws {
		let session = AVAudioSession.sharedInstance()
		
		// Use .playback category - .defaultToSpeaker is only valid for .playAndRecord
		// .mixWithOthers allows playing alongside other audio apps
		try session.setCategory(
			.playback,
			mode: .default,
			options: [.mixWithOthers]
		)
		
		// Use a reasonable buffer duration (5.8ms) - very low values can fail on some devices
		try session.setPreferredIOBufferDuration(0.005)
		try session.setActive(true)
		
		// Set up interruption handling for when the app goes to background/foreground
		setupInterruptionHandling()
		
		print("✓ Audio session configured: \(session.category.rawValue), buffer: \(session.ioBufferDuration)s")
	}
	
	private func setupInterruptionHandling() {
		NotificationCenter.default.addObserver(
			forName: AVAudioSession.interruptionNotification,
			object: AVAudioSession.sharedInstance(),
			queue: .main
		) { [weak self] notification in
			guard let self = self else { return }
			
			guard let userInfo = notification.userInfo,
				  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
				  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
				return
			}
			
			switch type {
			case .began:
				print("🔇 Audio interrupted - pausing engine")
				self.engine.pause()
			case .ended:
				print("🔊 Audio interruption ended - resuming")
				do {
					try AVAudioSession.sharedInstance().setActive(true)
					try self.engine.start()
					print("✓ Engine resumed after interruption")
				} catch {
					print("❌ Failed to resume after interruption: \(error)")
				}
			@unknown default:
				break
			}
		}
		
		// Handle route changes (headphones plugged/unplugged)
		NotificationCenter.default.addObserver(
			forName: AVAudioSession.routeChangeNotification,
			object: AVAudioSession.sharedInstance(),
			queue: .main
		) { [weak self] notification in
			guard let self = self else { return }
			
			guard let userInfo = notification.userInfo,
				  let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
				  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
				return
			}
			
			if reason == .oldDeviceUnavailable {
				print("🎧 Audio route changed (device unplugged) - restarting engine")
				do {
					try self.engine.start()
				} catch {
					print("❌ Failed to restart after route change: \(error)")
				}
			}
		}
	}
	
	func start() throws {
		if !engine.isRunning {
			try engine.start()
		}
	}
	
	// MARK: - SoundFont Loading
	
	func loadSoundFonts() throws {
		guard let sf2 = Bundle.main.url(forResource: "GM", withExtension: "sf2") else {
			throw NSError(
				domain: "Tish88",
				code: -1,
				userInfo: [NSLocalizedDescriptionKey: "GM.sf2 missing (add to target)"]
			)
		}
		// 808 is optional – proceed even if it's not bundled
		let sf808 = Bundle.main.url(forResource: "808", withExtension: "sf2")
		soundFontURL = sf2
		soundFont808URL = sf808
		try click.loadDrumKit(soundFontURL: sf2)
	}
	
	// MARK: - Instrument Selection
	
	func setLeft(program: InstrumentProgram) throws {
		guard let sf2 = soundFontURL else {
			throw NSError(domain: "Tish88", code: -3, userInfo: [NSLocalizedDescriptionKey: "GM.sf2 not loaded"])
		}
		try left.load(program: program, soundFontURL: sf2)
	}
	
	func setRight(program: InstrumentProgram) throws {
		guard let sf2 = soundFontURL else {
			throw NSError(domain: "Tish88", code: -3, userInfo: [NSLocalizedDescriptionKey: "GM.sf2 not loaded"])
		}
		try right.load(program: program, soundFontURL: sf2)
	}
	
	func setLeftDrums() throws {
		guard let sf2 = soundFontURL else {
			throw NSError(domain: "Tish88", code: -3, userInfo: [NSLocalizedDescriptionKey: "GM.sf2 not loaded"])
		}
		try left.loadDrumKit(soundFontURL: sf2)
	}
	
	func setRightDrums() throws {
		guard let sf2 = soundFontURL else {
			throw NSError(domain: "Tish88", code: -3, userInfo: [NSLocalizedDescriptionKey: "GM.sf2 not loaded"])
		}
		try right.loadDrumKit(soundFontURL: sf2)
	}
	
	func setLeft808() throws {
		guard let sf808 = soundFont808URL else {
			throw NSError(domain: "Tish88", code: -4, userInfo: [NSLocalizedDescriptionKey: "808.sf2 not loaded"])
		}
		try left.load(program: .acousticPiano, soundFontURL: sf808)
	}
	
	func setRight808() throws {
		guard let sf808 = soundFont808URL else {
			throw NSError(domain: "Tish88", code: -4, userInfo: [NSLocalizedDescriptionKey: "808.sf2 not loaded"])
		}
		try right.load(program: .acousticPiano, soundFontURL: sf808)
	}
	
	// MARK: - Note Routing
	
	func noteOn(note: UInt8, velocity: UInt8, isLeft: Bool) {
		#if DEBUG
		print("🎹 noteOn: \(note), vel: \(velocity), left: \(isLeft), engine running: \(engine.isRunning)")
		#endif
		
		guard engine.isRunning else {
			print("⚠️ Engine not running! Attempting restart...")
			try? start()
			return
		}
		
		if isLeft {
			left.send(noteOn: note, velocity: velocity)
		} else {
			right.send(noteOn: note, velocity: velocity)
		}
	}
	
	func noteOff(note: UInt8, isLeft: Bool) {
		if isLeft {
			left.send(noteOff: note)
		} else {
			right.send(noteOff: note)
		}
	}
	
	func stopAllNotes() {
		left.stopAll()
		right.stopAll()
		click.stopAll()
	}
	
	// MARK: - Metronome
	
	func clickBeat(accent: Bool) {
		// Use GM percussion: 42 Closed Hi-Hat, 36 Bass Drum 1
		let note: UInt8 = accent ? 36 : 42
		click.send(noteOn: note, velocity: accent ? 110 : 90)
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
			self?.click.send(noteOff: note)
		}
	}
}

