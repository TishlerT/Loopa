package com.loopa.core.looper

import com.loopa.core.model.*
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.AfterEach

/**
 * Tests for MultiTrackLooper — ported from iOS MultiTrackLooperTests.swift
 */
class MultiTrackLooperTest {

    private lateinit var looper: MultiTrackLooper

    @BeforeEach
    fun setUp() {
        looper = MultiTrackLooper()
    }

    @AfterEach
    fun tearDown() {
        looper.stopPlayback()
    }

    // MARK: - Initial State

    @Test
    fun `initial state`() {
        assertFalse(looper.isRecording)
        assertFalse(looper.isPlaying)
        assertFalse(looper.isPaused)
        assertTrue(looper.tracks.isEmpty())
        assertEquals(BarCount.FOUR, looper.barCount)
    }

    // MARK: - Bar Count

    @Test
    fun `set bar count`() {
        looper.setBarCount(BarCount.EIGHT)
        assertEquals(BarCount.EIGHT, looper.barCount)

        looper.setBarCount(BarCount.SIXTEEN)
        assertEquals(BarCount.SIXTEEN, looper.barCount)
    }

    @Test
    fun `loop length calculation`() {
        looper.bpm = 120.0
        looper.setBarCount(BarCount.FOUR)
        // 4 bars * 4 beats/bar = 16 beats; at 120 BPM, 1 beat = 0.5s; 16 * 0.5 = 8s
        assertEquals(8.0, looper.loopLength, 0.01)

        looper.setBarCount(BarCount.EIGHT)
        assertEquals(16.0, looper.loopLength, 0.01)
    }

    @Test
    fun `loop length with different BPM`() {
        looper.setBarCount(BarCount.FOUR)

        looper.bpm = 60.0
        assertEquals(16.0, looper.loopLength, 0.01)

        looper.bpm = 180.0
        assertEquals(16.0 / 3.0, looper.loopLength, 0.01)
    }

    // MARK: - Recording

    @Test
    fun `start recording`() {
        looper.startRecording(Instrument.PIANO)
        assertTrue(looper.isRecording)
        assertTrue(looper.isPlaying, "Recording should auto-start playback")
    }

    @Test
    fun `stop recording creates track`() {
        looper.startRecording(Instrument.PIANO)
        looper.addLiveEvent(60u, 100u, true)
        looper.addLiveEvent(60u, 0u, false)
        looper.stopRecording()

        assertFalse(looper.isRecording)
        assertEquals(1, looper.tracks.size)
        assertEquals("Piano", looper.tracks.first().instrumentName)
    }

    @Test
    fun `empty recording does not create track`() {
        looper.startRecording(Instrument.PIANO)
        looper.stopRecording()
        assertTrue(looper.tracks.isEmpty())
    }

    // MARK: - Multi-Track

    @Test
    fun `multiple tracks`() {
        looper.startRecording(Instrument.PIANO)
        looper.addLiveEvent(60u, 100u, true)
        looper.stopRecording()

        looper.startRecording(Instrument.DRUMS)
        looper.addLiveEvent(36u, 100u, true)
        looper.stopRecording()

        assertEquals(2, looper.tracks.size)
        assertEquals("Piano", looper.tracks[0].instrumentName)
        assertEquals("Drums", looper.tracks[1].instrumentName)
    }

    // MARK: - Track Management

    @Test
    fun `undo last track`() {
        looper.startRecording(Instrument.PIANO)
        looper.addLiveEvent(60u, 100u, true)
        looper.stopRecording()

        looper.startRecording(Instrument.DRUMS)
        looper.addLiveEvent(36u, 100u, true)
        looper.stopRecording()

        assertEquals(2, looper.tracks.size)
        looper.undoLastTrack()
        assertEquals(1, looper.tracks.size)
        assertEquals("Piano", looper.tracks.first().instrumentName)
    }

    @Test
    fun `clear all tracks`() {
        looper.startRecording(Instrument.PIANO)
        looper.addLiveEvent(60u, 100u, true)
        looper.stopRecording()

        looper.startRecording(Instrument.DRUMS)
        looper.addLiveEvent(36u, 100u, true)
        looper.stopRecording()

        looper.clearAllTracks()
        assertTrue(looper.tracks.isEmpty())
        assertFalse(looper.isPlaying)
    }

