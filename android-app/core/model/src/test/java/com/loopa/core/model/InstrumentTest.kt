package com.loopa.core.model

import org.junit.jupiter.api.Test
import org.junit.jupiter.api.Assertions.*

class InstrumentTest {

    @Test
    fun `all instruments have icons`() {
        for (instrument in Instrument.entries) {
            assertTrue(instrument.icon.isNotEmpty(), "${instrument.displayName} should have an icon")
        }
    }

    @Test
    fun `drum kit identification`() {
        assertTrue(Instrument.DRUMS.isDrumKit)
        assertFalse(Instrument.PIANO.isDrumKit)
        assertFalse(Instrument.BASS.isDrumKit)
    }

    @Test
    fun `program numbers`() {
        assertEquals(0.toUByte(), Instrument.PIANO.programNumber)
        assertEquals(4.toUByte(), Instrument.ELECTRIC_PIANO.programNumber)
        assertEquals(32.toUByte(), Instrument.BASS.programNumber)
    }

    @Test
    fun `all bar counts`() {
        val expectedCounts = listOf(1, 2, 4, 8, 16)
        val actualCounts = BarCount.entries.map { it.rawValue }
        assertEquals(expectedCounts, actualCounts)
    }

    @Test
    fun `display names`() {
        assertEquals("1 bar", BarCount.ONE.displayName)
        assertEquals("4 bars", BarCount.FOUR.displayName)
        assertEquals("16 bars", BarCount.SIXTEEN.displayName)
    }
}
