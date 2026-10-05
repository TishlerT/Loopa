// App-owned OAuth storage only. Never reads another application's credentials.
// Build: xcrun swiftc -parse-as-library CredentialStore.swift -o credential-store
// IPC: one compact UTF-8 JSON line followed by EOF, over private child pipes.
// Anonymous Unix stream socketpairs used by Node/libuv stdio are also accepted.
//   {"op":"read"} -> {"ok":true,"record":{"version":1,"payload":{...}}}
//   {"op":"replace","record":{"version":1,"payload":{...}}} -> {"ok":true}
//   {"op":"delete"} -> {"ok":true}
// Failure: {"ok":false,"error":"<CredentialStoreError raw value>"}, exit 1.
// Missing read/delete is an error. Replace creates only after verified absence.
// Record envelope is fixed; payload schema belongs to the trusted Node repository.
// Node must be the sole writer and serialize read/modify/write across its helpers.
// Each SecItemUpdate replaces the WHOLE blob atomically; read + update is NOT CAS.
// Check cancellation before dispatching a replacement. Once dispatched, cancellation,
// child death or broken output does NOT imply rollback: re-read to reconcile state.
// Persistence is not permission to activate an account or perform inference.
// No secret argv, environment variables, files, diagnostics or generic store API.

import Foundation
import Security
import LocalAuthentication
import Darwin

// The complete stored envelope, rather than just the token fields, is capped.
enum CredentialStoreError: String, Error {
    case invalidRequest = "invalid_request"
    case tooLarge = "too_large"
    case missing, denied, corrupt, conflict, unavailable
    case ioFailure = "io_failure"
}

struct CredentialRecord {
    static let maximumBytes = 65_536
    let bytes: Data

    init(bytes: Data) throws {
        guard bytes.count <= Self.maximumBytes else { throw CredentialStoreError.tooLarge }
        let value = try StrictJSON.object(bytes)
        try self.init(object: value)
    }

    init(object: [String: Any]) throws {
        guard Set(object.keys) == ["version", "payload"],
              let version = object["version"] as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(), version == 1,
              object["payload"] is [String: Any], JSONSerialization.isValidJSONObject(object)
        else { throw CredentialStoreError.invalidRequest }
        let encoded: Data
        do { encoded = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) }
        catch { throw CredentialStoreError.invalidRequest }
        guard encoded.count <= Self.maximumBytes else { throw CredentialStoreError.tooLarge }
        self.bytes = encoded
    }
}

// Foundation accepts duplicate JSON keys. Reject them, including differently escaped
// spellings of the same key, before allowing Foundation to build the value tree.
private struct StrictJSON {
    private let bytes: [UInt8]
    private var offset = 0
    private static let maximumDepth = 32