    @Test
    fun `delete specific track`() {
        looper.startRecording(Instrument.PIANO)
        looper.addLiveEvent(60u, 100u, true)
        looper.stopRecording()

        looper.startRecording(Instrument.DRUMS)
        looper.addLiveEvent(36u, 100u, true)
        looper.stopRecording()

        val pianoTrack = looper.tracks[0]
        looper.deleteTrack(pianoTrack)

        assertEquals(1, looper.tracks.size)
        assertEquals("Drums", looper.tracks.first().instrumentName)
    }

    // MARK: - Mute

    @Test
    fun `toggle mute`() {
        looper.startRecording(Instrument.PIANO)
        looper.addLiveEvent(60u, 100u, true)
        looper.stopRecording()

        var track = looper.tracks[0]
        assertFalse(track.isMuted)

        looper.toggleMute(track)
        track = looper.tracks[0]
        assertTrue(track.isMuted)

        looper.toggleMute(track)
        track = looper.tracks[0]
        assertFalse(track.isMuted)
    }

    // MARK: - Playback

    @Test
    fun `start playback`() {
        looper.startRecording(Instrument.PIANO)
        looper.addLiveEvent(60u, 100u, true)
        looper.stopRecording()
        looper.stopPlayback()

        looper.startPlayback()
        assertTrue(looper.isPlaying)
        assertFalse(looper.isPaused)
    }

    @Test
    fun `stop playback`() {
        looper.startRecording(Instrument.PIANO)
        looper.addLiveEvent(60u, 100u, true)
        looper.stopRecording()

        looper.stopPlayback()
        assertFalse(looper.isPlaying)
        assertFalse(looper.isRecording)
        assertFalse(looper.isPaused)
    }

    // MARK: - Pause/Resume

    @Test
    fun `pause playback`() {
        looper.startRecording(Instrument.PIANO)
        looper.addLiveEvent(60u, 100u, true)
        looper.stopRecording()

        assertTrue(looper.isPlaying)
        looper.pausePlayback()
        assertFalse(looper.isPlaying)
        assertTrue(looper.isPaused)
    }

    @Test
    fun `resume playback`() {
        looper.startRecording(Instrument.PIANO)
        looper.addLiveEvent(60u, 100u, true)
        looper.stopRecording()

        looper.pausePlayback()
        assertTrue(looper.isPaused)

        looper.resumePlayback()
        assertTrue(looper.isPlaying)
        assertFalse(looper.isPaused)
    }

    @Test
    fun `pause does nothing when not playing`() {
        assertFalse(looper.isPlaying)
        assertFalse(looper.isPaused)

        looper.pausePlayback()
        assertFalse(looper.isPaused)
    }

    @Test
    fun `resume starts playback when not paused`() {
        looper.startRecording(Instrument.PIANO)
        looper.addLiveEvent(60u, 100u, true)
        looper.stopRecording()
        looper.stopPlayback()

        assertFalse(looper.isPaused)
        assertFalse(looper.isPlaying)

        looper.resumePlayback()
        assertTrue(looper.isPlaying)
    }

    @Test
    fun `stop clears paused state`() {
        looper.startRecording(Instrument.PIANO)
        looper.addLiveEvent(60u, 100u, true)
        looper.stopRecording()

        looper.pausePlayback()
        assertTrue(looper.isPaused)

        looper.stopPlayback()
        assertFalse(looper.isPaused)
        assertFalse(looper.isPlaying)
    }

    // MARK: - Volume

