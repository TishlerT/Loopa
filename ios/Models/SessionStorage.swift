import Foundation

/// Manages saving and loading of loop sessions
final class SessionStorage {
	static let shared = SessionStorage()
	
	private let sessionsKey = "savedSessions"
	private let fileManager = FileManager.default
	
	private var sessionsURL: URL {
		let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
		return documents.appendingPathComponent("sessions.json")
	}
	
	/// URL for the auto-saved working session (separate from named sessions)
	private var workingSessionURL: URL {
		let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
		return documents.appendingPathComponent("working_session.json")
	}
	
	private init() {}
	
	// MARK: - Public API
	
	/// Get all saved sessions
	func loadSessions() -> [SavedSession] {
		guard fileManager.fileExists(atPath: sessionsURL.path) else {
			return []
		}
		
		do {
			let data = try Data(contentsOf: sessionsURL)
			let sessions = try JSONDecoder().decode([SavedSession].self, from: data)
			return sessions.sorted { $0.lastModifiedAt > $1.lastModifiedAt }
		} catch {
			print("❌ Failed to load sessions: \(error)")
			return []
		}
	}
	
	/// Save a new session or update existing
	func saveSession(_ session: SavedSession) {
		var sessions = loadSessions()
		
		if let index = sessions.firstIndex(where: { $0.id == session.id }) {
			// Update existing
			var updated = session
			updated.lastModifiedAt = Date()
			sessions[index] = updated
		} else {
			// Add new
			sessions.insert(session, at: 0)
		}
		
		writeSessions(sessions)
	}
	
	/// Delete a session
	func deleteSession(_ session: SavedSession) {
		var sessions = loadSessions()
		sessions.removeAll { $0.id == session.id }
		writeSessions(sessions)
	}
	
	/// Rename a session
	func renameSession(_ session: SavedSession, to newName: String) {
		var sessions = loadSessions()
		if let index = sessions.firstIndex(where: { $0.id == session.id }) {
			sessions[index].name = newName
			sessions[index].lastModifiedAt = Date()
			writeSessions(sessions)
		}
	}
	
	// MARK: - Working Session (Auto-Save)
	
	/// Save the current working session for auto-restore
	func saveWorkingSession(_ session: SavedSession) {
		do {
			let data = try JSONEncoder().encode(session)
			try data.write(to: workingSessionURL)
			print("✓ Auto-saved working session")
		} catch {
			print("❌ Failed to auto-save working session: \(error)")
		}
	}
	
	/// Load the auto-saved working session (if any)
	func loadWorkingSession() -> SavedSession? {
		guard fileManager.fileExists(atPath: workingSessionURL.path) else {
			return nil
		}
		
		do {
			let data = try Data(contentsOf: workingSessionURL)
			let session = try JSONDecoder().decode(SavedSession.self, from: data)
			return session
		} catch {
			print("❌ Failed to load working session: \(error)")
			return nil
		}
	}
	
	/// Clear the auto-saved working session
	func clearWorkingSession() {
		guard fileManager.fileExists(atPath: workingSessionURL.path) else {
			return
		}
		
		do {
			try fileManager.removeItem(at: workingSessionURL)
			print("✓ Cleared working session")
		} catch {
			print("❌ Failed to clear working session: \(error)")
		}
	}
	
	// MARK: - Private
	
	private func writeSessions(_ sessions: [SavedSession]) {
		do {
			let data = try JSONEncoder().encode(sessions)
			try data.write(to: sessionsURL)
			print("✓ Saved \(sessions.count) sessions")
		} catch {
			print("❌ Failed to save sessions: \(error)")
		}
	}
}

