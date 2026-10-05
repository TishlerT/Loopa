// Standalone, offline first; no packages or Xcode project required.
// xcrun swiftc -parse-as-library -D CREDENTIAL_STORE_TESTS \
//   CredentialStore.swift CredentialStoreTests.swift -o credential-store-tests
// ./credential-store-tests /absolute/path/to/production/credential-store
// Separate opt-in real Keychain smoke: ./credential-store-tests --keychain-smoke
// The smoke's account is generated inside the test-only factory; no account/service
// argument or environment override can direct it to production or another app.

import Foundation
import Security
import LocalAuthentication
import Darwin

private struct TestFailure: Error {}
private func require(_ condition: @autoclosure () throws -> Bool) throws {
    if try !condition() { throw TestFailure() }
}
private func expect(_ expected: CredentialStoreError, _ operation: () throws -> Void) throws {
    do { try operation() }
    catch let error as CredentialStoreError {
        try require(error == expected)
        return
    }
    throw TestFailure()
}
private func record(_ label: String = "synthetic-initial") throws -> CredentialRecord {
    try CredentialRecord(object: ["version": 1, "payload": ["accessToken": label, "refreshToken": label + "-refresh"]])
}
private func json(_ text: String) -> Data { Data(text.utf8) }

private final class FakeSecurity {
    var bytes: Data?
    var readStatus: OSStatus?
    var readValue: Any?
    var addStatus: OSStatus = errSecSuccess
    var updateStatus: OSStatus = errSecSuccess
    var deleteStatus: OSStatus = errSecSuccess
    var reads = 0
    var adds = 0
    var updates = 0
    var deletes = 0
    var validQueries = true

    private func inspect(_ query: [String: Any], read: Bool = false, add: Bool = false) {
        let context = query[kSecUseAuthenticationContext as String] as? LAContext
        let expected: Set<String> = [kSecClass as String, kSecAttrService as String,
            kSecAttrAccount as String, kSecAttrSynchronizable as String, kSecUseAuthenticationContext as String]
        var keys = expected
        if read { keys.formUnion([kSecMatchLimit as String, kSecReturnData as String]) }
        if add { keys.insert(kSecValueData as String) }
        validQueries = validQueries && Set(query.keys) == keys &&
            query[kSecClass as String] as? String == kSecClassGenericPassword as String &&
            query[kSecAttrService as String] as? String == "Loopa ChatGPT Local" &&
            query[kSecAttrAccount as String] as? String == "state-v1" &&
            query[kSecAttrSynchronizable as String] as? Bool == false && context?.interactionNotAllowed == true
        if read {
            validQueries = validQueries && query[kSecMatchLimit as String] as? String == kSecMatchLimitOne as String &&
                query[kSecReturnData as String] as? Bool == true
        }
    }
    var calls: CredentialSecurityCalls {
        CredentialSecurityCalls(copy: { [self] query in
            inspect(query, read: true); reads += 1
            if let readStatus { return (readStatus, readValue ?? bytes) }
            return (bytes == nil ? errSecItemNotFound : errSecSuccess, bytes)
        }, add: { [self] query in
            inspect(query, add: true); adds += 1
            guard addStatus == errSecSuccess else { return addStatus }
            guard bytes == nil else { return errSecDuplicateItem }
            bytes = query[kSecValueData as String] as? Data
            return errSecSuccess
        }, update: { [self] query, updatesDictionary in
            inspect(query); updates += 1
            validQueries = validQueries && Set(updatesDictionary.keys) == [kSecValueData as String]
            guard updateStatus == errSecSuccess else { return updateStatus }
            guard bytes != nil else { return errSecItemNotFound }
            bytes = updatesDictionary[kSecValueData as String] as? Data
            return errSecSuccess
        }, delete: { [self] query in
            inspect(query); deletes += 1
            guard deleteStatus == errSecSuccess else { return deleteStatus }
            guard bytes != nil else { return errSecItemNotFound }
            bytes = nil
            return errSecSuccess
        })
    }
    var store: CredentialStore { CredentialStore(security: calls) }
}

@main
private struct CredentialStoreTests {
    static var passed = 0
    static var failed = 0

