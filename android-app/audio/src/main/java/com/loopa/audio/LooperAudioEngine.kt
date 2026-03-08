package com.loopa.audio

import com.loopa.core.model.Instrument
import com.loopa.core.model.Track

/**
 * The active audio engine for the shipped looper.
 * Manages the live input sampler, click sampler, and a pool of playback samplers.
 * Mirrors iOS LooperAudioEngine.
 */
class LooperAudioEngine(private val synthEngine: SynthEngine) {

    companion object {
        /** Number of pooled samplers for concurrent track playback */
        const val POOL_SIZE = 16
        /** Channel for the live keyboard input */
        const val LIVE_CHANNEL = 0
        /** Channel for metronome click */
        const val CLICK_CHANNEL = 15
    }

    /** The live performance sampler */
    val liveSampler = KeyboardSampler(synthEngine, LIVE_CHANNEL)

    /** Click sampler for metronome */
    val clickSampler = KeyboardSampler(synthEngine, CLICK_CHANNEL)

    /** Pool of samplers for track playback, channels 1-14 */
    val trackSamplers: List<KeyboardSampler> = (1..POOL_SIZE.coerceAtMost(14)).map {
        KeyboardSampler(synthEngine, it)
    }

    /** Track-to-sampler channel mapping */
    private val trackChannelMap = mutableMapOf<String, Int>()

    /** Start the audio engine */
    fun start(): Boolean {
        val initialized = synthEngine.initialize()
        if (!initialized) return false
        return true
    }

    /** Load the SoundFont */
    fun loadSoundFont(path: String): Boolean {
        return synthEngine.loadSoundFont(path)
    }

    /** Prepare a sampler for a specific track */
    fun prepareTrack(track: Track): KeyboardSampler? {
        val instrument = track.instrument ?: return null
        val channelIndex = trackChannelMap.size
        if (channelIndex >= trackSamplers.size) return null

        val sampler = trackSamplers[channelIndex]
        sampler.loadProgram(instrument)
        trackChannelMap[track.id] = channelIndex
        return sampler
    }

    /** Get the sampler assigned to a track */
    fun samplerForTrack(trackId: String): KeyboardSampler? {
        val index = trackChannelMap[trackId] ?: return null
        return trackSamplers.getOrNull(index)
    }

    /** Set the live instrument */
    fun setLiveInstrument(instrument: Instrument) {
        liveSampler.loadProgram(instrument)
    }

    /** Stop all audio */
    fun stopAll() {
        synthEngine.allNotesOff()
    }

    /** Release all resources */
    fun release() {
        synthEngine.release()
        trackChannelMap.clear()
    }
}
