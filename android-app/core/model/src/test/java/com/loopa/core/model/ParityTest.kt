package com.loopa.core.model

import org.junit.jupiter.api.Test
import org.junit.jupiter.api.Assertions.*
import kotlinx.serialization.json.Json
import kotlinx.serialization.encodeToString

/**
 * Parity tests — verify Android model shapes match iOS exactly.
 * Uses the test session fixture from migration/fixtures/test_session.json.
 */
class ParityTest {

    private val json = Json {
        prettyPrint = true
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    // MARK: - Enum Parity

    @Test
    fun `TrackType values match iOS`() {
        assertEquals(2, TrackType.entries.size)
        assertNotNull(TrackType.MIDI)
        assertNotNull(TrackType.AUDIO)
    }

    @Test
    fun `Instrument count matches iOS (9 instruments)`() {
        assertEquals(9, Instrument.entries.size)
    }

    @Test
    fun `Instrument display names match iOS raw values`() {
        assertEquals("Piano", Instrument.PIANO.displayName)
        assertEquals("E-Piano", Instrument.ELECTRIC_PIANO.displayName)
        assertEquals("Organ", Instrument.ORGAN.displayName)
        assertEquals("Guitar", Instrument.GUITAR.displayName)
        assertEquals("Strings", Instrument.STRINGS.displayName)
        assertEquals("Lead", Instrument.LEAD.displayName)
        assertEquals("Pad", Instrument.PAD.displayName)
        assertEquals("Drums", Instrument.DRUMS.displayName)
        assertEquals("Bass", Instrument.BASS.displayName)
    }

    @Test
    fun `Instrument program numbers match iOS`() {
        assertEquals(0.toUByte(), Instrument.PIANO.programNumber)
        assertEquals(4.toUByte(), Instrument.ELECTRIC_PIANO.programNumber)
        assertEquals(16.toUByte(), Instrument.ORGAN.programNumber)
        assertEquals(24.toUByte(), Instrument.GUITAR.programNumber)
        assertEquals(48.toUByte(), Instrument.STRINGS.programNumber)
        assertEquals(80.toUByte(), Instrument.LEAD.programNumber)
        assertEquals(88.toUByte(), Instrument.PAD.programNumber)
        assertEquals(0.toUByte(), Instrument.DRUMS.programNumber)
        assertEquals(32.toUByte(), Instrument.BASS.programNumber)
    }

    @Test
    fun `BarCount values match iOS (1, 2, 4, 8, 16)`() {
        assertEquals(5, BarCount.entries.size)
        assertEquals(listOf(1, 2, 4, 8, 16), BarCount.entries.map { it.rawValue })
    }

    @Test
    fun `QuantizeDivision values match iOS`() {
        assertEquals(5, QuantizeDivision.entries.size)
        assertNull(QuantizeDivision.OFF.beatFraction)
        assertEquals(1.0, QuantizeDivision.QUARTER.beatFraction!!, 0.001)
        assertEquals(0.5, QuantizeDivision.EIGHTH.beatFraction!!, 0.001)
        assertEquals(0.25, QuantizeDivision.SIXTEENTH.beatFraction!!, 0.001)
        assertEquals(0.125, QuantizeDivision.THIRTY_SECOND.beatFraction!!, 0.001)
    }

    // MARK: - Model Shape Parity

    @Test
    fun `MidiNote minimum duration matches iOS (0_0625)`() {
        assertEquals(0.0625, MidiNote.MIN_DURATION, 0.0001)
    }

    @Test
    fun `Track default volume matches iOS (0_8)`() {
        val track = Track.midi(instrumentName = "Piano", instrumentProgram = 0u, isDrumKit = false)
        assertEquals(0.8f, track.volume, 0.001f)
    }

    @Test
    fun `Track default isLooping matches iOS (true)`() {
        val track = Track.midi(instrumentName = "Piano", instrumentProgram = 0u, isDrumKit = false)
        assertTrue(track.isLooping)
    }

    @Test
    fun `Track default recordedLengthBeats matches iOS (16_0)`() {
        val track = Track.midi(instrumentName = "Piano", instrumentProgram = 0u, isDrumKit = false)
        assertEquals(16.0, track.recordedLengthBeats, 0.001)
    }

    @Test
    fun `Track isVocal correctly identifies audio tracks`() {
        val midiTrack = Track.midi(instrumentName = "Piano", instrumentProgram = 0u, isDrumKit = false)
        val audioTrack = Track.audio(audioFileName = "vocals.m4a")
        assertFalse(midiTrack.isVocal)
        assertTrue(audioTrack.isVocal)
    }

    @Test
    fun `vocal track has correct defaults`() {
        val track = Track.audio(audioFileName = "vocals.m4a")
        assertEquals("Vocals", track.instrumentName)
        assertEquals(0.toUByte(), track.instrumentProgram)
        assertFalse(track.isDrumKit)
        assertTrue(track.notes.isEmpty())
    }

    // MARK: - Serialization Round-Trip

    @Test
    fun `SavedSession serializes and deserializes correctly`() {
        val session = SavedSession(
            id = "11111111-1111-1111-1111-111111111111",
            name = "Test",
            bpm = 100.0,
            barCount = 4,
            tracks = listOf(
                Track.midi(
                    instrumentName = "Piano", instrumentProgram = 0u, isDrumKit = false,
                    notes = listOf(MidiNote.create(pitch = 60u, velocity = 104u, startBeat = 0.0, durationBeats = 1.0))
                )
            )
        )

        val encoded = json.encodeToString(session)
        val decoded = json.decodeFromString<SavedSession>(encoded)

        assertEquals(session.id, decoded.id)
        assertEquals(session.name, decoded.name)
        assertEquals(session.bpm, decoded.bpm, 0.001)
        assertEquals(session.barCount, decoded.barCount)
        assertEquals(1, decoded.tracks.size)
        assertEquals("Piano", decoded.tracks[0].instrumentName)
        assertEquals(1, decoded.tracks[0].notes.size)
        assertEquals(60.toUByte(), decoded.tracks[0].notes[0].pitch)
        assertEquals(104.toUByte(), decoded.tracks[0].notes[0].velocity)
    }

    @Test
    fun `MidiNote noteName matches iOS convention`() {
        assertEquals("C4", MidiNote.create(pitch = 60u, startBeat = 0.0, durationBeats = 1.0).noteName)
        assertEquals("A4", MidiNote.create(pitch = 69u, startBeat = 0.0, durationBeats = 1.0).noteName)
        assertEquals("C3", MidiNote.create(pitch = 48u, startBeat = 0.0, durationBeats = 1.0).noteName)
        assertEquals("F#5", MidiNote.create(pitch = 78u, startBeat = 0.0, durationBeats = 1.0).noteName)
    }

    // MARK: - Audibility Logic Parity

    @Test
    fun `mute takes precedence over solo (matches iOS)`() {
        val track = Track.midi(instrumentName = "Piano", instrumentProgram = 0u, isDrumKit = false, isMuted = true, isSolo = true)
        assertFalse(track.isAudible(anyTrackSoloed = true), "iOS behavior: mute always wins over solo")
    }
}
