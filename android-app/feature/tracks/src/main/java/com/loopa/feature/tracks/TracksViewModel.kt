package com.loopa.feature.tracks

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.loopa.core.model.*
import com.loopa.feature.looper.LooperViewModel

/**
 * Lightweight mixer-screen adapter around LooperViewModel.
 * Ported from iOS TracksViewModel.swift.
 */
class TracksViewModel(val looperViewModel: LooperViewModel) {

    var selectedTrackId by mutableStateOf<String?>(null)
    var showingQuantizeSheet by mutableStateOf(false)
    var trackToQuantize by mutableStateOf<Track?>(null)
    var showingInstrumentPicker by mutableStateOf(false)
    var trackToChangeInstrument by mutableStateOf<Track?>(null)
    var selectedTrackForFocus by mutableStateOf<Track?>(null)

    val tracks: List<Track> get() = looperViewModel.tracks
    val isPlaying: Boolean get() = looperViewModel.isPlaying
    val isPaused: Boolean get() = looperViewModel.isPaused
    val currentPosition: Double get() = looperViewModel.currentPosition
    val anyTrackSoloed: Boolean get() = looperViewModel.anyTrackSoloed
    val loopLengthBeats: Double get() = looperViewModel.loopLengthBeats
    val bpm: Double get() = looperViewModel.bpm

    fun toggleMute(track: Track) = looperViewModel.toggleMute(track)
    fun toggleSolo(track: Track) = looperViewModel.toggleSolo(track)
    fun toggleLoop(track: Track) = looperViewModel.toggleLoop(track)
    fun setVolume(track: Track, volume: Float) = looperViewModel.setTrackVolume(track, volume)
    fun setInstrument(track: Track, instrument: Instrument) = looperViewModel.setTrackInstrument(track, instrument)
    fun deleteTrack(track: Track) = looperViewModel.deleteTrack(track)
    fun quantizeTrack(track: Track, division: QuantizeDivision) = looperViewModel.quantizeTrack(track, division)

    fun requestQuantize(track: Track) {
        trackToQuantize = track
        showingQuantizeSheet = true
    }

    fun applyQuantize(division: QuantizeDivision) {
        trackToQuantize?.let { quantizeTrack(it, division) }
        showingQuantizeSheet = false
        trackToQuantize = null
    }

    fun cancelQuantize() {
        showingQuantizeSheet = false
        trackToQuantize = null
    }

    fun requestInstrumentChange(track: Track) {
        trackToChangeInstrument = track
        showingInstrumentPicker = true
    }

    fun applyInstrumentChange(instrument: Instrument) {
        trackToChangeInstrument?.let { setInstrument(it, instrument) }
        showingInstrumentPicker = false
        trackToChangeInstrument = null
    }

    fun cancelInstrumentChange() {
        showingInstrumentPicker = false
        trackToChangeInstrument = null
    }

    fun selectTrackForFocus(track: Track) {
        selectedTrackForFocus = track
    }

    fun closeTrackFocus() {
        selectedTrackForFocus = null
    }

    fun getTrack(withId: String): Track? = tracks.firstOrNull { it.id == withId }
}
