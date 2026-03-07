import Foundation

/// Note value divisions for quantization
enum QuantizeDivision: String, CaseIterable, Identifiable {
	case off = "Off"
	case quarter = "1/4"
	case eighth = "1/8"
	case sixteenth = "1/16"
	case thirtysecond = "1/32"
	
	var id: String { rawValue }
	
	/// Returns the fraction of a beat this division represents (nil for off)
	var beatFraction: Double? {
		switch self {
		case .off: return nil
		case .quarter: return 1.0
		case .eighth: return 0.5
		case .sixteenth: return 0.25
		case .thirtysecond: return 0.125
		}
	}
}

/// Quantizer for snapping MIDI event times to a grid
struct Quantizer {
	/// Current BPM (beats per minute)
	var bpm: Double
	
	/// Quantization division (how fine the grid is)
	var division: QuantizeDivision
	
	/// Seconds per beat at current BPM
	var secondsPerBeat: Double {
		60.0 / bpm
	}
	
	/// Grid size in seconds (nil if quantization is off)
	var gridSize: Double? {
		guard let fraction = division.beatFraction else { return nil }
		return secondsPerBeat * fraction
	}
	
	/// Grid size in beats (nil if quantization is off)
	var gridSizeBeats: Double? {
		division.beatFraction
	}
	
	/// Quantize a time value to the nearest grid point
	/// - Parameter time: Time in seconds
	/// - Returns: Quantized time (same as input if division is .off)
	func quantize(time: Double) -> Double {
		guard let grid = gridSize else { return time }
		guard grid > 0 else { return time }
		
		// Round to nearest grid point
		let gridIndex = round(time / grid)
		return gridIndex * grid
	}
	
	/// Quantize a time value within a loop boundary
	/// - Parameters:
	///   - time: Time in seconds
	///   - loopLength: Total loop length in seconds
	/// - Returns: Quantized time, wrapped to loop bounds if necessary
	func quantize(time: Double, loopLength: Double) -> Double {
		guard let grid = gridSize else { return time }
		guard grid > 0, loopLength > 0 else { return time }
		
		// Round to nearest grid point
		let gridIndex = round(time / grid)
		var quantized = gridIndex * grid
		
		// Handle wrap-around: if quantized is at or past loop end, wrap to start
		if quantized >= loopLength {
			quantized = fmod(quantized, loopLength)
		}
		
		return quantized
	}
	
	/// Quantize an array of MIDI events
	/// - Parameters:
	///   - events: Array of events to quantize
	///   - loopLength: Optional loop length for wrap-around handling
	/// - Returns: New array with quantized event times
	func quantize(events: [MidiEvent], loopLength: Double? = nil) -> [MidiEvent] {
		return events.map { event in
			let quantizedTime: Double
			if let loop = loopLength {
				quantizedTime = quantize(time: event.time, loopLength: loop)
			} else {
				quantizedTime = quantize(time: event.time)
			}
			
			return MidiEvent(
				time: quantizedTime,
				note: event.note,
				velocity: event.velocity,
				isNoteOn: event.isNoteOn,
				isLeft: event.isLeft
			)
		}
	}
	
	// MARK: - Beat-Based Quantization (for MidiNote)
	
	/// Quantize a beat value to the nearest grid point
	/// - Parameter beat: Beat position
	/// - Returns: Quantized beat (same as input if division is .off)
	func quantizeBeat(_ beat: Double) -> Double {
		guard let gridBeats = gridSizeBeats else { return beat }
		guard gridBeats > 0 else { return beat }
		
		let gridIndex = round(beat / gridBeats)
		return gridIndex * gridBeats
	}
	
	/// Quantize a beat value within loop bounds
	/// - Parameters:
	///   - beat: Beat position
	///   - loopLengthBeats: Total loop length in beats
	/// - Returns: Quantized beat, clamped to [0, loopLengthBeats)
	func quantizeBeat(_ beat: Double, loopLengthBeats: Double) -> Double {
		guard let gridBeats = gridSizeBeats else { return beat }
		guard gridBeats > 0, loopLengthBeats > 0 else { return beat }
		
		let gridIndex = round(beat / gridBeats)
		var quantized = gridIndex * gridBeats
		
		// Clamp to loop bounds
		if quantized >= loopLengthBeats {
			quantized = fmod(quantized, loopLengthBeats)
		}
		if quantized < 0 {
			quantized = 0
		}
		
		return quantized
	}
	
