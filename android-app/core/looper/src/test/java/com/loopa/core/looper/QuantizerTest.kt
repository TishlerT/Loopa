package com.loopa.core.looper

import com.loopa.core.model.MidiEvent
import com.loopa.core.model.MidiNote
import com.loopa.core.model.QuantizeDivision
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.Assertions.*

/**
 * Tests for Quantizer — ported from iOS QuantizerTests.swift and MidiNoteTests.swift
 */
class QuantizerTest {

    // MARK: - Division Tests

    @Test
    fun `division beat fractions`() {
        assertNull(QuantizeDivision.OFF.beatFraction)
        assertEquals(1.0, QuantizeDivision.QUARTER.beatFraction!!, 0.001)
        assertEquals(0.5, QuantizeDivision.EIGHTH.beatFraction!!, 0.001)
        assertEquals(0.25, QuantizeDivision.SIXTEENTH.beatFraction!!, 0.001)
        assertEquals(0.125, QuantizeDivision.THIRTY_SECOND.beatFraction!!, 0.001)
    }

    // MARK: - Time Quantization

    @Test
    fun `quantize time off`() {
        val quantizer = Quantizer(bpm = 120.0, division = QuantizeDivision.OFF)
        assertEquals(0.123, quantizer.quantize(0.123), 0.001)
    }

    @Test
    fun `quantize time quarter`() {
        val quantizer = Quantizer(bpm = 120.0, division = QuantizeDivision.QUARTER)
        assertEquals(0.0, quantizer.quantize(0.0), 0.001)
        assertEquals(0.0, quantizer.quantize(0.1), 0.001)
        assertEquals(0.5, quantizer.quantize(0.3), 0.001)
        assertEquals(0.5, quantizer.quantize(0.5), 0.001)
        assertEquals(0.5, quantizer.quantize(0.7), 0.001)
        assertEquals(1.0, quantizer.quantize(0.9), 0.001)
    }

    @Test
    fun `quantize time eighth`() {
        val quantizer = Quantizer(bpm = 120.0, division = QuantizeDivision.EIGHTH)
        assertEquals(0.0, quantizer.quantize(0.0), 0.001)
        assertEquals(0.0, quantizer.quantize(0.1), 0.001)
        assertEquals(0.25, quantizer.quantize(0.15), 0.001)
        assertEquals(0.25, quantizer.quantize(0.25), 0.001)
    }

    @Test
    fun `quantize time sixteenth`() {
        val quantizer = Quantizer(bpm = 120.0, division = QuantizeDivision.SIXTEENTH)
        assertEquals(0.0, quantizer.quantize(0.0), 0.001)
        assertEquals(0.0, quantizer.quantize(0.05), 0.001)
        assertEquals(0.125, quantizer.quantize(0.1), 0.001)
        assertEquals(0.125, quantizer.quantize(0.125), 0.001)
    }

    // MARK: - Event Quantization

    @Test
    fun `quantize events off`() {
        val quantizer = Quantizer(bpm = 120.0, division = QuantizeDivision.OFF)
        val events = listOf(MidiEvent(time = 0.123, note = 60u, velocity = 100u, isNoteOn = true, isLeft = false))
        val quantized = quantizer.quantize(events)
        assertEquals(1, quantized.size)
        assertEquals(0.123, quantized[0].time, 0.001)
    }

    @Test
    fun `quantize events quarter`() {
        val quantizer = Quantizer(bpm = 120.0, division = QuantizeDivision.QUARTER)
        val events = listOf(
            MidiEvent(time = 0.1, note = 60u, velocity = 100u, isNoteOn = true, isLeft = false),
            MidiEvent(time = 0.6, note = 62u, velocity = 100u, isNoteOn = true, isLeft = false)
        )
        val quantized = quantizer.quantize(events)
        assertEquals(2, quantized.size)
        assertEquals(0.0, quantized[0].time, 0.001)
        assertEquals(0.5, quantized[1].time, 0.001)
    }