    static func test(_ name: String, _ body: () throws -> Void) {
        do {
            try body()
            passed += 1
            print("PASS \(name)")
        } catch {
            failed += 1
            // Never stringify arbitrary errors, request data or credential records.
            print("FAIL \(name)")
        }
    }

    static func main() {
        signal(SIGPIPE, SIG_IGN)
        if CommandLine.arguments.count == 2, CommandLine.arguments[1] == "--keychain-smoke" {
            smoke()
            return
        }
        guard CommandLine.arguments.count == 2, CommandLine.arguments[1].hasPrefix("/") else {
            print("Usage: credential-store-tests <absolute helper path> OR --keychain-smoke")
            exit(2)
        }
        let helper = CommandLine.arguments[1]
        offline()
        ipc(helper)
        print("Offline tests: \(passed) passed, \(failed) failed. Real Keychain smoke is separate.")
        exit(failed == 0 ? 0 : 1)
    }

    static func offline() {
        test("record-roundtrip-and-fixed-query-scope") {
            let fake = FakeSecurity(); let original = try record()
            try fake.store.replace(original)
            try require(try fake.store.read().bytes == original.bytes)
            try require(fake.adds == 1 && fake.updates == 0 && fake.validQueries)
        }
        test("whole-record-replacement-retains-no-old-rotating-fields") {
            let fake = FakeSecurity(); fake.bytes = try record().bytes
            let next = try record("synthetic-rotated")
            try fake.store.replace(next)
            try require(fake.bytes == next.bytes && fake.updates == 1 && fake.adds == 0 && fake.deletes == 0 && fake.validQueries)
        }
        test("delete-valid-record") {
            let fake = FakeSecurity(); fake.bytes = try record().bytes
            try fake.store.delete()
            try require(fake.bytes == nil && fake.deletes == 1 && fake.validQueries)
        }
        test("read-missing-is-explicit") {
            try expect(.missing) { _ = try FakeSecurity().store.read() }
        }
        test("delete-missing-does-not-call-delete") {
            let fake = FakeSecurity()
            try expect(.missing) { try fake.store.delete() }
            try require(fake.deletes == 0)
        }
        for (name, status, error) in [
            ("denied", errSecAuthFailed, CredentialStoreError.denied),
            ("locked", errSecInteractionNotAllowed, .denied),
            ("cancelled", errSecUserCanceled, .denied),
            ("unavailable", errSecNotAvailable, .unavailable),
            ("unknown-status", OSStatus(-123456), .unavailable)
        ] {
            test("read-\(name)-prevents-all-mutations") {
                let fake = FakeSecurity(); let old = try record().bytes
                fake.bytes = old; fake.readStatus = status
                try expect(error) { try fake.store.replace(record("synthetic-new")) }
                try expect(error) { try fake.store.delete() }
                try require(fake.bytes == old && fake.adds == 0 && fake.updates == 0 && fake.deletes == 0)
            }
            test("update-\(name)-preserves-existing-record") {
                let fake = FakeSecurity(); let old = try record().bytes
                fake.bytes = old; fake.updateStatus = status
                try expect(error) { try fake.store.replace(record("synthetic-new")) }
                try require(fake.bytes == old && fake.updates == 1 && fake.adds == 0 && fake.deletes == 0)
            }
        }
        let corrupt: [(String, Data)] = [
            ("malformed", json("not-json")),
            ("unsupported-version", json("{\"version\":2,\"payload\":{}}")),
            ("unknown-envelope-key", json("{\"version\":1,\"payload\":{},\"extra\":true}")),
            ("duplicate-envelope-key", json("{\"version\":1,\"version\":1,\"payload\":{}}")),
            ("duplicate-nested-key", json("{\"version\":1,\"payload\":{\"key\":1,\"key\":2}}")),
            ("boolean-version", json("{\"version\":true,\"payload\":{}}")),
            ("oversized", Data(repeating: 65, count: CredentialRecord.maximumBytes + 1)),
            ("invalid-utf8", Data([0xff, 0xfe])),
        ]
        for (name, bytes) in corrupt {
            test("corrupt-\(name)-is-preserved") {
                let fake = FakeSecurity(); fake.bytes = bytes
                try expect(.corrupt) { _ = try fake.store.read() }
                try expect(.corrupt) { try fake.store.replace(record()) }
                try expect(.corrupt) { try fake.store.delete() }
                try require(fake.bytes == bytes && fake.updates == 0 && fake.adds == 0 && fake.deletes == 0)
            }
        }
        test("unexpected-keychain-type-is-corrupt") {
            let fake = FakeSecurity(); fake.readStatus = errSecSuccess; fake.readValue = "synthetic-data"
            try expect(.corrupt) { try fake.store.replace(record()) }
            try require(fake.updates == 0 && fake.adds == 0)
        }
        test("failed-add-does-not-update-or-delete") {
            let fake = FakeSecurity(); fake.addStatus = errSecAuthFailed
            try expect(.denied) { try fake.store.replace(record()) }
            try require(fake.bytes == nil && fake.adds == 1 && fake.updates == 0 && fake.deletes == 0)
        }
        test("concurrent-create-conflict-never-blindly-overwrites") {
            let fake = FakeSecurity(); let other = try record("synthetic-other-writer").bytes
            fake.bytes = other; fake.readStatus = errSecItemNotFound; fake.addStatus = errSecDuplicateItem
            try expect(.conflict) { try fake.store.replace(record()) }
            try require(fake.bytes == other && fake.updates == 0 && fake.deletes == 0)
        }
        test("concurrent-removal-during-update-is-conflict-not-add") {
            let fake = FakeSecurity(); fake.bytes = try record().bytes; fake.updateStatus = errSecItemNotFound
            try expect(.conflict) { try fake.store.replace(record()) }
            try require(fake.adds == 0 && fake.deletes == 0)
        }
        test("failed-delete-preserves-valid-record") {
            let fake = FakeSecurity(); let old = try record().bytes
            fake.bytes = old; fake.deleteStatus = errSecInteractionNotAllowed
            try expect(.denied) { try fake.store.delete() }
            try require(fake.bytes == old && fake.deletes == 1)
        }
        test("exact-64KiB-record-and-bounded-read-response") {
            let overhead = try CredentialRecord(object: ["version": 1, "payload": ["data": ""]]).bytes.count
            let large = try CredentialRecord(object: ["version": 1, "payload": ["data": String(repeating: "x", count: 65_536 - overhead)]])
            try require(large.bytes.count == 65_536)
            let fake = FakeSecurity(); fake.bytes = large.bytes
            let response = CredentialIPC.response(to: json("{\"op\":\"read\"}\n"), store: fake.store)
            try require(response.status == 0 && response.data.count <= CredentialIPC.maximumOutputBytes)
        }
        test("64KiB-plus-one-record-rejected") {
            let overhead = try CredentialRecord(object: ["version": 1, "payload": ["data": ""]]).bytes.count
            try expect(.tooLarge) {
                _ = try CredentialRecord(object: ["version": 1, "payload": ["data": String(repeating: "x", count: 65_537 - overhead)]])
            }
        }
        test("full-ipc-create-read-replace-delete-cycle-with-fake-security") {
            let fake = FakeSecurity()
            for label in ["synthetic-first", "synthetic-next"] {
                let value = try record(label)
                let input = json("{\"op\":\"replace\",\"record\":") + value.bytes + json("}\n")
                try require(CredentialIPC.response(to: input, store: fake.store).status == 0)
                let response = CredentialIPC.response(to: json("{\"op\":\"read\"}\n"), store: fake.store)
                let parsed = try JSONSerialization.jsonObject(with: response.data) as? [String: Any]
                try require(response.status == 0 && parsed?["ok"] as? Bool == true)
                try require(fake.bytes == value.bytes)
            }
            try require(CredentialIPC.response(to: json("{\"op\":\"delete\"}\n"), store: fake.store).status == 0)
            try require(fake.bytes == nil && fake.validQueries)
        }
        let invalid: [(String, Data)] = [
            ("empty", Data()), ("malformed", json("{")), ("array-root", json("[]")),
            ("unknown-operation", json("{\"op\":\"list\"}")),
            ("service-override", json("{\"op\":\"read\",\"service\":\"other\"}")),
            ("account-override", json("{\"op\":\"delete\",\"account\":\"other\"}")),
            ("missing-record", json("{\"op\":\"replace\"}")),
            ("null-record", json("{\"op\":\"replace\",\"record\":null}")),
            ("extra-record", json("{\"op\":\"read\",\"record\":{}}")),
            ("duplicate-operation", json("{\"op\":\"delete\",\"op\":\"read\"}")),
            ("escaped-duplicate-key", json("{\"op\":\"delete\",\"\\u006fp\":\"read\"}")),
            ("duplicate-payload-key", json("{\"op\":\"replace\",\"record\":{\"version\":1,\"payload\":{\"x\":1,\"x\":2}}}")),
            ("two-lines", json("{\"op\":\"read\"}\n{\"op\":\"delete\"}\n")),
            ("pretty-printed", json("{\n\"op\":\"read\"\n}")),
            ("trailing-value", json("{\"op\":\"read\"} false")),
            ("utf8-bom", Data([0xef, 0xbb, 0xbf]) + json("{\"op\":\"read\"}")),
            ("invalid-utf8", Data([0xff])),
            ("excessive-nesting", json("{\"op\":\"replace\",\"record\":{\"version\":1,\"payload\":{\"x\":" + String(repeating: "[", count: 40) + "0" + String(repeating: "]", count: 40) + "}}}"))
        ]
        for (name, input) in invalid {
            test("strict-ipc-\(name)-never-touches-security") {
                let fake = FakeSecurity(); let old = try record().bytes; fake.bytes = old
                let response = CredentialIPC.response(to: input, store: fake.store)
                try require(response.status == 1 && response.data == json("{\"ok\":false,\"error\":\"invalid_request\"}\n"))
                try require(fake.reads == 0 && fake.bytes == old && fake.updates == 0 && fake.adds == 0 && fake.deletes == 0)
            }
        }
        test("oversized-input-never-touches-security") {
            let fake = FakeSecurity()
            let result = CredentialIPC.response(to: Data(repeating: 32, count: CredentialIPC.maximumInputBytes + 1), store: fake.store)
            try require(result.data == json("{\"ok\":false,\"error\":\"too_large\"}\n") && fake.reads == 0)
        }
        test("unicode-and-escaped-control-values-are-roundtripped") {
            let fake = FakeSecurity()
            let input = json("{\"op\":\"replace\",\"record\":{\"version\":1,\"payload\":{\"label\":\"音楽🎵\\nquoted \\\"ok\\\"\"}}}\n")
            try require(CredentialIPC.response(to: input, store: fake.store).status == 0)
            try require(try fake.store.read().bytes == fake.bytes)
        }
        test("unknown-errors-are-sanitized-without-reflection") {
            struct SecretError: Error { let token = "synthetic-never-output" }
            let result = CredentialIPC.failure(SecretError())
            try require(result.data == json("{\"ok\":false,\"error\":\"unavailable\"}\n"))
        }
        test("descriptor-guard-rejects-network-sockets") {
            let descriptor = socket(AF_INET, SOCK_STREAM, 0)
            try require(descriptor >= 0)
            defer { close(descriptor) }
            try require(!CredentialIPC.isChildChannel(descriptor))
        }
        test("read-input-stops-at-cap-plus-one") {
            let pipe = Pipe()
            let payload = Data(repeating: 32, count: CredentialIPC.maximumInputBytes + 1)
            DispatchQueue.global().async {
                try? pipe.fileHandleForWriting.write(contentsOf: payload)
                try? pipe.fileHandleForWriting.close()
            }
            try expect(.tooLarge) { _ = try CredentialIPC.readInput(pipe.fileHandleForReading) }
            try pipe.fileHandleForReading.close()
        }
    }

