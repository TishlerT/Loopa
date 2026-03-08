package com.loopa.feature.looper

import com.loopa.core.model.*
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.BeforeEach

/**
 * Tests for LooperViewModel — ported from iOS ViewModelTests.swift
 */
class LooperViewModelTest {

    private lateinit var vm: LooperViewModel

    @BeforeEach
    fun setUp() {
        vm = LooperViewModel()
    }

    // MARK: - Initial State

    @Test
    fun `initial instrument is piano`() {
        assertEquals(Instrument.PIANO, vm.currentInstrument)
    }

    @Test
    fun `initial BPM is 100`() {
        assertEquals(100.0, vm.bpm, 0.001)
    }

    @Test
    fun `initial bar count is four`() {
        assertEquals(BarCount.FOUR, vm.barCount)
    }

    @Test
    fun `initial tracks empty`() {
        assertTrue(vm.tracks.isEmpty())
    }

    @Test
    fun `initial not recording`() {
        assertFalse(vm.isRecording)
    }

    @Test
    fun `initial not playing`() {
        assertFalse(vm.isPlaying)
    }

    @Test
    fun `initial not paused`() {
        assertFalse(vm.isPaused)
    }

    @Test
    fun `initial not in vocal mode`() {
        assertFalse(vm.isVocalMode)
    }

    @Test
    fun `initial quantize division is off`() {
        assertEquals(QuantizeDivision.OFF, vm.quantizeDivision)
    }

    // MARK: - BPM

    @Test
    fun `set BPM updates looper`() {
        vm.setBpm(120.0)
        assertEquals(120.0, vm.bpm, 0.001)
        assertEquals(120.0, vm.looper.bpm, 0.001)
    }

    @Test
    fun `BPM clamps to range`() {
        vm.setBpm(10.0)
        assertTrue(vm.bpm >= 40.0)

        vm.setBpm(500.0)
        assertTrue(vm.bpm <= 300.0)
    }

    // MARK: - Bar Count

    @Test
    fun `set bar count`() {
        vm.setBarCount(BarCount.EIGHT)
        assertEquals(BarCount.EIGHT, vm.barCount)
        assertEquals(BarCount.EIGHT, vm.looper.barCount)
    }

    // MARK: - Quantize Division

    @Test
    fun `cycle quantize division`() {
        assertEquals(QuantizeDivision.OFF, vm.quantizeDivision)
        vm.cycleQuantizeDivision()
        assertEquals(QuantizeDivision.SIXTEENTH, vm.quantizeDivision)
        vm.cycleQuantizeDivision()
        assertEquals(QuantizeDivision.EIGHTH, vm.quantizeDivision)
        vm.cycleQuantizeDivision()
        assertEquals(QuantizeDivision.QUARTER, vm.quantizeDivision)
        vm.cycleQuantizeDivision()
        assertEquals(QuantizeDivision.OFF, vm.quantizeDivision)
    }

    // MARK: - Octave

    @Test
    fun `octave offset starts at 0`() {
        assertEquals(0, vm.octaveOffset)
        assertEquals("C4", vm.currentOctaveName)
    }

    @Test
    fun `octave up`() {
        vm.octaveUp()
        assertEquals(1, vm.octaveOffset)
    }

    @Test
    fun `octave down`() {
        vm.octaveDown()
        assertEquals(-1, vm.octaveOffset)
    }

    @Test
    fun `start note clamps to range`() {
        // Push octave up until clamped
        for (i in 0..10) vm.octaveUp()
        assertTrue(vm.startNote.toInt() <= 84)

        // Reset and push down
        vm = LooperViewModel()
        for (i in 0..10) vm.octaveDown()
        assertTrue(vm.startNote.toInt() >= 24)
    }

    // MARK: - Key Count

    @Test
    fun `key count is 25`() {
        assertEquals(25, vm.keyCount)
    }

    // MARK: - Vocal Mode

    @Test
    fun `toggle vocal mode`() {
        assertFalse(vm.isVocalMode)
        vm.toggleVocalMode()
        assertTrue(vm.isVocalMode)
        vm.toggleVocalMode()
        assertFalse(vm.isVocalMode)
    }

    // MARK: - Track Operations

    @Test
    fun `toggle mute syncs state`() {
        val track = Track.midi(instrumentName = "Piano", instrumentProgram = 0u, isDrumKit = false)
        vm.looper.loadTracks(listOf(track))
        vm.syncState()

        assertFalse(vm.tracks[0].isMuted)
        vm.toggleMute(vm.tracks[0])
        assertTrue(vm.tracks[0].isMuted)
    }

    @Test
    fun `toggle solo syncs state`() {
        val track = Track.midi(instrumentName = "Piano", instrumentProgram = 0u, isDrumKit = false)
        vm.looper.loadTracks(listOf(track))
        vm.syncState()

        assertFalse(vm.tracks[0].isSolo)
        vm.toggleSolo(vm.tracks[0])
        assertTrue(vm.tracks[0].isSolo)
    }

    @Test
    fun `delete track syncs state`() {
        val track = Track.midi(instrumentName = "Piano", instrumentProgram = 0u, isDrumKit = false)
        vm.looper.loadTracks(listOf(track))
        vm.syncState()

        assertEquals(1, vm.tracks.size)
        vm.deleteTrack(vm.tracks[0])
        assertTrue(vm.tracks.isEmpty())
    }

    @Test
    fun `clear all resets state`() {
        val track = Track.midi(instrumentName = "Piano", instrumentProgram = 0u, isDrumKit = false)
        vm.looper.loadTracks(listOf(track))
        vm.syncState()

        vm.clearAll()
        assertTrue(vm.tracks.isEmpty())
        assertEquals("", vm.currentSessionName)
    }

    @Test
    fun `set track volume`() {
        val track = Track.midi(instrumentName = "Piano", instrumentProgram = 0u, isDrumKit = false)
        vm.looper.loadTracks(listOf(track))
        vm.syncState()

        vm.setTrackVolume(vm.tracks[0], 0.3f)
        assertEquals(0.3f, vm.tracks[0].volume, 0.001f)
    }

    @Test
    fun `set track instrument`() {
        val track = Track.midi(instrumentName = "Piano", instrumentProgram = 0u, isDrumKit = false)
        vm.looper.loadTracks(listOf(track))
        vm.syncState()

        vm.setTrackInstrument(vm.tracks[0], Instrument.BASS)
        assertEquals("Bass", vm.tracks[0].instrumentName)
    }

    // MARK: - Preview Note (should not crash)

    @Test
    fun `preview note does not crash`() {
        vm.previewNote(pitch = 60u, velocity = 100u, trackId = "nonexistent")
        // If we get here without crashing, the test passes
    }

    @Test
    fun `preview note with drum track does not crash`() {
        val drumTrack = Track.midi(instrumentName = "Drums", instrumentProgram = 0u, isDrumKit = true)
        vm.previewNote(pitch = 36u, velocity = 100u, trackId = drumTrack.id)
        vm.previewNote(pitch = 38u, velocity = 90u, trackId = drumTrack.id)
        vm.previewNote(pitch = 42u, velocity = 80u, trackId = drumTrack.id)
    }
}
