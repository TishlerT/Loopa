import XCTest
import Combine
@testable import Loopa

/// Persistence faults use test-owned files, never shared Documents.
final class SessionSaveFailureTests: XCTestCase {
    private var directory: URL!
    private var storage: SessionStorage!

    private final class Faults {
        var read = false
        var write = false
        var remove = false
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionSaveFailure-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storage = SessionStorage(directoryURL: directory)
    }

    override func tearDownWithError() throws {
        storage = nil
        if let directory { try FileManager.default.removeItem(at: directory) }
        directory = nil
        try super.tearDownWithError()
    }

    private func session(_ name: String = "Original") -> SavedSession {
        let track = Track(instrumentName: "Piano", instrumentProgram: 0, isDrumKit: false,
                          notes: [MidiNote(pitch: 60, velocity: 90, startBeat: 0, durationBeats: 1)])
        return SavedSession(name: name, bpm: 100, barCount: 4, tracks: [track])
    }

    private func faultStorage(_ faults: Faults) -> SessionStorage {
        SessionStorage(directoryURL: directory, readData: { url in
            if faults.read { throw CocoaError(.fileReadNoPermission) }
            return try Data(contentsOf: url)
        }, writeData: { data, url, options in
            if faults.write { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: url, options: options)
        }, removeFile: { url in
            if faults.remove { throw CocoaError(.fileWriteNoPermission) }
            try FileManager.default.removeItem(at: url)
        })
    }

