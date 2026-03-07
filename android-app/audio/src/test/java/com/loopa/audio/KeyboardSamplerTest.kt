package com.loopa.audio

import com.loopa.core.model.Instrument
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.BeforeEach

/**
 * Tests for KeyboardSampler — note routing, program changes.
 * Uses a mock SynthEngine to verify routing logic on JVM.
 */
class KeyboardSamplerTest {

    private lateinit var mockEngine: MockSynthEngine
    private lateinit var sampler: KeyboardSampler

    @BeforeEach
    fun setUp() {
        mockEngine = MockSynthEngine()
        mockEngine.initialize()
        sampler = KeyboardSampler(mockEngine, channel = 0)
    }

    @Test
    fun `load piano program sends programChange`() {
        sampler.loadProgram(Instrument.PIANO)
        assertFalse(sampler.percussionMode)
        assertEquals(0, sampler.program)
        assertTrue(mockEngine.programChanges.any { it.first == 0 && it.second == 0 })
    }

    @Test
    fun `load bass program sends correct program number`() {
        sampler.loadProgram(Instrument.BASS)
        assertEquals(32, sampler.program)
        assertTrue(mockEngine.programChanges.any { it.second == 32 })
    }

    @Test
    fun `load drums switches to percussion mode`() {
        sampler.loadProgram(Instrument.DRUMS)
        assertTrue(sampler.percussionMode)
    }

    @Test
    fun `noteOn routes to correct channel`() {
        sampler.loadProgram(Instrument.PIANO)
        sampler.noteOn(60, 100)
        val event = mockEngine.noteOns.last()
        assertEquals(0, event.first) // channel 0
        assertEquals(60, event.second) // note
        assertEquals(100, event.third) // velocity
    }

    @Test
    fun `noteOn in percussion mode routes to channel 9`() {
        sampler.loadProgram(Instrument.DRUMS)
        sampler.noteOn(36, 120)
        val event = mockEngine.noteOns.last()
        assertEquals(9, event.first) // GM percussion channel
        assertEquals(36, event.second) // kick drum
    }

    @Test
    fun `noteOff routes to correct channel`() {
        sampler.loadProgram(Instrument.PIANO)
        sampler.noteOff(60)
        val event = mockEngine.noteOffs.last()
        assertEquals(0, event.first) // channel
        assertEquals(60, event.second) // note
    }

    @Test
    fun `noteOff in percussion mode routes to channel 9`() {
        sampler.loadProgram(Instrument.DRUMS)
        sampler.noteOff(36)
        val event = mockEngine.noteOffs.last()
        assertEquals(9, event.first) // GM percussion channel
    }

    @Test
    fun `switching from drums to piano clears percussion mode`() {
        sampler.loadProgram(Instrument.DRUMS)
        assertTrue(sampler.percussionMode)

        sampler.loadProgram(Instrument.PIANO)
        assertFalse(sampler.percussionMode)
    }

    @Test
    fun `stopAll calls allNotesOff on engine`() {
        sampler.stopAll()
        assertTrue(mockEngine.allNotesOffCalled)
    }

    @Test
    fun `all instruments can be loaded`() {
        for (instrument in Instrument.entries) {
            sampler.loadProgram(instrument)
            if (instrument.isDrumKit) {
                assertTrue(sampler.percussionMode)
            } else {
                assertFalse(sampler.percussionMode)
                assertEquals(instrument.programNumber.toInt(), sampler.program)
            }
        }
    }
}