    static func object(_ data: Data) throws -> [String: Any] {
        guard String(data: data, encoding: .utf8) != nil else { throw CredentialStoreError.invalidRequest }
        var parser = StrictJSON(bytes: Array(data))
        parser.whitespace()
        guard parser.offset < parser.bytes.count, parser.bytes[parser.offset] == 123 else { throw CredentialStoreError.invalidRequest }
        try parser.value(depth: 0)
        parser.whitespace()
        guard parser.offset == parser.bytes.count else { throw CredentialStoreError.invalidRequest }
        do {
            guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CredentialStoreError.invalidRequest
            }
            return value
        } catch { throw CredentialStoreError.invalidRequest }
    }

    private mutating func whitespace() {
        while offset < bytes.count && [9, 10, 13, 32].contains(bytes[offset]) { offset += 1 }
    }
    private mutating func consume(_ byte: UInt8) -> Bool {
        whitespace()
        guard offset < bytes.count, bytes[offset] == byte else { return false }
        offset += 1
        return true
    }
    private mutating func string() throws -> String {
        whitespace()
        let start = offset
        guard offset < bytes.count, bytes[offset] == 34 else { throw CredentialStoreError.invalidRequest }
        offset += 1
        while offset < bytes.count {
            let byte = bytes[offset]
            offset += 1
            if byte == 34 {
                let quoted = Data([91] + Array(bytes[start..<offset]) + [93])
                guard let array = try? JSONSerialization.jsonObject(with: quoted) as? [String], let text = array.first else {
                    throw CredentialStoreError.invalidRequest
                }
                return text
            }
            if byte == 92 {
                guard offset < bytes.count else { throw CredentialStoreError.invalidRequest }
                offset += 1
            } else if byte < 32 { throw CredentialStoreError.invalidRequest }
        }
        throw CredentialStoreError.invalidRequest
    }
    private mutating func value(depth: Int) throws {
        guard depth <= Self.maximumDepth else { throw CredentialStoreError.invalidRequest }
        whitespace()
        guard offset < bytes.count else { throw CredentialStoreError.invalidRequest }
        switch bytes[offset] {
        case 123:
            offset += 1
            if consume(125) { return }
            var keys = Set<String>()
            repeat {
                let key = try string()
                guard keys.insert(key).inserted, consume(58) else { throw CredentialStoreError.invalidRequest }
                try value(depth: depth + 1)
                if consume(125) { return }
                guard consume(44) else { throw CredentialStoreError.invalidRequest }
            } while true
        case 91:
            offset += 1
            if consume(93) { return }
            repeat {
                try value(depth: depth + 1)
                if consume(93) { return }
                guard consume(44) else { throw CredentialStoreError.invalidRequest }
            } while true
        case 34: _ = try string()
        default:
            let start = offset
            while offset < bytes.count && ![9, 10, 13, 32, 44, 93, 125].contains(bytes[offset]) { offset += 1 }
            guard offset > start else { throw CredentialStoreError.invalidRequest }
            // Foundation validates primitive spellings and number ranges below.
        }
    }
}

// Injection is at the Security call boundary; tests inspect every query and model
// failure without reading or modifying any real Keychain item.
struct CredentialSecurityCalls {
    let copy: ([String: Any]) -> (OSStatus, Any?)
    let add: ([String: Any]) -> OSStatus
    let update: ([String: Any], [String: Any]) -> OSStatus
    let delete: ([String: Any]) -> OSStatus

    static func system() throws -> Self {
        // Legacy macOS default Keychain, encrypted by macOS and explicitly not synced.
        // Disabling interaction in this single-purpose child prevents UI hangs. This
        // does not claim Data Protection / ThisDeviceOnly semantics or add entitlements.
        guard SecKeychainSetUserInteractionAllowed(false) == errSecSuccess else {
            throw CredentialStoreError.unavailable
        }
        var keychain: SecKeychain?
        guard SecKeychainCopyDefault(&keychain) == errSecSuccess, let keychain else {
            throw CredentialStoreError.unavailable
        }
        // Scope every operation to the SAME default Keychain. Never search across
        // multiple keychains, where update/delete could touch several same-name items.
        func scoped(_ query: [String: Any], adding: Bool = false) -> CFDictionary {
            var value = query
            if adding { value[kSecUseKeychain as String] = keychain }
            else { value[kSecMatchSearchList as String] = [keychain] }
            return value as CFDictionary
        }
        return Self(copy: { query in
            var result: CFTypeRef?
            let status = SecItemCopyMatching(scoped(query), &result)
            return (status, result)
        }, add: { SecItemAdd(scoped($0, adding: true), nil) },
        update: { SecItemUpdate(scoped($0), $1 as CFDictionary) },
        delete: { SecItemDelete(scoped($0)) })
    }
}

struct CredentialStore {
    static let service = "Loopa ChatGPT Local"
    static let productionAccount = "state-v1"
    private let account: String
    private let security: CredentialSecurityCalls

