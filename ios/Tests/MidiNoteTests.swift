import XCTest
@testable import Loopa

final class MidiNoteTests: XCTestCase {
    
    // MARK: - Beat-Based Quantization Tests
    
    func testSnapToGridQuarterNote() {
        let quantizer = Quantizer(bpm: 120, division: .quarter)
        
        // Grid is 1 beat
        XCTAssertEqual(quantizer.quantizeBeat(0.0), 0.0)
        XCTAssertEqual(quantizer.quantizeBeat(0.4), 0.0)
        XCTAssertEqual(quantizer.quantizeBeat(0.6), 1.0)
        XCTAssertEqual(quantizer.quantizeBeat(1.2), 1.0)
        XCTAssertEqual(quantizer.quantizeBeat(1.8), 2.0)
    }
    
    func testSnapToGridSixteenthNote() {
        let quantizer = Quantizer(bpm: 120, division: .sixteenth)
        
        // Grid is 0.25 beats
        XCTAssertEqual(quantizer.quantizeBeat(0.0), 0.0)
        XCTAssertEqual(quantizer.quantizeBeat(0.1), 0.0)
        XCTAssertEqual(quantizer.quantizeBeat(0.15), 0.25)
        XCTAssertEqual(quantizer.quantizeBeat(0.3), 0.25)
        XCTAssertEqual(quantizer.quantizeBeat(0.4), 0.5)
    }
    
    func testQuantizeBeatWithLoopBounds() {
        let quantizer = Quantizer(bpm: 120, division: .quarter)
        let loopLength: Double = 16.0 // 4 bars
        
        // Should wrap at loop boundary
        XCTAssertEqual(quantizer.quantizeBeat(15.8, loopLengthBeats: loopLength), 0.0)
        XCTAssertEqual(quantizer.quantizeBeat(16.0, loopLengthBeats: loopLength), 0.0)
    }
    
    func testQuantizeDurationMinimum() {
        let quantizer = Quantizer(bpm: 120, division: .sixteenth)
        
        // Duration should be at least one grid step (0.25)
        XCTAssertEqual(quantizer.quantizeDuration(0.1), 0.25)
        XCTAssertEqual(quantizer.quantizeDuration(0.2), 0.25)
        XCTAssertEqual(quantizer.quantizeDuration(0.3), 0.25)
        XCTAssertEqual(quantizer.quantizeDuration(0.4), 0.5)
    }
    
    func testQuantizeMidiNote() {
        let quantizer = Quantizer(bpm: 120, division: .sixteenth)
        let loopLength: Double = 16.0
        
        let note = MidiNote(
            pitch: 60,
            velocity: 100,
            startBeat: 0.1,
            durationBeats: 0.3
        )
        
        let quantized = quantizer.quantize(note: note, loopLengthBeats: loopLength)
        
        XCTAssertEqual(quantized.startBeat, 0.0)
        XCTAssertEqual(quantized.durationBeats, 0.25)
        XCTAssertEqual(quantized.pitch, 60)
        XCTAssertEqual(quantized.velocity, 100)
    }
    
    func testQuantizeNotesArray() {
        let quantizer = Quantizer(bpm: 120, division: .quarter)
        let loopLength: Double = 8.0
        
        let notes = [
            MidiNote(pitch: 60, startBeat: 0.2, durationBeats: 0.8),
            MidiNote(pitch: 64, startBeat: 1.1, durationBeats: 0.9),
            MidiNote(pitch: 67, startBeat: 2.3, durationBeats: 1.2)
        ]
        
        let quantized = quantizer.quantize(notes: notes, loopLengthBeats: loopLength)
        
        XCTAssertEqual(quantized.count, 3)
        XCTAssertEqual(quantized[0].startBeat, 0.0)
        XCTAssertEqual(quantized[1].startBeat, 1.0)
        XCTAssertEqual(quantized[2].startBeat, 2.0)
    }
    
    func testQuantizeOffDoesNotModify() {
        let quantizer = Quantizer(bpm: 120, division: .off)
        
        let note = MidiNote(
            pitch: 60,
            velocity: 100,
            startBeat: 0.123,
            durationBeats: 0.456
        )
        
        let quantized = quantizer.quantize(note: note, loopLengthBeats: 16.0)
        
        XCTAssertEqual(quantized.startBeat, 0.123)
        XCTAssertEqual(quantized.durationBeats, 0.456)
    }
    
    // MARK: - Static Helpers Tests
    
    func testStaticSnap() {
        XCTAssertEqual(Quantizer.snap(0.1, toGrid: 0.25), 0.0)
        XCTAssertEqual(Quantizer.snap(0.15, toGrid: 0.25), 0.25)
        XCTAssertEqual(Quantizer.snap(0.9, toGrid: 0.5), 1.0)
    }
    
