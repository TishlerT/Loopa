package com.loopa.feature.editor

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.loopa.core.looper.Quantizer
import com.loopa.core.model.*
import com.loopa.feature.looper.LooperViewModel
import kotlin.math.max
import kotlin.math.min

enum class HorizontalEdge { LEADING, TRAILING }

/**
 * Stateful editor view model for a single non-vocal track.
 * Ported from iOS TrackFocusViewModel.swift.
 */
class TrackFocusViewModel(
    initialTrack: Track,
    val looperVM: LooperViewModel
) {
    val trackId: String = initialTrack.id

    // Published State
    var isPlaying by mutableStateOf(false)
    var currentBeat by mutableStateOf(0.0)
    var track by mutableStateOf(initialTrack)
        private set

    var selectedNoteId by mutableStateOf<String?>(null)
    var selectedNoteIds by mutableStateOf<Set<String>>(emptySet())
    var isMultiSelectMode by mutableStateOf(false)
    var gridStep by mutableStateOf(0.0)
    var showingQuantizeSheet by mutableStateOf(false)
    var hideEmptyDrumRows by mutableStateOf(false)

    var draggedNoteId by mutableStateOf<String?>(null)
    var isResizing by mutableStateOf(false)
    var resizeEdge by mutableStateOf(HorizontalEdge.TRAILING)
    var dragPreviewStartBeat by mutableStateOf<Double?>(null)
    var dragPreviewDuration by mutableStateOf<Double?>(null)
    var dragPreviewPitch by mutableStateOf<UByte?>(null)
    var isResizeMode by mutableStateOf(false)
    var isAddNoteMode by mutableStateOf(false)
    var isDeleteMode by mutableStateOf(false)
    var lastNoteDuration by mutableStateOf(0.25)

    var isMultiDragging by mutableStateOf(false)
    var multiDragStartPositions = mutableMapOf<String, Pair<Double, UByte>>()
    var multiDragDeltaBeats by mutableStateOf(0.0)
    var multiDragDeltaPitch by mutableStateOf(0)

    var isPlayheadSelected by mutableStateOf(false)
    var zoomLevel by mutableStateOf(1.0f)
    var verticalZoomLevel by mutableStateOf(1.0f)

    private val minNoteDuration = 0.125
    private val maxUndoSteps = 50
    private val undoStack = mutableListOf<List<MidiNote>>()
    private var copiedNotes = listOf<MidiNote>()
    private var copyBaseStartBeat = 0.0

    // Computed
    val canUndo: Boolean get() = undoStack.isNotEmpty()
    val loopLengthBeats: Double get() = looperVM.loopLengthBeats
    val trackLengthBeats: Double get() = track.recordedLengthBeats
    val bpm: Double get() = looperVM.bpm
    val selectedNote: MidiNote? get() = selectedNoteId?.let { id -> track.notes.firstOrNull { it.id == id } }

    val pitchRangeMin: UByte
        get() = if (track.notes.isEmpty()) 48u else track.notes.minOf { it.pitch }
    val pitchRangeMax: UByte
        get() = if (track.notes.isEmpty()) 72u else track.notes.maxOf { it.pitch }

    val isBackgroundLocked: Boolean
        get() = selectedNoteId != null || isPlayheadSelected || (isMultiSelectMode && selectedNoteIds.isNotEmpty())

    val canCopy: Boolean get() = selectedNoteId != null || selectedNoteIds.isNotEmpty()
    val canPaste: Boolean get() = copiedNotes.isNotEmpty()
    val selectedNotes: List<MidiNote> get() = track.notes.filter { it.id in selectedNoteIds }

    companion object {
        const val MIN_ZOOM = 0.5f
        const val MAX_ZOOM = 4.0f
        const val MIN_VERTICAL_ZOOM = 0.6f
        const val MAX_VERTICAL_ZOOM = 2.5f
    }

    // MARK: - Undo

    private fun pushUndo() {
        undoStack.add(track.notes)
        if (undoStack.size > maxUndoSteps) undoStack.removeFirst()
    }

    fun undo() {
        if (undoStack.isEmpty()) return
        val prev = undoStack.removeLast()
        track = track.copy(notes = prev)
        syncTrackToLooper()
    }

    private fun syncTrackToLooper() {
        looperVM.looper.updateTrack(track)
        looperVM.syncState()
    }

    // MARK: - Note Selection

    fun selectNote(noteId: String) {
        selectedNoteId = noteId
    }

    fun deselectNote() {
        selectedNoteId = null
    }

    fun toggleNoteSelection(noteId: String) {
        if (selectedNoteIds.contains(noteId)) {
            selectedNoteIds = selectedNoteIds - noteId
        } else {
            selectedNoteIds = selectedNoteIds + noteId
        }
    }

    fun selectNotes(ids: Set<String>) {
        selectedNoteIds = ids
    }

    fun deselectAll() {
        selectedNoteId = null
        selectedNoteIds = emptySet()
        isMultiDragging = false
        multiDragStartPositions.clear()
    }

    // MARK: - Move Note

    fun moveNote(noteId: String, toStartBeat: Double) {
        pushUndo()
        val noteIndex = track.notes.indexOfFirst { it.id == noteId }
        if (noteIndex < 0) return
        val note = track.notes[noteIndex]

        var newStart = if (gridStep > 0) Quantizer.snap(toStartBeat, gridStep) else toStartBeat
        newStart = max(0.0, newStart)
        newStart = min(loopLengthBeats - note.durationBeats, newStart)

        val updated = note.copy(startBeat = newStart)
        val newNotes = track.notes.toMutableList()
        newNotes[noteIndex] = updated
        track = track.copy(notes = newNotes)
        syncTrackToLooper()
    }

    // MARK: - Resize Note

    fun resizeNote(noteId: String, toDuration: Double) {
        pushUndo()
        val noteIndex = track.notes.indexOfFirst { it.id == noteId }
        if (noteIndex < 0) return
        val note = track.notes[noteIndex]

        val minDur = if (gridStep > 0) gridStep else minNoteDuration
        var newDuration = if (gridStep > 0) Quantizer.snap(toDuration, gridStep) else toDuration
        newDuration = max(minDur, newDuration)
        newDuration = min(loopLengthBeats - note.startBeat, newDuration)

        val updated = note.copy(durationBeats = newDuration)
        val newNotes = track.notes.toMutableList()
        newNotes[noteIndex] = updated
        track = track.copy(notes = newNotes)
        syncTrackToLooper()
    }

    // MARK: - Delete Note

    fun deleteNote(noteId: String) {
        pushUndo()
        val newNotes = track.notes.filter { it.id != noteId }
        track = track.copy(notes = newNotes)
        if (selectedNoteId == noteId) selectedNoteId = null
        selectedNoteIds = selectedNoteIds - noteId
        syncTrackToLooper()
    }

    // MARK: - Add Note

    fun addNote(pitch: UByte, startBeat: Double, duration: Double, velocity: UByte = 100u) {
        pushUndo()
        var newStart = if (gridStep > 0) Quantizer.snap(startBeat, gridStep) else startBeat
        var newDuration = if (gridStep > 0) Quantizer.snap(duration, gridStep).coerceAtLeast(gridStep) else duration
        newStart = max(0.0, newStart)
        newDuration = max(if (gridStep > 0) gridStep else minNoteDuration, newDuration)

        val note = MidiNote.create(pitch = pitch, velocity = velocity, startBeat = newStart, durationBeats = newDuration)
        val newNotes = track.notes + note
        track = track.copy(notes = newNotes)
        selectedNoteId = note.id
        lastNoteDuration = newDuration
        syncTrackToLooper()
    }

    // MARK: - Grid Step

    fun setGridStep(division: QuantizeDivision) {
        gridStep = division.beatFraction ?: 0.0
    }

    // MARK: - Quantize Track

    fun quantizeTrack(division: QuantizeDivision) {
        pushUndo()
        val quantizer = Quantizer(bpm = bpm, division = division)
        val quantized = quantizer.quantize(track.notes, loopLengthBeats)
        track = track.copy(notes = quantized)
        syncTrackToLooper()
    }

    // MARK: - Multi-Select Mode

    fun toggleMultiSelectMode() {
        isMultiSelectMode = !isMultiSelectMode
        if (!isMultiSelectMode) {
            selectedNoteIds = emptySet()
        }
    }

    // MARK: - Copy/Paste

    fun copySelectedNotes() {
        val notesToCopy = if (isMultiSelectMode && selectedNoteIds.isNotEmpty()) {
            track.notes.filter { it.id in selectedNoteIds }
        } else if (selectedNoteId != null) {
            track.notes.filter { it.id == selectedNoteId }
        } else return

        if (notesToCopy.isEmpty()) return
        copyBaseStartBeat = notesToCopy.minOf { it.startBeat }
        copiedNotes = notesToCopy
    }

    fun pasteNotes() {
        if (copiedNotes.isEmpty()) return
        pushUndo()

        val newNotes = track.notes.toMutableList()
        for (note in copiedNotes) {
            val offset = note.startBeat - copyBaseStartBeat
            val newStart = currentBeat + offset
            if (newStart >= 0 && newStart + note.durationBeats <= loopLengthBeats) {
                newNotes.add(MidiNote.create(
                    pitch = note.pitch,
                    velocity = note.velocity,
                    startBeat = newStart,
                    durationBeats = note.durationBeats
                ))
            }
        }
        track = track.copy(notes = newNotes)
        syncTrackToLooper()
    }

    // MARK: - Multi-Drag

    fun beginMultiDrag() {
        isMultiDragging = true
        multiDragStartPositions.clear()
        for (note in track.notes) {
            if (note.id in selectedNoteIds) {
                multiDragStartPositions[note.id] = Pair(note.startBeat, note.pitch)
            }
        }
        multiDragDeltaBeats = 0.0
        multiDragDeltaPitch = 0
    }

    fun updateMultiDragPosition(deltaBeats: Double, deltaPitch: Int) {
        val snappedDelta = if (gridStep > 0) Quantizer.snap(deltaBeats, gridStep) else deltaBeats
        multiDragDeltaBeats = snappedDelta
        multiDragDeltaPitch = deltaPitch
    }

    fun endMultiDrag() {
        if (!isMultiDragging) return
        pushUndo()

        val newNotes = track.notes.toMutableList()
        for (i in newNotes.indices) {
            val startPos = multiDragStartPositions[newNotes[i].id] ?: continue
            val newStart = max(0.0, startPos.first + multiDragDeltaBeats)
            val newPitch = (startPos.second.toInt() + multiDragDeltaPitch).coerceIn(0, 127).toUByte()
            newNotes[i] = newNotes[i].copy(startBeat = newStart, pitch = newPitch)
        }

        track = track.copy(notes = newNotes)
        isMultiDragging = false
        multiDragStartPositions.clear()
        multiDragDeltaBeats = 0.0
        multiDragDeltaPitch = 0
        syncTrackToLooper()
    }

    fun cancelMultiDrag() {
        isMultiDragging = false
        multiDragStartPositions.clear()
        multiDragDeltaBeats = 0.0
        multiDragDeltaPitch = 0
    }

    fun multiDragPreviewPosition(noteId: String): Pair<Double, UByte>? {
        val startPos = multiDragStartPositions[noteId] ?: return null
        val newStart = startPos.first + multiDragDeltaBeats
        val newPitch = (startPos.second.toInt() + multiDragDeltaPitch).coerceIn(0, 127).toUByte()
        return Pair(newStart, newPitch)
    }

    // MARK: - Zoom

    fun setZoom(level: Float) {
        zoomLevel = level.coerceIn(MIN_ZOOM, MAX_ZOOM)
    }

    fun setVerticalZoom(level: Float) {
        verticalZoomLevel = level.coerceIn(MIN_VERTICAL_ZOOM, MAX_VERTICAL_ZOOM)
    }
}
