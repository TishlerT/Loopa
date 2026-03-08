package com.loopa.audio

import com.loopa.core.model.MidiNote
import com.loopa.core.model.Track
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.BeforeEach

/**
 * Tests for AudioExporter — state management and filtering logic.
 * Actual M4A export requires device (DEFERRED_TO_LOCAL).
 */
class AudioExporterTest {

    private lateinit var mockEngine: MockSynthEngine
    private lateinit var exporter: AudioExporter

    @BeforeEach
    fun setUp() {
        mockEngine = MockSynthEngine()
        mockEngine.initialize()
        exporter = AudioExporter(mockEngine)
    }

    @Test
    fun `initial state is IDLE`() {
        assertEquals(AudioExporter.ExportState.IDLE, exporter.state)
        assertEquals(0f, exporter.progress)
    }

    @Test
    fun `export with no audible tracks returns error`() {
        val tracks = listOf(
            Track.midi(instrumentName = "Piano", instrumentProgram = 0u, isDrumKit = false, isMuted = true)
        )
        val result = exporter.export(tracks, 100.0, 16.0, "/tmp/test.m4a")
        assertFalse(result)
        assertEquals(AudioExporter.ExportState.ERROR, exporter.state)
        assertNotNull(exporter.errorMessage)
    }

    @Test
    fun `export with audible tracks succeeds`() {
        val tracks = listOf(
            Track.midi(
                instrumentName = "Piano",
                instrumentProgram = 0u,
                isDrumKit = false,
                notes = listOf(MidiNote.create(pitch = 60u, startBeat = 0.0, durationBeats = 1.0))
            )
        )
        val result = exporter.export(tracks, 100.0, 16.0, "/tmp/test.m4a")
        assertTrue(result)
        assertEquals(AudioExporter.ExportState.COMPLETE, exporter.state)
        assertEquals(1f, exporter.progress)
    }

    @Test
    fun `export filters out vocal tracks`() {
        val tracks = listOf(
            Track.audio(audioFileName = "vocals.m4a") // vocal, should be excluded
        )
        val result = exporter.export(tracks, 100.0, 16.0, "/tmp/test.m4a")
        assertFalse(result) // no non-vocal audible tracks
        assertEquals(AudioExporter.ExportState.ERROR, exporter.state)
    }

    @Test
    fun `export respects solo state`() {
        val tracks = listOf(
            Track.midi(instrumentName = "Piano", instrumentProgram = 0u, isDrumKit = false, isSolo = true,
                notes = listOf(MidiNote.create(pitch = 60u, startBeat = 0.0, durationBeats = 1.0))),
            Track.midi(instrumentName = "Bass", instrumentProgram = 32u, isDrumKit = false, isSolo = false,
                notes = listOf(MidiNote.create(pitch = 36u, startBeat = 0.0, durationBeats = 1.0)))
        )
        // Only piano is soloed, bass is not audible
        val result = exporter.export(tracks, 100.0, 16.0, "/tmp/test.m4a")
        assertTrue(result)
    }

    @Test
    fun `reset clears state`() {
        exporter.export(
            listOf(Track.midi(instrumentName = "Piano", instrumentProgram = 0u, isDrumKit = false,
                notes = listOf(MidiNote.create(pitch = 60u, startBeat = 0.0, durationBeats = 1.0)))),
            100.0, 16.0, "/tmp/test.m4a"
        )
        assertEquals(AudioExporter.ExportState.COMPLETE, exporter.state)

        exporter.reset()
        assertEquals(AudioExporter.ExportState.IDLE, exporter.state)
        assertEquals(0f, exporter.progress)
        assertNull(exporter.errorMessage)
    }
}
