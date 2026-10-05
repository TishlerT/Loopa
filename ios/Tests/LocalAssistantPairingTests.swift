import XCTest
import Foundation
import Darwin
@testable import Loopa

final class LocalAssistantPairingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private var capability: String {
        Data(repeating: 7, count: 32).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    private func document() -> [String: Any] {
        ["version": 1, "endpoint": "http://127.0.0.1:54321/", "capability": capability,
         "expires_at": 1_700_000_600_000 as Int64]
    }
    private func fixture(_ body: (URL, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("loopa-pair-test-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory, directory.appendingPathComponent(LocalAssistantPairing.filename))
    }
    private func write(_ data: Data, to file: URL, permissions: mode_t = 0o600) throws {
        try data.write(to: file)
        XCTAssertEqual(chmod(file.path, permissions), 0)
    }
    private func write(_ value: [String: Any], to file: URL) throws {
        try write(JSONSerialization.data(withJSONObject: value), to: file)
    }
    private func rejected(_ directory: URL, _ file: URL, data: Data, error: LocalAssistantPairing.Failure = .invalidPairing) throws {
        try write(data, to: file)
        XCTAssertThrowsError(try LocalAssistantPairing.consume(directory: directory, now: now)) {
            XCTAssertEqual($0 as? LocalAssistantPairing.Failure, error)
            XCTAssertFalse(String(describing: $0).contains(self.capability))
        }
        XCTAssertEqual(try Data(contentsOf: file), data, "Rejected input must not be consumed")
    }
    func testMissingFileReturnsNil() throws {
        try fixture { directory, _ in XCTAssertNil(try LocalAssistantPairing.consume(directory: directory, now: now)) }
    }
    func testValidPairingIsConsumedOnceAndRetainedAsValue() throws {
        try fixture { directory, file in
            try write(document(), to: file)
            let pairing = try XCTUnwrap(LocalAssistantPairing.consume(directory: directory, now: now))
            XCTAssertEqual(pairing.endpoint.absoluteString, "http://127.0.0.1:54321/")
            XCTAssertEqual(pairing.capability, capability)
            XCTAssertEqual(pairing.expiresAt.timeIntervalSince(now), 600, accuracy: 0.0001)
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
            XCTAssertNil(try LocalAssistantPairing.consume(directory: directory, now: now))
        }
    }
    func testExactLifetimeBoundaries() throws {
        for remaining in [1.0, 900_000.0] {
            try fixture { directory, file in
                var value = document(); value["expires_at"] = now.timeIntervalSince1970 * 1000 + remaining
                try write(value, to: file)
                XCTAssertNotNil(try LocalAssistantPairing.consume(directory: directory, now: now))
            }
        }
        for remaining in [-1.0, 0.0, 900_001.0] {
            try fixture { directory, file in
                var value = document(); value["expires_at"] = now.timeIntervalSince1970 * 1000 + remaining
                try rejected(directory, file, data: JSONSerialization.data(withJSONObject: value))
            }
        }
    }
    func testUnsafeEndpointsAreRejectedWithoutConsumption() throws {
        for endpoint in ["https://127.0.0.1:54321/", "http://localhost:54321/", "http://127.1:54321/",
                         "http://127.0.0.1:80/", "http://127.0.0.1:65536/", "http://127.0.0.1:054321/",
                         "http://127.0.0.1:54321", "http://127.0.0.1:54321/path", "http://127.0.0.1:54321/?a=b",
                         "http://127.0.0.1:54321/#x", "http://user@127.0.0.1:54321/", "http://[::1]:54321/",
                         "http://192.168.0.1:54321/", "file:///tmp/private"] {
            try fixture { directory, file in
                var value = document(); value["endpoint"] = endpoint
                try rejected(directory, file, data: JSONSerialization.data(withJSONObject: value))
            }
        }
    }
    func testPortBoundariesAreAccepted() throws {
        for port in [1024, 65535] {
            try fixture { directory, file in
                var value = document(); value["endpoint"] = "http://127.0.0.1:\(port)/"
                try write(value, to: file)
                XCTAssertNotNil(try LocalAssistantPairing.consume(directory: directory, now: now))
            }
        }
    }
    func testNoncanonicalCapabilitiesAreRejected() throws {
        for token in ["", capability + "=", String(capability.dropLast()), String(repeating: "x", count: 43),
                      String(repeating: "+", count: 43), String(repeating: "_", count: 43)] {
            try fixture { directory, file in
                var value = document(); value["capability"] = token
                try rejected(directory, file, data: JSONSerialization.data(withJSONObject: value))
            }
        }
    }
    func testUnknownMissingAndWrongTypedFieldsAreRejected() throws {
        let changes: [(inout [String: Any]) -> Void] = [
            { $0["version"] = true }, { $0["version"] = "1" }, { $0["version"] = 2 },
            { $0["expires_at"] = true }, { $0["expires_at"] = "1700000600000" },
            { $0["expires_at"] = 1_700_000_600_000.5 }, { $0["expires_at"] = NSNull() },
            { $0["capability"] = ["nested"] }, { $0["endpoint"] = 123 },
            { $0["extra"] = "SYNTHETIC_PRIVATE" }, { $0.removeValue(forKey: "version") }
        ]
        for change in changes {
            try fixture { directory, file in
                var value = document(); change(&value)
                try rejected(directory, file, data: JSONSerialization.data(withJSONObject: value))
            }
        }
    }
    func testMalformedDuplicateAndInvalidUTF8AreRejected() throws {
        let valid = String(data: try JSONSerialization.data(withJSONObject: document()), encoding: .utf8)!
        for data in [Data(), Data("{".utf8), Data("[]".utf8), Data((valid + "{}" ).utf8), Data([0xff]),
                     Data(("{\"version\":2," + valid.dropFirst()).utf8),
                     Data(("{\"\\u0076ersion\":1," + valid.dropFirst()).utf8),
                     Data([0xef,0xbb,0xbf]) + Data(valid.utf8)] {
            try fixture { directory, file in try rejected(directory, file, data: data) }
        }
    }
    func testExactByteCapAndOversize() throws {
        try fixture { directory, file in
            var data = try JSONSerialization.data(withJSONObject: document())
            data.append(Data(repeating: 32, count: 2048 - data.count))
            try write(data, to: file)
            XCTAssertNotNil(try LocalAssistantPairing.consume(directory: directory, now: now))
            data.append(32)
            try rejected(directory, file, data: data, error: .unsafeFile)
        }
    }
    func testGroupWorldAndSpecialPermissionsAreRejected() throws {
        for permissions: mode_t in [0o644, 0o640, 0o604, 0o666, 0o700, 0o1600] {
            try fixture { directory, file in
                try write(JSONSerialization.data(withJSONObject: document()), to: file, permissions: permissions)
                XCTAssertThrowsError(try LocalAssistantPairing.consume(directory: directory, now: now)) {
                    XCTAssertEqual($0 as? LocalAssistantPairing.Failure, .unsafeFile)
                }
                XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
            }
        }
    }
    func testNonownerMetadataIsRejected() throws {
        var info = stat(); info.st_mode = mode_t(S_IFREG | 0o600); info.st_nlink = 1; info.st_size = 100
        info.st_uid = geteuid() == 0 ? 1 : 0
        XCTAssertThrowsError(try LocalAssistantPairing.validateFileMetadata(info)) {
            XCTAssertEqual($0 as? LocalAssistantPairing.Failure, .unsafeFile)
        }
    }
    func testExtendedACLIsRejectedEvenWithPrivateMode() throws {
        try fixture { directory, file in
            try write(document(), to: file)
            let descriptor = open(file.path, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
            XCTAssertGreaterThanOrEqual(descriptor, 0)
            defer { close(descriptor) }
            var acl = acl_init(1)
            defer { if let acl { acl_free(UnsafeMutableRawPointer(acl)) } }
            var entry: acl_entry_t?
            XCTAssertEqual(acl_create_entry(&acl, &entry), 0)
            let value = try XCTUnwrap(entry)
            XCTAssertEqual(acl_set_tag_type(value, ACL_EXTENDED_ALLOW), 0)
            // A synthetic principal keeps this test independent of real accounts.
            var identity = UUID().uuid
            XCTAssertEqual(acl_set_qualifier(value, &identity), 0)
            var permissions: acl_permset_t?
            XCTAssertEqual(acl_get_permset(value, &permissions), 0)
            XCTAssertEqual(acl_add_perm(permissions, ACL_READ_DATA), 0)
            XCTAssertEqual(acl_set_fd(descriptor, acl), 0)
            var info = stat()
            XCTAssertEqual(fstat(descriptor, &info), 0)
            XCTAssertEqual(info.st_mode & 0o7777, 0o600)
            XCTAssertThrowsError(try LocalAssistantPairing.consume(directory: directory, now: now)) {
                XCTAssertEqual($0 as? LocalAssistantPairing.Failure, .unsafeFile)
            }
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        }
    }
    func testWritableByOthersDirectoryIsRejected() throws {
        try fixture { directory, file in
            try write(document(), to: file)
            XCTAssertEqual(chmod(directory.path, 0o770), 0)
            XCTAssertThrowsError(try LocalAssistantPairing.consume(directory: directory, now: now)) {
                XCTAssertEqual($0 as? LocalAssistantPairing.Failure, .unsafeFile)
            }
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        }
    }
    func testSymlinkAndHardLinkAreRejectedWithoutRemovingTarget() throws {
        try fixture { directory, file in
            let target = directory.appendingPathComponent("synthetic-target")
            try write(document(), to: target)
            XCTAssertEqual(symlink(target.path, file.path), 0)
            XCTAssertThrowsError(try LocalAssistantPairing.consume(directory: directory, now: now))
            XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
            XCTAssertEqual(unlink(file.path), 0)
            XCTAssertEqual(link(target.path, file.path), 0)
            XCTAssertThrowsError(try LocalAssistantPairing.consume(directory: directory, now: now))
            XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        }
    }
    func testDirectoryAndFIFOAreRejectedWithoutBlocking() throws {
        try fixture { directory, file in
            try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
            XCTAssertThrowsError(try LocalAssistantPairing.consume(directory: directory, now: now))
            try FileManager.default.removeItem(at: file)
            XCTAssertEqual(mkfifo(file.path, 0o600), 0)
            XCTAssertThrowsError(try LocalAssistantPairing.consume(directory: directory, now: now))
        }
    }
    func testPathSwapNeverDeletesReplacementOrReturnsOldCapability() throws {
        try fixture { directory, file in
            try write(document(), to: file)
            let original = directory.appendingPathComponent("original")
            let replacement = Data("SYNTHETIC_REPLACEMENT".utf8)
            XCTAssertThrowsError(try LocalAssistantPairing.consume(directory: directory, now: now, beforeUnlink: {
                XCTAssertEqual(rename(file.path, original.path), 0)
                try self.write(replacement, to: file)
            })) { XCTAssertEqual($0 as? LocalAssistantPairing.Failure, .fileChanged) }
            XCTAssertEqual(try Data(contentsOf: file), replacement)
            XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        }
    }
    func testSameInodeRewriteIsRejectedAndPreserved() throws {
        try fixture { directory, file in
            try write(document(), to: file)
            let replacement = Data("SYNTHETIC_CHANGED".utf8)
            XCTAssertThrowsError(try LocalAssistantPairing.consume(directory: directory, now: now, beforeUnlink: {
                let handle = try FileHandle(forWritingTo: file); defer { try? handle.close() }
                try handle.truncate(atOffset: 0); try handle.write(contentsOf: replacement)
            })) { XCTAssertEqual($0 as? LocalAssistantPairing.Failure, .fileChanged) }
            XCTAssertEqual(try Data(contentsOf: file), replacement)
        }
    }
    func testPathRemovalBeforeUnlinkRejects() throws {
        try fixture { directory, file in
            try write(document(), to: file)
            XCTAssertThrowsError(try LocalAssistantPairing.consume(directory: directory, now: now, beforeUnlink: {
                XCTAssertEqual(unlink(file.path), 0)
            })) { XCTAssertEqual($0 as? LocalAssistantPairing.Failure, .fileChanged) }
        }
    }
    func testSymlinkDirectoryAndInvalidClockAreRejected() throws {
        try fixture { directory, file in
            try write(document(), to: file)
            let alias = directory.appendingPathComponent("alias")
            XCTAssertEqual(symlink(directory.path, alias.path), 0)
            XCTAssertThrowsError(try LocalAssistantPairing.consume(directory: alias, now: now))
            XCTAssertThrowsError(try LocalAssistantPairing.consume(directory: directory, now: Date(timeIntervalSince1970: .nan)))
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        }
    }
    func testProductionEntryIsDisabledOutsideSimulator() throws {
        #if !targetEnvironment(simulator)
        XCTAssertNil(try LocalAssistantPairing.consume())
        #endif
    }
}
