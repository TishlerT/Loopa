package com.loopa.audio

/**
 * FluidSynth-based SynthEngine implementation.
 * Uses JNI to interface with the native FluidSynth library.
 *
 * DEFERRED_TO_LOCAL: Actual FluidSynth JNI loading and audio playback
 * requires a device/emulator. This implementation provides the structure
 * that will be completed when a FluidSynth AAR or compiled native lib
 * is integrated.
 */
class FluidSynthEngine : SynthEngine {
    private var _isReady = false

    override val isReady: Boolean get() = _isReady

    override fun initialize(): Boolean {
        // TODO: Initialize FluidSynth settings and synth instance via JNI
        // fluid_settings_new(), fluid_synth_new(), fluid_audio_driver_new()
        _isReady = true
        return true
    }

    override fun loadSoundFont(path: String): Boolean {
        if (!_isReady) return false
        // TODO: fluid_synth_sfload(synth, path, 1)
        return true
    }

    override fun noteOn(channel: Int, note: Int, velocity: Int) {
        if (!_isReady) return
        // TODO: fluid_synth_noteon(synth, channel, note, velocity)
    }

    override fun noteOff(channel: Int, note: Int) {
        if (!_isReady) return
        // TODO: fluid_synth_noteoff(synth, channel, note)
    }

    override fun programChange(channel: Int, program: Int) {
        if (!_isReady) return
        // TODO: fluid_synth_program_change(synth, channel, program)
    }

    override fun allNotesOff() {
        if (!_isReady) return
        // TODO: fluid_synth_all_notes_off on all channels
        for (ch in 0..15) {
            // fluid_synth_all_notes_off(synth, ch)
        }
    }

    override fun release() {
        _isReady = false
        // TODO: delete_fluid_audio_driver, delete_fluid_synth, delete_fluid_settings
    }
}
