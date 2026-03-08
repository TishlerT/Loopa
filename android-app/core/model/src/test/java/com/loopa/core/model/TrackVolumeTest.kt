package com.loopa.core.model

import org.junit.jupiter.api.Test
import org.junit.jupiter.api.Assertions.*

/**
 * Tests for track volume — ported from iOS TrackVolumeTests.swift
 */
class TrackVolumeTest {

    @Test
    fun `track default volume is 0_8`() {
        val track = Track.midi(instrumentName = "Piano", instrumentProgram = 0u, isDrumKit = false)
        assertEquals(0.8f, track.volume, 0.001f)
    }

    @Test
    fun `track custom volume`() {
        val track = Track.midi(instrumentName = "Piano", instrumentProgram = 0u, isDrumKit = false, volume = 0.5f)
        assertEquals(0.5f, track.volume, 0.001f)
    }

    @Test
    fun `vocal track default volume`() {
        val vocalTrack = Track.audio(audioFileName = "vocals.m4a")
        assertEquals(0.8f, vocalTrack.volume, 0.001f)
    }

    @Test
    fun `vocal track custom volume`() {
        val vocalTrack = Track.audio(audioFileName = "vocals.m4a", volume = 0.3f)
        assertEquals(0.3f, vocalTrack.volume, 0.001f)
    }

    @Test
    fun `volume is preserved when muted`() {
        val track = Track.midi(instrumentName = "Piano", instrumentProgram = 0u, isDrumKit = false, volume = 0.6f, isMuted = true)
        assertTrue(track.isMuted)
        assertEquals(0.6f, track.volume, 0.001f)
    }

    @Test
    fun `volume is preserved when soloed`() {
        val track = Track.midi(instrumentName = "Piano", instrumentProgram = 0u, isDrumKit = false, volume = 0.4f, isSolo = true)
        assertTrue(track.isSolo)
        assertEquals(0.4f, track.volume, 0.001f)
    }

    @Test
    fun `volume after loading session`() {
        val tracks = listOf(
            Track.midi(instrumentName = "Piano", instrumentProgram = 0u, isDrumKit = false, volume = 0.3f),
            Track.midi(instrumentName = "Bass", instrumentProgram = 32u, isDrumKit = false, volume = 0.6f),
            Track.audio(audioFileName = "vocals.m4a", volume = 0.9f)
        )
        assertEquals(0.3f, tracks[0].volume, 0.001f)
        assertEquals(0.6f, tracks[1].volume, 0.001f)
        assertEquals(0.9f, tracks[2].volume, 0.001f)
    }
}
