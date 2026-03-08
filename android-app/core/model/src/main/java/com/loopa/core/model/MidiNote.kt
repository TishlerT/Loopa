package com.loopa.core.model

import kotlinx.serialization.Serializable
import kotlin.math.max
import kotlin.math.min

/**
 * Represents a single MIDI note with beat-based timing.
 * Used for piano roll editing and playback.
 * Ported from iOS MidiNote.swift.
 */
@Serializable
data class MidiNote(
    val id: String = java.util.UUID.randomUUID().toString(),
    /** MIDI note number (0-127, where 60 = middle C) */
    val pitch: UByte,
    /** Note velocity (1-127, higher = louder) */
    val velocity: UByte = 100u,
    /** Start position in beats from loop start */
    val startBeat: Double,
    /** Duration in beats */
    val durationBeats: Double
) {
    /** End beat (computed) */
    val endBeat: Double
        get() = startBeat + durationBeats

    /** Human-readable note name (e.g., "C4", "F#5") */
    val noteName: String
        get() {
            val noteNames = listOf("C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B")
            val octave = pitch.toInt() / 12 - 1
            val name = noteNames[pitch.toInt() % 12]
            return "$name$octave"
        }

    init {
        // Enforce constraints matching iOS: velocity clamped 1-127, startBeat >= 0, durationBeats >= 0.0625
        require(velocity in 1u..127u || velocity == 0.toUByte()) // Allow construction, clamp below
    }

    companion object {
        /** Minimum note duration (1/64 note) */
        const val MIN_DURATION = 0.0625

        /**
         * Create a MidiNote with clamped values matching iOS behavior.
         */
        fun create(
            id: String = java.util.UUID.randomUUID().toString(),
            pitch: UByte,
            velocity: UByte = 100u,
            startBeat: Double,
            durationBeats: Double
        ): MidiNote {
            return MidiNote(
                id = id,
                pitch = pitch,
                velocity = max(1u.toInt(), min(127, velocity.toInt())).toUByte(),
                startBeat = max(0.0, startBeat),
                durationBeats = max(MIN_DURATION, durationBeats)
            )
        }

        /**
         * Convert a pair of note-on/note-off MidiEvents to a MidiNote.
         */
        fun from(noteOn: MidiEvent, noteOff: MidiEvent, bpm: Double): MidiNote? {
            if (!noteOn.isNoteOn || noteOff.isNoteOn || noteOn.note != noteOff.note) {
                return null
            }

            val secondsPerBeat = 60.0 / bpm
            val startBeat = noteOn.time / secondsPerBeat
            val endBeat = noteOff.time / secondsPerBeat
            val duration = max(MIN_DURATION, endBeat - startBeat)

            return create(
                pitch = noteOn.note,
                velocity = noteOn.velocity,
                startBeat = startBeat,
                durationBeats = duration
            )
        }

        /**
         * Convert an array of MidiEvents to MidiNotes by pairing note-on/off events.
         * Ported exactly from iOS MidiNote.fromEvents().
         */
        fun fromEvents(events: List<MidiEvent>, bpm: Double, loopLengthBeats: Double): List<MidiNote> {
            val notes = mutableListOf<MidiNote>()
            val pendingNoteOns = mutableMapOf<UByte, MutableList<MidiEvent>>()

            val secondsPerBeat = 60.0 / bpm

            for (event in events.sortedBy { it.time }) {
                if (event.isNoteOn && event.velocity > 0u) {
                    pendingNoteOns.getOrPut(event.note) { mutableListOf() }.add(event)
                } else {
                    val queue = pendingNoteOns[event.note]
                    if (queue != null && queue.isNotEmpty()) {
                        val noteOn = queue.removeFirst()

                        val startBeat = noteOn.time / secondsPerBeat
                        var endBeat = event.time / secondsPerBeat

                        // Handle wrap-around
                        if (endBeat < startBeat) {
                            endBeat += loopLengthBeats
                        }

                        val duration = max(MIN_DURATION, endBeat - startBeat)

                        notes.add(create(
                            pitch = noteOn.note,
                            velocity = noteOn.velocity,
                            startBeat = startBeat,
                            durationBeats = min(duration, loopLengthBeats - startBeat)
                        ))
                    }
                }
            }

            // Handle remaining note-ons (no matching note-off)
            for ((_, queue) in pendingNoteOns) {
                for (noteOn in queue) {
                    val startBeat = noteOn.time / secondsPerBeat
                    notes.add(create(
                        pitch = noteOn.note,
                        velocity = noteOn.velocity,
                        startBeat = startBeat,
                        durationBeats = min(0.25, loopLengthBeats - startBeat)
                    ))
                }
            }

            return notes.sortedBy { it.startBeat }
        }
    }

    /**
     * Convert this MidiNote back to MidiEvents for playback.
     */
    fun toEvents(bpm: Double): List<MidiEvent> {
        val secondsPerBeat = 60.0 / bpm
        val startTime = startBeat * secondsPerBeat
        val endTime = endBeat * secondsPerBeat

        val noteOn = MidiEvent(
            time = startTime,
            note = pitch,
            velocity = velocity,
            isNoteOn = true,
            isLeft = false
        )

        val noteOff = MidiEvent(
            time = endTime,
            note = pitch,
            velocity = 0u,
            isNoteOn = false,
            isLeft = false
        )

        return listOf(noteOn, noteOff)
    }
}
