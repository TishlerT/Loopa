package com.loopa.audio

import android.content.Context
import android.media.MediaRecorder
import java.io.File

/**
 * Vocal recording/playback service.
 * Uses MediaRecorder for mic input and AAC file recording.
 * Mirrors iOS VocalRecorder.
 */
class VocalRecorder(private val context: Context) {

    enum class State {
        IDLE, RECORDING, PLAYING
    }

    var state: State = State.IDLE
        private set

    /** Live input level (0.0-1.0) for waveform display */
    var inputLevel: Float = 0f
        private set

    private var mediaRecorder: MediaRecorder? = null
    private var outputFile: File? = null

    /** Start recording vocals to a file */
    fun startRecording(filename: String): Boolean {
        if (state != State.IDLE) return false
        try {
            val file = File(context.filesDir, filename)
            outputFile = file

            @Suppress("DEPRECATION")
            mediaRecorder = MediaRecorder().apply {
                setAudioSource(MediaRecorder.AudioSource.MIC)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                setAudioSamplingRate(44100)
                setAudioChannels(1)
                setAudioEncodingBitRate(128000)
                setOutputFile(file.absolutePath)
                prepare()
                start()
            }

            state = State.RECORDING
            return true
        } catch (e: Exception) {
            cleanup()
            return false
        }
    }

    /** Stop recording */
    fun stopRecording(): String? {
        if (state != State.RECORDING) return null
        try {
            mediaRecorder?.stop()
        } catch (_: Exception) { }
        cleanup()
        state = State.IDLE
        return outputFile?.name
    }

    /** Delete a vocal recording file */
    fun deleteRecording(filename: String) {
        val file = File(context.filesDir, filename)
        if (file.exists()) file.delete()
    }

    private fun cleanup() {
        mediaRecorder?.release()
        mediaRecorder = null
    }

    /** Release all resources */
    fun release() {
        cleanup()
        state = State.IDLE
    }
}
