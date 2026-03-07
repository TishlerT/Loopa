import Foundation

/// Represents a single MIDI note with beat-based timing
/// Used for piano roll editing and playback
struct MidiNote: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    
    /// MIDI note number (0-127, where 60 = middle C)
    var pitch: UInt8
    
    /// Note velocity (1-127, higher = louder)
    var velocity: UInt8
    
    /// Start position in beats from loop start
    var startBeat: Double
    
    /// Duration in beats
    var durationBeats: Double
    
    /// End beat (computed)
    var endBeat: Double {
        startBeat + durationBeats
    }
    
    init(
        id: UUID = UUID(),
        pitch: UInt8,
        velocity: UInt8 = 100,
        startBeat: Double,
        durationBeats: Double
    ) {
        self.id = id
        self.pitch = pitch
        self.velocity = max(1, min(127, velocity))
        self.startBeat = max(0, startBeat)
        self.durationBeats = max(0.0625, durationBeats) // Minimum 1/64 note
    }
    
    /// Human-readable note name (e.g., "C4", "F#5")
    var noteName: String {
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let octave = Int(pitch) / 12 - 1
        let noteName = noteNames[Int(pitch) % 12]
        return "\(noteName)\(octave)"
    }
}

// MARK: - Conversion from MidiEvent pairs

extension MidiNote {
    /// Convert a pair of note-on/note-off MidiEvents to a MidiNote
    /// - Parameters:
    ///   - noteOn: The note-on event
    ///   - noteOff: The corresponding note-off event
    ///   - bpm: Current tempo for time-to-beat conversion
    /// - Returns: A MidiNote, or nil if events don't match
    static func from(noteOn: MidiEvent, noteOff: MidiEvent, bpm: Double) -> MidiNote? {
        guard noteOn.isNoteOn && !noteOff.isNoteOn,
              noteOn.note == noteOff.note else {
            return nil
        }
        
        let secondsPerBeat = 60.0 / bpm
        let startBeat = noteOn.time / secondsPerBeat
        let endBeat = noteOff.time / secondsPerBeat
        let duration = max(0.0625, endBeat - startBeat) // Minimum 1/64 note
        
        return MidiNote(
            pitch: noteOn.note,
            velocity: noteOn.velocity,
            startBeat: startBeat,
            durationBeats: duration
        )
    }
    
    /// Convert an array of MidiEvents to MidiNotes by pairing note-on/off events
    /// - Parameters:
    ///   - events: Array of MidiEvents (note-on and note-off)
    ///   - bpm: Current tempo
    ///   - loopLengthBeats: Total loop length in beats (for wrapping)
    /// - Returns: Array of MidiNotes
    static func fromEvents(_ events: [MidiEvent], bpm: Double, loopLengthBeats: Double) -> [MidiNote] {
        var notes: [MidiNote] = []
        // Use array of pending note-ons per pitch to handle rapid repeated notes (e.g., hi-hat)
        var pendingNoteOns: [UInt8: [MidiEvent]] = [:]
        
        let secondsPerBeat = 60.0 / bpm
        
        for event in events.sorted(by: { $0.time < $1.time }) {
            if event.isNoteOn && event.velocity > 0 {
                // Note on - add to queue for this pitch
                if pendingNoteOns[event.note] == nil {
                    pendingNoteOns[event.note] = []
                }
                pendingNoteOns[event.note]?.append(event)
            } else {
                // Note off - find oldest matching note on (FIFO)
                if var queue = pendingNoteOns[event.note], !queue.isEmpty {
                    let noteOn = queue.removeFirst()
                    pendingNoteOns[event.note] = queue
                    
                    let startBeat = noteOn.time / secondsPerBeat
                    var endBeat = event.time / secondsPerBeat
                    
                    // Handle wrap-around (note off came before note on in time)
                    if endBeat < startBeat {
                        endBeat += loopLengthBeats
                    }
                    
                    let duration = max(0.0625, endBeat - startBeat)
                    
                    let note = MidiNote(
                        pitch: noteOn.note,
                        velocity: noteOn.velocity,
                        startBeat: startBeat,
                        durationBeats: min(duration, loopLengthBeats - startBeat)
                    )
                    notes.append(note)
                }
            }
        }
        
        // Handle any remaining note-ons (no matching note-off, assume short note for drums)
        for (_, queue) in pendingNoteOns {
            for noteOn in queue {
                let startBeat = noteOn.time / secondsPerBeat
                let note = MidiNote(
                    pitch: noteOn.note,
                    velocity: noteOn.velocity,
                    startBeat: startBeat,
                    durationBeats: min(0.25, loopLengthBeats - startBeat) // Short duration for unmatched (likely drums)
                )
                notes.append(note)
            }
        }
        
        return notes.sorted { $0.startBeat < $1.startBeat }
    }
    
    /// Convert this MidiNote back to MidiEvents for playback
    /// - Parameter bpm: Current tempo
    /// - Returns: Array containing note-on and note-off events
    func toEvents(bpm: Double) -> [MidiEvent] {
        let secondsPerBeat = 60.0 / bpm
        let startTime = startBeat * secondsPerBeat
        let endTime = endBeat * secondsPerBeat
        
        let noteOn = MidiEvent(
            time: startTime,
            note: pitch,
            velocity: velocity,
            isNoteOn: true,
            isLeft: false
        )
        
        let noteOff = MidiEvent(
            time: endTime,
            note: pitch,
            velocity: 0,
            isNoteOn: false,
            isLeft: false
        )
        
        return [noteOn, noteOff]
    }
}

