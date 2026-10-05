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
}
