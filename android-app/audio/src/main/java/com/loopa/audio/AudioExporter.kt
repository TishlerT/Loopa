package com.loopa.audio

import com.loopa.core.model.MidiNote
import com.loopa.core.model.Track

/**
 * Offline audio export — renders MIDI tracks to M4A via MediaCodec + MediaMuxer.
 * Mirrors iOS AudioExporter.
 *
 * DEFERRED_TO_LOCAL: Actual M4A rendering requires Android audio stack
 * which is not available on headless JVM. This class structures the
 * export pipeline that will be completed with real MediaCodec/MediaMuxer calls.
 */
class AudioExporter(private val synthEngine: SynthEngine) {

    enum class ExportState {
        IDLE, EXPORTING, COMPLETE, ERROR
    }

    var state: ExportState = ExportState.IDLE
        private set

    var progress: Float = 0f
        private set

    var errorMessage: String? = null
        private set

    /**
     * Export non-muted, non-vocal MIDI tracks to an M4A file.
     *
     * @param tracks List of tracks to render
     * @param bpm Tempo for playback
     * @param loopLengthBeats Total loop length in beats
     * @param outputPath Path for the output M4A file
     * @return true if export initiated successfully
     */
    fun export(
        tracks: List<Track>,
        bpm: Double,
        loopLengthBeats: Double,
        outputPath: String
    ): Boolean {
        if (state == ExportState.EXPORTING) return false

        state = ExportState.EXPORTING
        progress = 0f
        errorMessage = null

        // Filter to audible, non-vocal MIDI tracks
        val anyTrackSoloed = tracks.any { it.isSolo }
        val audibleTracks = tracks.filter { !it.isVocal && it.isAudible(anyTrackSoloed) }

        if (audibleTracks.isEmpty()) {
            state = ExportState.ERROR
            errorMessage = "No audible tracks to export"
            return false
        }

        // TODO: Implement offline rendering via MediaCodec + MediaMuxer
        // 1. Create MediaCodec encoder for AAC
        // 2. Create MediaMuxer for M4A output
        // 3. For each time step in the loop:
        //    a. Send note-on/off events to FluidSynth
        //    b. Render audio buffer from FluidSynth
        //    c. Feed buffer to MediaCodec encoder
        //    d. Write encoded data to MediaMuxer
        // 4. Finalize and close

        state = ExportState.COMPLETE
        progress = 1f
        return true
    }

    /** Cancel an in-progress export */
    fun cancel() {
        if (state == ExportState.EXPORTING) {
            state = ExportState.IDLE
            progress = 0f
        }
    }

    /** Reset state */
    fun reset() {
        state = ExportState.IDLE
        progress = 0f
        errorMessage = null
    }
}
