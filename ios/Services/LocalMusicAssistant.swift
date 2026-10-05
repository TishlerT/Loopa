import Foundation
import CoreFoundation

/// Simulator-to-Mac transport only. Pairing is supplied by a trusted launcher;
/// this client never reads, stores or sends ChatGPT OAuth credentials.
@MainActor
final class LocalMusicAssistant {
    struct Pairing {
        let endpoint: URL
        let capability: String
        let expiresAt: Date
    }
    enum Connection: String { case connected, disconnected, connecting, reconnect_required, usage_unavailable }
    struct Status: Equatable { let connection: Connection; let sharing: Bool }
    struct Model: Equatable { let slug: String; let displayName: String }
    enum Failure: Error, Equatable, LocalizedError {
        case notPaired, invalidPairing, pairingExpired, busy, cancelled, timeout
        case invalidRequest, invalidResponse, responseTooLarge, unavailable
        var errorDescription: String? {
            switch self {
            case .notPaired: return "Pair this simulator with the local Mac assistant."
            case .invalidPairing, .pairingExpired: return "Pair with the local Mac assistant again."
            case .busy: return "Another assistant request is still running."
            case .cancelled: return "The assistant request was cancelled."
            case .timeout: return "The local assistant took too long. Your project is unchanged."
            case .invalidRequest: return "Select a track and describe a volume change."
            case .invalidResponse: return "The assistant returned an unusable response. Your project is unchanged."
            case .responseTooLarge: return "The assistant response exceeded its size limit."
            case .unavailable: return "The local Mac assistant is unavailable."
            }
        }
    }

    nonisolated static let maximumResponseBytes = 262_144
    private let pairing: Pairing?
    private let now: () -> Date
    private let configuration: () -> URLSessionConfiguration
    private let timeout: TimeInterval
    private var generation = UUID()
    private var active: (id: UUID, proposalID: UUID?, transport: Transport?)?

    /// Configuration injection is for offline URLProtocol fixtures. Security settings
    /// are overwritten below, including caches, cookies and stored credentials.
    init(pairing: Pairing? = nil, now: @escaping () -> Date = Date.init,
         configuration: @escaping () -> URLSessionConfiguration = { .ephemeral },
         timeout: TimeInterval = 45) {
        self.pairing = pairing; self.now = now; self.configuration = configuration; self.timeout = timeout
    }

    func status() async throws -> Status {
        let operation = try begin()
        defer { end(operation) }
        let data = try await exchange(path: "v1/status", operation: operation)
        let object = try response(data, keys: ["version", "status", "sharing"])
        guard let raw = object["status"] as? String, let state = Connection(rawValue: raw),
              let sharing = object["sharing"] as? NSNumber, CFGetTypeID(sharing) == CFBooleanGetTypeID() else { throw Failure.invalidResponse }
        try current(operation)
        return Status(connection: state, sharing: sharing.boolValue)
    }

