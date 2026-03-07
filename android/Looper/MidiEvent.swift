import Foundation

/// Represents a single MIDI note event in a loop
struct MidiEvent: Codable, Hashable, Equatable {
	/// Time in seconds from loop start
	let time: Double
	
	/// MIDI note number (0-127)
	let note: UInt8
	
	/// Velocity (0-127, 0 typically indicates note off)
	let velocity: UInt8
	
	/// Whether this is a note on (true) or note off (false) event
	let isNoteOn: Bool
	
	/// Which side of the split keyboard (true = left, false = right)
	let isLeft: Bool
	
	/// Unique identifier for deduplication during playback
	var id: String {
		"\(time)-\(note)-\(isNoteOn)-\(isLeft)"
	}
}