    @Test
    fun `quantize events preserves other properties`() {
        val quantizer = Quantizer(bpm = 120.0, division = QuantizeDivision.QUARTER)
        val event = MidiEvent(time = 0.1, note = 60u, velocity = 100u, isNoteOn = true, isLeft = true)
        val quantized = quantizer.quantize(listOf(event))
        assertEquals(60.toUByte(), quantized[0].note)
        assertEquals(100.toUByte(), quantized[0].velocity)
        assertTrue(quantized[0].isNoteOn)
        assertTrue(quantized[0].isLeft)
    }

    // MARK: - BPM Variation

    @Test
    fun `quantize at different BPMs`() {
        val slow = Quantizer(bpm = 60.0, division = QuantizeDivision.QUARTER)
        assertEquals(0.0, slow.quantize(0.3), 0.001)
        assertEquals(1.0, slow.quantize(0.7), 0.001)

        val fast = Quantizer(bpm = 180.0, division = QuantizeDivision.QUARTER)
        assertEquals(0.0, fast.quantize(0.1), 0.001)
        assertEquals(0.333, fast.quantize(0.25), 0.01)
    }

    // MARK: - Loop Length

    @Test
    fun `quantize with loop length`() {
        val quantizer = Quantizer(bpm = 120.0, division = QuantizeDivision.QUARTER)
        val quantized = quantizer.quantize(2.3, 2.0)
        assertEquals(0.5, quantized, 0.001)
    }

    // MARK: - Beat Quantization

    @Test
    fun `snap to grid quarter note`() {
        val quantizer = Quantizer(bpm = 120.0, division = QuantizeDivision.QUARTER)
        assertEquals(0.0, quantizer.quantizeBeat(0.0), 0.001)
        assertEquals(0.0, quantizer.quantizeBeat(0.4), 0.001)
        assertEquals(1.0, quantizer.quantizeBeat(0.6), 0.001)
        assertEquals(1.0, quantizer.quantizeBeat(1.2), 0.001)
        assertEquals(2.0, quantizer.quantizeBeat(1.8), 0.001)
    }

    @Test
    fun `snap to grid sixteenth note`() {
        val quantizer = Quantizer(bpm = 120.0, division = QuantizeDivision.SIXTEENTH)
        assertEquals(0.0, quantizer.quantizeBeat(0.0), 0.001)
        assertEquals(0.0, quantizer.quantizeBeat(0.1), 0.001)
        assertEquals(0.25, quantizer.quantizeBeat(0.15), 0.001)
        assertEquals(0.25, quantizer.quantizeBeat(0.3), 0.001)
        assertEquals(0.5, quantizer.quantizeBeat(0.4), 0.001)
    }

    @Test
    fun `quantize beat with loop bounds`() {
        val quantizer = Quantizer(bpm = 120.0, division = QuantizeDivision.QUARTER)
        assertEquals(0.0, quantizer.quantizeBeat(15.8, 16.0), 0.001)
        assertEquals(0.0, quantizer.quantizeBeat(16.0, 16.0), 0.001)
    }

    @Test
    fun `quantize duration minimum`() {
        val quantizer = Quantizer(bpm = 120.0, division = QuantizeDivision.SIXTEENTH)
        assertEquals(0.25, quantizer.quantizeDuration(0.1), 0.001)
        assertEquals(0.25, quantizer.quantizeDuration(0.2), 0.001)
        assertEquals(0.25, quantizer.quantizeDuration(0.3), 0.001)
        assertEquals(0.5, quantizer.quantizeDuration(0.4), 0.001)
    }

    @Test
    fun `quantize MidiNote`() {
        val quantizer = Quantizer(bpm = 120.0, division = QuantizeDivision.SIXTEENTH)
        val note = MidiNote.create(pitch = 60u, velocity = 100u, startBeat = 0.1, durationBeats = 0.3)
        val quantized = quantizer.quantize(note, 16.0)
        assertEquals(0.0, quantized.startBeat, 0.001)
        assertEquals(0.25, quantized.durationBeats, 0.001)
        assertEquals(60.toUByte(), quantized.pitch)
        assertEquals(100.toUByte(), quantized.velocity)
    }

