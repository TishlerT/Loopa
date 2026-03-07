package com.loopa.audio

import com.loopa.core.model.Instrument

/**
 * Thin SoundFont sampler wrapper that mirrors iOS KeyboardSampler.
 * Routes note events to the correct channel/program on the synth engine.
 */
class KeyboardSampler(private val engine: SynthEngine, private val channel: Int = 0) {

    private var currentProgram: Int = 0
    private var isPercussion: Boolean = false

    /** Load a melodic instrument program */
    fun loadProgram(instrument: Instrument) {
        if (instrument.isDrumKit) {
            loadPercussion()
            return
        }
        isPercussion = false
        currentProgram = instrument.programNumber.toInt()
        engine.programChange(channel, currentProgram)
    }

    /** Switch to percussion mode (channel 9 in General MIDI) */
    fun loadPercussion() {
        isPercussion = true
        // GM percussion is always on channel 9
    }

    /** Play a note */
    fun noteOn(note: Int, velocity: Int) {
        val ch = if (isPercussion) 9 else channel
        engine.noteOn(ch, note, velocity)
    }

    /** Stop a note */
    fun noteOff(note: Int) {
        val ch = if (isPercussion) 9 else channel
        engine.noteOff(ch, note)
    }

    /** Stop all notes */
    fun stopAll() {
        engine.allNotesOff()
    }

    /** Current program number */
    val program: Int get() = currentProgram

    /** Whether this sampler is in percussion mode */
    val percussionMode: Boolean get() = isPercussion
}
