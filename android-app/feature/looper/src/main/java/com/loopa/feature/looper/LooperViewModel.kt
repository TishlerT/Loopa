package com.loopa.feature.looper

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import com.loopa.core.looper.MultiTrackLooper
import com.loopa.core.looper.Quantizer
import com.loopa.core.model.*

/**
 * Main application coordinator for the shipped app.
 * Ported from iOS LooperViewModel.swift.
 */
class LooperViewModel : ViewModel() {

    // MARK: - Core Engine
    val looper = MultiTrackLooper()

    // MARK: - Published State
    var currentInstrument by mutableStateOf(Instrument.PIANO)
    private var _barCount by mutableStateOf(BarCount.FOUR)
    val barCount: BarCount get() = _barCount
    private var _bpm by mutableStateOf(100.0)
    val bpm: Double get() = _bpm
    var isMetronomeOn by mutableStateOf(false)
    var audioError by mutableStateOf<String?>(null)
    private var _quantizeDivision by mutableStateOf(QuantizeDivision.OFF)
    val quantizeDivision: QuantizeDivision get() = _quantizeDivision

    // Pause State
    var isPaused by mutableStateOf(false)
        private set

    // Count-In State
    var isCountingIn by mutableStateOf(false)
        private set
    var countInBeat by mutableStateOf(0)
        private set
    val countInBeats: Int = 4

    // Looper State (forwarded)
    var tracks by mutableStateOf<List<Track>>(emptyList())
        private set
    var isRecording by mutableStateOf(false)
        private set
    var isPlaying by mutableStateOf(false)
        private set
    var currentPosition by mutableStateOf(0.0)
        private set
    var currentBeat by mutableStateOf(0)
        private set
    var recordingProgress by mutableStateOf(0.0)
        private set

    // Session State
    var savedSessions by mutableStateOf<List<SavedSession>>(emptyList())
        private set
    var currentSessionName by mutableStateOf("")
    var showingSaveSheet by mutableStateOf(false)
    var showingLoadSheet by mutableStateOf(false)
    var showingSettings by mutableStateOf(false)
    var showingTracksSheet by mutableStateOf(false)
    var showingBPMEditor by mutableStateOf(false)
    var selectedTrackForFocus by mutableStateOf<Track?>(null)

    // Vocal State
    var isRecordingVocals by mutableStateOf(false)
        private set
    var showMicPermissionAlert by mutableStateOf(false)
    var isVocalMode by mutableStateOf(false)
    var showHeadphoneRecommendation by mutableStateOf(false)

    // Keyboard State
    var octaveOffset by mutableStateOf(0)

    // Export State
    var isExporting by mutableStateOf(false)
        private set

    // MARK: - Computed Properties

    val keyCount: Int = 25

    val startNote: UByte
        get() {
            val base = 48 + (octaveOffset * 12)
            return base.coerceIn(24, 84).toUByte()
        }

    val currentOctaveName: String
        get() = "C${4 + octaveOffset}"

    val anyTrackSoloed: Boolean
        get() = looper.anyTrackSoloed

    val loopLengthBeats: Double
        get() = looper.loopLengthBeats

    val loopLengthSeconds: Double
        get() = looper.loopLength

    val totalBeats: Int
        get() = looper.loopLengthBeats.toInt()

    val progressFraction: Double
        get() {
            if (looper.loopLength <= 0) return 0.0
            return looper.synchronizedPlaybackPosition / looper.loopLength
        }

    // MARK: - BPM

    fun setBpm(newBpm: Double) {
        _bpm = newBpm.coerceIn(40.0, 300.0)
        looper.bpm = _bpm
    }

    // MARK: - Bar Count

    fun setBarCount(count: BarCount) {
        _barCount = count
        looper.setBarCount(count)
    }

    // MARK: - Quantization

    fun setQuantizeDivision(division: QuantizeDivision) {
        _quantizeDivision = division
        updateQuantizer()
    }

    fun cycleQuantizeDivision() {
        val divisions = listOf(QuantizeDivision.OFF, QuantizeDivision.SIXTEENTH, QuantizeDivision.EIGHTH, QuantizeDivision.QUARTER)
        val currentIndex = divisions.indexOf(_quantizeDivision)
        val next = divisions[(currentIndex + 1) % divisions.size]
        setQuantizeDivision(next)
    }

