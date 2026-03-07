package com.loopa.core.looper

import com.loopa.core.model.*
import kotlin.math.max
import kotlin.math.min

/**
 * Multi-track looper with bar-based recording.
 * Ported from iOS MultiTrackLooper.swift.
 *
 * This is the core transport engine for the app. It manages tracks,
 * recording/playback state, bar-based timing, mute/solo/loop behavior,
 * and note scheduling via callbacks.
 */
class MultiTrackLooper {

    // MARK: - Observable State

    private val _tracks = mutableListOf<Track>()
    val tracks: List<Track> get() = _tracks.toList()

    var isRecording: Boolean = false
        private set
    var isPlaying: Boolean = false
        private set
    var isPaused: Boolean = false
        private set

    var barCount: BarCount = BarCount.FOUR
        private set
    var bpm: Double = 100.0
        set(value) {
            field = value
            recalculateLoopLength()
        }

    // MARK: - Loop Timing

    /** Total loop length in seconds */
    var loopLength: Double = 0.0
        private set

    /** Recording loop length in beats (based on barCount setting) */
    val recordingLoopLengthBeats: Double
        get() = barCount.rawValue.toDouble() * 4.0

    /** Effective loop length in beats (longest track, or barCount if no tracks) */
    val loopLengthBeats: Double
        get() {
            if (_tracks.isEmpty()) return recordingLoopLengthBeats
            return _tracks.maxOfOrNull { it.recordedLengthBeats } ?: recordingLoopLengthBeats
        }

    var currentPosition: Double = 0.0
        private set
    var currentBeat: Int = 0
        private set
    var recordingProgress: Double = 0.0
        private set

    // MARK: - Recording State

    private val recordingEvents = mutableListOf<MidiEvent>()
    private var recordStartTime: Long = 0L // nanoTime
    private var recordingInstrument: Instrument = Instrument.PIANO
    private var punchInTrackId: String? = null
    private var punchInPosition: Double = 0.0

    /** Quantizer for snapping MIDI events to the beat grid */
    var quantizer: Quantizer? = null

    // MARK: - Playback State

    private var playStartTime: Long = 0L // nanoTime
    private var lastTickPosition: Double = 0.0
    private var currentLoopCycle: Int = 0
    private val dispatchedThisCycle = mutableSetOf<String>()
    private var pausedPosition: Double = 0.0

    /** Whether any track has solo enabled */
    val anyTrackSoloed: Boolean
        get() = _tracks.any { it.isSolo }

    // MARK: - Callbacks

    /** Called when a MIDI event should be played */
    var onPlayEvent: ((MidiEvent, Track) -> Unit)? = null

    /** Called on each beat (beatNumber, isDownbeat) */
    var onBeat: ((Int, Boolean) -> Unit)? = null

    /** Called when recording auto-stops at loop wrap */
    var onRecordingAutoStop: (() -> Unit)? = null

    // MARK: - Initialization

    init {
        recalculateLoopLength()
    }

    // MARK: - Loop Length

    private fun recalculateLoopLength() {
        val secondsPerBeat = 60.0 / bpm
        loopLength = loopLengthBeats * secondsPerBeat
    }

    fun setBarCount(count: BarCount) {
        barCount = count
        recalculateLoopLength()
    }

    // MARK: - Recording

    fun startRecording(instrument: Instrument, fromPosition: Double? = null) {
        if (isRecording) return

        recordingEvents.clear()
        recordingInstrument = instrument
        recordStartTime = System.nanoTime()
        isRecording = true

        val startPos = fromPosition ?: 0.0
        punchInPosition = startPos
        punchInTrackId = null

        if (startPos > 0) {
            _tracks.lastOrNull { it.instrumentName == instrument.displayName && !it.isVocal }?.let {
                punchInTrackId = it.id
            }
        }

        if (!isPlaying) {
            if (startPos > 0) {
                pausedPosition = startPos
                isPaused = true
                resumePlayback()
            } else {
                startPlayback()
            }
        }
    }

