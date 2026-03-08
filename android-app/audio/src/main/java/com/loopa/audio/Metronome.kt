package com.loopa.audio

import android.os.Handler
import android.os.Looper

/**
 * Metronome with beat-accurate timing callbacks.
 * Uses Handler for scheduling to avoid thread overhead.
 */
class Metronome {

    /** Callback for each beat: (beatNumber: Int, isDownbeat: Boolean) */
    var onBeat: ((Int, Boolean) -> Unit)? = null

    /** BPM (beats per minute) */
    var bpm: Double = 100.0
        set(value) {
            field = value
            intervalMs = (60_000.0 / value).toLong()
        }

    private var intervalMs: Long = 600L // 100 BPM default
    private var isRunning = false
    private var currentBeat = 0
    private var handler: Handler? = null
    private var scheduledRunnable: Runnable? = null

    /** Start the metronome */
    fun start() {
        if (isRunning) return
        isRunning = true
        currentBeat = 0
        handler = Handler(Looper.getMainLooper())
        scheduleTick()
    }

    /** Stop the metronome */
    fun stop() {
        isRunning = false
        scheduledRunnable?.let { handler?.removeCallbacks(it) }
        scheduledRunnable = null
        handler = null
    }

    private fun scheduleTick() {
        if (!isRunning) return
        val runnable = Runnable {
            if (!isRunning) return@Runnable
            val isDownbeat = (currentBeat % 4) == 0
            onBeat?.invoke(currentBeat, isDownbeat)
            currentBeat++
            scheduleTick()
        }
        scheduledRunnable = runnable
        handler?.postDelayed(runnable, if (currentBeat == 0) 0 else intervalMs)
    }

    /** Reset beat counter */
    fun reset() {
        currentBeat = 0
    }

    /** Whether the metronome is currently running */
    val running: Boolean get() = isRunning

    /** Milliseconds per beat at current BPM */
    val beatIntervalMs: Long get() = intervalMs
}