    func testStaticClamp() {
        XCTAssertEqual(Quantizer.clamp(-1.0, loopLengthBeats: 16.0), 0.0)
        XCTAssertEqual(Quantizer.clamp(20.0, loopLengthBeats: 16.0), 16.0)
        XCTAssertEqual(Quantizer.clamp(8.0, loopLengthBeats: 16.0), 8.0)
    }
    
    func testStaticClampDuration() {
        let duration = Quantizer.clampDuration(5.0, startBeat: 14.0, loopLengthBeats: 16.0, gridStep: 0.25)
        XCTAssertEqual(duration, 2.0) // Can only fit 2 beats
        
        let minDuration = Quantizer.clampDuration(0.1, startBeat: 0.0, loopLengthBeats: 16.0, gridStep: 0.25)
        XCTAssertEqual(minDuration, 0.25) // Minimum is grid step
    }
    
    // MARK: - Event Conversion Tests
    
    func testConvertEventsToNotes() {
        let bpm: Double = 120
        let loopLengthBeats: Double = 8.0
        
        let events = [
            MidiEvent(time: 0.0, note: 60, velocity: 100, isNoteOn: true, isLeft: false),
            MidiEvent(time: 0.5, note: 60, velocity: 0, isNoteOn: false, isLeft: false),
            MidiEvent(time: 1.0, note: 64, velocity: 90, isNoteOn: true, isLeft: false),
            MidiEvent(time: 1.5, note: 64, velocity: 0, isNoteOn: false, isLeft: false)
        ]
        
        let notes = MidiNote.fromEvents(events, bpm: bpm, loopLengthBeats: loopLengthBeats)
        
        XCTAssertEqual(notes.count, 2)
        XCTAssertEqual(notes[0].pitch, 60)
        XCTAssertEqual(notes[0].startBeat, 0.0)
        XCTAssertEqual(notes[0].durationBeats, 1.0, accuracy: 0.01) // 0.5 seconds at 120 BPM = 1 beat
        XCTAssertEqual(notes[1].pitch, 64)
    }
    
    // MARK: - Drum Quantization Tests
    
    func testDrumNotesAreQuantizedToSixteenthNotes() {
        // Simulate drum notes recorded at off-grid positions (common when playing live)
        // Quantizer uses round(), so values snap to nearest 0.25 boundary
        let offGridNotes = [
            MidiNote(pitch: 36, velocity: 100, startBeat: 0.13, durationBeats: 0.25),  // 0.13 / 0.25 = 0.52 -> rounds to 1 -> 0.25
            MidiNote(pitch: 38, velocity: 100, startBeat: 0.38, durationBeats: 0.25),  // 0.38 / 0.25 = 1.52 -> rounds to 2 -> 0.5
            MidiNote(pitch: 42, velocity: 100, startBeat: 0.87, durationBeats: 0.25),  // 0.87 / 0.25 = 3.48 -> rounds to 3 -> 0.75
            MidiNote(pitch: 46, velocity: 100, startBeat: 1.63, durationBeats: 0.25),  // 1.63 / 0.25 = 6.52 -> rounds to 7 -> 1.75
        ]
        
        let quantizer = Quantizer(bpm: 100, division: .sixteenth)
        let quantized = quantizer.quantize(notes: offGridNotes, loopLengthBeats: 4.0)
        
        // All notes should now align with 16th note grid (0, 0.25, 0.5, 0.75, 1.0, etc.)
        XCTAssertEqual(quantized[0].startBeat, 0.25, accuracy: 0.001)
        XCTAssertEqual(quantized[1].startBeat, 0.5, accuracy: 0.001)
        XCTAssertEqual(quantized[2].startBeat, 0.75, accuracy: 0.001)
        XCTAssertEqual(quantized[3].startBeat, 1.75, accuracy: 0.001)
    }
    
    func testDrumNotesVisibleInStepSequencerGrid() {
        // This tests that quantized drum notes will be found by DrumGridView's noteAt() function
        // which uses a tolerance of 0.0625 beats (half of a 32nd note)
        let tolerance = 0.125 / 2  // Same as DrumGridView.noteAt()
        
        let offGridNotes = [
            MidiNote(pitch: 36, velocity: 100, startBeat: 0.18, durationBeats: 0.25),
            MidiNote(pitch: 38, velocity: 100, startBeat: 0.93, durationBeats: 0.25),
        ]
        
        let quantizer = Quantizer(bpm: 100, division: .sixteenth)
        let quantized = quantizer.quantize(notes: offGridNotes, loopLengthBeats: 4.0)
        
        // Check that each quantized note is within tolerance of its target grid position
        let gridPositions: [Double] = [0.25, 1.0]  // Expected snap positions
        
        for (note, expectedBeat) in zip(quantized, gridPositions) {
            let distance = abs(note.startBeat - expectedBeat)
            XCTAssertLessThan(distance, tolerance, 
                "Note at \(note.startBeat) is \(distance) beats from grid position \(expectedBeat), exceeds tolerance \(tolerance)")
        }
    }
}