    func models() async throws -> [Model] {
        let operation = try begin()
        defer { end(operation) }
        let data = try await exchange(path: "v1/models", operation: operation)
        let object = try response(data, keys: ["version", "models"])
        guard let values = object["models"] as? [[String: Any]], !values.isEmpty, values.count <= 100 else { throw Failure.invalidResponse }
        var seen = Set<String>()
        let models = try values.map { item -> Model in
            guard Set(item.keys) == ["slug", "display_name"],
                  let slug = item["slug"] as? String, Self.validSlug(slug), seen.insert(slug).inserted,
                  let name = item["display_name"] as? String, Self.validText(name, limit: 128),
                  !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw Failure.invalidResponse }
            return Model(slug: slug, displayName: name)
        }
        try current(operation) // A cancelled discovery cannot return a late catalog.
        return models
    }

    /// Returns validated value edits only. MusicProposalSession must independently
    /// check current request/session revision at receive and again at explicit Keep.
    func proposeGain(context: MusicAssistantContext, userText: String, model: String) async throws -> [MusicEdit] {
        guard Self.validText(userText, limit: 2_048), Self.validSlug(model), context.region == nil else { throw Failure.invalidRequest }
        let project: [String: Any]
        do {
            guard let decoded = try JSONSerialization.jsonObject(with: context.encodedProject()) as? [String: Any],
                  decoded["capabilities"] as? [String] == ["gain"] else { throw Failure.invalidRequest }
            project = decoded
        } catch { throw Failure.invalidRequest }
        let body: Data
        do {
            body = try JSONSerialization.data(withJSONObject: ["request_id": context.requestID.uuidString,
                "user_text": userText, "project": project, "model": model], options: [.sortedKeys])
        } catch { throw Failure.invalidRequest }
        guard body.count <= 16_384 else { throw Failure.invalidRequest }
        let operation = try begin(proposalID: context.requestID)
        defer { end(operation) }
        let data = try await exchange(path: "v1/proposals", method: "POST", body: body, operation: operation)
        let object = try response(data, keys: ["version", "request_id", "proposal"])
        guard let rawID = object["request_id"] as? String, UUID(uuidString: rawID) == context.requestID,
              let proposal = object["proposal"] as? [String: Any], Set(proposal.keys) == ["operations"],
              let operations = proposal["operations"] as? [[String: Any]], operations.count == 1,
              operations[0]["kind"] as? String == "gain" else { throw Failure.invalidResponse }
        let edits: [MusicEdit]
        do { edits = try context.decodeProposal(JSONSerialization.data(withJSONObject: proposal)) }
        catch { throw Failure.invalidResponse }
        guard edits.count == 1, case .gain = edits[0] else { throw Failure.invalidResponse }
        try current(operation) // No await between authority check and return.
        return edits
    }

    /// Local invalidation is immediate and authoritative. Remote cancellation is
    /// best effort and cannot restore this operation or refund remote usage.
    func cancel() {
        let old = active
        generation = UUID()
        active = nil
        old?.transport?.cancel()
        guard let requestID = old?.proposalID, let pairing = try? validPairing() else { return }
        let request = makeRequest(pairing, path: "v1/proposals/" + requestID.uuidString, method: "DELETE", body: nil)
        let transport = Transport(configuration: safeConfiguration(), timeout: timeout)
        Task { _ = try? await transport.run(request) }
    }

    private func validPairing() throws -> Pairing {
        guard let pairing else { throw Failure.notPaired }
        let components = URLComponents(url: pairing.endpoint, resolvingAgainstBaseURL: false)
        guard let port = components?.port, (1_024...65_535).contains(port),
              pairing.endpoint.absoluteString == "http://127.0.0.1:\(port)/",
              pairing.capability.utf8.count == 43,
              pairing.capability.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil,
              let capability = Data(base64Encoded: pairing.capability.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/") + "="),
              capability.count == 32,
              capability.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") == pairing.capability,
              timeout.isFinite, timeout > 0, timeout <= 45 else { throw Failure.invalidPairing }
        let remaining = pairing.expiresAt.timeIntervalSince(now())
        guard remaining.isFinite, remaining <= 900 else { throw Failure.invalidPairing }
        guard remaining > 0 else { throw Failure.pairingExpired }
        return pairing
    }
    private func begin(proposalID: UUID? = nil) throws -> UUID {
        guard active == nil else { throw Failure.busy }
        guard !Task.isCancelled else { throw Failure.cancelled }
        _ = try validPairing()
        let id = UUID(); generation = id
        active = (id, proposalID, nil)
        return id
    }
    private func current(_ id: UUID) throws {
        guard !Task.isCancelled, generation == id, active?.id == id else { throw Failure.cancelled }
        _ = try validPairing()
        guard !Task.isCancelled, generation == id, active?.id == id else { throw Failure.cancelled }
    }
    private func end(_ id: UUID) { if active?.id == id { active = nil } }
    private func exchange(path: String, method: String = "GET", body: Data? = nil, operation: UUID) async throws -> Data {
        try current(operation)
        let request = makeRequest(try validPairing(), path: path, method: method, body: body)
        let transport = Transport(configuration: safeConfiguration(), timeout: timeout)
        active?.transport = transport
        do {
            let data = try await transport.run(request)
            try current(operation)
            return data
        } catch {
            try current(operation)
            throw (error as? Failure) ?? Failure.unavailable
        }
    }
    private func makeRequest(_ pairing: Pairing, path: String, method: String, body: Data?) -> URLRequest {
        var request = URLRequest(url: pairing.endpoint.appendingPathComponent(path), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = method; request.httpBody = body
        request.setValue("Bearer " + pairing.capability, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return request
    }
    private func safeConfiguration() -> URLSessionConfiguration {
        let config = configuration()
        config.urlCache = nil; config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil; config.httpAdditionalHeaders = nil
        config.connectionProxyDictionary = [:]
        config.timeoutIntervalForRequest = timeout; config.timeoutIntervalForResource = timeout
        return config
    }
    private static func validText(_ value: String, limit: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf8.count <= limit
    }
    private static func validSlug(_ value: String) -> Bool {
        validText(value, limit: 128) && value.range(of: "^[a-zA-Z0-9][a-zA-Z0-9._:-]*$", options: .regularExpression) != nil
    }
    private func response(_ data: Data, keys: Set<String>) throws -> [String: Any] {
        guard String(data: data, encoding: .utf8) != nil,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == keys, let version = object["version"] as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(), version == 1 else { throw Failure.invalidResponse }
        return object
    }

    /// One session per attempt, with bounded incremental accumulation. Delegates
    /// never expose server text. The lock also fences cancellation before start.
    private final class Transport: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        private let configuration: URLSessionConfiguration
        private let timeout: TimeInterval
        private let lock = NSLock()
        private var terminal: Result<Data, Error>?
        private var continuation: CheckedContinuation<Data, Error>?
        private var session: URLSession?
        private var task: URLSessionDataTask?
        private var timer: DispatchWorkItem?
        private var bytes = Data()
        private var acceptedResponse = false
        private var expectedURL: URL?

        init(configuration: URLSessionConfiguration, timeout: TimeInterval) {
            self.configuration = configuration; self.timeout = timeout
        }
        func run(_ request: URLRequest) async throws -> Data {
            try await withTaskCancellationHandler(operation: {
                try await withCheckedThrowingContinuation { continuation in
                    lock.lock()
                    if let terminal { lock.unlock(); continuation.resume(with: terminal); return }
                    self.continuation = continuation
                    expectedURL = request.url
                    let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                    self.session = session
                    let task = session.dataTask(with: request); self.task = task
                    let timer = DispatchWorkItem { [weak self] in self?.finish(.failure(Failure.timeout)) }
                    self.timer = timer
                    lock.unlock()
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
                    task.resume()
                }
            }, onCancel: { self.cancel() })
        }
        func cancel() { finish(.failure(Failure.cancelled)) }
        private func finish(_ result: Result<Data, Error>) {
            lock.lock()
            guard terminal == nil else { lock.unlock(); return }
            terminal = result
            let continuation = self.continuation; self.continuation = nil
            let session = self.session; self.session = nil
            let task = self.task; self.task = nil
            let timer = self.timer; self.timer = nil
            bytes.removeAll(keepingCapacity: false)
            lock.unlock()
            timer?.cancel(); task?.cancel(); session?.invalidateAndCancel()
            continuation?.resume(with: result)
        }
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            lock.lock()
            let valid = terminal == nil && !acceptedResponse && response.url == expectedURL &&
                (response as? HTTPURLResponse)?.statusCode == 200
            let oversized = response.expectedContentLength > Int64(LocalMusicAssistant.maximumResponseBytes)
            if valid && !oversized { acceptedResponse = true }
            lock.unlock()
            guard valid && !oversized else {
                completionHandler(.cancel)
                finish(.failure(oversized ? Failure.responseTooLarge : Failure.unavailable))
                return
            }
            completionHandler(.allow)
        }
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            lock.lock()
            guard terminal == nil else { lock.unlock(); return }
            guard acceptedResponse else { lock.unlock(); finish(.failure(Failure.invalidResponse)); return }
            guard data.count <= LocalMusicAssistant.maximumResponseBytes - bytes.count else {
                lock.unlock(); finish(.failure(Failure.responseTooLarge)); return
            }
            bytes.append(data)
            lock.unlock()
        }
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            lock.lock()
            let accepted = acceptedResponse; let result = bytes
            lock.unlock()
            if let error = error as? URLError, error.code == .timedOut { finish(.failure(Failure.timeout)) }
            else if error != nil { finish(.failure(Failure.unavailable)) }
            else if !accepted { finish(.failure(Failure.invalidResponse)) }
            else { finish(.success(result)) }
        }
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
            finish(.failure(Failure.invalidResponse))
        }
        func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            completionHandler(.cancelAuthenticationChallenge, nil)
            finish(.failure(Failure.unavailable))
        }
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, willCacheResponse proposedResponse: CachedURLResponse,
                        completionHandler: @escaping (CachedURLResponse?) -> Void) { completionHandler(nil) }
    }
}
