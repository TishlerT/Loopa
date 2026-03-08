package com.loopa.audio

/**
 * Interface for the SoundFont synthesis engine.
 * Abstracts FluidSynth JNI so that logic tests can use a mock.
 */
interface SynthEngine {
    /** Initialize the engine */
    fun initialize(): Boolean
    /** Load a SoundFont file, returns true on success */
    fun loadSoundFont(path: String): Boolean
    /** Send a note-on event */
    fun noteOn(channel: Int, note: Int, velocity: Int)
    /** Send a note-off event */
    fun noteOff(channel: Int, note: Int)
    /** Change the program (instrument) on a channel */
    fun programChange(channel: Int, program: Int)
    /** Stop all notes on all channels */
    fun allNotesOff()
    /** Release all resources */
    fun release()
    /** Whether the engine is initialized and ready */
    val isReady: Boolean
}
