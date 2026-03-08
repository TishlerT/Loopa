package com.loopa.feature.editor

import com.loopa.core.model.*
import com.loopa.feature.looper.LooperViewModel
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.BeforeEach

/**
 * Tests for TrackFocusViewModel — ported from iOS TrackFocusViewModelTests.swift
 */
class TrackFocusViewModelTest {

    private lateinit var looperVM: LooperViewModel
    private lateinit var track: Track
    private lateinit var focusVM: TrackFocusViewModel

    @BeforeEach
    fun setUp() {
        looperVM = LooperViewModel()
        track = Track.midi(
            instrumentName = "Piano",
            instrumentProgram = 0u,
            isDrumKit = false,
            notes = listOf(
                MidiNote.create(pitch = 60u, velocity = 100u, startBeat = 0.0, durationBeats = 1.0),
                MidiNote.create(pitch = 64u, velocity = 90u, startBeat = 2.0, durationBeats = 0.5),
                MidiNote.create(pitch = 67u, velocity = 80u, startBeat = 4.0, durationBeats = 2.0)
            )
        )
        // Load track into looper so syncTrackToLooper works
        looperVM.looper.loadTracks(listOf(track))
        looperVM.syncState()
        focusVM = TrackFocusViewModel(initialTrack = track, looperVM = looperVM)
    }

    // MARK: - Note Selection

    @Test
    fun `select note`() {
        val noteId = focusVM.track.notes[0].id
        focusVM.selectNote(noteId)
        assertEquals(noteId, focusVM.selectedNoteId)
        assertNotNull(focusVM.selectedNote)
        assertEquals(60.toUByte(), focusVM.selectedNote?.pitch)
    }

    @Test
    fun `deselect note`() {
        val noteId = focusVM.track.notes[0].id
        focusVM.selectNote(noteId)
        focusVM.deselectNote()
        assertNull(focusVM.selectedNoteId)
        assertNull(focusVM.selectedNote)
    }

    // MARK: - Move Note

    @Test
    fun `move note snaps to grid`() {
        val note = focusVM.track.notes[0]
        focusVM.gridStep = 0.25
        focusVM.moveNote(note.id, 0.1)
        val movedNote = focusVM.track.notes.first { it.id == note.id }
        assertEquals(0.0, movedNote.startBeat, 0.001)
    }

    @Test
    fun `move note snaps to grid eighth note`() {
        val note = focusVM.track.notes[0]
        focusVM.gridStep = 0.25
        focusVM.moveNote(note.id, 0.4)
        val movedNote = focusVM.track.notes.first { it.id == note.id }
        assertEquals(0.5, movedNote.startBeat, 0.001)
    }

    @Test
    fun `move note clamps to bounds`() {
        val note = focusVM.track.notes[0]
        focusVM.moveNote(note.id, focusVM.loopLengthBeats + 5.0)
        val movedNote = focusVM.track.notes.first { it.id == note.id }
        assertTrue(movedNote.endBeat <= focusVM.loopLengthBeats)
    }

    @Test
    fun `move note clamps to start`() {
        val note = focusVM.track.notes[0]
        focusVM.moveNote(note.id, -5.0)
        val movedNote = focusVM.track.notes.first { it.id == note.id }
        assertTrue(movedNote.startBeat >= 0)
    }

    // MARK: - Resize Note

    @Test
    fun `resize note minimum duration`() {
        val note = focusVM.track.notes[0]
        focusVM.gridStep = 0.25
        focusVM.resizeNote(note.id, 0.05)
        val resizedNote = focusVM.track.notes.first { it.id == note.id }
        assertTrue(resizedNote.durationBeats >= focusVM.gridStep)
    }

    @Test
    fun `resize note snaps to grid`() {
        val note = focusVM.track.notes[0]
        focusVM.gridStep = 0.25
        focusVM.resizeNote(note.id, 0.6)
        val resizedNote = focusVM.track.notes.first { it.id == note.id }
        assertEquals(0.5, resizedNote.durationBeats, 0.001)
    }

    // MARK: - Delete Note

    @Test
    fun `delete note removes from track`() {
        val initialCount = focusVM.track.notes.size
        val noteToDelete = focusVM.track.notes[0]
        focusVM.deleteNote(noteToDelete.id)
        assertEquals(initialCount - 1, focusVM.track.notes.size)
        assertNull(focusVM.track.notes.firstOrNull { it.id == noteToDelete.id })
    }

    @Test
    fun `delete selected note deselects it`() {
        val note = focusVM.track.notes[0]
        focusVM.selectNote(note.id)
        focusVM.deleteNote(note.id)
        assertNull(focusVM.selectedNoteId)
    }

    // MARK: - Add Note