    static func child(_ helper: String, input: Data, args: [String] = [], pipeInput: Bool = true, pipeOutput: Bool = true) throws -> (Int32, Data, Data) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: helper)
        process.arguments = args
        // Tests never place credential values in the environment; only synthetic
        // malformed inputs reach the production binary, avoiding production reads.
        process.environment = [:]
        let stdin = Pipe(); let stdout = Pipe(); let stderr = Pipe()
        process.standardInput = pipeInput ? stdin : FileHandle.nullDevice
        process.standardOutput = pipeOutput ? stdout : FileHandle.nullDevice
        process.standardError = stderr
        try process.run()
        if pipeInput {
            DispatchQueue.global().async {
                try? stdin.fileHandleForWriting.write(contentsOf: input)
                try? stdin.fileHandleForWriting.close()
            }
        }
        let output = pipeOutput ? stdout.fileHandleForReading.readDataToEndOfFile() : Data()
        let errors = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, output, errors)
    }
    static func socketChild(_ helper: String) throws -> (Int32, Data, Data) {
        func pair() throws -> (FileHandle, FileHandle) {
            var sockets: [Int32] = [-1, -1]
            guard socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets) == 0 else { throw TestFailure() }
            return (FileHandle(fileDescriptor: sockets[0], closeOnDealloc: true), FileHandle(fileDescriptor: sockets[1], closeOnDealloc: true))
        }
        let input = try pair(); let output = try pair(); let errors = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: helper)
        process.environment = [:]
        process.standardInput = input.1; process.standardOutput = output.1; process.standardError = errors
        try process.run()
        try input.1.close(); try output.1.close()
        try input.0.write(contentsOf: json("{\"op\":\"invalid\"}\n"))
        try input.0.close()
        let data = output.0.readDataToEndOfFile()
        let stderr = errors.fileHandleForReading.readDataToEndOfFile()
        try output.0.close()
        process.waitUntilExit()
        return (process.terminationStatus, data, stderr)
    }
    static func ipc(_ helper: String) {
        test("production-child-accepts-Node-compatible-anonymous-Unix-socketpairs") {
            let result = try socketChild(helper)
            try require(result.0 == 1 && result.1 == json("{\"ok\":false,\"error\":\"invalid_request\"}\n") && result.2.isEmpty)
        }
        test("production-child-rejects-unknown-operation-without-reflecting-input") {
            let result = try child(helper, input: json("{\"op\":\"synthetic-never-output\"}\n"))
            try require(result.0 == 1 && result.1 == json("{\"ok\":false,\"error\":\"invalid_request\"}\n") && result.2.isEmpty)
        }
        test("production-child-rejects-duplicate-operation-before-security") {
            let result = try child(helper, input: json("{\"op\":\"read\",\"op\":\"delete\"}\n"))
            try require(result.0 == 1 && result.1 == json("{\"ok\":false,\"error\":\"invalid_request\"}\n") && result.2.isEmpty)
        }
        test("production-child-caps-input-before-security") {
            let result = try child(helper, input: Data(repeating: 32, count: CredentialIPC.maximumInputBytes + 1))
            try require(result.0 == 1 && result.1 == json("{\"ok\":false,\"error\":\"too_large\"}\n") && result.2.isEmpty)
        }
        test("production-child-refuses-argv-options") {
            let result = try child(helper, input: Data(), args: ["--unexpected"])
            try require(result.0 == 1 && result.1 == json("{\"ok\":false,\"error\":\"invalid_request\"}\n") && result.2.isEmpty)
        }
        test("production-child-refuses-nonpipe-input") {
            let result = try child(helper, input: Data(), pipeInput: false)
            try require(result.0 == 2 && result.1.isEmpty && result.2.isEmpty)
        }
        test("production-child-refuses-nonpipe-output") {
            let result = try child(helper, input: Data(), pipeOutput: false)
            try require(result.0 == 2 && result.1.isEmpty && result.2.isEmpty)
        }
    }

    static func smoke() {
        var store: CredentialStore?
        var created = false
        do {
            let isolated = try CredentialStore.isolatedSmokeStore()
            store = isolated
            try expect(.missing) { _ = try isolated.read() }
            let initial = try record("synthetic-keychain-first")
            try isolated.replace(initial)
            created = true
            try require(try isolated.read().bytes == initial.bytes)
            let rotated = try record("synthetic-keychain-rotated")
            try isolated.replace(rotated)
            try require(try isolated.read().bytes == rotated.bytes)
            try isolated.delete()
            created = false
            try expect(.missing) { _ = try isolated.read() }
            print("PASS real Keychain synthetic unique-account create/read/replace/delete; cleanup verified; production account untouched.")
        } catch {
            let safe = error as? CredentialStoreError
            if created, let store {
                do { try store.delete(); print("Synthetic Keychain cleanup succeeded.") }
                catch { print("Synthetic Keychain cleanup failed; unique test item may remain.") }
            }
            print("FAIL real Keychain smoke: \(safe?.rawValue ?? "verification_failed"); no production account access.")
            exit(1)
        }
    }
}