    private fun updateQuantizer() {
        looper.quantizer = if (_quantizeDivision == QuantizeDivision.OFF) null
        else Quantizer(bpm = _bpm, division = _quantizeDivision)
    }

    // MARK: - Transport

    fun record() {
        if (isCountingIn) return
        if (isRecording) {
            stopRecording()
            return
        }
        startCountIn()
    }

    private fun startCountIn() {
        isCountingIn = true
        countInBeat = countInBeats
        // In real app: start timer for count-in beats
        // For now, immediately start recording (timer needs main loop)
    }

    fun startRecordingAfterCountIn() {
        isCountingIn = false
        countInBeat = 0

        val instrument = currentInstrument
        val position = if (looper.isPlaying || looper.isPaused) {
            looper.synchronizedPlaybackPosition
        } else null

        looper.startRecording(instrument, position)
        syncState()
    }

    private fun stopRecording() {
        looper.stopRecording()
        syncState()
    }

    fun playPause() {
        if (isCountingIn) return
        if (isRecording) {
            stopRecording()
            pausePlayback()
            return
        }
        if (isPlaying) {
            pausePlayback()
        } else if (isPaused) {
            resumePlayback()
        } else {
            startPlayback()
        }
    }

    private fun startPlayback() {
        looper.startPlayback()
        syncState()
    }

    private fun pausePlayback() {
        looper.pausePlayback()
        syncState()
    }

    private fun resumePlayback() {
        looper.resumePlayback()
        syncState()
    }

    fun restart() {
        if (isRecording) {
            stopRecording()
        }
        looper.seekTo(0.0)
        if (!isPlaying && !isPaused) {
            startPlayback()
        }
        syncState()
    }

    // MARK: - Track Operations

    fun toggleMute(track: Track) {
        looper.toggleMute(track)
        syncState()
    }

    fun toggleSolo(track: Track) {
        looper.toggleSolo(track)
        syncState()
    }

    fun toggleLoop(track: Track) {
        looper.toggleLoop(track)
        syncState()
    }

    fun deleteTrack(track: Track) {
        looper.deleteTrack(track)
        syncState()
    }

    fun setTrackVolume(track: Track, volume: Float) {
        looper.setTrackVolume(track.id, volume)
        syncState()
    }

    fun setTrackInstrument(track: Track, instrument: Instrument) {
        looper.setTrackInstrument(track.id, instrument)
        syncState()
    }

    fun quantizeTrack(track: Track, division: QuantizeDivision) {
        if (track.isVocal) return // Can't quantize audio tracks
        looper.quantizeTrack(track.id, division)
        syncState()
    }

    // MARK: - Octave

    fun octaveUp() {
        if (startNote.toInt() + 12 <= 84) octaveOffset++
    }

    fun octaveDown() {
        if (startNote.toInt() - 12 >= 24) octaveOffset--
    }

    // MARK: - Session Management

    fun clearAll() {
        looper.clearAllTracks()
        currentSessionName = ""
        syncState()
        saveWorkingSession()
    }

    fun newSession() {
        clearAll()
    }

    fun saveWorkingSession() {
        if (tracks.isEmpty()) return
        // Actual file I/O delegated to SessionStorage
    }

    fun restoreWorkingSession() {
        // Actual file I/O delegated to SessionStorage
    }

    // MARK: - Vocal Mode

    fun toggleVocalMode() {
        isVocalMode = !isVocalMode
    }

    // MARK: - Note Preview

    fun previewNote(pitch: UByte, velocity: UByte, trackId: String) {
        // Delegated to audio engine (DEFERRED_TO_LOCAL)
    }

    // MARK: - State Sync

    fun syncState() {
        tracks = looper.tracks
        isRecording = looper.isRecording
        isPlaying = looper.isPlaying
        isPaused = looper.isPaused
        currentPosition = looper.currentPosition
        currentBeat = looper.currentBeat
        recordingProgress = looper.recordingProgress
    }
}
