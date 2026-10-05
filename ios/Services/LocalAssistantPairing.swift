import Foundation
import CoreFoundation
import Darwin

/// One-use capability handoff from the trusted Mac launcher to its disposable
/// simulator. OAuth credentials never belong in this file or in the simulator.
/// The launcher exclusively creates the file with mode 0600 and does not mutate
/// it after publication. The app retains only the validated returned value.
enum LocalAssistantPairing {
    static let filename = "loopa-assistant-pair.json"
    private static let maximumBytes = 2_048

    enum Failure: Error, Equatable, LocalizedError {
        case unsafeFile, invalidPairing, fileChanged, unavailable
        var errorDescription: String? { "Pair with the local Mac assistant again." }
    }

    /// The only production entry point. Physical devices never inspect Documents.
    static func consume() throws -> LocalMusicAssistant.Pairing? {
        #if targetEnvironment(simulator)
        guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw Failure.unavailable
        }
        return try consume(directory: directory, now: Date())
        #else
        return nil
        #endif
    }

    /// Internal fixture entry: callers supply a disposable directory and clock.
    /// beforeUnlink permits deterministic replacement races in offline tests.
    static func consume(directory: URL, now: Date, beforeUnlink: (() throws -> Void)? = nil) throws -> LocalMusicAssistant.Pairing? {
        guard directory.isFileURL, directory.path.hasPrefix("/"), now.timeIntervalSince1970.isFinite else {
            throw Failure.invalidPairing
        }
        let directoryFD = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directoryFD >= 0 else { throw Failure.unsafeFile }
        defer { close(directoryFD) }
        var directoryInfo = stat()
        guard fstat(directoryFD, &directoryInfo) == 0, directoryInfo.st_uid == geteuid(),
              directoryInfo.st_mode & S_IFMT == S_IFDIR, directoryInfo.st_mode & 0o022 == 0 else { throw Failure.unsafeFile }

        // O_NONBLOCK prevents a substituted FIFO from blocking before fstat.
        let fileFD = openat(directoryFD, filename, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if fileFD < 0 {
            if errno == ENOENT { return nil }
            throw Failure.unsafeFile
        }
        defer { close(fileFD) }
        var opened = stat()
        guard fstat(fileFD, &opened) == 0 else { throw Failure.unavailable }
        try validateFileMetadata(opened)
        try noExtendedAccess(fileFD)

        var bytes = Data()
        var buffer = [UInt8](repeating: 0, count: 512)
        while true {
            let count = Darwin.read(fileFD, &buffer, min(buffer.count, maximumBytes + 1 - bytes.count))
            if count < 0 {
                if errno == EINTR { continue }
                throw Failure.unavailable
            }
            if count == 0 { break }
            bytes.append(contentsOf: buffer.prefix(count))
            guard bytes.count <= maximumBytes else { throw Failure.unsafeFile }
        }
        var readInfo = stat()
        guard fstat(fileFD, &readInfo) == 0, sameFile(opened, readInfo), bytes.count == opened.st_size else {
            throw Failure.fileChanged
        }
        let pairing = try parse(bytes, now: now)
        do { try beforeUnlink?() } catch { throw Failure.fileChanged }

        // Use the pinned directory, not a re-resolved URL. Recheck both the open
        // inode and its directory entry after validation, before consuming it.
        // The trusted app-container owner must serialize publication/consumption;
        // POSIX has no conditional-unlink-by-inode primitive against that owner.
        var finalInfo = stat(); var pathInfo = stat()
        guard fstat(fileFD, &finalInfo) == 0, sameFile(opened, finalInfo),
              fstatat(directoryFD, filename, &pathInfo, AT_SYMLINK_NOFOLLOW) == 0,
              sameFile(opened, pathInfo) else { throw Failure.fileChanged }
        try validateFileMetadata(finalInfo)
        try noExtendedAccess(fileFD)
        guard unlinkat(directoryFD, filename, 0) == 0 else { throw Failure.fileChanged }
        return pairing
    }

    /// Kept separate so nonowner metadata can be tested without privilege changes.
    static func validateFileMetadata(_ info: stat) throws {
        guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == geteuid(),
              info.st_mode & 0o7777 == 0o600, info.st_nlink == 1,
              info.st_size >= 0, info.st_size <= maximumBytes else { throw Failure.unsafeFile }
    }
    private static func sameFile(_ a: stat, _ b: stat) -> Bool {
        a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_uid == b.st_uid &&
        a.st_mode == b.st_mode && a.st_nlink == b.st_nlink && a.st_size == b.st_size &&
        a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec &&
        a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec
    }
    private static func noExtendedAccess(_ descriptor: Int32) throws {
        // Mode 0600 alone does not rule out an additional ACL grant. This narrow
        // launcher-created handoff accepts no extended ACL entries at all.
        errno = 0
        guard let acl = acl_get_fd(descriptor) else {
            // Darwin reports an absent extended ACL as ENOENT.
            if errno == ENOENT { return }
            throw Failure.unsafeFile
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        var entry: acl_entry_t?
        errno = 0
        let result = acl_get_entry(acl, Int32(ACL_FIRST_ENTRY.rawValue), &entry)
        guard result == -1, errno == EINVAL || errno == ENOENT else { throw Failure.unsafeFile }
    }
    private static func parse(_ data: Data, now: Date) throws -> LocalMusicAssistant.Pairing {
        guard String(data: data, encoding: .utf8) != nil,
              data.first(where: { ![9, 10, 13, 32].contains($0) }) == 123,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["version", "endpoint", "capability", "expires_at"] else { throw Failure.invalidPairing }
        try rejectDuplicateKeys(data)
        guard let version = object["version"] as? NSNumber, CFGetTypeID(version) != CFBooleanGetTypeID(), version == 1,
              let endpoint = object["endpoint"] as? String, let url = URL(string: endpoint),
              let components = URLComponents(string: endpoint), let port = components.port,
              (1_024...65_535).contains(port), endpoint == "http://127.0.0.1:\(port)/",
              let capability = object["capability"] as? String, capability.utf8.count == 43,
              capability.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil,
              let decoded = Data(base64Encoded: capability.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/") + "="), decoded.count == 32,
              decoded.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") == capability,
              let expiry = object["expires_at"] as? NSNumber, CFGetTypeID(expiry) != CFBooleanGetTypeID() else { throw Failure.invalidPairing }
        let milliseconds = expiry.doubleValue
        let remaining = milliseconds - now.timeIntervalSince1970 * 1000
        guard milliseconds.isFinite, milliseconds.rounded() == milliseconds,
              abs(milliseconds) <= 9_007_199_254_740_991, remaining.isFinite,
              remaining > 0, remaining <= 900_000 else { throw Failure.invalidPairing }
        return .init(endpoint: url, capability: capability, expiresAt: Date(timeIntervalSince1970: milliseconds / 1000))
    }
    private static func rejectDuplicateKeys(_ data: Data) throws {
        // Foundation accepts duplicate keys. With the already-validated flat
        // four-scalar schema, scan quoted tokens and compare decoded key names.
        let bytes = Array(data); var index = 0; var keys = Set<String>()
        while index < bytes.count {
            guard bytes[index] == 34 else { index += 1; continue }
            let start = index; index += 1
            while index < bytes.count && bytes[index] != 34 {
                if bytes[index] == 92 { index += 1 }
                index += 1
            }
            guard index < bytes.count else { throw Failure.invalidPairing }
            index += 1; var next = index
            while next < bytes.count && [9, 10, 13, 32].contains(bytes[next]) { next += 1 }
            if next < bytes.count && bytes[next] == 58 {
                let quoted = Data([91] + bytes[start..<index] + [93])
                guard let values = try? JSONSerialization.jsonObject(with: quoted) as? [String],
                      let key = values.first, keys.insert(key).inserted else { throw Failure.invalidPairing }
            }
        }
    }
}
