package com.loopa.feature.looper.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import com.loopa.app.ui.components.TishTransportButton
import com.loopa.app.ui.theme.TishColors
import com.loopa.app.ui.theme.TishTypography
import com.loopa.core.model.QuantizeDivision

/**
 * Transport controls row — record, play/pause, restart, quantize.
 * Ported from iOS LooperView transport section.
 */
@Composable
fun TransportControls(
    isRecording: Boolean,
    isPlaying: Boolean,
    isPaused: Boolean,
    isCountingIn: Boolean,
    countInBeat: Int,
    quantizeDivision: QuantizeDivision,
    hasTracksOrRecording: Boolean,
    onRecord: () -> Unit,
    onPlayPause: () -> Unit,
    onRestart: () -> Unit,
    onQuantize: () -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Record Button
        TishTransportButton(
            onClick = onRecord,
            isActive = isRecording || isCountingIn,
            activeColor = TishColors.recording,
            modifier = Modifier.testTag("recordButton")
        ) {
            if (isCountingIn) {
                Text(
                    text = "$countInBeat",
                    style = TishTypography.headline,
                    color = TishColors.recording
                )
            } else {
                Text(
                    text = "●",
                    style = TishTypography.title,
                    color = if (isRecording) TishColors.recording else TishColors.textSecondary
                )
            }
        }

        // Play/Pause Button
        TishTransportButton(
            onClick = onPlayPause,
            isActive = isPlaying,
            activeColor = if (isPlaying) TishColors.playing else TishColors.accent,
            modifier = Modifier.testTag("playPauseButton")
        ) {
            Text(
                text = if (isPlaying) "⏸" else if (isPaused) "▶" else "▶",
                style = TishTypography.title,
                color = when {
                    isPlaying -> TishColors.playing
                    isPaused -> TishColors.accentTertiary
                    else -> TishColors.textSecondary
                }
            )
        }

        // Restart Button
        TishTransportButton(
            onClick = onRestart,
            isActive = false,
            modifier = Modifier.testTag("restartButton")
        ) {
            Text(
                text = "⏮",
                style = TishTypography.headline,
                color = if (hasTracksOrRecording) TishColors.textPrimary else TishColors.textTertiary
            )
        }

        // Quantize Button
        TishTransportButton(
            onClick = onQuantize,
            isActive = quantizeDivision != QuantizeDivision.OFF,
            activeColor = TishColors.accent,
            modifier = Modifier.testTag("quantizeButton")
        ) {
            Text(
                text = if (quantizeDivision == QuantizeDivision.OFF) "Q" else quantizeDivision.rawValue,
                style = TishTypography.headline,
                color = if (quantizeDivision != QuantizeDivision.OFF) TishColors.accent else TishColors.textSecondary
            )
        }
    }
}
