import XCTest
import Combine
import AVFoundation
@testable import Loopa

@MainActor
final class ExportLeaseTests: XCTestCase {
    private final class Gate {
        var continuation: CheckedContinuation<Void, Never>?
        func wait(_ entered: XCTestExpectation) async {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                entered.fulfill()
            }
        }
        func release() { continuation?.resume(); continuation = nil }
    }

    func testCompetingOperationsCannotEnterWhileFirstIsSuspended() async {
        let exporter = AudioExporter.shared
        let gate = Gate(), entered = expectation(description: "first owns renderer")
        let first = Task { await exporter.withExclusiveExport { await gate.wait(entered); return 11 } }
        await fulfillment(of: [entered], timeout: 2)
        XCTAssertTrue(exporter.isExporting)
        var secondEntered = false
        let second = await exporter.withExclusiveExport { secondEntered = true; return 22 }
        XCTAssertNil(second)
        XCTAssertFalse(secondEntered)
        XCTAssertTrue(exporter.isExporting)
        gate.release()
        let result = await first.value
        XCTAssertEqual(result, 11)
        XCTAssertFalse(exporter.isExporting)
    }

    func testRealExportRouteCannotBypassReservation() async throws {
        let exporter = AudioExporter.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LeaseFixture-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_410))
        pcm.frameLength = 4_410
        for frame in 0..<4_410 {
            pcm.floatChannelData![0][frame] = Float(sin(2 * Double.pi * 440 * Double(frame) / 44_100)) * 0.1
        }
        let vocal = directory.appendingPathComponent("fixture.wav")
        do {
            let file = try AVAudioFile(forWriting: vocal, settings: format.settings)
            try file.write(from: pcm)
        }
        let track = Track(audioFileName: "fixture.wav", recordedLengthBeats: 0.2)
        func render() async -> URL? {
            await exporter.exportToM4A(tracks: [track], bpm: 120, loopLengthBeats: 0.2,
                sessionName: "lease-test", soundFontURL: URL(fileURLWithPath: "/unused.sf2"),
                vocalsDirectory: directory)
        }
        let gate = Gate(), entered = expectation(description: "preview render suspended")
        let first = Task { await exporter.withExclusiveExport { await gate.wait(entered); return true } }
        await fulfillment(of: [entered], timeout: 2)
        let result = await render()
        XCTAssertNil(result)
        XCTAssertTrue(exporter.isExporting)
        gate.release()
        _ = await first.value
        XCTAssertFalse(exporter.isExporting)
        // Identical arguments must really render when admission is available.
        let positive = await render()
        let output = try XCTUnwrap(positive)
        defer { try? FileManager.default.removeItem(at: output.deletingLastPathComponent()) }
        let decoded = try AVAudioFile(forReading: output)
        XCTAssertEqual(decoded.length, 4_410)
        XCTAssertFalse(exporter.isExporting)
    }

    func testFailedOperationReleasesBeforeReturning() async {
        let exporter = AudioExporter.shared
        let result: URL?? = await exporter.withExclusiveExport { () -> URL? in nil }
        XCTAssertNotNil(result as Any?)
        XCTAssertNil(result!)
        XCTAssertFalse(exporter.isExporting)
        let next = await exporter.withExclusiveExport { 9 }
        XCTAssertEqual(next, 9)
        XCTAssertFalse(exporter.isExporting)
    }

    func testCancelledOperationRetainsLeaseUntilItsWorkFinishes() async {
        let exporter = AudioExporter.shared
        let gate = Gate(), entered = expectation(description: "render started")
        let first = Task { await exporter.withExclusiveExport { await gate.wait(entered); return 1 } }
        await fulfillment(of: [entered], timeout: 2)
        first.cancel()
        let overlap = await exporter.withExclusiveExport { 2 }
        XCTAssertNil(overlap)
        XCTAssertTrue(exporter.isExporting)
        gate.release()
        let result = await first.value
        // A rendered file must still reach its owner for cancellation cleanup.
        XCTAssertEqual(result, 1)
        XCTAssertFalse(exporter.isExporting)
    }

    func testAlreadyCancelledOperationNeverStarts() async {
        let exporter = AudioExporter.shared
        let gate = Gate(), entered = expectation(description: "before admission")
        var executed = false
        let task = Task {
            await gate.wait(entered)
            return await exporter.withExclusiveExport { executed = true; return 1 }
        }
        await fulfillment(of: [entered], timeout: 2)
        task.cancel()
        gate.release()
        let result = await task.value
        XCTAssertNil(result)
        XCTAssertFalse(executed)
        XCTAssertFalse(exporter.isExporting)
    }

    func testNestedOperationFailsWithoutReleasingOuterOwner() async {
        let exporter = AudioExporter.shared
        let value = await exporter.withExclusiveExport {
            let nested = await exporter.withExclusiveExport { 2 }
            XCTAssertNil(nested)
            XCTAssertTrue(exporter.isExporting)
            return 1
        }
        XCTAssertEqual(value, 1)
        XCTAssertFalse(exporter.isExporting)
    }

    func testEachOperationPublishesOneCompleteBusyInterval() async {
        let exporter = AudioExporter.shared
        var values: [Bool] = []
        let observation = exporter.$isExporting.sink { values.append($0) }
        _ = await exporter.withExclusiveExport { 1 }
        _ = await exporter.withExclusiveExport { 2 }
        XCTAssertEqual(values, [false, true, false, true, false])
        withExtendedLifetime(observation) {}
    }

    func testInvalidActualExportReleasesAndAllowsImmediateRetry() async {
        let exporter = AudioExporter.shared
        for _ in 0..<2 {
            let result = await exporter.exportToM4A(tracks: [], bpm: 120, loopLengthBeats: 4,
                sessionName: "invalid-test", soundFontURL: URL(fileURLWithPath: "/nonexistent.sf2"))
            XCTAssertNil(result)
            XCTAssertFalse(exporter.isExporting)
        }
    }
}