    fun addLiveEvent(note: UByte, velocity: UByte, isNoteOn: Boolean) {
        if (!isRecording) return

        val now = System.nanoTime()
        val elapsed = (now - recordStartTime) / 1_000_000_000.0
        val recordingLoopSeconds = recordingLoopLengthBeats * (60.0 / bpm)
        val time = elapsed.mod(recordingLoopSeconds)

        val event = MidiEvent(
            time = time,
            note = note,
            velocity = velocity,
            isNoteOn = isNoteOn,
            isLeft = false
        )
        recordingEvents.add(event)
    }

    fun stopRecording() {
        if (!isRecording) return
        isRecording = false

        if (recordingEvents.isNotEmpty()) {
            val recordingLoopSeconds = recordingLoopLengthBeats * (60.0 / bpm)

            var finalEvents = recordingEvents.toList()
            quantizer?.let { q ->
                finalEvents = q.quantize(finalEvents, recordingLoopSeconds).sortedBy { it.time }
            }

            var notes = MidiNote.fromEvents(finalEvents, bpm, recordingLoopLengthBeats)

            // Always quantize drums to 16th notes for step sequencer visibility
            if (recordingInstrument.isDrumKit) {
                val drumQuantizer = Quantizer(bpm = bpm, division = QuantizeDivision.SIXTEENTH)
                notes = drumQuantizer.quantize(notes, recordingLoopLengthBeats)
            }

            val punchTrackId = punchInTrackId
            if (punchTrackId != null) {
                val trackIndex = _tracks.indexOfFirst { it.id == punchTrackId }
                if (trackIndex >= 0) {
                    val punchInBeat = punchInPosition / (60.0 / bpm)
                    val existingNotes = _tracks[trackIndex].notes.toMutableList()
                    existingNotes.removeAll { it.startBeat >= punchInBeat }
                    existingNotes.addAll(notes)
                    existingNotes.sortBy { it.startBeat }
                    _tracks[trackIndex] = _tracks[trackIndex].copy(notes = existingNotes)
                }
            } else {
                val track = Track.midi(
                    instrumentName = recordingInstrument.displayName,
                    instrumentProgram = recordingInstrument.programNumber,
                    isDrumKit = recordingInstrument.isDrumKit,
                    notes = notes,
                    recordedLengthBeats = recordingLoopLengthBeats,
                    isLooping = true
                )
                _tracks.add(track)
            }
        }

        recordingEvents.clear()
        punchInTrackId = null
        punchInPosition = 0.0
        recordingProgress = 0.0
    }

    // MARK: - Playback

    fun startPlayback() {
        if (isPlaying) return

        recalculateLoopLength()
        if (loopLength <= 0) return

        isPlaying = true
        isPaused = false
        pausedPosition = 0.0
        playStartTime = System.nanoTime()
        resetPlaybackState()
    }

    fun stopPlayback() {
        isPlaying = false
        isRecording = false
        isPaused = false
        resetPlaybackState()
        pausedPosition = 0.0
    }

    fun pausePlayback() {
        if (!isPlaying) return
        pausedPosition = currentPosition
        isPaused = true
        isPlaying = false
    }

    fun resumePlayback() {
        if (!isPaused) {
            startPlayback()
            return
        }
        if (loopLength <= 0) {
            recalculateLoopLength()
            if (loopLength <= 0) return
        }

        isPlaying = true
        isPaused = false

        playStartTime = System.nanoTime() - (pausedPosition * 1_000_000_000.0).toLong()
        lastTickPosition = pausedPosition
        currentLoopCycle = 0
        dispatchedThisCycle.clear()

        val secondsPerBeat = 60.0 / bpm
        currentBeat = (pausedPosition / secondsPerBeat).toInt()
    }

    fun togglePlayback() {
        if (isPlaying) stopPlayback() else startPlayback()
    }

