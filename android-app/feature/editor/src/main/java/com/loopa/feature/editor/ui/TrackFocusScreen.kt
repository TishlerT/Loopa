package com.loopa.feature.editor.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.loopa.app.ui.components.TishButton
import com.loopa.app.ui.theme.TishColors
import com.loopa.app.ui.theme.TishSpacing
import com.loopa.app.ui.theme.TishTypography
import com.loopa.feature.editor.TrackFocusViewModel

@Composable
fun TrackFocusScreen(
    viewModel: TrackFocusViewModel,
    onClose: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier.fillMaxSize().background(TishColors.background)
    ) {
        // Toolbar
        Row(
            modifier = Modifier.fillMaxWidth().padding(TishSpacing.sm),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            TishButton(text = "Close", onClick = onClose)
            Text(
                text = viewModel.track.instrumentName,
                style = TishTypography.title,
                color = TishColors.textPrimary
            )
            Text(
                text = "Beat: ${viewModel.currentBeat.toInt()}",
                style = TishTypography.mono,
                color = TishColors.textSecondary
            )
        }

        // Editor toolbar
        EditorToolbar(viewModel)

        // Main editor area
        Box(modifier = Modifier.weight(1f).fillMaxWidth()) {
            if (viewModel.track.isDrumKit) {
                DrumGridView(
                    notes = viewModel.track.notes,
                    loopLengthBeats = viewModel.loopLengthBeats,
                    currentBeat = viewModel.currentBeat,
                    hideEmptyRows = viewModel.hideEmptyDrumRows,
                    onToggleNote = { pitch, beat ->
                        val existing = viewModel.track.notes.firstOrNull {
                            it.pitch.toInt() == pitch && kotlin.math.abs(it.startBeat - beat) < 0.125
                        }
                        if (existing != null) {
                            viewModel.deleteNote(existing.id)
                        } else {
                            viewModel.addNote(pitch.toUByte(), beat, 0.25)
                        }
                    }
                )
            } else {
                PianoRollCanvasView(
                    notes = viewModel.track.notes,
                    loopLengthBeats = viewModel.loopLengthBeats,
                    pitchRangeMin = viewModel.pitchRangeMin,
                    pitchRangeMax = viewModel.pitchRangeMax,
                    currentBeat = viewModel.currentBeat,
                    selectedNoteId = viewModel.selectedNoteId,
                    isPlaying = viewModel.isPlaying,
                    zoomLevel = viewModel.zoomLevel,
                    verticalZoomLevel = viewModel.verticalZoomLevel,
                    onNoteTap = { viewModel.selectNote(it) },
                    onEmptyTap = { beat, pitch ->
                        if (viewModel.isAddNoteMode) {
                            viewModel.addNote(pitch, beat, viewModel.lastNoteDuration)
                        }
                    }
                )
            }
        }
    }
}

@Composable
private fun EditorToolbar(viewModel: TrackFocusViewModel) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = TishSpacing.sm, vertical = TishSpacing.xs),
        horizontalArrangement = Arrangement.spacedBy(TishSpacing.xs)
    ) {
        TishButton(text = if (viewModel.isMultiSelectMode) "✓ Multi" else "Multi",
            onClick = { viewModel.toggleMultiSelectMode() },
            isActive = viewModel.isMultiSelectMode)

        TishButton(text = "+", onClick = { viewModel.isAddNoteMode = !viewModel.isAddNoteMode },
            isActive = viewModel.isAddNoteMode)

        TishButton(text = "✕", onClick = { viewModel.isDeleteMode = !viewModel.isDeleteMode },
            isActive = viewModel.isDeleteMode)

        if (viewModel.canCopy) {
            TishButton(text = "Copy", onClick = { viewModel.copySelectedNotes() })
        }
        if (viewModel.canPaste) {
            TishButton(text = "Paste", onClick = { viewModel.pasteNotes() })
        }
        if (viewModel.canUndo) {
            TishButton(text = "Undo", onClick = { viewModel.undo() })
        }
    }
}
