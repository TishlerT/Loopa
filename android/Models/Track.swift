import Foundation

/// Track type - MIDI (instruments) or Audio (vocals)
enum TrackType: String, Codable {
	case midi
	case audio
}

/// Represents a single recorded track in the looper
struct Track: Identifiable, Codable {
	let id: UUID
	let trackType: TrackType
	var instrumentName: String
	var instrumentProgram: UInt8
	let isDrumKit: Bool
	var notes: [MidiNote]  // For MIDI tracks (beat-based)
	var audioFileName: String?  // For audio tracks (vocals)
	let recordedAt: Date
	var isMuted: Bool
	var isSolo: Bool
	var volume: Float  // 0.0 to 1.0
	var recordedLengthBeats: Double  // The original recorded length of this track
	var isLooping: Bool  // Whether this track loops to fill the longest track
	
	/// Create a MIDI instrument track
	init(
		id: UUID = UUID(),
		instrumentName: String,
		instrumentProgram: UInt8,
		isDrumKit: Bool,
		notes: [MidiNote] = [],
		recordedAt: Date = Date(),
		isMuted: Bool = false,
		isSolo: Bool = false,
		volume: Float = 0.8,
		recordedLengthBeats: Double = 16.0,
		isLooping: Bool = true
	) {
		self.id = id
		self.trackType = .midi
		self.instrumentName = instrumentName
		self.instrumentProgram = instrumentProgram
		self.isDrumKit = isDrumKit
		self.notes = notes
		self.audioFileName = nil
		self.recordedAt = recordedAt
		self.isMuted = isMuted
		self.isSolo = isSolo
		self.volume = volume
		self.recordedLengthBeats = recordedLengthBeats
		self.isLooping = isLooping
	}
	
	/// Create an audio (vocal) track
	init(
		id: UUID = UUID(),
		audioFileName: String,
		recordedAt: Date = Date(),
		isMuted: Bool = false,
		isSolo: Bool = false,
		volume: Float = 0.8,
		recordedLengthBeats: Double = 16.0,
		isLooping: Bool = true
	) {
		self.id = id
		self.trackType = .audio
		self.instrumentName = "Vocals"
		self.instrumentProgram = 0
		self.isDrumKit = false
		self.notes = []
		self.audioFileName = audioFileName
		self.recordedAt = recordedAt
		self.isMuted = isMuted
		self.isSolo = isSolo
		self.volume = volume
		self.recordedLengthBeats = recordedLengthBeats
		self.isLooping = isLooping
	}
	
	/// Is this a vocal/audio track?
	var isVocal: Bool {
		trackType == .audio
	}
	
	/// Determine if this track should be audible based on mute/solo state
	/// - Parameter anyTrackSoloed: Whether any track in the session has solo enabled
	/// - Returns: true if this track should play audio
	func isAudible(anyTrackSoloed: Bool) -> Bool {
		// Muted tracks are always silent
		if isMuted { return false }
		// If any track is soloed, only soloed tracks play
		if anyTrackSoloed { return isSolo }
		// Otherwise, non-muted tracks play
		return true
	}
	
	/// Get the instrument enum for this track (nil for vocals)
	var instrument: Instrument? {
		Instrument(rawValue: instrumentName)
	}
}

/// A saved session containing tracks and settings
struct SavedSession: Identifiable, Codable {
	let id: UUID
	var name: String
	let createdAt: Date
	var lastModifiedAt: Date
	let bpm: Double
	let barCount: Int
	var tracks: [Track]
	
	init(
		id: UUID = UUID(),
		name: String,
		bpm: Double,
		barCount: Int,
		tracks: [Track]
	) {
		self.id = id
		self.name = name
		self.createdAt = Date()
		self.lastModifiedAt = Date()
		self.bpm = bpm
		self.barCount = barCount
		self.tracks = tracks
	}
}

/// Available bar counts for loop length
enum BarCount: Int, CaseIterable, Identifiable {
	case one = 1
	case two = 2
	case four = 4
	case eight = 8
	case sixteen = 16
	
	var id: Int { rawValue }
	
	var displayName: String {
		rawValue == 1 ? "1 bar" : "\(rawValue) bars"
	}
}

/// Available instruments
enum Instrument: String, CaseIterable, Identifiable {
	case piano = "Piano"
	case electricPiano = "E-Piano"
	case organ = "Organ"
	case guitar = "Guitar"
	case strings = "Strings"
	case lead = "Lead"
	case pad = "Pad"
	case drums = "Drums"
	case bass = "Bass"
	
	var id: String { rawValue }
	
	var programNumber: UInt8 {
		switch self {
		case .piano: return 0
		case .electricPiano: return 4
		case .organ: return 16
		case .guitar: return 24
		case .strings: return 48
		case .lead: return 80
		case .pad: return 88
		case .drums: return 0 // Uses percussion bank
		case .bass: return 32 // Acoustic Bass
		}
	}
	
	var isDrumKit: Bool {
		self == .drums
	}
	
	var icon: String {
		switch self {
		case .piano: return "pianokeys"
		case .electricPiano: return "pianokeys.inverse"
		case .organ: return "music.note.house"
		case .guitar: return "guitars"
		case .strings: return "music.quarternote.3"
		case .lead: return "waveform"
		case .pad: return "waveform.path"
		case .drums: return "cylinder.split.1x2.fill"  // Represents drum shape
		case .bass: return "speaker.wave.2"
		}
	}
}


