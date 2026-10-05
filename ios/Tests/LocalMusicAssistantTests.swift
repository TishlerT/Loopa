import XCTest
import Foundation
@testable import Loopa

@MainActor
final class LocalMusicAssistantTests: XCTestCase {
    private final class Wire: URLProtocol, @unchecked Sendable {
        private static let lock = NSLock()
        private static var action: ((Wire) -> Void)?
        private static var received: [URLRequest] = []
        static func install(_ action: @escaping (Wire) -> Void) {
            lock.lock(); self.action = action; received = []; lock.unlock()
        }
        static var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return received }
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            Self.lock.lock(); Self.received.append(request); let action = Self.action; Self.lock.unlock()
            action?(self)
        }
        override func stopLoading() {}
        func send(_ data: Data, status: Int = 200, length: Int? = nil, chunks: Int = 1) {
            var headers = ["Content-Type": "application/json"]
            if let length { headers["Content-Length"] = String(length) }
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            let step = max(1, (data.count + chunks - 1) / chunks)
            for start in stride(from: 0, to: data.count, by: step) {
                client?.urlProtocol(self, didLoad: data.subdata(in: start..<min(data.count, start + step)))
            }
            client?.urlProtocolDidFinishLoading(self)
        }
        func json(_ object: Any, status: Int = 200) {
            send(try! JSONSerialization.data(withJSONObject: object), status: status)
        }
        func fail() { client?.urlProtocol(self, didFailWithError: NSError(domain: "SYNTHETIC_PRIVATE_ERROR", code: 17)) }
    }

    private let date = Date(timeIntervalSince1970: 1_700_000_000)
    private var capability: String { Data(repeating: 7, count: 32).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    private func pair(endpoint: String = "http://127.0.0.1:54321/", expires: TimeInterval = 600, capability: String? = nil) -> LocalMusicAssistant.Pairing {
        .init(endpoint: URL(string: endpoint)!, capability: capability ?? self.capability, expiresAt: date.addingTimeInterval(expires))
    }
    private func assistant(pairing: LocalMusicAssistant.Pairing? = nil, clock: (() -> Date)? = nil, timeout: TimeInterval = 45) -> LocalMusicAssistant {
        LocalMusicAssistant(pairing: pairing ?? pair(), now: clock ?? { self.date }, configuration: {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [Wire.self]
            return config
        }, timeout: timeout)
    }
    private func context() throws -> MusicAssistantContext {
        let track = Track(instrumentName: "Piano", instrumentProgram: 0, isDrumKit: false,
                          notes: [MidiNote(pitch: 60, velocity: 80, startBeat: 0, durationBeats: 0.25)], volume: 0.5)
        let other = Track(audioFileName: "private-recording-do-not-send.m4a", volume: 0.3)
        return try MusicAssistantContext(snapshot: .init(token: .init(sessionID: UUID(), revision: 3),
             tracks: [track, other], bpm: 120, barCount: .four), trackID: track.id)
    }
    private func proposal(_ context: MusicAssistantContext, value: Any = 0.7, requestID: UUID? = nil, trackID: UUID? = nil) -> [String: Any] {
        ["version": 1, "request_id": (requestID ?? context.requestID).uuidString,
         "proposal": ["operations": [["kind": "gain", "track_id": (trackID ?? context.trackID).uuidString, "value": value]]]]
    }
    private func expect(_ expected: LocalMusicAssistant.Failure, _ operation: () async throws -> Void,
                        file: StaticString = #filePath, line: UInt = #line) async {
        do { try await operation(); XCTFail("Expected fixed failure", file: file, line: line) }
        catch { XCTAssertEqual(error as? LocalMusicAssistant.Failure, expected, file: file, line: line) }
    }

    func testDefaultClientIsDisabledWithoutPairing() async {
        Wire.install { _ in XCTFail("Unpaired client must not send") }
        await expect(.notPaired) { _ = try await LocalMusicAssistant().status() }
        XCTAssertTrue(Wire.requests.isEmpty)
    }
    func testOnlyExactLoopbackEndpointAndNonprivilegedPortAreAllowed() async {
        for endpoint in ["https://127.0.0.1:54321/", "http://localhost:54321/", "http://192.168.1.1:54321/",
                         "http://127.0.0.1:80/", "http://user@127.0.0.1:54321/", "http://127.0.0.1:54321/path",
                         "http://127.0.0.1:54321/?x=1", "http://127.0.0.1:54321/#fragment"] {
            Wire.install { _ in XCTFail("Invalid endpoint must not send") }
            await expect(.invalidPairing) { _ = try await assistant(pairing: pair(endpoint: endpoint)).status() }
            XCTAssertTrue(Wire.requests.isEmpty)
        }
    }
    func testPairingRequiresCanonical32ByteCapability() async {
        for value in ["", "OAuth-token", String(repeating: "A", count: 42), String(repeating: "A", count: 42) + "B", capability + "="] {
            Wire.install { _ in XCTFail("Invalid capability must not send") }
            await expect(.invalidPairing) { _ = try await assistant(pairing: pair(capability: value)).status() }
        }
    }
    func testExpiredOrOverlongPairingNeverSends() async {
        for (expiry, error) in [(0.0, LocalMusicAssistant.Failure.pairingExpired), (-1, .pairingExpired), (901, .invalidPairing)] {
            Wire.install { _ in XCTFail("Invalid lifetime must not send") }
            await expect(error) { _ = try await assistant(pairing: pair(expires: expiry)).status() }
        }
    }
    func testStatusUsesPairingBearerAndNeverOAuthOrCookies() async throws {
        Wire.install { wire in wire.json(["version": 1, "status": "connected", "sharing": true]) }
        let result = try await assistant().status()
        XCTAssertEqual(result, .init(connection: .connected, sharing: true))
        let request = try XCTUnwrap(Wire.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:54321/v1/status")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer " + capability)
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store")
        XCTAssertNil(request.httpBody)
    }
    func testAllDeclaredConnectionStatesAreAccepted() async throws {
        for raw in ["connected", "disconnected", "connecting", "reconnect_required", "usage_unavailable"] {
            Wire.install { wire in wire.json(["version": 1, "status": raw, "sharing": false]) }
            let result = try await assistant().status()
            XCTAssertEqual(result.connection.rawValue, raw)
        }
    }
    func testStatusRejectsUnknownKeysBooleanVersionAndNumericSharing() async {
        let values: [[String: Any]] = [["version": 1, "status": "connected", "sharing": true, "token": "synthetic"],
            ["version": true, "status": "connected", "sharing": true], ["version": 1, "status": "unknown", "sharing": true],
            ["version": 1, "status": "connected", "sharing": 1]]
        for value in values {
            Wire.install { $0.json(value) }
            await expect(.invalidResponse) { _ = try await assistant().status() }
        }
    }
    func testModelsPreserveOrderAndDisplayNames() async throws {
        Wire.install { $0.json(["version": 1, "models": [["slug": "second", "display_name": "Second 🎵"], ["slug": "first", "display_name": "First"]]]) }
        let result = try await assistant().models()
        XCTAssertEqual(result, [.init(slug: "second", displayName: "Second 🎵"), .init(slug: "first", displayName: "First")])
        XCTAssertEqual(Wire.requests.first?.url?.path, "/v1/models")
    }
    func testModelsRejectDuplicateSlugAndControlCharacterLabel() async {
        for models in [ [["slug": "same", "display_name": "One"], ["slug": "same", "display_name": "Two"]],
                        [["slug": "valid", "display_name": "Bad\nLabel"]], [["slug": "../bad", "display_name": "Bad"]] ] {
            Wire.install { $0.json(["version": 1, "models": models]) }
            await expect(.invalidResponse) { _ = try await assistant().models() }
        }
    }
    func testGainRequestUsesCapturedContextAndReturnsValueEditsWithoutMutation() async throws {
        let context = try context()
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let before = try encoder.encode(context.snapshot.tracks)
        Wire.install { $0.json(self.proposal(context)) }
        let edits = try await assistant().proposeGain(context: context, userText: "Make piano louder", model: "selected-model")
        guard case .gain(let id, let old, let new) = try XCTUnwrap(edits.first) else { return XCTFail("Expected gain") }
        XCTAssertEqual(id, context.trackID); XCTAssertEqual(old, 0.5); XCTAssertEqual(new, 0.7)
        XCTAssertEqual(try encoder.encode(context.snapshot.tracks), before)
        let request = try XCTUnwrap(Wire.requests.first)
        XCTAssertEqual(request.url?.path, "/v1/proposals"); XCTAssertEqual(request.httpMethod, "POST")
        let data: Data
        if let body = request.httpBody { data = body }
        else {
            let stream = try XCTUnwrap(request.httpBodyStream); stream.open(); defer { stream.close() }
            var bytes = Data(); var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; bytes.append(buffer, count: n) }
            data = bytes
        }
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["request_id", "user_text", "project", "model"])
        XCTAssertEqual(object["request_id"] as? String, context.requestID.uuidString)
        XCTAssertEqual(object["model"] as? String, "selected-model")
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("private-recording"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(context.snapshot.tracks[1].id.uuidString))
    }
    func testWrongRequestIDOrTrackIDIsRejected() async throws {
        let context = try context()
        for value in [proposal(context, requestID: UUID()), proposal(context, trackID: UUID())] {
            Wire.install { $0.json(value) }
            await expect(.invalidResponse) { _ = try await assistant().proposeGain(context: context, userText: "louder", model: "m") }
        }
    }
    func testGainRejectsBooleansOutOfRangeAndNonfiniteJSON() async throws {
        let context = try context()
        for value: Any in [true, -0.1, 1.1, "NaN"] {
            Wire.install { $0.json(self.proposal(context, value: value)) }
            await expect(.invalidResponse) { _ = try await assistant().proposeGain(context: context, userText: "louder", model: "m") }
        }
        Wire.install { $0.send(Data("{\"version\":1,\"request_id\":\"\(context.requestID)\",\"proposal\":{\"operations\":[{\"kind\":\"gain\",\"track_id\":\"\(context.trackID)\",\"value\":1e999}]}}".utf8)) }
        await expect(.invalidResponse) { _ = try await assistant().proposeGain(context: context, userText: "louder", model: "m") }
    }
    func testMultipleOperationsOrUnknownProposalFieldsAreRejected() async throws {
        let context = try context()
        let gain: [String: Any] = ["kind": "gain", "track_id": context.trackID.uuidString, "value": 0.7]
        for operations in [[gain, gain], [["kind": "midi_region", "track_id": context.trackID.uuidString]], [["kind": "gain", "track_id": context.trackID.uuidString, "value": 0.7, "before": 0.1]]] {
            Wire.install { $0.json(["version": 1, "request_id": context.requestID.uuidString, "proposal": ["operations": operations]]) }
            await expect(.invalidResponse) { _ = try await assistant().proposeGain(context: context, userText: "louder", model: "m") }
        }
    }
    func testUserTextLimitAndStoredLabelsStayPrivate() async throws {
        let context = try context()
        for text in [" ", String(repeating: "🎵", count: 513)] {
            Wire.install { _ in XCTFail("Oversized input must not send") }
            await expect(.invalidRequest) { _ = try await assistant().proposeGain(context: context, userText: text, model: "m") }
        }
        // Arbitrary stored labels must not bypass the context's known enum labels.
        var track = context.snapshot.tracks[0]; track.instrumentName = String(repeating: "x", count: 20_000)
        let huge = try MusicAssistantContext(snapshot: .init(token: context.snapshot.token, tracks: [track], bpm: 120, barCount: .four), trackID: track.id)
        Wire.install { $0.json(self.proposal(huge)) }
        // encodedProject uses a known instrument enum, so arbitrary stored labels never leak.
        _ = try await assistant().proposeGain(context: huge, userText: "louder", model: "m")
        XCTAssertEqual(Wire.requests.count, 1)
    }
    func testIncrementalResponseCapRejectsOversizeWithoutAcceptingProposal() async {
        Wire.install { $0.send(Data(repeating: 32, count: 262_145), chunks: 65) }
        await expect(.responseTooLarge) { _ = try await assistant().status() }
    }
    func testDeclaredOversizeIsRejectedBeforeBody() async {
        Wire.install { $0.send(Data(), length: 262_145) }
        await expect(.responseTooLarge) { _ = try await assistant().status() }
    }
    func testInvalidUTF8AndTruncatedJSONEOFReject() async {
        for data in [Data([0xff]), Data("{\"version\":1".utf8)] {
            Wire.install { $0.send(data) }
            await expect(.invalidResponse) { _ = try await assistant().status() }
        }
    }
    func testHTTPErrorNeverExposesServerText() async {
        Wire.install { $0.send(Data("SYNTHETIC SECRET SERVER DETAIL".utf8), status: 500) }
        do { _ = try await assistant().status(); XCTFail("Expected failure") }
        catch { XCTAssertEqual(error as? LocalMusicAssistant.Failure, .unavailable); XCTAssertFalse(error.localizedDescription.contains("SECRET")) }
    }
    func testTransportErrorIsSanitized() async {
        Wire.install { $0.fail() }
        do { _ = try await assistant().status(); XCTFail("Expected failure") }
        catch { XCTAssertEqual(error as? LocalMusicAssistant.Failure, .unavailable); XCTAssertFalse(error.localizedDescription.contains("PRIVATE")) }
    }
    func testRedirectStatusIsRejectedWithoutFollowingRemoteLocation() async {
        Wire.install { $0.send(Data(), status: 302) }
        await expect(.unavailable) { _ = try await assistant().status() }
        XCTAssertEqual(Wire.requests.count, 1)
    }
    func testHangingTransportHasExplicitDeadline() async {
        Wire.install { _ in }
        await expect(.timeout) { _ = try await assistant(timeout: 0.03).status() }
    }
    func testSecondOperationIsBusyAndNeverQueued() async {
        let entered = expectation(description: "first entered")
        Wire.install { _ in entered.fulfill() }
        let client = assistant(); let task = Task { try await client.status() }
        await fulfillment(of: [entered], timeout: 2)
        await expect(.busy) { _ = try await client.models() }
        client.cancel(); await expect(.cancelled) { _ = try await task.value }
        XCTAssertEqual(Wire.requests.count, 1)
    }
    func testExplicitCancellationBlocksLateCatalogAndAllowsFreshOperation() async throws {
        let entered = expectation(description: "catalog entered")
        Wire.install { _ in entered.fulfill() }
        let client = assistant(); let task = Task { try await client.models() }
        await fulfillment(of: [entered], timeout: 2)
        client.cancel(); await expect(.cancelled) { _ = try await task.value }
        Wire.install { $0.json(["version": 1, "status": "disconnected", "sharing": false]) }
        let fresh = try await client.status()
        XCTAssertEqual(fresh.connection, .disconnected)
    }
    func testCallerTaskCancellationStopsTransport() async {
        let entered = expectation(description: "status entered")
        Wire.install { _ in entered.fulfill() }
        let client = assistant(); let task = Task { try await client.status() }
        await fulfillment(of: [entered], timeout: 2)
        task.cancel(); await expect(.cancelled) { _ = try await task.value }
    }
    func testProposalCancellationIsLocalEvenWhenDeleteFails() async throws {
        let context = try context(); let post = expectation(description: "proposal entered"), delete = expectation(description: "remote cancellation attempted")
        Wire.install { wire in
            if wire.request.httpMethod == "DELETE" { XCTAssertEqual(wire.request.url?.lastPathComponent, context.requestID.uuidString); delete.fulfill(); wire.fail() }
            else { post.fulfill() }
        }
        let client = assistant(); let task = Task { try await client.proposeGain(context: context, userText: "louder", model: "m") }
        await fulfillment(of: [post], timeout: 2)
        client.cancel(); await expect(.cancelled) { _ = try await task.value }
        await fulfillment(of: [delete], timeout: 2)
    }
    func testPairingExpiryDuringResponseRejectsSuccess() async {
        var clock = date
        Wire.install { wire in
            Task { @MainActor in clock = self.date.addingTimeInterval(601); wire.json(["version": 1, "status": "connected", "sharing": true]) }
        }
        await expect(.pairingExpired) { _ = try await assistant(clock: { clock }).status() }
    }
    func testTerminalCancellationCannotReturnCatalog() async {
        var reads = 0; var client: LocalMusicAssistant!
        client = assistant(clock: {
            reads += 1
            // Cancel from the final pairing check, after exchange has completed,
            // to exercise the last success-publication authority boundary.
            if reads == 5 { client.cancel() }
            return self.date
        })
        Wire.install { $0.json(["version": 1, "models": [["slug": "m", "display_name": "M"]]]) }
        await expect(.cancelled) { _ = try await client.models() }
        client = nil
    }
    func testTerminalCancellationCannotReturnProposal() async throws {
        let context = try context(); let payload = proposal(context)
        var reads = 0; var client: LocalMusicAssistant!
        client = assistant(clock: {
            reads += 1
            if reads == 5 { client.cancel() }
            return self.date
        })
        Wire.install { wire in
            if wire.request.httpMethod == "DELETE" { wire.json(["version": 1, "cancelled": true]) }
            else { wire.json(payload) }
        }
        await expect(.cancelled) { _ = try await client.proposeGain(context: context, userText: "louder", model: "m") }
        client = nil
    }
    func testExpiredPairingCannotReturnProposal() async throws {
        let context = try context(); let payload = proposal(context)
        var clock = date
        Wire.install { wire in
            Task { @MainActor in clock = self.date.addingTimeInterval(601); wire.json(payload) }
        }
        await expect(.pairingExpired) { _ = try await assistant(clock: { clock }).proposeGain(context: context, userText: "louder", model: "m") }
    }
    func testExactResponseLimitAcceptsValidIncrementalJSON() async throws {
        var data = try JSONSerialization.data(withJSONObject: ["version": 1, "status": "connected", "sharing": true])
        data.append(Data(repeating: 32, count: 262_144 - data.count))
        Wire.install { $0.send(data, chunks: 257) }
        let result = try await assistant().status()
        XCTAssertEqual(result.connection, .connected)
    }
    func testRedirectDelegateRejectsRemoteLocationWithoutForwardingCapability() async {
        Wire.install { wire in
            let remote = URLRequest(url: URL(string: "https://example.invalid/private")!)
            let response = HTTPURLResponse(url: wire.request.url!, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": remote.url!.absoluteString])!
            wire.client?.urlProtocol(wire, wasRedirectedTo: remote, redirectResponse: response)
        }
        await expect(.invalidResponse) { _ = try await assistant().status() }
        XCTAssertEqual(Wire.requests.count, 1)
        XCTAssertEqual(Wire.requests.first?.url?.host, "127.0.0.1")
    }
    func testAlreadyCancelledTaskDoesNotStartTransport() async {
        Wire.install { _ in XCTFail("Cancelled task must not send") }
        let client = assistant()
        let task = Task { try await client.status() }
        task.cancel()
        await expect(.cancelled) { _ = try await task.value }
        XCTAssertTrue(Wire.requests.isEmpty)
    }
    func testInvalidDeadlineNeverStartsTransport() async {
        for timeout in [0.0, 46, .infinity] {
            Wire.install { _ in XCTFail("Invalid deadline must not send") }
            await expect(.invalidPairing) { _ = try await assistant(timeout: timeout).status() }
        }
    }

}
