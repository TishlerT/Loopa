package com.loopa.feature.editor.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import com.loopa.app.ui.theme.TishColors
import com.loopa.core.model.MidiNote

@Composable
fun PianoRollCanvasView(
    notes: List<MidiNote>,
    loopLengthBeats: Double,
    pitchRangeMin: UByte,
    pitchRangeMax: UByte,
    currentBeat: Double,
    selectedNoteId: String?,
    isPlaying: Boolean,
    zoomLevel: Float,
    verticalZoomLevel: Float,
    onNoteTap: (String) -> Unit,
    onEmptyTap: (Double, UByte) -> Unit,
    modifier: Modifier = Modifier
) {
    val pitchRange = (pitchRangeMax.toInt() - pitchRangeMin.toInt()).coerceAtLeast(12)
    val paddedMin = (pitchRangeMin.toInt() - 2).coerceAtLeast(0)
    val paddedMax = (pitchRangeMax.toInt() + 2).coerceAtMost(127)
    val totalPitches = paddedMax - paddedMin + 1

    Canvas(
        modifier = modifier
            .fillMaxSize()
            .background(TishColors.deepNavy)
            .pointerInput(notes, loopLengthBeats) {
                detectTapGestures { offset ->
                    val beatWidth = size.width / (loopLengthBeats * zoomLevel).toFloat()
                    val rowHeight = size.height / (totalPitches * verticalZoomLevel)
                    val tappedBeat = offset.x / beatWidth
                    val tappedPitch = paddedMax - (offset.y / rowHeight).toInt()

                    val tappedNote = notes.firstOrNull { note ->
                        tappedBeat >= note.startBeat && tappedBeat <= note.endBeat &&
                                note.pitch.toInt() == tappedPitch
                    }
                    if (tappedNote != null) {
                        onNoteTap(tappedNote.id)
                    } else {
                        onEmptyTap(tappedBeat, tappedPitch.coerceIn(0, 127).toUByte())
                    }
                }
            }
    ) {
        val beatWidth = size.width / (loopLengthBeats * zoomLevel).toFloat()
        val rowHeight = size.height / (totalPitches * verticalZoomLevel)

        // Draw grid lines
        for (beat in 0..loopLengthBeats.toInt()) {
            val x = beat * beatWidth
            val isBar = beat % 4 == 0
            drawLine(
                color = if (isBar) TishColors.textTertiary.copy(alpha = 0.5f) else TishColors.textTertiary.copy(alpha = 0.2f),
                start = Offset(x, 0f),
                end = Offset(x, size.height),
                strokeWidth = if (isBar) 2f else 1f
            )
        }

        // Draw horizontal pitch lines
        for (i in 0..totalPitches) {
            val y = i * rowHeight
            drawLine(
                color = TishColors.textTertiary.copy(alpha = 0.1f),
                start = Offset(0f, y),
                end = Offset(size.width, y)
            )
        }

        // Draw notes
        for (note in notes) {
            val x = (note.startBeat * beatWidth).toFloat()
            val width = (note.durationBeats * beatWidth).toFloat()
            val pitchIndex = paddedMax - note.pitch.toInt()
            val y = pitchIndex * rowHeight

            val isSelected = note.id == selectedNoteId
            val color = if (isSelected) TishColors.accent else TishColors.neonMint.copy(alpha = 0.8f)

            drawRect(
                color = color,
                topLeft = Offset(x, y),
                size = Size(width.coerceAtLeast(2f), rowHeight * 0.8f)
            )
        }

        // Draw playhead
        if (isPlaying || currentBeat > 0) {
            val playheadX = (currentBeat * beatWidth).toFloat()
            drawLine(
                color = TishColors.accent,
                start = Offset(playheadX, 0f),
                end = Offset(playheadX, size.height),
                strokeWidth = 2f
            )
        }
    }
}