    @Test
    fun `set track volume does not affect other tracks`() {
        val track1 = Track.midi(instrumentName = "Piano", instrumentProgram = 0u, isDrumKit = false,
            notes = listOf(MidiNote.create(pitch = 60u, startBeat = 0.0, durationBeats = 1.0)), volume = 0.8f)
        val track2 = Track.midi(instrumentName = "Drums", instrumentProgram = 0u, isDrumKit = true,
            notes = listOf(MidiNote.create(pitch = 36u, startBeat = 0.0, durationBeats = 0.5)), volume = 0.8f)
        looper.loadTracks(listOf(track1, track2))

        looper.setTrackVolume(track1.id, 0.2f)
        assertEquals(0.2f, looper.track(track1.id)?.volume ?: 0f, 0.001f)
        assertEquals(0.8f, looper.track(track2.id)?.volume ?: 0f, 0.001f)
    }

    @Test
    fun `volume clamping`() {
        val track = Track.midi(instrumentName = "Piano", instrumentProgram = 0u, isDrumKit = false)
        looper.loadTracks(listOf(track))

        looper.setTrackVolume(track.id, -0.5f)
        assertEquals(0.0f, looper.track(track.id)?.volume ?: 1f, 0.001f)

        looper.setTrackVolume(track.id, 1.5f)
        assertEquals(1.0f, looper.track(track.id)?.volume ?: 0f, 0.001f)
    }

    // MARK: - Instrument

    @Test
    fun `set track instrument`() {
        val track = Track.midi(instrumentName = "Piano", instrumentProgram = 0u, isDrumKit = false)
        looper.loadTracks(listOf(track))

        looper.setTrackInstrument(track.id, Instrument.BASS)
        val updated = looper.track(track.id)
        assertEquals("Bass", updated?.instrumentName)
        assertEquals(32.toUByte(), updated?.instrumentProgram)
    }

    // MARK: - Synchronized Position

    @Test
    fun `synchronized position when not playing`() {
        assertFalse(looper.isPlaying)
        assertFalse(looper.isPaused)
        assertEquals(0.0, looper.synchronizedPlaybackPosition, 0.001)
        assertEquals(0.0, looper.synchronizedPlaybackFraction, 0.001)
    }

    // MARK: - Seek

    @Test
    fun `seek updates position`() {
        looper.startRecording(Instrument.PIANO)
        looper.addLiveEvent(60u, 100u, true)
        looper.stopRecording()

        looper.seekTo(2.0)
        assertEquals(2.0, looper.currentPosition, 0.1)
    }

    @Test
    fun `seek clamps to loop bounds`() {
        looper.startRecording(Instrument.PIANO)
        looper.addLiveEvent(60u, 100u, true)
        looper.stopRecording()

        looper.seekTo(looper.loopLength + 5.0)
        assertTrue(looper.currentPosition <= looper.loopLength)
    }

    // MARK: - Quantize Track

    @Test
    fun `quantize track`() {
        val notes = listOf(
            MidiNote.create(pitch = 60u, startBeat = 0.1, durationBeats = 0.3),
            MidiNote.create(pitch = 64u, startBeat = 1.3, durationBeats = 0.7)
        )
        val track = Track.midi(instrumentName = "Piano", instrumentProgram = 0u, isDrumKit = false, notes = notes)
        looper.loadTracks(listOf(track))

        looper.quantizeTrack(track.id, QuantizeDivision.QUARTER)
        val quantized = looper.track(track.id)?.notes ?: emptyList()

        // Notes should snap to quarter-note grid
        assertTrue(quantized.all { it.startBeat.mod(1.0) < 0.001 || it.startBeat.mod(1.0) > 0.999 })
    }
}

/**
 * Additional tests from iOS InstrumentTests and BarCountTests
 */
class InstrumentEnumTest {

    @Test
    fun `all instruments have icons`() {
        for (instrument in Instrument.entries) {
            assertTrue(instrument.icon.isNotEmpty())
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
}

class BarCountEnumTest {

    @Test
    fun `all bar counts`() {
        val expected = listOf(1, 2, 4, 8, 16)
        val actual = BarCount.entries.map { it.rawValue }
        assertEquals(expected, actual)
    }

    @Test
    fun `display names`() {
        assertEquals("1 bar", BarCount.ONE.displayName)
        assertEquals("4 bars", BarCount.FOUR.displayName)
        assertEquals("16 bars", BarCount.SIXTEEN.displayName)
    }
}
