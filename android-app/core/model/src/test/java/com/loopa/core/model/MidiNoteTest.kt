package com.loopa.core.model

import org.junit.jupiter.api.Test
import org.junit.jupiter.api.Assertions.*

/**
 * Tests for MidiNote — ported from iOS MidiNoteTests.swift
 */
class MidiNoteTest {

    @Test
    fun `note name for middle C`() {
        val note = MidiNote.create(pitch = 60u, startBeat = 0.0, durationBeats = 1.0)
        assertEquals("C4", note.noteName)
    }

    @Test
    fun `endBeat is startBeat plus duration`() {
        val note = MidiNote.create(pitch = 60u, startBeat = 2.0, durationBeats = 1.5)
        assertEquals(3.5, note.endBeat, 0.001)
    }

    @Test
    fun `velocity clamped to 1-127`() {
        val low = MidiNote.create(pitch = 60u, velocity = 0u, startBeat = 0.0, durationBeats = 1.0)
        assertEquals(1.toUByte(), low.velocity)
    }

    @Test
    fun `startBeat clamped to 0`() {
        val note = MidiNote.create(pitch = 60u, startBeat = -5.0, durationBeats = 1.0)
        assertTrue(note.startBeat >= 0.0)
    }

    @Test
    fun `duration clamped to minimum`() {
        val note = MidiNote.create(pitch = 60u, startBeat = 0.0, durationBeats = 0.001)
        assertTrue(note.durationBeats >= MidiNote.MIN_DURATION)
    }

    @Test
    fun `convert events to notes`() {
        val bpm = 120.0
        val loopLengthBeats = 8.0
        val events = listOf(
            MidiEvent(time = 0.0, note = 60u, velocity = 100u, isNoteOn = true, isLeft = false),
            MidiEvent(time = 0.5, note = 60u, velocity = 0u, isNoteOn = false, isLeft = false),
            MidiEvent(time = 1.0, note = 64u, velocity = 90u, isNoteOn = true, isLeft = false),
            MidiEvent(time = 1.5, note = 64u, velocity = 0u, isNoteOn = false, isLeft = false)
        )
        val notes = MidiNote.fromEvents(events, bpm, loopLengthBeats)
        assertEquals(2, notes.size)
        assertEquals(60.toUByte(), notes[0].pitch)
        assertEquals(0.0, notes[0].startBeat, 0.001)
        assertEquals(1.0, notes[0].durationBeats, 0.01) // 0.5s at 120 BPM = 1 beat
        assertEquals(64.toUByte(), notes[1].pitch)
    }

    @Test
    fun `toEvents round trip`() {
        val note = MidiNote.create(pitch = 60u, velocity = 100u, startBeat = 2.0, durationBeats = 1.0)
        val events = note.toEvents(120.0)
        assertEquals(2, events.size)
        assertTrue(events[0].isNoteOn)
        assertFalse(events[1].isNoteOn)
        assertEquals(60.toUByte(), events[0].note)
        assertEquals(60.toUByte(), events[1].note)
    }
}
