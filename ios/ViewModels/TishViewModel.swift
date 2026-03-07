import SwiftUI
import AVFoundation

/// Main ViewModel for the Tish88 music production app.
/// Manages audio engine, looper, metronome, and instrument state.
final class TishViewModel: ObservableObject {
	
	// MARK: - Published State
	
	@Published var leftInstrument: String = "Drum Kit"
	@Published var rightInstrument: String = "Piano"
	@Published var bpm: Double = 100
	@Published var isMetronomeOn: Bool = false
	@Published var isRecording: Bool = false
	@Published var isPlaying: Bool = false
	@Published var isOverdubbing: Bool = false
	@Published var audioInitError: String? = nil
	@Published var quantizeDivision: QuantizeDivision = .sixteenth {
		didSet { updateQuantizer() }
	}
	
	// MARK: - Audio Components
	
	let audio = TishAudioEngine()
	let looper = MidiLooper()
	let metro = Metronome()
	
	// MARK: - Configuration
	
	/// MIDI note range C4..F#5 (60..78)
	let startNote: UInt8 = 60
	let numSemitones: Int = 18
	
	// MARK: - Initialization
	
	init() {
		setup()
	}
	
	private func setup() {
		do {
			print("🎵 Setting up audio...")
			try audio.configureSession()
			print("🎵 Loading SoundFonts...")
			try audio.loadSoundFonts()
			print("🎵 Setting left instrument (Drum Kit)...")
			try audio.setLeftDrums()
			print("🎵 Setting right instrument (Piano)...")
			try audio.setRight(program: .acousticPiano)
			print("🎵 Starting audio engine...")
			try audio.start()
			
			// Verify engine is running
			if audio.engine.isRunning {
				print("✓ Audio setup complete! Engine is running.")
				audioInitError = nil
			} else {
				audioInitError = "Engine failed to start"
				print("⚠️ Engine not running after start()")
			}
		} catch {
			audioInitError = error.localizedDescription
			print("❌ Audio init error: \(error)")
		}
		
		looper.onDispatch = { [weak self] e in
			DispatchQueue.main.async { self?.audioEvent(e) }
		}
		
		metro.onBeat = { [weak self] beat in
			guard let self else { return }
			let accent = (beat % self.metro.beatsPerBar) == 0
			self.audio.clickBeat(accent: accent)
			
			// Haptic feedback on beat
			if accent {
				HapticManager.shared.metronomeDownbeat()
			} else {
				HapticManager.shared.metronomeBeat()
			}
		}
		
		// Initialize quantizer
		updateQuantizer()
	}
	
	private func updateQuantizer() {
		if quantizeDivision == .off {
			looper.quantizer = nil
		} else {
			looper.quantizer = Quantizer(bpm: bpm, division: quantizeDivision)
		}
	}
	
	// MARK: - Metronome Control
	
	func toggleMetronome() {
		isMetronomeOn.toggle()
		metro.bpm = bpm
		isMetronomeOn ? metro.start() : metro.stop()
	}
	
	// MARK: - Recording Control
	
	func startRecord() {
		isRecording = true
		looper.startRecording()
		HapticManager.shared.recordingStarted()
	}
	
	func setLoopNow() {
		// Snap loop length to nearest beat subdivision
		let secondsPerBeat = 60.0 / bpm
		let length = looper.currentRecordingElapsed()
		let beats = max(1, Int(round(length / secondsPerBeat)))
		let snapped = Double(beats) * secondsPerBeat
		looper.finalizeLoop(lengthSeconds: snapped)
		isRecording = false
		isPlaying = true
		HapticManager.shared.loopSet()
	}
	
	func startOverdub() {
		isOverdubbing = true
		looper.startOverdub()
	}
	
	func stopAll() {
		isOverdubbing = false
		isPlaying = false
		isRecording = false
		looper.stop()
		audio.stopAllNotes()
	}
	
	func clearLoop() {
		looper.clear()
		isPlaying = false
		isOverdubbing = false
		isRecording = false
	}
	
	// MARK: - Instrument Selection
	