    @Test
    fun `add note`() {
        val initialCount = focusVM.track.notes.size
        focusVM.addNote(pitch = 72u, startBeat = 6.0, duration = 1.0)
        assertEquals(initialCount + 1, focusVM.track.notes.size)
        val addedNote = focusVM.track.notes.firstOrNull { it.pitch == 72.toUByte() }
        assertNotNull(addedNote)
        assertEquals(6.0, addedNote!!.startBeat, 0.001)
    }

    @Test
    fun `add note snaps to grid`() {
        focusVM.gridStep = 0.25
        focusVM.addNote(pitch = 72u, startBeat = 0.1, duration = 0.6)
        val addedNote = focusVM.track.notes.first { it.pitch == 72.toUByte() }
        assertEquals(0.0, addedNote.startBeat, 0.001)
        assertEquals(0.5, addedNote.durationBeats, 0.001)
    }

    @Test
    fun `add note selects it`() {
        focusVM.addNote(pitch = 72u, startBeat = 6.0, duration = 1.0)
        val addedNote = focusVM.track.notes.first { it.pitch == 72.toUByte() }
        assertEquals(addedNote.id, focusVM.selectedNoteId)
    }

    @Test
    fun `add note with different velocities`() {
        focusVM.addNote(pitch = 72u, startBeat = 6.0, duration = 0.5, velocity = 127u)
        focusVM.addNote(pitch = 74u, startBeat = 7.0, duration = 0.5, velocity = 64u)
        focusVM.addNote(pitch = 76u, startBeat = 8.0, duration = 0.5, velocity = 32u)

        val loudNote = focusVM.track.notes.first { it.pitch == 72.toUByte() && it.startBeat == 6.0 }
        val medNote = focusVM.track.notes.first { it.pitch == 74.toUByte() && it.startBeat == 7.0 }
        val softNote = focusVM.track.notes.first { it.pitch == 76.toUByte() && it.startBeat == 8.0 }

        assertEquals(127.toUByte(), loudNote.velocity)
        assertEquals(64.toUByte(), medNote.velocity)
        assertEquals(32.toUByte(), softNote.velocity)
    }

    // MARK: - Chord Tests

    @Test
    fun `chords remain independent`() {
        focusVM.addNote(pitch = 60u, startBeat = 8.0, duration = 1.0)
        focusVM.addNote(pitch = 64u, startBeat = 8.0, duration = 1.0)
        focusVM.addNote(pitch = 67u, startBeat = 8.0, duration = 1.0)

        val chordNotes = focusVM.track.notes.filter { it.startBeat == 8.0 }
        assertEquals(3, chordNotes.size)

        val noteToMove = chordNotes.first { it.pitch == 64.toUByte() }
        focusVM.moveNote(noteToMove.id, 10.0)

        val remainingChord = focusVM.track.notes.filter { it.startBeat == 8.0 }
        assertEquals(2, remainingChord.size)
        assertEquals(10.0, focusVM.track.notes.first { it.id == noteToMove.id }.startBeat, 0.001)
    }

    // MARK: - Grid Step

    @Test
    fun `set grid step`() {
        focusVM.setGridStep(QuantizeDivision.EIGHTH)
        assertEquals(0.5, focusVM.gridStep, 0.001)

        focusVM.setGridStep(QuantizeDivision.QUARTER)
        assertEquals(1.0, focusVM.gridStep, 0.001)

        focusVM.setGridStep(QuantizeDivision.SIXTEENTH)
        assertEquals(0.25, focusVM.gridStep, 0.001)

        focusVM.setGridStep(QuantizeDivision.THIRTY_SECOND)
        assertEquals(0.125, focusVM.gridStep, 0.001)
    }

    // MARK: - Quantize Track

    @Test
    fun `quantize track`() {
        focusVM.addNote(pitch = 60u, startBeat = 0.1, duration = 0.3)
        focusVM.addNote(pitch = 64u, startBeat = 1.3, duration = 0.7)

        focusVM.quantizeTrack(QuantizeDivision.QUARTER)

        val notes = focusVM.track.notes.filter { it.pitch.toInt() >= 60 }
        assertTrue(notes.all { note ->
            note.startBeat.mod(1.0) < 0.001 || note.startBeat.mod(1.0) > 0.999
        })
    }

    // MARK: - Copy & Paste

