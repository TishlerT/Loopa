package com.loopa.feature.looper.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.unit.dp
import com.loopa.app.ui.theme.TishColors
import com.loopa.app.ui.theme.TishTypography

/**
 * Animated vocal-mode waveform visualization.
 * Ported from iOS VocalWaveformView.swift.
 */
@Composable
fun VocalWaveformView(
    isRecording: Boolean,
    inputLevel: Float,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .fillMaxSize()
            .background(TishColors.background),
        contentAlignment = Alignment.Center
    ) {
        // Waveform canvas
        Canvas(modifier = Modifier.fillMaxSize().padding(16.dp)) {
            val centerY = size.height / 2
            val width = size.width
            val barCount = 40
            val barWidth = width / barCount

            for (i in 0 until barCount) {
                val x = i * barWidth + barWidth / 2
                val amplitude = if (isRecording) {
                    inputLevel * (0.3f + 0.7f * kotlin.math.abs(kotlin.math.sin((i * 0.3f) + inputLevel * 10)))
                } else {
                    0.05f
                }
                val barHeight = amplitude * size.height * 0.4f

                drawLine(
                    color = if (isRecording) TishColors.accent else TishColors.textTertiary,
                    start = Offset(x, centerY - barHeight),
                    end = Offset(x, centerY + barHeight),
                    strokeWidth = barWidth * 0.6f,
                    cap = StrokeCap.Round
                )
            }

            // Center line
            drawLine(
                color = if (isRecording) TishColors.accent.copy(alpha = 0.5f) else TishColors.textTertiary.copy(alpha = 0.3f),
                start = Offset(0f, centerY),
                end = Offset(width, centerY),
                strokeWidth = 1f
            )
        }

        // Mic icon / status
        if (!isRecording) {
            Text(
                text = "🎤",
                style = TishTypography.largeTitle,
                color = TishColors.textSecondary
            )
        }
    }
}
