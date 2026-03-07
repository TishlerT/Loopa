package com.loopa.audio

import org.junit.jupiter.api.Test
import org.junit.jupiter.api.Assertions.*

/**
 * Tests for Metronome — timing math and state management.
 * Note: actual timing accuracy requires device testing (DEFERRED_TO_LOCAL).
 */
class MetronomeTest {

    @Test
    fun `default BPM is 100`() {
        val metronome = Metronome()
        assertEquals(100.0, metronome.bpm, 0.001)
    }

    @Test
    fun `beat interval at 100 BPM is 600ms`() {
        val metronome = Metronome()
        assertEquals(600L, metronome.beatIntervalMs)
    }

    @Test
    fun `beat interval at 120 BPM is 500ms`() {
        val metronome = Metronome()
        metronome.bpm = 120.0
        assertEquals(500L, metronome.beatIntervalMs)
    }

    @Test
    fun `beat interval at 60 BPM is 1000ms`() {
        val metronome = Metronome()
        metronome.bpm = 60.0
        assertEquals(1000L, metronome.beatIntervalMs)
    }

    @Test
    fun `beat interval at 180 BPM is 333ms`() {
        val metronome = Metronome()
        metronome.bpm = 180.0
        assertEquals(333L, metronome.beatIntervalMs)
    }

    @Test
    fun `not running initially`() {
        val metronome = Metronome()
        assertFalse(metronome.running)
    }

    @Test
    fun `changing BPM updates interval`() {
        val metronome = Metronome()
        metronome.bpm = 200.0
        assertEquals(300L, metronome.beatIntervalMs)
        metronome.bpm = 60.0
        assertEquals(1000L, metronome.beatIntervalMs)
    }
}