    fun seekTo(position: Double) {
        val clampedPosition = max(0.0, min(position, loopLength))

        currentPosition = clampedPosition
        pausedPosition = clampedPosition

        val secondsPerBeat = 60.0 / bpm
        currentBeat = (clampedPosition / secondsPerBeat).toInt()

        dispatchedThisCycle.clear()
        lastTickPosition = clampedPosition

        if (isPlaying) {
            playStartTime = System.nanoTime() - (clampedPosition * 1_000_000_000.0).toLong()
        }
    }

    // MARK: - Synchronized Position

    /** Current playback position for UI synchronization */
    val synchronizedPlaybackPosition: Double
        get() {
            if (!isPlaying) {
                return if (isPaused) pausedPosition else 0.0
            }
            if (loopLength <= 0) return 0.0
            val now = System.nanoTime()
            val elapsed = (now - playStartTime) / 1_000_000_000.0
            return elapsed.mod(loopLength)
        }

    /** Current playback fraction (0.0 to 1.0) */
    val synchronizedPlaybackFraction: Double
        get() {
            if (loopLength <= 0) return 0.0
            return synchronizedPlaybackPosition / loopLength
        }

    // MARK: - Track Management

    fun deleteTrack(track: Track) {
        _tracks.removeAll { it.id == track.id }
    }

    fun toggleMute(track: Track) {
        val index = _tracks.indexOfFirst { it.id == track.id }
        if (index >= 0) {
            _tracks[index] = _tracks[index].copy(isMuted = !_tracks[index].isMuted)
        }
    }

    fun toggleSolo(track: Track) {
        val index = _tracks.indexOfFirst { it.id == track.id }
        if (index >= 0) {
            _tracks[index] = _tracks[index].copy(isSolo = !_tracks[index].isSolo)
        }
    }

    fun toggleLoop(track: Track) {
        val index = _tracks.indexOfFirst { it.id == track.id }
        if (index >= 0) {
            _tracks[index] = _tracks[index].copy(isLooping = !_tracks[index].isLooping)
        }
    }

    fun setTrackSolo(trackId: String, solo: Boolean) {
        val index = _tracks.indexOfFirst { it.id == trackId }
        if (index >= 0) {
            _tracks[index] = _tracks[index].copy(isSolo = solo)
        }
    }

    fun clearAllTracks() {
        stopPlayback()
        _tracks.clear()
    }

    fun undoLastTrack() {
        if (_tracks.isNotEmpty()) _tracks.removeLast()
    }

    fun setTrackVolume(trackId: String, volume: Float) {
        val index = _tracks.indexOfFirst { it.id == trackId }
        if (index >= 0) {
            _tracks[index] = _tracks[index].copy(volume = max(0f, min(1f, volume)))
        }
    }

    fun setTrackInstrument(trackId: String, instrument: Instrument) {
        val index = _tracks.indexOfFirst { it.id == trackId }
        if (index >= 0) {
            _tracks[index] = _tracks[index].copy(
                instrumentName = instrument.displayName,
                instrumentProgram = instrument.programNumber
            )
        }
    }

    fun loadTracks(newTracks: List<Track>) {
        _tracks.clear()
        _tracks.addAll(newTracks)
    }

    fun addAudioTrack(track: Track) {
        _tracks.add(track)
    }

    fun updateTrack(track: Track) {
        val index = _tracks.indexOfFirst { it.id == track.id }
        if (index >= 0) {
            _tracks[index] = track
        }
    }

    fun track(withId: String): Track? {
        return _tracks.firstOrNull { it.id == withId }
    }

    fun quantizeTrack(trackId: String, division: QuantizeDivision) {
        val index = _tracks.indexOfFirst { it.id == trackId }
        if (index < 0) return
        val q = Quantizer(bpm = bpm, division = division)
        _tracks[index] = _tracks[index].copy(notes = q.quantize(_tracks[index].notes, loopLengthBeats))
    }

    // MARK: - Tick (called from playback timer)

