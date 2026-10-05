import XCTest
@testable import Loopa

/// Every fixture belongs to a UUID temporary directory; never use shared storage.
final class SessionStorageSafetyTests: XCTestCase {
    private var directory: URL!
    private var storage: SessionStorage!
    private let corruptBytes = Data("{\"recoverable-original\": unfinished".utf8)

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionStorageSafety-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storage = SessionStorage(directoryURL: directory)
    }

    override func tearDownWithError() throws {
        storage = nil
        if let directory {
            try FileManager.default.removeItem(at: directory)
        }
        directory = nil
        try super.tearDownWithError()
    }

    private func session(_ name: String = "New beat", bpm: Double = 100) -> SavedSession {
        SavedSession(name: name, bpm: bpm, barCount: 4, tracks: [])
    }

    // These three controls call existing APIs and require only directory injection.
    // They must fail against the original destructive storage behavior.
    func testCorruptLibrarySurvivesSaveUsingExistingAPI() throws {
        let url = directory.appendingPathComponent("sessions.json")
        try corruptBytes.write(to: url, options: .atomic)

        storage.saveSession(session())

        XCTAssertEqual(try Data(contentsOf: url), corruptBytes)
    }

    func testCorruptWorkingFileSurvivesClearUsingExistingAPI() throws {
        let url = directory.appendingPathComponent("working_session.json")
        try corruptBytes.write(to: url, options: .atomic)

        _ = storage.loadWorkingSession()
        storage.clearWorkingSession()

        XCTAssertEqual(try? Data(contentsOf: url), corruptBytes)
    }

    func testCorruptWorkingFileSurvivesAutosaveUsingExistingAPI() throws {
        let url = directory.appendingPathComponent("working_session.json")
        try corruptBytes.write(to: url, options: .atomic)

        storage.saveWorkingSession(session())

        XCTAssertEqual(try Data(contentsOf: url), corruptBytes)
    }

    private func assertFailure<Value>(
        _ result: Result<Value, SessionStorageError>,
        operation: SessionStorageError.Operation,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        switch result {
        case .success:
            XCTFail("Expected an explicit \(operation) failure", file: file, line: line)
        case .failure(let error):
            XCTAssertEqual(error.operation, operation, file: file, line: line)
        }
    }

    func testMissingFilesAreExplicitEmptySuccessAndDoNotCreateFiles() throws {
        XCTAssertTrue(try storage.readSessionsResult().get().isEmpty)
        XCTAssertNil(try storage.readWorkingSessionResult().get())
        try storage.clearWorkingSession().get()
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    func testCorruptReadsAndEveryLibraryMutationReturnDecodeFailure() throws {
        let url = directory.appendingPathComponent("sessions.json")
        try corruptBytes.write(to: url, options: .atomic)
        let beat = session()

        assertFailure(storage.readSessionsResult(), operation: .decode)
        assertFailure(storage.saveSession(beat), operation: .decode)
        XCTAssertEqual(try Data(contentsOf: url), corruptBytes)
        assertFailure(storage.deleteSession(beat), operation: .decode)
        XCTAssertEqual(try Data(contentsOf: url), corruptBytes)
        assertFailure(storage.renameSession(beat, to: "Changed"), operation: .decode)
        XCTAssertEqual(try Data(contentsOf: url), corruptBytes)
    }

    func testCorruptWorkingReadSaveAndClearReturnDecodeFailure() throws {
        let url = directory.appendingPathComponent("working_session.json")
        try corruptBytes.write(to: url, options: .atomic)

        assertFailure(storage.readWorkingSessionResult(), operation: .decode)
        assertFailure(storage.saveWorkingSession(session()), operation: .decode)
        assertFailure(storage.clearWorkingSession(), operation: .decode)
        XCTAssertEqual(try Data(contentsOf: url), corruptBytes)
    }

    func testUnreadableFilesBlockWritesAndRemovalWithoutTreatingThemAsMissing() throws {
        let libraryURL = directory.appendingPathComponent("sessions.json")
        let workingURL = directory.appendingPathComponent("working_session.json")
        let original = session("Original")
        try storage.saveSession(original).get()
        try storage.saveWorkingSession(original).get()
        let libraryBytes = try Data(contentsOf: libraryURL)
        let workingBytes = try Data(contentsOf: workingURL)
        var writes = 0
        var removals = 0
        let unreadable = SessionStorage(directoryURL: directory, readData: { _ in
            throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.Code.fileReadNoPermission.rawValue)
        }, writeData: { _, _, _ in
            writes += 1
        }, removeFile: { _ in
            removals += 1
        })

        assertFailure(unreadable.readSessionsResult(), operation: .read)
        assertFailure(unreadable.readWorkingSessionResult(), operation: .read)
        assertFailure(unreadable.saveSession(session()), operation: .read)
        assertFailure(unreadable.deleteSession(original), operation: .read)
        assertFailure(unreadable.renameSession(original, to: "Changed"), operation: .read)
        assertFailure(unreadable.saveWorkingSession(session()), operation: .read)
        assertFailure(unreadable.clearWorkingSession(), operation: .read)
        XCTAssertEqual(writes, 0)
        XCTAssertEqual(removals, 0)
        XCTAssertEqual(try Data(contentsOf: libraryURL), libraryBytes)
        XCTAssertEqual(try Data(contentsOf: workingURL), workingBytes)
    }

    func testMatchingErrorCodeInAnotherDomainIsNotAMissingFile() {
        let unreadable = SessionStorage(directoryURL: directory, readData: { _ in
            throw NSError(domain: "StorageTestFailure", code: CocoaError.Code.fileReadNoSuchFile.rawValue)
        })
        assertFailure(unreadable.readSessionsResult(), operation: .read)
        assertFailure(unreadable.readWorkingSessionResult(), operation: .read)
    }

    func testSuccessfulAtomicReplacementsPreserveOtherSessionsAndSurviveReopen() throws {
        var first = session("First")
        first.lastModifiedAt = Date(timeIntervalSince1970: 100)
        var second = session("Second")
        second.lastModifiedAt = Date(timeIntervalSince1970: 200)
        try storage.saveSession(first).get()
        try storage.saveSession(second).get()
        XCTAssertEqual(try storage.readSessionsResult().get().map(\.id), [second.id, first.id])
        first.name = "Edited first"
        try storage.saveSession(first).get()
        try storage.saveWorkingSession(first).get()

        let reopened = SessionStorage(directoryURL: directory)
        let sessions = try reopened.readSessionsResult().get()
        XCTAssertEqual(sessions.map(\.id), [first.id, second.id])
        XCTAssertEqual(sessions[0].name, "Edited first")
        XCTAssertEqual(sessions[1].name, "Second")
        XCTAssertEqual(try reopened.readWorkingSessionResult().get()?.id, first.id)
        XCTAssertEqual(try reopened.readWorkingSessionResult().get()?.name, "Edited first")
    }

    func testRenameDeleteAndClearReportSuccessfulPersistence() throws {
        let first = session("First")
        let second = session("Second")
        try storage.saveSession(first).get()
        try storage.saveSession(second).get()
        try storage.renameSession(first, to: "Renamed").get()
        try storage.deleteSession(second).get()
        XCTAssertEqual(try storage.readSessionsResult().get().map(\.name), ["Renamed"])
        try storage.saveWorkingSession(first).get()
        try storage.clearWorkingSession().get()
        XCTAssertNil(try storage.readWorkingSessionResult().get())
    }

    func testEncodingFailureNeverCallsWriterAndKeepsPreviousValidBytes() throws {
        let original = session("Original")
        try storage.saveSession(original).get()
        try storage.saveWorkingSession(original).get()
        let libraryURL = directory.appendingPathComponent("sessions.json")
        let workingURL = directory.appendingPathComponent("working_session.json")
        let libraryBytes = try Data(contentsOf: libraryURL)
        let workingBytes = try Data(contentsOf: workingURL)
        var writes = 0
        let checked = SessionStorage(directoryURL: directory, writeData: { _, _, _ in writes += 1 })
        let invalid = session("Invalid", bpm: .nan)

        assertFailure(checked.saveSession(invalid), operation: .encode)
        assertFailure(checked.saveWorkingSession(invalid), operation: .encode)
        XCTAssertEqual(writes, 0)
        XCTAssertEqual(try Data(contentsOf: libraryURL), libraryBytes)
        XCTAssertEqual(try Data(contentsOf: workingURL), workingBytes)
    }

    func testInterruptedAtomicWriterKeepsCanonicalBytesAndReportsFailure() throws {
        let original = session("Original")
        try storage.saveSession(original).get()
        try storage.saveWorkingSession(original).get()
        let libraryURL = directory.appendingPathComponent("sessions.json")
        let workingURL = directory.appendingPathComponent("working_session.json")
        let libraryBytes = try Data(contentsOf: libraryURL)
        let workingBytes = try Data(contentsOf: workingURL)
        let directory = try XCTUnwrap(self.directory)
        var calls = 0
        let interrupted = SessionStorage(directoryURL: directory, writeData: { data, url, options in
            calls += 1
            XCTAssertTrue(options.contains(.atomic))
            // Model failure after partial auxiliary bytes but before promotion.
            // This is not a claim to test power loss inside Foundation itself.
            let auxiliary = directory.appendingPathComponent("partial-" + url.lastPathComponent)
            try Data(data.prefix(3)).write(to: auxiliary)
            throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.Code.fileWriteOutOfSpace.rawValue)
        })

        assertFailure(interrupted.saveSession(session("Replacement")), operation: .write)
        assertFailure(interrupted.saveWorkingSession(session("Replacement")), operation: .write)
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(try Data(contentsOf: libraryURL), libraryBytes)
        XCTAssertEqual(try Data(contentsOf: workingURL), workingBytes)
        let reopened = SessionStorage(directoryURL: directory)
        XCTAssertEqual(try reopened.readSessionsResult().get().map(\.id), [original.id])
        XCTAssertEqual(try reopened.readWorkingSessionResult().get()?.id, original.id)
    }

    func testWorkingFileRemovalFailureIsObservableAndPreservesBytes() throws {
        try storage.saveWorkingSession(session()).get()
        let url = directory.appendingPathComponent("working_session.json")
        let originalBytes = try Data(contentsOf: url)
        let failing = SessionStorage(directoryURL: directory, removeFile: { _ in
            throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.Code.fileWriteNoPermission.rawValue)
        })

        assertFailure(failing.clearWorkingSession(), operation: .remove)
        XCTAssertEqual(try Data(contentsOf: url), originalBytes)
    }
}