    init(security: CredentialSecurityCalls) {
        self.init(security: security, account: Self.productionAccount)
    }
    private init(security: CredentialSecurityCalls, account: String) {
        self.security = security
        self.account = account
    }
    private var query: [String: Any] {
        let context = LAContext()
        context.interactionNotAllowed = true
        return [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Self.service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false,
         kSecUseAuthenticationContext as String: context]
    }
    private func failure(_ status: OSStatus) -> CredentialStoreError {
        switch status {
        case errSecItemNotFound: return .missing
        case errSecAuthFailed, errSecInteractionNotAllowed, errSecUserCanceled: return .denied
        case errSecDuplicateItem: return .conflict
        default: return .unavailable
        }
    }
    func read() throws -> CredentialRecord {
        var request = query
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        request[kSecReturnData as String] = true
        let (status, value) = security.copy(request)
        guard status == errSecSuccess else { throw failure(status) }
        guard let data = value as? Data else { throw CredentialStoreError.corrupt }
        do { return try CredentialRecord(bytes: data) }
        catch { throw CredentialStoreError.corrupt }
    }
    func replace(_ record: CredentialRecord) throws {
        do {
            _ = try read()
        } catch CredentialStoreError.missing {
            var item = query
            item[kSecValueData as String] = record.bytes
            let status = security.add(item)
            guard status == errSecSuccess else { throw failure(status) }
            return
        }
        // No delete/add fallback: failed whole-record update leaves old data intact.
        let status = security.update(query, [kSecValueData as String: record.bytes])
        guard status == errSecSuccess else {
            if status == errSecItemNotFound { throw CredentialStoreError.conflict }
            throw failure(status)
        }
    }
    func delete() throws {
        _ = try read() // Never remove denied, malformed, unsupported or oversized data.
        let status = security.delete(query)
        guard status == errSecSuccess else { throw failure(status) }
    }

    #if CREDENTIAL_STORE_TESTS
    // Only the test binary contains account selection, and callers cannot supply it.
    // A fresh synthetic account cannot address production or another application's item.
    static func isolatedSmokeStore() throws -> Self {
        Self(security: try .system(), account: "synthetic-test-" + UUID().uuidString)
    }
    #endif
}

enum CredentialIPC {
    static let maximumInputBytes = CredentialRecord.maximumBytes + 1_024
    static let maximumOutputBytes = CredentialRecord.maximumBytes + 128