    @Test
    fun `copy paste preserves relative offsets`() {
        val testTrack = Track.midi(
            instrumentName = "Piano", instrumentProgram = 0u, isDrumKit = false,
            notes = listOf(
                MidiNote.create(pitch = 60u, velocity = 100u, startBeat = 2.0, durationBeats = 0.5),
                MidiNote.create(pitch = 64u, velocity = 100u, startBeat = 4.0, durationBeats = 0.5),
                MidiNote.create(pitch = 67u, velocity = 100u, startBeat = 6.0, durationBeats = 0.5)
            )
        )
        looperVM.looper.loadTracks(listOf(testTrack))
        looperVM.syncState()
        val testVM = TrackFocusViewModel(initialTrack = testTrack, looperVM = looperVM)

        testVM.toggleMultiSelectMode()
        testVM.selectNotes(testVM.track.notes.map { it.id }.toSet())
        testVM.copySelectedNotes()
        assertTrue(testVM.canPaste)

        testVM.currentBeat = 10.0
        val originalIds = testVM.track.notes.map { it.id }
        for (id in originalIds) testVM.deleteNote(id)
        assertEquals(0, testVM.track.notes.size)

        testVM.pasteNotes()
        assertEquals(3, testVM.track.notes.size)

        val pastedNotes = testVM.track.notes.sortedBy { it.startBeat }
        assertEquals(10.0, pastedNotes[0].startBeat, 0.001)
        assertEquals(12.0, pastedNotes[1].startBeat, 0.001)
        assertEquals(14.0, pastedNotes[2].startBeat, 0.001)
        assertEquals(60.toUByte(), pastedNotes[0].pitch)
        assertEquals(64.toUByte(), pastedNotes[1].pitch)
        assertEquals(67.toUByte(), pastedNotes[2].pitch)
    }

    @Test
    fun `copy paste single note`() {
        val testTrack = Track.midi(
            instrumentName = "Piano", instrumentProgram = 0u, isDrumKit = false,
            notes = listOf(MidiNote.create(pitch = 60u, velocity = 100u, startBeat = 3.0, durationBeats = 1.0))
        )
        looperVM.looper.loadTracks(listOf(testTrack))
        looperVM.syncState()
        val testVM = TrackFocusViewModel(initialTrack = testTrack, looperVM = looperVM)

        testVM.selectNote(testVM.track.notes[0].id)
        testVM.copySelectedNotes()
        testVM.deleteNote(testVM.track.notes[0].id)
        testVM.currentBeat = 8.0
        testVM.pasteNotes()

        assertEquals(1, testVM.track.notes.size)
        assertEquals(8.0, testVM.track.notes[0].startBeat, 0.001)
        assertEquals(60.toUByte(), testVM.track.notes[0].pitch)
        assertEquals(1.0, testVM.track.notes[0].durationBeats, 0.001)
    }

    @Test
    fun `cannot paste with empty clipboard`() {
        assertFalse(focusVM.canPaste)
    }

    @Test
    fun `can copy with selection`() {
        assertFalse(focusVM.canCopy)
        focusVM.selectNote(focusVM.track.notes[0].id)
        assertTrue(focusVM.canCopy)
    }

    // MARK: - Multi-Drag

    @Test
    fun `multi drag preserves relative positions`() {
        val testTrack = Track.midi(
            instrumentName = "Piano", instrumentProgram = 0u, isDrumKit = false,
            notes = listOf(
                MidiNote.create(pitch = 60u, velocity = 100u, startBeat = 1.0, durationBeats = 0.5),
                MidiNote.create(pitch = 64u, velocity = 100u, startBeat = 2.0, durationBeats = 0.5),
                MidiNote.create(pitch = 67u, velocity = 100u, startBeat = 3.0, durationBeats = 0.5)
            )
        )
        looperVM.looper.loadTracks(listOf(testTrack))
        looperVM.syncState()
        val testVM = TrackFocusViewModel(initialTrack = testTrack, looperVM = looperVM)

        testVM.toggleMultiSelectMode()
        testVM.selectNotes(testVM.track.notes.map { it.id }.toSet())
        testVM.beginMultiDrag()
        assertTrue(testVM.isMultiDragging)
        assertEquals(3, testVM.multiDragStartPositions.size)

        testVM.updateMultiDragPosition(deltaBeats = 2.0, deltaPitch = 2)
        testVM.endMultiDrag()

        val movedNotes = testVM.track.notes.sortedBy { it.startBeat }
        assertEquals(3.0, movedNotes[0].startBeat, 0.001)
        assertEquals(4.0, movedNotes[1].startBeat, 0.001)
        assertEquals(5.0, movedNotes[2].startBeat, 0.001)
        assertEquals(62.toUByte(), movedNotes[0].pitch)
        assertEquals(66.toUByte(), movedNotes[1].pitch)
        assertEquals(69.toUByte(), movedNotes[2].pitch)
    }