	func changeLeftInstrument(_ name: String) {
		leftInstrument = name
		HapticManager.shared.selectionChanged()
		
		// Stop any currently playing notes before changing program
		audio.left.stopAll()
		
		do {
			switch name {
			case "Drum Kit": try audio.setLeftDrums()
			case "808 Bass": 
				// 808 is optional - fallback to piano if not available
				do {
					try audio.setLeft808()
				} catch {
					print("808 not available, using piano: \(error)")
					try audio.setLeft(program: .acousticPiano)
				}
			case "Piano": try audio.setLeft(program: .acousticPiano)
			case "E-Piano", "E‑Piano": try audio.setLeft(program: .electricPiano)
			case "Organ": try audio.setLeft(program: .organ)
			case "Guitar": try audio.setLeft(program: .nylonGuitar)
			case "Strings": try audio.setLeft(program: .strings)
			case "Lead": try audio.setLeft(program: .synthLead)
			case "Pad": try audio.setLeft(program: .synthPad)
			default: 
				print("Unknown left instrument: '\(name)' - bytes: \(Array(name.utf8))")
			}
		} catch { 
			audioInitError = "Left: \(error.localizedDescription)"
			print("Left program error: \(error)") 
		}
	}
	
	func changeRightInstrument(_ name: String) {
		rightInstrument = name
		HapticManager.shared.selectionChanged()
		
		// Stop any currently playing notes before changing program
		audio.right.stopAll()
		
		do {
			switch name {
			case "Drum Kit": try audio.setRightDrums()
			case "808 Bass": 
				// 808 is optional - fallback to piano if not available
				do {
					try audio.setRight808()
				} catch {
					print("808 not available, using piano: \(error)")
					try audio.setRight(program: .acousticPiano)
				}
			case "Piano": try audio.setRight(program: .acousticPiano)
			case "E-Piano", "E‑Piano": try audio.setRight(program: .electricPiano)
			case "Organ": try audio.setRight(program: .organ)
			case "Guitar": try audio.setRight(program: .nylonGuitar)
			case "Strings": try audio.setRight(program: .strings)
			case "Lead": try audio.setRight(program: .synthLead)
			case "Pad": try audio.setRight(program: .synthPad)
			default: 
				print("Unknown right instrument: '\(name)' - bytes: \(Array(name.utf8))")
			}
		} catch { 
			audioInitError = "Right: \(error.localizedDescription)"
			print("Right program error: \(error)") 
		}
	}
	
	// MARK: - Note Events
	
	func noteOn(note: UInt8, velocity: UInt8, isLeft: Bool) {
		let effective = isLeft && leftInstrument == "Drum Kit" ? mapDrum(note: note) : note
		audio.noteOn(note: effective, velocity: velocity, isLeft: isLeft)
		looper.addLiveEvent(note: effective, velocity: velocity, isNoteOn: true, isLeft: isLeft)
		
		// Haptic feedback scaled to velocity
		HapticManager.shared.keyPressed(velocity: Double(velocity) / 127.0)
	}
	
	func noteOff(note: UInt8, isLeft: Bool) {
		let effective = isLeft && leftInstrument == "Drum Kit" ? mapDrum(note: note) : note
		audio.noteOff(note: effective, isLeft: isLeft)
		looper.addLiveEvent(note: effective, velocity: 0, isNoteOn: false, isLeft: isLeft)
	}
	
	// MARK: - Private Helpers
	
	private func mapDrum(note: UInt8) -> UInt8 {
		let idx = Int(note &- startNote)
		let leftIndex = max(0, min(8, idx))
		// GM Drum Map: Kick, Snare, CH, OH, Clap, Tom1, Tom2, Rim, Crash
		let layout: [UInt8] = [36, 38, 42, 46, 39, 41, 43, 37, 49]
		return layout[leftIndex]
	}
	
	private func audioEvent(_ e: MidiEvent) {
		if e.isNoteOn {
			audio.noteOn(note: e.note, velocity: e.velocity, isLeft: e.isLeft)
		} else {
			audio.noteOff(note: e.note, isLeft: e.isLeft)
		}
	}
	
	/// Quick sanity tone on right side for testing
	func ping() {
		let note: UInt8 = 60
		audio.noteOn(note: note, velocity: 110, isLeft: false)
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
			self?.audio.noteOff(note: note, isLeft: false)
		}
	}
}

