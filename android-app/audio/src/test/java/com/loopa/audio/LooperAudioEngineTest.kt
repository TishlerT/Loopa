package com.loopa.audio

import com.loopa.core.model.Instrument
import com.loopa.core.model.MidiNote
import com.loopa.core.model.Track
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.BeforeEach

/**
 * Tests for LooperAudioEngine — track preparation, channel mapping.
 */
class LooperAudioEngineTest {

    private lateinit var mockEngine: MockSynthEngine
    private lateinit var audioEngine: LooperAudioEngine

    @BeforeEach
    fun setUp() {
        mockEngine = MockSynthEngine()
        audioEngine = LooperAudioEngine(mockEngine)
        audioEngine.start()
    }

    @Test
    fun `engine starts successfully`() {
        assertTrue(mockEngine.isReady)
    }

    @Test
    fun `set live instrument changes program`() {
        audioEngine.setLiveInstrument(Instrument.PIANO)
        assertFalse(audioEngine.liveSampler.percussionMode)
        assertEquals(0, audioEngine.liveSampler.program)

        audioEngine.setLiveInstrument(Instrument.DRUMS)
        assertTrue(audioEngine.liveSampler.percussionMode)
    }

    @Test
    fun `prepare track assigns sampler`() {
        val track = Track.midi(
            instrumentName = "Piano",
            instrumentProgram = 0u,
            isDrumKit = false,
            notes = listOf(MidiNote.create(pitch = 60u, startBeat = 0.0, durationBeats = 1.0))
        )

        val sampler = audioEngine.prepareTrack(track)
        assertNotNull(sampler)
        assertEquals(0, sampler!!.program)
    }

    @Test
    fun `prepare track assigns different channels`() {
        val track1 = Track.midi(instrumentName = "Piano", instrumentProgram = 0u, isDrumKit = false)
        val track2 = Track.midi(instrumentName = "Bass", instrumentProgram = 32u, isDrumKit = false)

        val sampler1 = audioEngine.prepareTrack(track1)
        val sampler2 = audioEngine.prepareTrack(track2)

        assertNotNull(sampler1)
        assertNotNull(sampler2)
        assertNotSame(sampler1, sampler2)
    }

    @Test
    fun `sampler for track returns correct sampler`() {
        val track = Track.midi(instrumentName = "Piano", instrumentProgram = 0u, isDrumKit = false)
        audioEngine.prepareTrack(track)

        val sampler = audioEngine.samplerForTrack(track.id)
        assertNotNull(sampler)
    }

    @Test
    fun `sampler for unknown track returns null`() {
        assertNull(audioEngine.samplerForTrack("nonexistent"))
    }

    @Test
    fun `vocal track returns null sampler`() {
        val vocalTrack = Track.audio(audioFileName = "vocals.m4a")
        val sampler = audioEngine.prepareTrack(vocalTrack)
        assertNull(sampler)
    }

    @Test
    fun `stopAll calls engine allNotesOff`() {
        audioEngine.stopAll()
        assertTrue(mockEngine.allNotesOffCalled)
    }

    @Test
    fun `release stops engine`() {
        audioEngine.release()
        assertFalse(mockEngine.isReady)
    }
}
