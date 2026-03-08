package com.loopa.feature.editor.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.loopa.app.ui.theme.TishColors
import com.loopa.app.ui.theme.TishTypography
import com.loopa.core.model.MidiNote

private val drumNames = mapOf(
    36 to "Kick", 38 to "Snare", 42 to "HiHat", 46 to "Open HH",
    39 to "Clap", 41 to "Tom1", 43 to "Tom2", 37 to "Rim",
    49 to "Crash", 51 to "Ride", 44 to "Pedal", 56 to "Bell"
)

@Composable
fun DrumGridView(
    notes: List<MidiNote>,
    loopLengthBeats: Double,
    currentBeat: Double,
    hideEmptyRows: Boolean,
    onToggleNote: (Int, Double) -> Unit,
    modifier: Modifier = Modifier
) {
    val stepsPerBeat = 4 // 16th notes
    val totalSteps = (loopLengthBeats * stepsPerBeat).toInt()
    val stepDuration = 1.0 / stepsPerBeat

    val activePitches = if (hideEmptyRows) {
        notes.map { it.pitch.toInt() }.distinct().sorted()
    } else {
        drumNames.keys.sorted()
    }

    Column(modifier = modifier.fillMaxSize().background(TishColors.background)) {
        // Header with step numbers
        Row(modifier = Modifier.fillMaxWidth().padding(start = 50.dp)) {
            for (step in 0 until totalSteps.coerceAtMost(64)) {
                val isCurrentStep = (currentBeat / stepDuration).toInt() == step
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .height(16.dp)
                        .background(if (isCurrentStep) TishColors.accent.copy(alpha = 0.3f) else TishColors.background),
                    contentAlignment = Alignment.Center
                ) {
                    if (step % stepsPerBeat == 0) {
                        Text("${step / stepsPerBeat + 1}", style = TishTypography.caption, color = TishColors.textTertiary)
                    }
                }
            }
        }

        // Grid rows
        LazyColumn(modifier = Modifier.weight(1f)) {
            items(activePitches) { pitch ->
                DrumGridRow(
                    pitch = pitch,
                    label = drumNames[pitch] ?: "P$pitch",
                    notes = notes.filter { it.pitch.toInt() == pitch },
                    totalSteps = totalSteps.coerceAtMost(64),
                    stepDuration = stepDuration,
                    currentBeat = currentBeat,
                    onToggle = { step -> onToggleNote(pitch, step * stepDuration) }
                )
            }
        }
    }
}

@Composable
private fun DrumGridRow(
    pitch: Int,
    label: String,
    notes: List<MidiNote>,
    totalSteps: Int,
    stepDuration: Double,
    currentBeat: Double,
    onToggle: (Int) -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth().height(36.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = label,
            style = TishTypography.caption,
            color = TishColors.textSecondary,
            modifier = Modifier.width(50.dp).padding(start = 4.dp)
        )

        for (step in 0 until totalSteps) {
            val stepBeat = step * stepDuration
            val tolerance = stepDuration / 2
            val hasNote = notes.any { kotlin.math.abs(it.startBeat - stepBeat) < tolerance }
            val isCurrentStep = (currentBeat / stepDuration).toInt() == step

            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxHeight()
                    .padding(1.dp)
                    .background(
                        when {
                            hasNote && isCurrentStep -> TishColors.accent
                            hasNote -> TishColors.neonMint.copy(alpha = 0.7f)
                            isCurrentStep -> TishColors.accent.copy(alpha = 0.15f)
                            step % 4 == 0 -> TishColors.elevated
                            else -> TishColors.surface
                        }
                    )
                    .border(0.5.dp, TishColors.keyBorder.copy(alpha = 0.3f))
                    .clickable { onToggle(step) }
            )
        }
    }
}
