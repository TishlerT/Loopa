package com.loopa.core.looper

import com.loopa.core.model.MidiEvent
import com.loopa.core.model.MidiNote
import com.loopa.core.model.QuantizeDivision
import kotlin.math.max
import kotlin.math.round

/**
 * Quantizer for snapping MIDI event times to a grid.
 * Ported from iOS Quantizer.swift.
 */
data class Quantizer(
    /** Current BPM (beats per minute) */
    val bpm: Double,
    /** Quantization division (how fine the grid is) */
    val division: QuantizeDivision
) {
    /** Seconds per beat at current BPM */
    val secondsPerBeat: Double
        get() = 60.0 / bpm

    /** Grid size in seconds (null if quantization is off) */
    val gridSize: Double?
        get() {
            val fraction = division.beatFraction ?: return null
            return secondsPerBeat * fraction
        }

    /** Grid size in beats (null if quantization is off) */
    val gridSizeBeats: Double?
        get() = division.beatFraction

    // MARK: - Time-Based Quantization

    /** Quantize a time value to the nearest grid point */
    fun quantize(time: Double): Double {
        val grid = gridSize ?: return time
        if (grid <= 0) return time
        val gridIndex = round(time / grid)
        return gridIndex * grid
    }

    /** Quantize a time value within a loop boundary */
    fun quantize(time: Double, loopLength: Double): Double {
        val grid = gridSize ?: return time
        if (grid <= 0 || loopLength <= 0) return time
        val gridIndex = round(time / grid)
        var quantized = gridIndex * grid
        if (quantized >= loopLength) {
            quantized = quantized.mod(loopLength)
        }
        return quantized
    }

    /** Quantize an array of MIDI events */
    fun quantize(events: List<MidiEvent>, loopLength: Double? = null): List<MidiEvent> {
        return events.map { event ->
            val quantizedTime = if (loopLength != null) {
                quantize(event.time, loopLength)
            } else {
                quantize(event.time)
            }
            event.copy(time = quantizedTime)
        }
    }

    // MARK: - Beat-Based Quantization (for MidiNote)

    /** Quantize a beat value to the nearest grid point */
    fun quantizeBeat(beat: Double): Double {
        val gridBeats = gridSizeBeats ?: return beat
        if (gridBeats <= 0) return beat
        val gridIndex = round(beat / gridBeats)
        return gridIndex * gridBeats
    }

    /** Quantize a beat value within loop bounds */
    fun quantizeBeat(beat: Double, loopLengthBeats: Double): Double {
        val gridBeats = gridSizeBeats ?: return beat
        if (gridBeats <= 0 || loopLengthBeats <= 0) return beat
        val gridIndex = round(beat / gridBeats)
        var quantized = gridIndex * gridBeats
        if (quantized >= loopLengthBeats) {
            quantized = quantized.mod(loopLengthBeats)
        }
        if (quantized < 0) {
            quantized = 0.0
        }
        return quantized
    }

    /** Quantize a duration value with minimum constraint */
    fun quantizeDuration(duration: Double, minDuration: Double? = null): Double {
        val gridBeats = gridSizeBeats ?: return duration
        if (gridBeats <= 0) return duration
        val minimum = minDuration ?: gridBeats
        val gridIndex = max(1.0, round(duration / gridBeats))
        return max(minimum, gridIndex * gridBeats)
    }

    /** Quantize a single MidiNote */
    fun quantize(note: MidiNote, loopLengthBeats: Double): MidiNote {
        val gridBeats = gridSizeBeats ?: return note
        val quantizedStart = quantizeBeat(note.startBeat, loopLengthBeats)
        var quantizedDuration = quantizeDuration(note.durationBeats, gridBeats)
        val maxDuration = loopLengthBeats - quantizedStart
        quantizedDuration = minOf(quantizedDuration, max(gridBeats, maxDuration))

        return MidiNote.create(
            id = note.id,
            pitch = note.pitch,
            velocity = note.velocity,
            startBeat = quantizedStart,
            durationBeats = quantizedDuration
        )
    }

    /** Quantize an array of MidiNotes */
    fun quantize(notes: List<MidiNote>, loopLengthBeats: Double): List<MidiNote> {
        if (division == QuantizeDivision.OFF) return notes
        return notes.map { quantize(it, loopLengthBeats) }.sortedBy { it.startBeat }
    }

    companion object {
        /** Snap a beat value to a grid */
        fun snap(beat: Double, gridStep: Double): Double {
            if (gridStep <= 0) return beat
            return round(beat / gridStep) * gridStep
        }

        /** Clamp a beat value within loop bounds */
        fun clamp(beat: Double, loopLengthBeats: Double, minBeat: Double = 0.0): Double {
            return max(minBeat, minOf(beat, loopLengthBeats))
        }

        /** Clamp a duration within valid bounds */
        fun clampDuration(duration: Double, startBeat: Double, loopLengthBeats: Double, gridStep: Double): Double {
            val minDuration = gridStep
            val maxDuration = loopLengthBeats - startBeat
            return max(minDuration, minOf(duration, maxDuration))
        }
    }
}