    @Test
    fun `quantize notes array`() {
        val quantizer = Quantizer(bpm = 120.0, division = QuantizeDivision.QUARTER)
        val notes = listOf(
            MidiNote.create(pitch = 60u, startBeat = 0.2, durationBeats = 0.8),
            MidiNote.create(pitch = 64u, startBeat = 1.1, durationBeats = 0.9),
            MidiNote.create(pitch = 67u, startBeat = 2.3, durationBeats = 1.2)
        )
        val quantized = quantizer.quantize(notes, 8.0)
        assertEquals(3, quantized.size)
        assertEquals(0.0, quantized[0].startBeat, 0.001)
        assertEquals(1.0, quantized[1].startBeat, 0.001)
        assertEquals(2.0, quantized[2].startBeat, 0.001)
    }

    @Test
    fun `quantize off does not modify`() {
        val quantizer = Quantizer(bpm = 120.0, division = QuantizeDivision.OFF)
        val note = MidiNote.create(pitch = 60u, velocity = 100u, startBeat = 0.123, durationBeats = 0.456)
        val quantized = quantizer.quantize(note, 16.0)
        assertEquals(0.123, quantized.startBeat, 0.001)
        assertEquals(0.456, quantized.durationBeats, 0.001)
    }

    // MARK: - Static Helpers

    @Test
    fun `static snap`() {
        assertEquals(0.0, Quantizer.snap(0.1, 0.25), 0.001)
        assertEquals(0.25, Quantizer.snap(0.15, 0.25), 0.001)
        assertEquals(1.0, Quantizer.snap(0.9, 0.5), 0.001)
    }

    @Test
    fun `static clamp`() {
        assertEquals(0.0, Quantizer.clamp(-1.0, 16.0), 0.001)
        assertEquals(16.0, Quantizer.clamp(20.0, 16.0), 0.001)
        assertEquals(8.0, Quantizer.clamp(8.0, 16.0), 0.001)
    }

    @Test
    fun `static clamp duration`() {
        assertEquals(2.0, Quantizer.clampDuration(5.0, 14.0, 16.0, 0.25), 0.001)
        assertEquals(0.25, Quantizer.clampDuration(0.1, 0.0, 16.0, 0.25), 0.001)
    }

    // MARK: - Drum Quantization

    @Test
    fun `drum notes quantized to sixteenth notes`() {
        val offGridNotes = listOf(
            MidiNote.create(pitch = 36u, velocity = 100u, startBeat = 0.13, durationBeats = 0.25),
            MidiNote.create(pitch = 38u, velocity = 100u, startBeat = 0.38, durationBeats = 0.25),
            MidiNote.create(pitch = 42u, velocity = 100u, startBeat = 0.87, durationBeats = 0.25),
            MidiNote.create(pitch = 46u, velocity = 100u, startBeat = 1.63, durationBeats = 0.25)
        )
        val quantizer = Quantizer(bpm = 100.0, division = QuantizeDivision.SIXTEENTH)
        val quantized = quantizer.quantize(offGridNotes, 4.0)

        assertEquals(0.25, quantized[0].startBeat, 0.001)
        assertEquals(0.5, quantized[1].startBeat, 0.001)
        assertEquals(0.75, quantized[2].startBeat, 0.001)
        assertEquals(1.75, quantized[3].startBeat, 0.001)
    }

    @Test
    fun `drum notes visible in step sequencer grid`() {
        val tolerance = 0.125 / 2
        val offGridNotes = listOf(
            MidiNote.create(pitch = 36u, velocity = 100u, startBeat = 0.18, durationBeats = 0.25),
            MidiNote.create(pitch = 38u, velocity = 100u, startBeat = 0.93, durationBeats = 0.25)
        )
        val quantizer = Quantizer(bpm = 100.0, division = QuantizeDivision.SIXTEENTH)
        val quantized = quantizer.quantize(offGridNotes, 4.0)

        val gridPositions = listOf(0.25, 1.0)
        for ((note, expectedBeat) in quantized.zip(gridPositions)) {
            val distance = kotlin.math.abs(note.startBeat - expectedBeat)
            assertTrue(distance < tolerance, "Note at ${note.startBeat} is $distance beats from grid $expectedBeat, exceeds tolerance $tolerance")
        }
    }
}
