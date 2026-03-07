package com.loopa.core.model

import kotlinx.serialization.Serializable

/**
 * Represents a single MIDI note event in a loop.
 * Ported from iOS MidiEvent.swift.
 */
@Serializable
data class MidiEvent(
    /** Time in seconds from loop start */
    val time: Double,
    /** MIDI note number (0-127) */
    val note: UByte,
    /** Velocity (0-127, 0 typically indicates note off) */
    val velocity: UByte,
    /** Whether this is a note on (true) or note off (false) event */
    val isNoteOn: Boolean,
    /** Which side of the split keyboard (true = left, false = right) */
    val isLeft: Boolean
) {
    /** Unique identifier for deduplication during playback */
    val id: String
        get() = "$time-$note-$isNoteOn-$isLeft"
}
