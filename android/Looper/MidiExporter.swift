import Foundation

/// Exports MidiEvents to Standard MIDI File format
struct MidiExporter {
	
	/// Ticks per quarter note (standard MIDI resolution)
	static let ticksPerQuarterNote: UInt16 = 480
	
	/// Export events to MIDI file data
	/// - Parameters:
	///   - events: Array of MIDI events to export
	///   - bpm: Tempo in beats per minute
	///   - loopLength: Total loop length in seconds (for calculating proper durations)
	/// - Returns: Data representing a Standard MIDI File (Type 0)
	static func export(events: [MidiEvent], bpm: Double, loopLength: Double) -> Data {
		var data = Data()
		
		// MIDI Header chunk
		data.append(contentsOf: midiHeader())
		
		// MIDI Track chunk
		let trackData = buildTrack(events: events, bpm: bpm, loopLength: loopLength)
		data.append(contentsOf: trackData)
		
		return data
	}
	
	/// Save events to a MIDI file
	/// - Parameters:
	///   - events: Array of MIDI events
	///   - bpm: Tempo
	///   - loopLength: Loop duration in seconds
	///   - name: Filename (without extension)
	/// - Returns: URL of saved file
	static func saveToFile(events: [MidiEvent], bpm: Double, loopLength: Double, name: String) throws -> URL {
		let data = export(events: events, bpm: bpm, loopLength: loopLength)
		
		let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
		let midiDir = docs.appendingPathComponent("MIDI Exports", isDirectory: true)
		
		if !FileManager.default.fileExists(atPath: midiDir.path) {
			try FileManager.default.createDirectory(at: midiDir, withIntermediateDirectories: true)
		}
		
		let filename = "\(name).mid"
		let url = midiDir.appendingPathComponent(filename)
		try data.write(to: url, options: .atomic)
		
		return url
	}
	
	// MARK: - Private Helpers
	
	/// Create MIDI file header chunk
	private static func midiHeader() -> [UInt8] {
		var header: [UInt8] = []
		
		// "MThd" - header chunk type
		header.append(contentsOf: [0x4D, 0x54, 0x68, 0x64])
		
		// Chunk length (always 6 for header)
		header.append(contentsOf: [0x00, 0x00, 0x00, 0x06])
		
		// Format type 0 (single track)
		header.append(contentsOf: [0x00, 0x00])
		
		// Number of tracks (1)
		header.append(contentsOf: [0x00, 0x01])
		
		// Division (ticks per quarter note)
		header.append(UInt8(ticksPerQuarterNote >> 8))
		header.append(UInt8(ticksPerQuarterNote & 0xFF))
		
		return header
	}
	
	/// Build track chunk from events
	private static func buildTrack(events: [MidiEvent], bpm: Double, loopLength: Double) -> [UInt8] {
		var trackEvents: [UInt8] = []
		
		// Add tempo meta event at start
		trackEvents.append(contentsOf: tempoEvent(bpm: bpm))
		
		// Convert events to MIDI format
		let secondsPerTick = 60.0 / (bpm * Double(ticksPerQuarterNote))
		
		// Sort events by time
		let sortedEvents = events.sorted { $0.time < $1.time }
		
		var lastTick: UInt32 = 0
		
		for event in sortedEvents {
			let eventTick = UInt32(event.time / secondsPerTick)
			let deltaTicks = eventTick > lastTick ? eventTick - lastTick : 0
			
			// Variable-length delta time
			trackEvents.append(contentsOf: variableLengthQuantity(deltaTicks))
			
			// Note On/Off event
			// Channel 0 for left, Channel 1 for right
			let channel: UInt8 = event.isLeft ? 0 : 1
			
			if event.isNoteOn {
				// Note On: 0x9n nn vv
				trackEvents.append(0x90 | channel)
				trackEvents.append(event.note)
				trackEvents.append(event.velocity)
			} else {
				// Note Off: 0x8n nn vv
				trackEvents.append(0x80 | channel)
				trackEvents.append(event.note)
				trackEvents.append(0x00) // Release velocity
			}
			
			lastTick = eventTick
		}
		
		// End of track meta event
		trackEvents.append(contentsOf: [0x00, 0xFF, 0x2F, 0x00])
		
		// Build full track chunk
		var track: [UInt8] = []
		
		// "MTrk" - track chunk type
		track.append(contentsOf: [0x4D, 0x54, 0x72, 0x6B])
		
		// Track length
		let length = UInt32(trackEvents.count)
		track.append(UInt8((length >> 24) & 0xFF))
		track.append(UInt8((length >> 16) & 0xFF))
		track.append(UInt8((length >> 8) & 0xFF))
		track.append(UInt8(length & 0xFF))
		
		// Track events
		track.append(contentsOf: trackEvents)
		
		return track
	}
	
	/// Create tempo meta event
	private static func tempoEvent(bpm: Double) -> [UInt8] {
		// Tempo meta event: FF 51 03 tt tt tt
		// tt tt tt = microseconds per quarter note
		let microsecondsPerQuarter = UInt32(60_000_000 / bpm)
		
		return [
			0x00, // Delta time
			0xFF, 0x51, 0x03, // Meta event: tempo
			UInt8((microsecondsPerQuarter >> 16) & 0xFF),
			UInt8((microsecondsPerQuarter >> 8) & 0xFF),
			UInt8(microsecondsPerQuarter & 0xFF)
		]
	}
	
	/// Convert value to MIDI variable-length quantity
	private static func variableLengthQuantity(_ value: UInt32) -> [UInt8] {
		if value == 0 {
			return [0x00]
		}
		
		var result: [UInt8] = []
		var remaining = value
		
		// Build bytes in reverse order
		result.append(UInt8(remaining & 0x7F))
		remaining >>= 7
		
		while remaining > 0 {
			result.insert(UInt8((remaining & 0x7F) | 0x80), at: 0)
			remaining >>= 7
		}
		
		return result
	}
}