    @Test
    fun `multi drag preview positions`() {
        val testTrack = Track.midi(
            instrumentName = "Piano", instrumentProgram = 0u, isDrumKit = false,
            notes = listOf(
                MidiNote.create(pitch = 60u, velocity = 100u, startBeat = 0.0, durationBeats = 0.5),
                MidiNote.create(pitch = 64u, velocity = 100u, startBeat = 1.0, durationBeats = 0.5)
            )
        )
        looperVM.looper.loadTracks(listOf(testTrack))
        looperVM.syncState()
        val testVM = TrackFocusViewModel(initialTrack = testTrack, looperVM = looperVM)

        testVM.toggleMultiSelectMode()
        testVM.selectNotes(testVM.track.notes.map { it.id }.toSet())
        testVM.beginMultiDrag()
        testVM.updateMultiDragPosition(deltaBeats = 1.5, deltaPitch = -3)

        val preview1 = testVM.multiDragPreviewPosition(testVM.track.notes[0].id)
        val preview2 = testVM.multiDragPreviewPosition(testVM.track.notes[1].id)

        assertNotNull(preview1)
        assertNotNull(preview2)
        assertEquals(1.5, preview1!!.first, 0.001)
        assertEquals(57.toUByte(), preview1.second)
        assertEquals(2.5, preview2!!.first, 0.001)
        assertEquals(61.toUByte(), preview2.second)

        testVM.cancelMultiDrag()
        assertFalse(testVM.isMultiDragging)
    }

    @Test
    fun `background locked with multi-select notes`() {
        focusVM.toggleMultiSelectMode()
        assertFalse(focusVM.isBackgroundLocked)

        focusVM.toggleNoteSelection(focusVM.track.notes[0].id)
        assertTrue(focusVM.isBackgroundLocked)

        focusVM.toggleNoteSelection(focusVM.track.notes[0].id)
        assertFalse(focusVM.isBackgroundLocked)
    }

    @Test
    fun `multi drag with grid snapping`() {
        val testTrack = Track.midi(
            instrumentName = "Piano", instrumentProgram = 0u, isDrumKit = false,
            notes = listOf(
                MidiNote.create(pitch = 60u, velocity = 100u, startBeat = 0.0, durationBeats = 0.5),
                MidiNote.create(pitch = 64u, velocity = 100u, startBeat = 1.0, durationBeats = 0.5)
            )
        )
        looperVM.looper.loadTracks(listOf(testTrack))
        looperVM.syncState()
        val testVM = TrackFocusViewModel(initialTrack = testTrack, looperVM = looperVM)
        testVM.gridStep = 0.5

        testVM.toggleMultiSelectMode()
        testVM.selectNotes(testVM.track.notes.map { it.id }.toSet())
        testVM.beginMultiDrag()
        testVM.updateMultiDragPosition(deltaBeats = 0.3, deltaPitch = 0)

        assertEquals(0.5, testVM.multiDragDeltaBeats, 0.001)
        testVM.cancelMultiDrag()
    }

    @Test
    fun `deselect all clears multi-drag state`() {
        focusVM.toggleMultiSelectMode()
        focusVM.selectNotes(focusVM.track.notes.map { it.id }.toSet())
        focusVM.beginMultiDrag()

        assertTrue(focusVM.isMultiDragging)
        assertTrue(focusVM.multiDragStartPositions.isNotEmpty())

        focusVM.deselectAll()

        assertFalse(focusVM.isMultiDragging)
        assertTrue(focusVM.multiDragStartPositions.isEmpty())
        assertTrue(focusVM.selectedNoteIds.isEmpty())
    }

    // MARK: - Undo

    @Test
    fun `undo restores previous state`() {
        val initialCount = focusVM.track.notes.size
        focusVM.addNote(pitch = 72u, startBeat = 6.0, duration = 1.0)
        assertEquals(initialCount + 1, focusVM.track.notes.size)

        focusVM.undo()
        assertEquals(initialCount, focusVM.track.notes.size)
    }

    @Test
    fun `can undo after add`() {
        assertFalse(focusVM.canUndo)
        focusVM.addNote(pitch = 72u, startBeat = 6.0, duration = 1.0)
        assertTrue(focusVM.canUndo)
    }

    // MARK: - Drum Track

    @Test
    fun `add drum note`() {
        val drumTrack = Track.midi(instrumentName = "Drums", instrumentProgram = 0u, isDrumKit = true, notes = emptyList())
        looperVM.looper.loadTracks(listOf(drumTrack))
        looperVM.syncState()
        val drumFocusVM = TrackFocusViewModel(initialTrack = drumTrack, looperVM = looperVM)

        drumFocusVM.addNote(pitch = 36u, startBeat = 0.0, duration = 0.25, velocity = 100u)
        assertEquals(1, drumFocusVM.track.notes.size)
        assertEquals(36.toUByte(), drumFocusVM.track.notes[0].pitch)
    }
}