	/// Quantize a duration value with minimum constraint
	/// - Parameters:
	///   - duration: Duration in beats
	///   - minDuration: Minimum duration (defaults to grid size or 1/64)
	/// - Returns: Quantized duration, at least minDuration
	func quantizeDuration(_ duration: Double, minDuration: Double? = nil) -> Double {
		guard let gridBeats = gridSizeBeats else { return duration }
		guard gridBeats > 0 else { return duration }
		
		let minimum = minDuration ?? gridBeats
		let gridIndex = max(1, round(duration / gridBeats))
		return max(minimum, gridIndex * gridBeats)
	}
	
	/// Quantize a single MidiNote
	/// - Parameters:
	///   - note: The note to quantize
	///   - loopLengthBeats: Total loop length in beats
	/// - Returns: A new MidiNote with quantized startBeat and durationBeats
	func quantize(note: MidiNote, loopLengthBeats: Double) -> MidiNote {
		guard let gridBeats = gridSizeBeats else { return note }
		
		let quantizedStart = quantizeBeat(note.startBeat, loopLengthBeats: loopLengthBeats)
		var quantizedDuration = quantizeDuration(note.durationBeats, minDuration: gridBeats)
		
		// Clamp duration so note doesn't exceed loop bounds
		let maxDuration = loopLengthBeats - quantizedStart
		quantizedDuration = min(quantizedDuration, max(gridBeats, maxDuration))
		
		return MidiNote(
			id: note.id,
			pitch: note.pitch,
			velocity: note.velocity,
			startBeat: quantizedStart,
			durationBeats: quantizedDuration
		)
	}
	
	/// Quantize an array of MidiNotes
	/// - Parameters:
	///   - notes: Array of notes to quantize
	///   - loopLengthBeats: Total loop length in beats
	/// - Returns: New array with quantized notes
	func quantize(notes: [MidiNote], loopLengthBeats: Double) -> [MidiNote] {
		guard division != .off else { return notes }
		
		return notes.map { note in
			quantize(note: note, loopLengthBeats: loopLengthBeats)
		}.sorted { $0.startBeat < $1.startBeat }
	}
}

// MARK: - Static Quantization Helpers

extension Quantizer {
	/// Snap a beat value to a grid without creating a Quantizer instance
	/// - Parameters:
	///   - beat: Beat position to snap
	///   - gridStep: Grid step size in beats (e.g., 0.25 for 1/16)
	/// - Returns: Snapped beat value
	static func snap(_ beat: Double, toGrid gridStep: Double) -> Double {
		guard gridStep > 0 else { return beat }
		return round(beat / gridStep) * gridStep
	}
	
	/// Clamp a beat value within loop bounds
	/// - Parameters:
	///   - beat: Beat position to clamp
	///   - loopLengthBeats: Total loop length in beats
	///   - minBeat: Minimum beat value (default 0)
	/// - Returns: Clamped beat value
	static func clamp(_ beat: Double, loopLengthBeats: Double, minBeat: Double = 0) -> Double {
		return max(minBeat, min(beat, loopLengthBeats))
	}
	
	/// Clamp a duration within valid bounds
	/// - Parameters:
	///   - duration: Duration in beats
	///   - startBeat: Start position of the note
	///   - loopLengthBeats: Total loop length in beats
	///   - gridStep: Minimum duration (grid step)
	/// - Returns: Clamped duration
	static func clampDuration(_ duration: Double, startBeat: Double, loopLengthBeats: Double, gridStep: Double) -> Double {
		let minDuration = gridStep
		let maxDuration = loopLengthBeats - startBeat
		return max(minDuration, min(duration, maxDuration))
	}
}

