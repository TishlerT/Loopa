package com.loopa.core.looper

import com.loopa.core.model.MidiEvent
import com.loopa.core.model.Track
import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.io.File
import java.io.FileOutputStream

/**
 * Standard MIDI file exporter — converts tracks to a type-0 .mid file.
 * Ported from iOS MidiExporter.swift.
 */
object MidiExporter {

    private const val TICKS_PER_QUARTER = 480

    /**
     * Export tracks to a standard MIDI file.
     *
     * @param tracks Tracks to export
     * @param bpm Tempo
     * @param loopLengthBeats Total loop length in beats
     * @param outputPath File path for output .mid file
     * @return true if export succeeds
     */
    fun export(
        tracks: List<Track>,
        bpm: Double,
        loopLengthBeats: Double,
        outputPath: String
    ): Boolean {
        val midiTracks = tracks.filter { !it.isVocal && it.notes.isNotEmpty() }
        if (midiTracks.isEmpty()) return false

        try {
            val trackData = buildTrackData(midiTracks, bpm, loopLengthBeats)
            val file = File(outputPath)
            FileOutputStream(file).use { fos ->
                DataOutputStream(fos).use { dos ->
                    // Write header chunk
                    writeHeader(dos, format = 0, numTracks = 1, ticksPerQuarter = TICKS_PER_QUARTER)
                    // Write track chunk
                    writeTrackChunk(dos, trackData)
                }
            }
            return true
        } catch (e: Exception) {
            return false
        }
    }

    private fun buildTrackData(tracks: List<Track>, bpm: Double, loopLengthBeats: Double): ByteArray {
        val baos = ByteArrayOutputStream()
        val dos = DataOutputStream(baos)

        // Tempo meta event
        val microsPerBeat = (60_000_000.0 / bpm).toLong()
        writeVarLen(dos, 0) // delta = 0
        dos.writeByte(0xFF)
        dos.writeByte(0x51)
        dos.writeByte(0x03)
        dos.writeByte(((microsPerBeat shr 16) and 0xFF).toInt())
        dos.writeByte(((microsPerBeat shr 8) and 0xFF).toInt())
        dos.writeByte((microsPerBeat and 0xFF).toInt())

        // Collect all events across tracks and convert to tick-based
        data class TickEvent(val tick: Long, val channel: Int, val isNoteOn: Boolean, val note: Int, val velocity: Int)

        val allEvents = mutableListOf<TickEvent>()
        for ((channelIndex, track) in tracks.withIndex()) {
            val channel = if (track.isDrumKit) 9 else channelIndex.coerceAtMost(14)
            for (note in track.notes) {
                val onTick = (note.startBeat * TICKS_PER_QUARTER).toLong()
                val offTick = (note.endBeat * TICKS_PER_QUARTER).toLong()
                allEvents.add(TickEvent(onTick, channel, true, note.pitch.toInt(), note.velocity.toInt()))
                allEvents.add(TickEvent(offTick, channel, false, note.pitch.toInt(), 0))
            }
        }

        // Sort by tick
        allEvents.sortBy { it.tick }

        // Write events with delta times
        var lastTick = 0L
        for (event in allEvents) {
            val delta = event.tick - lastTick
            writeVarLen(dos, delta.coerceAtLeast(0))
            lastTick = event.tick

            val status = if (event.isNoteOn) 0x90 else 0x80
            dos.writeByte(status or event.channel)
            dos.writeByte(event.note)
            dos.writeByte(event.velocity)
        }

        // End of track
        writeVarLen(dos, 0)
        dos.writeByte(0xFF)
        dos.writeByte(0x2F)
        dos.writeByte(0x00)

        return baos.toByteArray()
    }

    private fun writeHeader(dos: DataOutputStream, format: Int, numTracks: Int, ticksPerQuarter: Int) {
        // MThd
        dos.writeByte('M'.code)
        dos.writeByte('T'.code)
        dos.writeByte('h'.code)
        dos.writeByte('d'.code)
        dos.writeInt(6) // Header length
        dos.writeShort(format)
        dos.writeShort(numTracks)
        dos.writeShort(ticksPerQuarter)
    }

    private fun writeTrackChunk(dos: DataOutputStream, trackData: ByteArray) {
        // MTrk
        dos.writeByte('M'.code)
        dos.writeByte('T'.code)
        dos.writeByte('r'.code)
        dos.writeByte('k'.code)
        dos.writeInt(trackData.size)
        dos.write(trackData)
    }

    private fun writeVarLen(dos: DataOutputStream, value: Long) {
        var v = value
        var buffer = v and 0x7F
        v = v shr 7
        while (v > 0) {
            buffer = buffer shl 8
            buffer = buffer or ((v and 0x7F) or 0x80)
            v = v shr 7
        }
        while (true) {
            dos.writeByte((buffer and 0xFF).toInt())
            if (buffer and 0x80L != 0L) {
                buffer = buffer shr 8
            } else {
                break
            }
        }
    }
}
