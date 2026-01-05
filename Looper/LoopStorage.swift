import Foundation

/// Represents a saved loop with metadata
struct SavedLoop: Codable, Identifiable {
	let id: UUID
	let name: String
	let createdAt: Date
	let loopLength: Double
	let bpm: Double
	let events: [MidiEvent]
	
	init(name: String, loopLength: Double, bpm: Double, events: [MidiEvent]) {
		self.id = UUID()
		self.name = name
		self.createdAt = Date()
		self.loopLength = loopLength
		self.bpm = bpm
		self.events = events
	}
}

/// Handles saving and loading loops to/from device storage
final class LoopStorage {
	
	private let fileManager = FileManager.default
	
	/// Directory where loops are stored
	private var loopsDirectory: URL {
		let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
		let dir = docs.appendingPathComponent("Loops", isDirectory: true)
		
		// Create directory if it doesn't exist
		if !fileManager.fileExists(atPath: dir.path) {
			try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
		}
		
		return dir
	}
	
	// MARK: - Save
	
	/// Save a loop to storage
	/// - Parameters:
	///   - events: MIDI events in the loop
	///   - name: User-provided name for the loop
	///   - loopLength: Duration in seconds
	///   - bpm: Tempo at time of recording
	/// - Returns: URL where the loop was saved
	@discardableResult
	func save(events: [MidiEvent], name: String, loopLength: Double, bpm: Double) throws -> URL {
		let loop = SavedLoop(name: name, loopLength: loopLength, bpm: bpm, events: events)
		let filename = "\(loop.id.uuidString).tishloop"
		let url = loopsDirectory.appendingPathComponent(filename)
		
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601
		let data = try encoder.encode(loop)
		try data.write(to: url, options: .atomic)
		
		return url
	}
	
	// MARK: - Load
	
	/// Load a loop from a URL
	func load(from url: URL) throws -> SavedLoop {
		let data = try Data(contentsOf: url)
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		return try decoder.decode(SavedLoop.self, from: data)
	}
	
	/// List all saved loops
	func listSavedLoops() -> [SavedLoop] {
		do {
			let files = try fileManager.contentsOfDirectory(at: loopsDirectory, includingPropertiesForKeys: nil)
			let loops = files
				.filter { $0.pathExtension == "tishloop" }
				.compactMap { try? load(from: $0) }
				.sorted { $0.createdAt > $1.createdAt } // Newest first
			return loops
		} catch {
			print("Error listing loops: \(error)")
			return []
		}
	}
	
	/// Delete a saved loop
	func delete(loop: SavedLoop) throws {
		let filename = "\(loop.id.uuidString).tishloop"
		let url = loopsDirectory.appendingPathComponent(filename)
		try fileManager.removeItem(at: url)
	}
	
	/// Delete a loop by URL
	func delete(at url: URL) throws {
		try fileManager.removeItem(at: url)
	}
}

