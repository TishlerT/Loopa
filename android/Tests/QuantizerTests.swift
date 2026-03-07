import XCTest
@testable import Loopa

final class QuantizerTests: XCTestCase {
	
	// MARK: - Division Tests
	
	func testQuantizeDivisionBeatFractions() {
		XCTAssertNil(QuantizeDivision.off.beatFraction, "Off should have nil fraction")
		XCTAssertEqual(QuantizeDivision.quarter.beatFraction!, 1.0, accuracy: 0.001)
		XCTAssertEqual(QuantizeDivision.eighth.beatFraction!, 0.5, accuracy: 0.001)
		XCTAssertEqual(QuantizeDivision.sixteenth.beatFraction!, 0.25, accuracy: 0.001)
		XCTAssertEqual(QuantizeDivision.thirtysecond.beatFraction!, 0.125, accuracy: 0.001)
	}
	
	// MARK: - Time Quantization Tests
	
	func testQuantizeTimeOff() {
		let quantizer = Quantizer(bpm: 120, division: .off)
		let time = 0.123
		XCTAssertEqual(quantizer.quantize(time: time), time, "Off should not modify time")
	}
	
	func testQuantizeTimeQuarter() {
		let quantizer = Quantizer(bpm: 120, division: .quarter)
		// At 120 BPM, a quarter note is 0.5 seconds
		
		XCTAssertEqual(quantizer.quantize(time: 0.0), 0.0, accuracy: 0.001)
		XCTAssertEqual(quantizer.quantize(time: 0.1), 0.0, accuracy: 0.001, "0.1s should snap to 0.0")
		XCTAssertEqual(quantizer.quantize(time: 0.3), 0.5, accuracy: 0.001, "0.3s should snap to 0.5")
		XCTAssertEqual(quantizer.quantize(time: 0.5), 0.5, accuracy: 0.001)
		XCTAssertEqual(quantizer.quantize(time: 0.7), 0.5, accuracy: 0.001, "0.7s should snap to 0.5")
		XCTAssertEqual(quantizer.quantize(time: 0.9), 1.0, accuracy: 0.001, "0.9s should snap to 1.0")
	}
	
	func testQuantizeTimeEighth() {
		let quantizer = Quantizer(bpm: 120, division: .eighth)
		// At 120 BPM, an eighth note is 0.25 seconds
		
		XCTAssertEqual(quantizer.quantize(time: 0.0), 0.0, accuracy: 0.001)
		XCTAssertEqual(quantizer.quantize(time: 0.1), 0.0, accuracy: 0.001, "0.1s should snap to 0.0")
		XCTAssertEqual(quantizer.quantize(time: 0.15), 0.25, accuracy: 0.001, "0.15s should snap to 0.25")
		XCTAssertEqual(quantizer.quantize(time: 0.25), 0.25, accuracy: 0.001)
	}
	
	func testQuantizeTimeSixteenth() {
		let quantizer = Quantizer(bpm: 120, division: .sixteenth)
		// At 120 BPM, a sixteenth note is 0.125 seconds
		
		XCTAssertEqual(quantizer.quantize(time: 0.0), 0.0, accuracy: 0.001)
		XCTAssertEqual(quantizer.quantize(time: 0.05), 0.0, accuracy: 0.001)
		XCTAssertEqual(quantizer.quantize(time: 0.1), 0.125, accuracy: 0.001)
		XCTAssertEqual(quantizer.quantize(time: 0.125), 0.125, accuracy: 0.001)
	}
	
	// MARK: - Event Quantization Tests
	
	func testQuantizeEventsOff() {
		let quantizer = Quantizer(bpm: 120, division: .off)
		let events = [
			MidiEvent(time: 0.123, note: 60, velocity: 100, isNoteOn: true, isLeft: false)
		]
		
		let quantized = quantizer.quantize(events: events)
		XCTAssertEqual(quantized.count, 1)
		XCTAssertEqual(quantized[0].time, 0.123, "Off should not modify event time")
	}
	
	func testQuantizeEventsQuarter() {
		let quantizer = Quantizer(bpm: 120, division: .quarter)
		let events = [
			MidiEvent(time: 0.1, note: 60, velocity: 100, isNoteOn: true, isLeft: false),
			MidiEvent(time: 0.6, note: 62, velocity: 100, isNoteOn: true, isLeft: false)
		]
		
		let quantized = quantizer.quantize(events: events)
		XCTAssertEqual(quantized.count, 2)
		XCTAssertEqual(quantized[0].time, 0.0, accuracy: 0.001, "0.1s should snap to 0.0")
		XCTAssertEqual(quantized[1].time, 0.5, accuracy: 0.001, "0.6s should snap to 0.5")
	}
	
	func testQuantizeEventsPreservesOtherProperties() {
		let quantizer = Quantizer(bpm: 120, division: .quarter)
		let event = MidiEvent(time: 0.1, note: 60, velocity: 100, isNoteOn: true, isLeft: true)
		
		let quantized = quantizer.quantize(events: [event])
		XCTAssertEqual(quantized[0].note, 60, "Note should be preserved")
		XCTAssertEqual(quantized[0].velocity, 100, "Velocity should be preserved")
		XCTAssertTrue(quantized[0].isNoteOn, "isNoteOn should be preserved")
		XCTAssertTrue(quantized[0].isLeft, "isLeft should be preserved")
	}
	
	// MARK: - BPM Variation Tests
	
	func testQuantizeAtDifferentBPMs() {
		// At 60 BPM, a quarter note is 1.0 second
		let slow = Quantizer(bpm: 60, division: .quarter)
		XCTAssertEqual(slow.quantize(time: 0.3), 0.0, accuracy: 0.001)
		XCTAssertEqual(slow.quantize(time: 0.7), 1.0, accuracy: 0.001)
		
		// At 180 BPM, a quarter note is 0.333 seconds
		let fast = Quantizer(bpm: 180, division: .quarter)
		XCTAssertEqual(fast.quantize(time: 0.1), 0.0, accuracy: 0.001)
		XCTAssertEqual(fast.quantize(time: 0.25), 0.333, accuracy: 0.01)
	}
	
	// MARK: - Loop Length Tests
	
	func testQuantizeWithLoopLength() {
		let quantizer = Quantizer(bpm: 120, division: .quarter)
		// Quarter note at 120 BPM = 0.5s
		// With 2.0s loop, times should wrap
		
		let quantized = quantizer.quantize(time: 2.3, loopLength: 2.0)
		// 2.3 -> rounds to 2.5 -> mod 2.0 = 0.5
		XCTAssertEqual(quantized, 0.5, accuracy: 0.001)
	}
}