    private func bytes(_ filename: String) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent(filename))
    }

    @MainActor
    private func waitForTracks(_ vm: LooperViewModel, _ session: SavedSession) async {
        let updated = expectation(description: "Forwarded tracks match the restored session")
        let subscription = vm.$tracks.first { $0.map(\.id) == session.tracks.map(\.id) }
            .sink { _ in updated.fulfill() }
        await fulfillment(of: [updated], timeout: 3)
        withExtendedLifetime(subscription) {}
    }

    @MainActor
    func testEmptyNamedSaveFailsWithoutFilesOrSuccessFeedback() throws {
        var feedback = 0
        let vm = LooperViewModel(storage: storage, persistenceSuccessFeedback: { feedback += 1 })
        XCTAssertFalse(vm.saveCurrentSession(name: "Empty"))
        XCTAssertNotNil(vm.persistenceError)
        XCTAssertEqual(vm.currentSessionName, "")
        XCTAssertEqual(feedback, 0)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @MainActor
    func testFailedNamedSaveKeepsIdentityTracksRecoveryAndRetriesSameSession() async throws {
        let original = session()
        try storage.saveSession(original).get()
        try storage.saveWorkingSession(original).get()
        let originalLibrary = try bytes("sessions.json")
        let originalRecovery = try bytes("working_session.json")
        let faults = Faults()
        var feedback = 0
        let vm = LooperViewModel(storage: faultStorage(faults), persistenceSuccessFeedback: { feedback += 1 })
        XCTAssertTrue(vm.restoreWorkingSession())
        await waitForTracks(vm, original)
        XCTAssertTrue(vm.loadSavedSessions())
        faults.write = true

        XCTAssertFalse(vm.saveCurrentSession(name: "Changed"))
        XCTAssertNotNil(vm.persistenceError)
        XCTAssertEqual(vm.currentSessionName, original.name)
        XCTAssertEqual(vm.looper.tracks.map(\.id), original.tracks.map(\.id))
        XCTAssertEqual(vm.savedSessions.map(\.name), [original.name])
        XCTAssertEqual(try bytes("sessions.json"), originalLibrary)
        XCTAssertEqual(try bytes("working_session.json"), originalRecovery)
        XCTAssertEqual(feedback, 0)

        faults.write = false
        XCTAssertTrue(vm.saveCurrentSession(name: "Changed"))
        XCTAssertNil(vm.persistenceError)
        let saved = try storage.readSessionsResult().get()
        XCTAssertEqual(saved.map(\.id), [original.id])
        XCTAssertEqual(saved.map(\.name), ["Changed"])
        XCTAssertNil(try storage.readWorkingSessionResult().get())
        XCTAssertEqual(feedback, 1)
    }

    @MainActor
    func testFailedLibraryReadPreservesPreviouslyLoadedList() throws {
        let original = session()
        try storage.saveSession(original).get()
        let faults = Faults()
        let vm = LooperViewModel(storage: faultStorage(faults))
        XCTAssertTrue(vm.loadSavedSessions())
        faults.read = true
        XCTAssertFalse(vm.loadSavedSessions())
        XCTAssertNotNil(vm.persistenceError)
        XCTAssertEqual(vm.savedSessions.map(\.id), [original.id])
    }

    @MainActor
    func testCorruptLibraryReadDoesNotBecomeAnEmptyList() throws {
        let original = session()
        try storage.saveSession(original).get()
        let vm = LooperViewModel(storage: storage)
        XCTAssertTrue(vm.loadSavedSessions())
        let corrupt = Data("broken library".utf8)
        try corrupt.write(to: directory.appendingPathComponent("sessions.json"))
        XCTAssertFalse(vm.loadSavedSessions())
        XCTAssertEqual(vm.savedSessions.map(\.id), [original.id])
        XCTAssertNotNil(vm.persistenceError)
        XCTAssertEqual(try bytes("sessions.json"), corrupt)
    }

    @MainActor
    func testDurableNamedSaveReturnsTrueWhenRecoveryCleanupFails() async throws {
        let original = session()
        try storage.saveWorkingSession(original).get()
        let recovery = try bytes("working_session.json")
        let faults = Faults()
        faults.remove = true
        var feedback = 0
        let vm = LooperViewModel(storage: faultStorage(faults), persistenceSuccessFeedback: { feedback += 1 })
        XCTAssertTrue(vm.restoreWorkingSession())
        await waitForTracks(vm, original)
        XCTAssertTrue(vm.saveCurrentSession(name: "Durable"))
        XCTAssertNotNil(vm.persistenceError, "Cleanup warning must remain visible after the named save succeeds")
        XCTAssertEqual(vm.currentSessionName, "Durable")
        XCTAssertEqual(try storage.readSessionsResult().get().map(\.id), [original.id])
        XCTAssertEqual(try storage.readSessionsResult().get().map(\.name), ["Durable"])
        XCTAssertEqual(try bytes("working_session.json"), recovery)
        XCTAssertEqual(feedback, 1)
    }

    @MainActor
    func testDurableNamedSaveKeepsListAndWarningWhenRefreshFails() async throws {
        let original = session()
        try storage.saveSession(original).get()
        try storage.saveWorkingSession(original).get()
        var blockLibraryRead = false
        let checkedStorage = SessionStorage(directoryURL: directory, readData: { url in
            if blockLibraryRead && url.lastPathComponent == "sessions.json" {
                throw CocoaError(.fileReadNoPermission)
            }
            return try Data(contentsOf: url)
        }, writeData: { data, url, options in
            try data.write(to: url, options: options)
            if url.lastPathComponent == "sessions.json" { blockLibraryRead = true }
        })
        var feedback = 0
        let vm = LooperViewModel(storage: checkedStorage, persistenceSuccessFeedback: { feedback += 1 })
        XCTAssertTrue(vm.loadSavedSessions())
        XCTAssertTrue(vm.restoreWorkingSession())
        await waitForTracks(vm, original)
        XCTAssertTrue(vm.saveCurrentSession(name: "Durable change"))
        XCTAssertNotNil(vm.persistenceError)
        XCTAssertEqual(vm.savedSessions.map(\.name), [original.name])
        XCTAssertEqual(try storage.readSessionsResult().get().map(\.name), ["Durable change"])
        XCTAssertEqual(vm.currentSessionName, "Durable change")
        XCTAssertNil(try storage.readWorkingSessionResult().get())
        XCTAssertEqual(feedback, 1)
    }

    @MainActor
    func testNamedSaveReadFailureDoesNotClearRecoveryOrChangeIdentity() async throws {
        let original = session()
        try storage.saveWorkingSession(original).get()
        let recovery = try bytes("working_session.json")
        let faults = Faults()
        var feedback = 0
        let vm = LooperViewModel(storage: faultStorage(faults), persistenceSuccessFeedback: { feedback += 1 })
        XCTAssertTrue(vm.restoreWorkingSession())
        await waitForTracks(vm, original)
        faults.read = true
        XCTAssertFalse(vm.saveCurrentSession(name: "Failed"))
        XCTAssertEqual(vm.currentSessionName, original.name)
        XCTAssertEqual(try bytes("working_session.json"), recovery)
        XCTAssertEqual(feedback, 0)
        XCTAssertNotNil(vm.persistenceError)
    }

    @MainActor
    func testFailedAutosaveKeepsPreviousRecoveryBytes() async throws {
        let original = session()
        try storage.saveWorkingSession(original).get()
        let recovery = try bytes("working_session.json")
        let faults = Faults()
        let vm = LooperViewModel(storage: faultStorage(faults))
        XCTAssertTrue(vm.restoreWorkingSession())
        await waitForTracks(vm, original)
        vm.currentSessionName = "Unsaved change"
        faults.write = true
        XCTAssertFalse(vm.saveWorkingSession())
        XCTAssertNotNil(vm.persistenceError)
        XCTAssertEqual(try bytes("working_session.json"), recovery)
        XCTAssertEqual(vm.looper.tracks.map(\.id), original.tracks.map(\.id))
        faults.write = false
        XCTAssertTrue(vm.saveWorkingSession())
        XCTAssertNil(vm.persistenceError)
        XCTAssertEqual(try storage.readWorkingSessionResult().get()?.id, original.id)
        XCTAssertEqual(try storage.readWorkingSessionResult().get()?.name, "Unsaved change")
    }

    @MainActor
    func testEmptyAutosaveCannotDeleteCorruptRecovery() throws {
        let corrupt = Data("unreadable recovery".utf8)
        try corrupt.write(to: directory.appendingPathComponent("working_session.json"))
        let vm = LooperViewModel(storage: storage)
        XCTAssertFalse(vm.saveWorkingSession())
        XCTAssertNotNil(vm.persistenceError)
        XCTAssertEqual(try bytes("working_session.json"), corrupt)
    }

    @MainActor
    func testCorruptRestorePreservesCurrentTracksAndName() async throws {
        let current = session()
        let vm = LooperViewModel(storage: storage)
        XCTAssertTrue(vm.loadSession(current))
        await waitForTracks(vm, current)
        let corrupt = Data("broken recovery".utf8)
        try corrupt.write(to: directory.appendingPathComponent("working_session.json"))
        XCTAssertFalse(vm.restoreWorkingSession())
        XCTAssertNotNil(vm.persistenceError)
        XCTAssertEqual(vm.currentSessionName, current.name)
        XCTAssertEqual(vm.looper.tracks.map(\.id), current.tracks.map(\.id))
        XCTAssertEqual(try bytes("working_session.json"), corrupt)
    }

    @MainActor
    func testUnreadableRestorePreservesCurrentTracksAndName() async throws {
        let current = session()
        let faults = Faults()
        let vm = LooperViewModel(storage: faultStorage(faults))
        XCTAssertTrue(vm.loadSession(current))
        await waitForTracks(vm, current)
        faults.read = true
        XCTAssertFalse(vm.restoreWorkingSession())
        XCTAssertNotNil(vm.persistenceError)
        XCTAssertEqual(vm.currentSessionName, current.name)
        XCTAssertEqual(vm.looper.tracks.map(\.id), current.tracks.map(\.id))
    }

    @MainActor
    func testMissingRestoreIsSuccessfulWithoutReplacingCurrentWork() async throws {
        let current = session()
        let vm = LooperViewModel(storage: storage)
        XCTAssertTrue(vm.loadSession(current))
        await waitForTracks(vm, current)
        XCTAssertTrue(vm.restoreWorkingSession())
        XCTAssertNil(vm.persistenceError)
        XCTAssertEqual(vm.currentSessionName, current.name)
        XCTAssertEqual(vm.looper.tracks.map(\.id), current.tracks.map(\.id))
    }

    @MainActor
    func testImmediateAutosaveAfterRestoreUsesAuthoritativeTracks() async throws {
        let original = session()
        try storage.saveWorkingSession(original).get()
        let vm = LooperViewModel(storage: storage)
        XCTAssertTrue(vm.restoreWorkingSession())
        // Deliberately do not wait for the forwarded Combine publication first.
        XCTAssertTrue(vm.saveWorkingSession())
        XCTAssertEqual(try storage.readWorkingSessionResult().get()?.tracks.map(\.id), original.tracks.map(\.id))
        XCTAssertTrue(vm.saveCurrentSession(name: "Immediate"))
        XCTAssertEqual(try storage.readSessionsResult().get().first?.id, original.id)
        await waitForTracks(vm, original)
    }

    @MainActor
    func testFailedClearKeepsLiveWorkIdentityAndRecovery() async throws {
        let original = session()
        try storage.saveWorkingSession(original).get()
        let recovery = try bytes("working_session.json")
        let faults = Faults()
        let vm = LooperViewModel(storage: faultStorage(faults))
        XCTAssertTrue(vm.restoreWorkingSession())
        await waitForTracks(vm, original)
        faults.remove = true
        XCTAssertFalse(vm.clearAll())
        XCTAssertNotNil(vm.persistenceError)
        XCTAssertEqual(vm.currentSessionName, original.name)
        XCTAssertEqual(vm.looper.tracks.map(\.id), original.tracks.map(\.id))
        XCTAssertEqual(try bytes("working_session.json"), recovery)
        faults.remove = false
        XCTAssertTrue(vm.saveCurrentSession(name: "Still original identity"))
        XCTAssertEqual(try storage.readSessionsResult().get().map(\.id), [original.id])
    }

    @MainActor
    func testSuccessfulClearRemovesRecoveryAndResetsIdentity() async throws {
        let original = session()
        try storage.saveWorkingSession(original).get()
        let vm = LooperViewModel(storage: storage)
        XCTAssertTrue(vm.restoreWorkingSession())
        await waitForTracks(vm, original)
        XCTAssertTrue(vm.clearAll())
        XCTAssertNil(vm.persistenceError)
        XCTAssertEqual(vm.currentSessionName, "")
        XCTAssertTrue(vm.looper.tracks.isEmpty)
        XCTAssertNil(try storage.readWorkingSessionResult().get())
        vm.looper.loadTracks(original.tracks)
        XCTAssertTrue(vm.saveCurrentSession(name: "New identity"))
        XCTAssertNotEqual(try storage.readSessionsResult().get().first?.id, original.id)
    }

    @MainActor
    func testFailedLoadCleanupDoesNotReplaceCurrentSession() async throws {
        let original = session()
        try storage.saveWorkingSession(original).get()
        let faults = Faults()
        let vm = LooperViewModel(storage: faultStorage(faults))
        XCTAssertTrue(vm.restoreWorkingSession())
        await waitForTracks(vm, original)
        faults.remove = true
        XCTAssertFalse(vm.loadSession(session("Other")))
        XCTAssertNotNil(vm.persistenceError)
        XCTAssertEqual(vm.currentSessionName, original.name)
        XCTAssertEqual(vm.looper.tracks.map(\.id), original.tracks.map(\.id))
        XCTAssertEqual(try storage.readWorkingSessionResult().get()?.id, original.id)
    }

    @MainActor
    func testFailedDeletePreservesSavedListAndFileThenRetries() throws {
        let original = session()
        try storage.saveSession(original).get()
        let library = try bytes("sessions.json")
        let faults = Faults()
        let vm = LooperViewModel(storage: faultStorage(faults))
        XCTAssertTrue(vm.loadSavedSessions())
        faults.write = true
        XCTAssertFalse(vm.deleteSession(original))
        XCTAssertNotNil(vm.persistenceError)
        XCTAssertEqual(vm.savedSessions.map(\.id), [original.id])
        XCTAssertEqual(try bytes("sessions.json"), library)
        faults.write = false
        XCTAssertTrue(vm.deleteSession(original))
        XCTAssertTrue(vm.savedSessions.isEmpty)
        XCTAssertNil(vm.persistenceError)
        XCTAssertTrue(try storage.readSessionsResult().get().isEmpty)
    }

    @MainActor
    func testFailedImportPreservesCurrentWorkRecoveryAndIdentity() async throws {
        let original = session()
        try storage.saveWorkingSession(original).get()
        let recovery = try bytes("working_session.json")
        let faults = Faults()
        var feedback = 0
        let vm = LooperViewModel(storage: faultStorage(faults), persistenceSuccessFeedback: { feedback += 1 })
        XCTAssertTrue(vm.restoreWorkingSession())
        await waitForTracks(vm, original)
        faults.write = true
        XCTAssertFalse(vm.loadImportedSession(session("Imported")))
        XCTAssertNotNil(vm.persistenceError)
        XCTAssertEqual(vm.currentSessionName, original.name)
        XCTAssertEqual(vm.looper.tracks.map(\.id), original.tracks.map(\.id))
        XCTAssertEqual(try bytes("working_session.json"), recovery)
        XCTAssertEqual(feedback, 0)
        faults.write = false
        XCTAssertTrue(vm.saveCurrentSession(name: "Original after failure"))
        XCTAssertEqual(try storage.readSessionsResult().get().map(\.id), [original.id])
    }

    @MainActor
    func testImportCleanupFailureKeepsCurrentWorkWithoutSuccessFeedback() async throws {
        let original = session()
        let imported = session("Imported")
        try storage.saveWorkingSession(original).get()
        let faults = Faults()
        faults.remove = true
        var feedback = 0
        let vm = LooperViewModel(storage: faultStorage(faults), persistenceSuccessFeedback: { feedback += 1 })
        XCTAssertTrue(vm.restoreWorkingSession())
        await waitForTracks(vm, original)
        XCTAssertFalse(vm.loadImportedSession(imported))
        XCTAssertNotNil(vm.persistenceError)
        XCTAssertEqual(vm.currentSessionName, original.name)
        XCTAssertEqual(vm.looper.tracks.map(\.id), original.tracks.map(\.id))
        XCTAssertEqual(try storage.readWorkingSessionResult().get()?.id, original.id)
        XCTAssertEqual(try storage.readSessionsResult().get().map(\.id), [imported.id], "The import is durable, but loading it was blocked")
        XCTAssertEqual(feedback, 0)
    }

    @MainActor
    func testSuccessfulImportLoadsDurableSessionAndKeepsImportedIdentity() async throws {
        let original = session()
        let imported = session("Imported")
        try storage.saveWorkingSession(original).get()
        var feedback = 0
        let vm = LooperViewModel(storage: storage, persistenceSuccessFeedback: { feedback += 1 })
        XCTAssertTrue(vm.restoreWorkingSession())
        await waitForTracks(vm, original)
        XCTAssertTrue(vm.loadImportedSession(imported))
        await waitForTracks(vm, imported)
        XCTAssertNil(vm.persistenceError)
        XCTAssertEqual(vm.currentSessionName, imported.name)
        XCTAssertEqual(vm.savedSessions.map(\.id), [imported.id])
        XCTAssertNil(try storage.readWorkingSessionResult().get())
        XCTAssertEqual(feedback, 1)
        XCTAssertTrue(vm.saveCurrentSession(name: "Edited import"))
        XCTAssertEqual(try storage.readSessionsResult().get().map(\.id), [imported.id])
    }
}
