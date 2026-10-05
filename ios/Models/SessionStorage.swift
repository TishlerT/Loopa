import Foundation

/// An observable failure at the persistence boundary, never an empty-state success.
struct SessionStorageError: Error, LocalizedError {
    enum Operation: String {
        case read, decode, encode, write, remove
    }

    let operation: Operation
    let fileURL: URL
    let underlyingError: Error

    var errorDescription: String? {
        switch operation {
        case .read, .decode:
            return "Loopa couldn't read the saved session file. The existing file was kept."
        case .encode, .write:
            return "Loopa couldn't save this session. Keep it open and try again."
        case .remove:
            return "Loopa couldn't clear the recovery session. Please try again."
        }
    }
}

/// Manages the existing JSON session files without replacing unreadable data.
/// Callers must consume mutation results before clearing recovery or showing success.
final class SessionStorage {
    static let shared = SessionStorage()

    typealias ReadData = (URL) throws -> Data
    typealias WriteData = (Data, URL, Data.WritingOptions) throws -> Void
    typealias RemoveFile = (URL) throws -> Void

    private let directoryURL: URL
    private let readData: ReadData
    private let writeData: WriteData
    private let removeFile: RemoveFile

    private var sessionsURL: URL {
        directoryURL.appendingPathComponent("sessions.json")
    }

    private var workingSessionURL: URL {
        directoryURL.appendingPathComponent("working_session.json")
    }

    private convenience init() {
        self.init(directoryURL: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0])
    }

    /// The directory must already exist. Tests supply their own temporary directory.
    /// Injected writers must honor the supplied atomic replacement option.
    init(
        directoryURL: URL,
        readData: @escaping ReadData = { try Data(contentsOf: $0) },
        writeData: @escaping WriteData = { try $0.write(to: $1, options: $2) },
        removeFile: @escaping RemoveFile = { try FileManager.default.removeItem(at: $0) }
    ) {
        self.directoryURL = directoryURL
        self.readData = readData
        self.writeData = writeData
        self.removeFile = removeFile
    }

    // MARK: - Explicit read outcomes

    /// Only an absent file is an empty library. Read/decode failures remain failures.
    func readSessionsResult() -> Result<[SavedSession], SessionStorageError> {
        read([SavedSession].self, from: sessionsURL).map { sessions in
            (sessions ?? []).sorted { $0.lastModifiedAt > $1.lastModifiedAt }
        }
    }

    /// Only an absent file is a successful nil working session.
    func readWorkingSessionResult() -> Result<SavedSession?, SessionStorageError> {
        read(SavedSession.self, from: workingSessionURL)
    }

    /// Compatibility for existing callers. New recovery flows must use the Result API.
    func loadSessions() -> [SavedSession] {
        switch readSessionsResult() {
        case .success(let sessions): return sessions
        case .failure(let error):
            print("Failed to load sessions: \(error.localizedDescription)")
            return []
        }
    }

    /// Compatibility for existing callers. Storage mutations never use this fallback.
    func loadWorkingSession() -> SavedSession? {
        switch readWorkingSessionResult() {
        case .success(let session): return session
        case .failure(let error):
            print("Failed to load working session: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Named sessions

    @discardableResult
    func saveSession(_ session: SavedSession) -> Result<Void, SessionStorageError> {
        readSessionsResult().flatMap { existing in
            var sessions = existing
            if let index = sessions.firstIndex(where: { $0.id == session.id }) {
                var updated = session
                updated.lastModifiedAt = Date()
                sessions[index] = updated
            } else {
                sessions.insert(session, at: 0)
            }
            return write(sessions, to: sessionsURL)
        }
    }

    @discardableResult
    func deleteSession(_ session: SavedSession) -> Result<Void, SessionStorageError> {
        readSessionsResult().flatMap { existing in
            let sessions = existing.filter { $0.id != session.id }
            return write(sessions, to: sessionsURL)
        }
    }

    @discardableResult
    func renameSession(_ session: SavedSession, to newName: String) -> Result<Void, SessionStorageError> {
        readSessionsResult().flatMap { existing in
            var sessions = existing
            guard let index = sessions.firstIndex(where: { $0.id == session.id }) else {
                return .success(()) // Preserve the existing no-op for unknown IDs.
            }
            sessions[index].name = newName
            sessions[index].lastModifiedAt = Date()
            return write(sessions, to: sessionsURL)
        }
    }

    // MARK: - Working session

    @discardableResult
    func saveWorkingSession(_ session: SavedSession) -> Result<Void, SessionStorageError> {
        // A failed restore is not permission to overwrite the only recovery bytes.
        readWorkingSessionResult().flatMap { _ in
            write(session, to: workingSessionURL)
        }
    }

    @discardableResult
    func clearWorkingSession() -> Result<Void, SessionStorageError> {
        readWorkingSessionResult().flatMap { existing in
            guard existing != nil else { return .success(()) }
            do {
                try removeFile(workingSessionURL)
                return .success(())
            } catch {
                return .failure(SessionStorageError(operation: .remove, fileURL: workingSessionURL, underlyingError: error))
            }
        }
    }

    // MARK: - File boundary

    private func read<Value: Decodable>(_ type: Value.Type, from url: URL) -> Result<Value?, SessionStorageError> {
        let data: Data
        do {
            data = try readData(url)
        } catch {
            let fileError = error as NSError
            if fileError.domain == NSCocoaErrorDomain && fileError.code == CocoaError.Code.fileReadNoSuchFile.rawValue {
                return .success(nil)
            }
            return .failure(SessionStorageError(operation: .read, fileURL: url, underlyingError: error))
        }
        do {
            return .success(try JSONDecoder().decode(type, from: data))
        } catch {
            return .failure(SessionStorageError(operation: .decode, fileURL: url, underlyingError: error))
        }
    }

    private func write<Value: Encodable>(_ value: Value, to url: URL) -> Result<Void, SessionStorageError> {
        let data: Data
        do {
            data = try JSONEncoder().encode(value)
        } catch {
            return .failure(SessionStorageError(operation: .encode, fileURL: url, underlyingError: error))
        }
        do {
            // Foundation writes an auxiliary file before replacing the destination.
            // Never remove/truncate the destination before this operation succeeds.
            try writeData(data, url, .atomic)
            return .success(())
        } catch {
            return .failure(SessionStorageError(operation: .write, fileURL: url, underlyingError: error))
        }
    }
}
