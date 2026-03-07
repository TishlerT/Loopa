package com.loopa.core.storage

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.loopa.core.model.*
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.Assert.*
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.io.File

/**
 * Tests for SessionStorage — ported from iOS WorkingSessionTests.swift.
 * Uses Robolectric for Android Context (JUnit 4 required for @RunWith).
 */
@RunWith(RobolectricTestRunner::class)
class SessionStorageTest {

    private lateinit var context: Context
    private lateinit var storage: SessionStorage

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        storage = SessionStorage(context)
        storage.clearWorkingSession()
        val sessionsFile = File(context.filesDir, "sessions.json")
        if (sessionsFile.exists()) sessionsFile.delete()
    }

    @After
    fun tearDown() {
        storage.clearWorkingSession()
    }

    @Test
    fun `save and load working session`() {
        val track = Track.midi(
            instrumentName = "Piano", instrumentProgram = 0u, isDrumKit = false,
            notes = listOf(MidiNote.create(pitch = 60u, velocity = 100u, startBeat = 0.0, durationBeats = 1.0))
        )
        val session = SavedSession(name = "Test Session", bpm = 120.0, barCount = 4, tracks = listOf(track))
        storage.saveWorkingSession(session)

        val loaded = storage.loadWorkingSession()
        assertNotNull(loaded)
        assertEquals("Test Session", loaded!!.name)
        assertEquals(120.0, loaded.bpm, 0.001)
        assertEquals(4, loaded.barCount)
        assertEquals(1, loaded.tracks.size)
        assertEquals(1, loaded.tracks.first().notes.size)
    }

    @Test
    fun `clear working session`() {
        val session = SavedSession(name = "To Be Cleared", bpm = 100.0, barCount = 2, tracks = emptyList())
        storage.saveWorkingSession(session)
        assertNotNull(storage.loadWorkingSession())
        storage.clearWorkingSession()
        assertNull(storage.loadWorkingSession())
    }

    @Test
    fun `load working session returns null when empty`() {
        storage.clearWorkingSession()
        assertNull(storage.loadWorkingSession())
    }

    @Test
    fun `working session preserves track data`() {
        val note1 = MidiNote.create(pitch = 60u, velocity = 100u, startBeat = 0.0, durationBeats = 0.5)
        val note2 = MidiNote.create(pitch = 64u, velocity = 80u, startBeat = 1.0, durationBeats = 1.0)
        val pianoTrack = Track.midi(instrumentName = "Piano", instrumentProgram = 0u, isDrumKit = false,
            notes = listOf(note1, note2), volume = 0.7f)
        val drumTrack = Track.midi(instrumentName = "Drums", instrumentProgram = 0u, isDrumKit = true,
            notes = listOf(MidiNote.create(pitch = 36u, velocity = 127u, startBeat = 0.0, durationBeats = 0.25)),
            volume = 0.9f)
        val session = SavedSession(name = "Multi-Track", bpm = 95.0, barCount = 8, tracks = listOf(pianoTrack, drumTrack))

        storage.saveWorkingSession(session)
        val loaded = storage.loadWorkingSession()!!

        assertEquals(2, loaded.tracks.size)
        assertEquals("Piano", loaded.tracks[0].instrumentName)
        assertFalse(loaded.tracks[0].isDrumKit)
        assertEquals(2, loaded.tracks[0].notes.size)
        assertEquals(0.7f, loaded.tracks[0].volume, 0.01f)
        assertEquals("Drums", loaded.tracks[1].instrumentName)
        assertTrue(loaded.tracks[1].isDrumKit)
        assertEquals(1, loaded.tracks[1].notes.size)
        assertEquals(0.9f, loaded.tracks[1].volume, 0.01f)
    }

    @Test
    fun `save and load named session`() {
        val session = SavedSession(name = "My Song", bpm = 110.0, barCount = 4, tracks = emptyList())
        storage.saveSession(session)
        val sessions = storage.loadSessions()
        assertEquals(1, sessions.size)
        assertEquals("My Song", sessions[0].name)
    }

    @Test
    fun `delete named session`() {
        val session = SavedSession(name = "To Delete", bpm = 100.0, barCount = 4, tracks = emptyList())
        storage.saveSession(session)
        assertEquals(1, storage.loadSessions().size)
        storage.deleteSession(session)
        assertEquals(0, storage.loadSessions().size)
    }

    @Test
    fun `rename session`() {
        val session = SavedSession(name = "Old Name", bpm = 100.0, barCount = 4, tracks = emptyList())
        storage.saveSession(session)
        storage.renameSession(session, "New Name")
        assertEquals("New Name", storage.loadSessions()[0].name)
    }

    @Test
    fun `update existing session`() {
        val session = SavedSession(name = "Evolving", bpm = 100.0, barCount = 4, tracks = emptyList())
        storage.saveSession(session)
        val track = Track.midi(instrumentName = "Piano", instrumentProgram = 0u, isDrumKit = false)
        storage.saveSession(session.copy(tracks = listOf(track)))
        val sessions = storage.loadSessions()
        assertEquals(1, sessions.size)
        assertEquals(1, sessions[0].tracks.size)
    }
}
