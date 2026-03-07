import Foundation
import AVFoundation

/// General MIDI instrument program numbers
enum InstrumentProgram: UInt8, CaseIterable, Identifiable {
	case acousticPiano = 0
	case electricPiano = 4
	case organ = 16
	case nylonGuitar = 24
	case strings = 48
	case synthLead = 80
	case synthPad = 88
	
	var id: UInt8 { rawValue }
	
	var displayName: String {
		switch self {
		case .acousticPiano: return "Piano"
		case .electricPiano: return "E‑Piano"
		case .organ: return "Organ"
		case .nylonGuitar: return "Guitar"
		case .strings: return "Strings"
		case .synthLead: return "Lead"
		case .synthPad: return "Pad"
		}
	}
}

/// Special instrument types that don't map to standard GM programs
enum SpecialInstrument: String, CaseIterable, Identifiable {
	case drumKit = "Drum Kit"
	case bass808 = "808 Bass"
	
	var id: String { rawValue }
}

/// SoundFont-based sampler for keyboard instruments
final class KeyboardSampler {
	let sampler = AVAudioUnitSampler()
	private var currentProgram: UInt8 = 0
	private var isPercussion: Bool = false
	
	// MARK: - Loading
	
	/// Load a melodic instrument from a SoundFont
	func load(program: InstrumentProgram, soundFontURL: URL) throws {
		try loadProgram(program.rawValue, soundFontURL: soundFontURL)
	}
	
	/// Load a melodic instrument by program number
	func loadProgram(_ programNumber: UInt8, soundFontURL: URL) throws {
		// Stop any sounding notes first
		stopAll()
		
		try sampler.loadSoundBankInstrument(
			at: soundFontURL,
			program: programNumber,
			bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
			bankLSB: 0
		)
		
		// Boost the master gain
		sampler.masterGain = 6.0 // +6dB boost
		
		currentProgram = programNumber
		isPercussion = false
		print("✓ Loaded program \(programNumber), gain=\(sampler.masterGain)")
	}
	
	/// Load a drum kit from a SoundFont
	func loadDrumKit(soundFontURL: URL) throws {
		// Stop any sounding notes first
		stopAll()
		
		try sampler.loadSoundBankInstrument(
			at: soundFontURL,
			program: 0,
			bankMSB: UInt8(kAUSampler_DefaultPercussionBankMSB),
			bankLSB: 0
		)
		
		// Boost the master gain
		sampler.masterGain = 6.0 // +6dB boost
		
		currentProgram = 0
		isPercussion = true
		print("✓ Loaded drum kit, gain=\(sampler.masterGain)")
	}
	
	// MARK: - Note Control
	
	/// Send note on event
	func send(noteOn note: UInt8, velocity: UInt8) {
		print("📤 KeyboardSampler.send(noteOn: \(note), velocity: \(velocity)) - isPercussion=\(isPercussion), program=\(currentProgram), gain=\(sampler.masterGain)")
		sampler.startNote(note, withVelocity: velocity, onChannel: 0)
	}
	
	/// Send note off event
	func send(noteOff note: UInt8) {
		sampler.stopNote(note, onChannel: 0)
	}
	
	/// Stop all currently sounding notes
	func stopAll() {
		// All Sound Off (CC 120) and All Notes Off (CC 123)
		sampler.sendController(120, withValue: 0, onChannel: 0)
		sampler.sendController(123, withValue: 0, onChannel: 0)
	}
}

