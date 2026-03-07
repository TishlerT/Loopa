package com.loopa.core.model

import org.junit.jupiter.api.Test
import org.junit.jupiter.api.Assertions.*

/**
 * Tests for track audibility — ported from iOS SoloMuteTests.swift
 */
class SoloMuteTest {

    @Test
    fun `unmuted track is audible with no solo`() {
        val track = Track.midi(instrumentName = "Piano", instrumentProgram = 0u, isDrumKit = false, isMuted = false, isSolo = false)
        assertTrue(track.isAudible(anyTrackSoloed = false))
    }

    @Test
    fun `muted track is not audible`() {
        val track = Track.midi(instrumentName = "Piano", instrumentProgram = 0u, isDrumKit = false, isMuted = true, isSolo = false)
        assertFalse(track.isAudible(anyTrackSoloed = false))
        assertFalse(track.isAudible(anyTrackSoloed = true))
    }

    @Test
    fun `soloed track is audible when any soloed`() {
        val track = Track.midi(instrumentName = "Piano", instrumentProgram = 0u, isDrumKit = false, isMuted = false, isSolo = true)
        assertTrue(track.isAudible(anyTrackSoloed = true))
    }

    @Test
    fun `non-soloed track is not audible when any soloed`() {
        val track = Track.midi(instrumentName = "Piano", instrumentProgram = 0u, isDrumKit = false, isMuted = false, isSolo = false)
        assertFalse(track.isAudible(anyTrackSoloed = true))
    }

    @Test
    fun `muted soloed track is not audible`() {
        val track = Track.midi(instrumentName = "Piano", instrumentProgram = 0u, isDrumKit = false, isMuted = true, isSolo = true)
        assertFalse(track.isAudible(anyTrackSoloed = true))
    }

    @Test
    fun `multiple tracks no solo`() {
        val tracks = listOf(
            Track.midi(instrumentName = "Piano", instrumentProgram = 0u, isDrumKit = false, isMuted = false, isSolo = false),
            Track.midi(instrumentName = "Drums", instrumentProgram = 0u, isDrumKit = true, isMuted = false, isSolo = false),
            Track.midi(instrumentName = "Bass", instrumentProgram = 32u, isDrumKit = false, isMuted = true, isSolo = false)
        )
        val anyTrackSoloed = tracks.any { it.isSolo }
        assertFalse(anyTrackSoloed)
        assertTrue(tracks[0].isAudible(anyTrackSoloed))
        assertTrue(tracks[1].isAudible(anyTrackSoloed))
        assertFalse(tracks[2].isAudible(anyTrackSoloed))
    }

    @Test
    fun `multiple tracks with one solo`() {
        val tracks = listOf(
            Track.midi(instrumentName = "Piano", instrumentProgram = 0u, isDrumKit = false, isMuted = false, isSolo = true),
            Track.midi(instrumentName = "Drums", instrumentProgram = 0u, isDrumKit = true, isMuted = false, isSolo = false),
            Track.midi(instrumentName = "Bass", instrumentProgram = 32u, isDrumKit = false, isMuted = false, isSolo = false)
        )
        val anyTrackSoloed = tracks.any { it.isSolo }
        assertTrue(anyTrackSoloed)
        assertTrue(tracks[0].isAudible(anyTrackSoloed))
        assertFalse(tracks[1].isAudible(anyTrackSoloed))
        assertFalse(tracks[2].isAudible(anyTrackSoloed))
    }

    @Test
    fun `multiple tracks with multiple solos`() {
        val tracks = listOf(
            Track.midi(instrumentName = "Piano", instrumentProgram = 0u, isDrumKit = false, isMuted = false, isSolo = true),
            Track.midi(instrumentName = "Drums", instrumentProgram = 0u, isDrumKit = true, isMuted = false, isSolo = true),
            Track.midi(instrumentName = "Bass", instrumentProgram = 32u, isDrumKit = false, isMuted = false, isSolo = false)
        )
        val anyTrackSoloed = tracks.any { it.isSolo }
        assertTrue(anyTrackSoloed)
        assertTrue(tracks[0].isAudible(anyTrackSoloed))
        assertTrue(tracks[1].isAudible(anyTrackSoloed))
        assertFalse(tracks[2].isAudible(anyTrackSoloed))
    }

    @Test
    fun `vocal track audibility`() {
        val vocalTrack = Track.audio(audioFileName = "vocals.m4a", isMuted = false, isSolo = false)
        assertTrue(vocalTrack.isVocal)
        assertTrue(vocalTrack.isAudible(anyTrackSoloed = false))
        assertFalse(vocalTrack.isAudible(anyTrackSoloed = true))
    }

    @Test
    fun `soloed vocal track`() {
        val vocalTrack = Track.audio(audioFileName = "vocals.m4a", isMuted = false, isSolo = true)
        assertTrue(vocalTrack.isAudible(anyTrackSoloed = true))
    }
}