    fun tick() {
        if (!isPlaying || loopLength <= 0) return

        val now = System.nanoTime()
        val elapsed = (now - playStartTime) / 1_000_000_000.0
        val currentPos = elapsed.mod(loopLength)
        val newCycle = (elapsed / loopLength).toInt()

        val secondsPerBeat = 60.0 / bpm
        val currentBeatPos = currentPos / secondsPerBeat
        val lastBeatPos = lastTickPosition / secondsPerBeat

        currentPosition = currentPos

        val newBeat = currentBeatPos.toInt()
        if (newBeat != currentBeat) {
            val isDownbeat = (newBeat % 4) == 0
            currentBeat = newBeat
            onBeat?.invoke(newBeat, isDownbeat)
        }

        if (newCycle > currentLoopCycle) {
            currentLoopCycle = newCycle
            dispatchedThisCycle.clear()
            lastTickPosition = 0.0
        }

        // Auto-stop recording based on recording loop length
        if (isRecording) {
            val recordingElapsed = (now - recordStartTime) / 1_000_000_000.0
            val recordingLoopSeconds = recordingLoopLengthBeats * secondsPerBeat
            val progress = min(1.0, recordingElapsed / recordingLoopSeconds)
            if (progress != recordingProgress) {
                recordingProgress = progress
            }
            if (recordingElapsed >= recordingLoopSeconds) {
                stopRecording()
                onRecordingAutoStop?.invoke()
            }
        }

        val soloActive = anyTrackSoloed

        for (track in _tracks) {
            val isAudible = track.isAudible(soloActive)
            if (track.isVocal) continue

            val trackLength = track.recordedLengthBeats
            if (trackLength <= 0) continue

            val trackCycle = (currentBeatPos / trackLength).toInt()
            if (!track.isLooping && trackCycle > 0) continue

            val trackBeatPos = currentBeatPos.mod(trackLength)
            val trackLastBeatPos = lastBeatPos.mod(trackLength)
            val didTrackWrap = trackBeatPos < trackLastBeatPos

            for (note in track.notes) {
                val noteKey = "${track.id}-${note.id}-c$trackCycle"

                val shouldTriggerOn = if (didTrackWrap) {
                    (note.startBeat in 0.0..<trackBeatPos) ||
                            (note.startBeat >= trackLastBeatPos && note.startBeat < trackLength)
                } else {
                    note.startBeat >= trackLastBeatPos && note.startBeat < trackBeatPos
                }

                if (shouldTriggerOn && !dispatchedThisCycle.contains("$noteKey-on") && isAudible) {
                    dispatchedThisCycle.add("$noteKey-on")
                    val noteOnEvent = MidiEvent(
                        time = note.startBeat * secondsPerBeat,
                        note = note.pitch,
                        velocity = note.velocity,
                        isNoteOn = true,
                        isLeft = false
                    )
                    onPlayEvent?.invoke(noteOnEvent, track)
                }

                val shouldTriggerOff = if (didTrackWrap) {
                    (note.endBeat in 0.0..<trackBeatPos) ||
                            (note.endBeat >= trackLastBeatPos && note.endBeat < trackLength)
                } else {
                    note.endBeat >= trackLastBeatPos && note.endBeat < trackBeatPos
                }

                if (shouldTriggerOff && !dispatchedThisCycle.contains("$noteKey-off")) {
                    dispatchedThisCycle.add("$noteKey-off")
                    val noteOffEvent = MidiEvent(
                        time = note.endBeat * secondsPerBeat,
                        note = note.pitch,
                        velocity = 0u,
                        isNoteOn = false,
                        isLeft = false
                    )
                    onPlayEvent?.invoke(noteOffEvent, track)
                }
            }
        }

        lastTickPosition = currentPos
    }

    // MARK: - Private

    private fun resetPlaybackState() {
        lastTickPosition = 0.0
        currentLoopCycle = 0
        currentPosition = 0.0
        currentBeat = 0
        dispatchedThisCycle.clear()
    }
}
