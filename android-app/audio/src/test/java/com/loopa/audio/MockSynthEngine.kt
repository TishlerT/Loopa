package com.loopa.audio

/**
 * Mock SynthEngine for JVM testing.
 * Records all calls so tests can verify routing behavior.
 */
class MockSynthEngine : SynthEngine {
    private var _isReady = false
    override val isReady: Boolean get() = _isReady

    val noteOns = mutableListOf<Triple<Int, Int, Int>>() // (channel, note, velocity)
    val noteOffs = mutableListOf<Pair<Int, Int>>() // (channel, note)
    val programChanges = mutableListOf<Pair<Int, Int>>() // (channel, program)
    var allNotesOffCalled = false
    var soundFontPath: String? = null

    override fun initialize(): Boolean {
        _isReady = true
        return true
    }

    override fun loadSoundFont(path: String): Boolean {
        soundFontPath = path
        return _isReady
    }

    override fun noteOn(channel: Int, note: Int, velocity: Int) {
        noteOns.add(Triple(channel, note, velocity))
    }

    override fun noteOff(channel: Int, note: Int) {
        noteOffs.add(Pair(channel, note))
    }

    override fun programChange(channel: Int, program: Int) {
        programChanges.add(Pair(channel, program))
    }

    override fun allNotesOff() {
        allNotesOffCalled = true
    }

    override fun release() {
        _isReady = false
    }

    fun reset() {
        noteOns.clear()
        noteOffs.clear()
        programChanges.clear()
        allNotesOffCalled = false
        soundFontPath = null
    }
}
