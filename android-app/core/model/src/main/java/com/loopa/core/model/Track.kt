package com.loopa.core.model

import kotlinx.serialization.Serializable

/**
 * Represents a single recorded track in the looper.
 * Ported from iOS Track.swift.
 */
@Serializable
data class Track(
    val id: String = java.util.UUID.randomUUID().toString(),
    val trackType: TrackType,
    var instrumentName: String,
    var instrumentProgram: UByte,
    val isDrumKit: Boolean,
    var notes: List<MidiNote> = emptyList(),
    val audioFileName: String? = null,
    val recordedAt: Long = System.currentTimeMillis(), // epoch millis for serialization
    var isMuted: Boolean = false,
    var isSolo: Boolean = false,
    var volume: Float = 0.8f,
    var recordedLengthBeats: Double = 16.0,
    var isLooping: Boolean = true
) {
    /** Is this a vocal/audio track? */
    val isVocal: Boolean
        get() = trackType == TrackType.AUDIO

    /** Get the instrument enum for this track (null for vocals) */
    val instrument: Instrument?
        get() = Instrument.fromRawValue(instrumentName)

    /**
     * Determine if this track should be audible based on mute/solo state.
     * Muted tracks are always silent. If any track is soloed, only soloed tracks play.
     */
    fun isAudible(anyTrackSoloed: Boolean): Boolean {
        if (isMuted) return false
        if (anyTrackSoloed) return isSolo
        return true
    }

    companion object {
        /** Create a MIDI instrument track */
        fun midi(
            id: String = java.util.UUID.randomUUID().toString(),
            instrumentName: String,
            instrumentProgram: UByte,
            isDrumKit: Boolean,
            notes: List<MidiNote> = emptyList(),
            recordedAt: Long = System.currentTimeMillis(),
            isMuted: Boolean = false,
            isSolo: Boolean = false,
            volume: Float = 0.8f,
            recordedLengthBeats: Double = 16.0,
            isLooping: Boolean = true
        ): Track = Track(
            id = id,
            trackType = TrackType.MIDI,
            instrumentName = instrumentName,
            instrumentProgram = instrumentProgram,
            isDrumKit = isDrumKit,
            notes = notes,
            audioFileName = null,
            recordedAt = recordedAt,
            isMuted = isMuted,
            isSolo = isSolo,
            volume = volume,
            recordedLengthBeats = recordedLengthBeats,
            isLooping = isLooping
        )

        /** Create an audio (vocal) track */
        fun audio(
            id: String = java.util.UUID.randomUUID().toString(),
            audioFileName: String,
            recordedAt: Long = System.currentTimeMillis(),
            isMuted: Boolean = false,
            isSolo: Boolean = false,
            volume: Float = 0.8f,
            recordedLengthBeats: Double = 16.0,
            isLooping: Boolean = true
        ): Track = Track(
            id = id,
            trackType = TrackType.AUDIO,
            instrumentName = "Vocals",
            instrumentProgram = 0u,
            isDrumKit = false,
            notes = emptyList(),
            audioFileName = audioFileName,
            recordedAt = recordedAt,
            isMuted = isMuted,
            isSolo = isSolo,
            volume = volume,
            recordedLengthBeats = recordedLengthBeats,
            isLooping = isLooping
        )
    }
}