    static func parse(_ data: Data) throws -> (operation: String, record: CredentialRecord?) {
        guard data.count <= maximumInputBytes else { throw CredentialStoreError.tooLarge }
        var line = data
        if line.last == 10 { line.removeLast() }
        if line.last == 13 { line.removeLast() }
        guard !line.contains(10), !line.contains(13) else { throw CredentialStoreError.invalidRequest }
        let request = try StrictJSON.object(line)
        guard let op = request["op"] as? String else { throw CredentialStoreError.invalidRequest }
        switch op {
        case "read", "delete":
            guard Set(request.keys) == ["op"] else { throw CredentialStoreError.invalidRequest }
            return (op, nil)
        case "replace":
            guard Set(request.keys) == ["op", "record"], let record = request["record"] as? [String: Any] else {
                throw CredentialStoreError.invalidRequest
            }
            return (op, try CredentialRecord(object: record))
        default: throw CredentialStoreError.invalidRequest
        }
    }
    static func response(to input: Data, store: CredentialStore) -> (data: Data, status: Int32) {
        do {
            let request = try parse(input)
            let result: Data
            switch request.operation {
            case "read":
                let record = try store.read()
                result = Data("{\"ok\":true,\"record\":".utf8) + record.bytes + Data("}\n".utf8)
            case "replace":
                guard let record = request.record else { throw CredentialStoreError.invalidRequest }
                try store.replace(record)
                result = Data("{\"ok\":true}\n".utf8)
            case "delete":
                try store.delete()
                result = Data("{\"ok\":true}\n".utf8)
            default: throw CredentialStoreError.invalidRequest
            }
            guard result.count <= maximumOutputBytes else { throw CredentialStoreError.tooLarge }
            return (result, 0)
        } catch { return failure(error) }
    }
    static func failure(_ error: Error) -> (data: Data, status: Int32) {
        let safe = error as? CredentialStoreError ?? .unavailable
        return (Data("{\"ok\":false,\"error\":\"\(safe.rawValue)\"}\n".utf8), 1)
    }
    static func readInput(_ input: FileHandle) throws -> Data {
        var data = Data()
        do {
            while let chunk = try input.read(upToCount: min(4_096, maximumInputBytes + 1 - data.count)), !chunk.isEmpty {
                data.append(chunk)
                guard data.count <= maximumInputBytes else { throw CredentialStoreError.tooLarge }
            }
        } catch let error as CredentialStoreError { throw error }
        catch { throw CredentialStoreError.ioFailure }
        return data
    }
    static func isChildChannel(_ descriptor: Int32) -> Bool {
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { return false }
        if (info.st_mode & S_IFMT) == S_IFIFO { return info.st_nlink == 0 }
        // Node/libuv child stdio uses socketpair(AF_UNIX, SOCK_STREAM), not pipe().
        // Restrict both local and peer addresses to unnamed Unix endpoints; never
        // allow network sockets, listening sockets or named filesystem endpoints.
        guard (info.st_mode & S_IFMT) == S_IFSOCK else { return false }
        var type: Int32 = 0
        var typeLength = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(descriptor, SOL_SOCKET, SO_TYPE, &type, &typeLength) == 0, type == SOCK_STREAM else { return false }
        func unnamedUnix(peer: Bool) -> Bool {
            var address = sockaddr_un()
            var length = socklen_t(MemoryLayout<sockaddr_un>.size)
            let result = withUnsafeMutablePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    peer ? getpeername(descriptor, $0, &length) : getsockname(descriptor, $0, &length)
                }
            }
            // Parent stdin.end() can close its endpoint before the child examines
            // it. Local AF_UNIX/type checks still constrain the buffered input.
            if peer && result < 0 && (errno == ENOTCONN || errno == EINVAL) { return true }
            // Darwin returns a padded sockaddr (currently 16 bytes) for socketpair.
            // Inspect the empty name rather than assuming a particular padded size.
            let unnamed = withUnsafeBytes(of: address.sun_path) { $0.allSatisfy { $0 == 0 } }
            return result == 0 && address.sun_family == AF_UNIX && length >= 2 &&
                length <= MemoryLayout<sockaddr_un>.size && unnamed
        }
        // The trusted parent must also keep descriptors private; endpoint shape
        // checks cannot establish who else inherited a descriptor.
        return unnamedUnix(peer: false) && unnamedUnix(peer: true)
    }
    static func writeOutput(_ data: Data) -> Bool {
        guard data.count <= maximumOutputBytes else { return false }
        return data.withUnsafeBytes { bytes in
            var written = 0
            while written < data.count {
                let count = Darwin.write(STDOUT_FILENO, bytes.baseAddress!.advanced(by: written), data.count - written)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { return false }
                written += count
            }
            return true
        }
    }
}

#if !CREDENTIAL_STORE_TESTS
@main
struct CredentialStoreMain {
    static func main() {
        signal(SIGPIPE, SIG_IGN)
        // Refuse terminals and redirected plaintext files even for errors.
        guard CredentialIPC.isChildChannel(STDIN_FILENO), CredentialIPC.isChildChannel(STDOUT_FILENO) else { exit(2) }
        let response: (data: Data, status: Int32)
        do {
            guard CommandLine.arguments.count == 1 else { throw CredentialStoreError.invalidRequest }
            let input = try CredentialIPC.readInput(.standardInput)
            // Parse BEFORE instantiating Security so malformed IPC never accesses Keychain.
            _ = try CredentialIPC.parse(input)
            response = CredentialIPC.response(to: input, store: CredentialStore(security: try .system()))
        } catch { response = CredentialIPC.failure(error) }
        guard CredentialIPC.writeOutput(response.data) else { exit(2) }
        exit(response.status)
    }
}
#endif
