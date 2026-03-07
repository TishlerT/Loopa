package com.loopa.feature.looper.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import com.loopa.app.ui.components.TishButton
import com.loopa.app.ui.theme.TishColors
import com.loopa.app.ui.theme.TishRadius
import com.loopa.app.ui.theme.TishSpacing
import com.loopa.app.ui.theme.TishTypography

/**
 * Full-screen tempo editor with +/- 5 BPM controls.
 * Ported from iOS BPMEditorView.swift.
 */
@Composable
fun BPMEditorView(
    currentBpm: Double,
    onBpmChange: (Double) -> Unit,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .fillMaxSize()
            .background(TishColors.background.copy(alpha = 0.95f))
            .clickable(onClick = onDismiss),
        contentAlignment = Alignment.Center
    ) {
        Column(
            modifier = Modifier
                .clip(RoundedCornerShape(TishRadius.xl))
                .background(TishColors.surface)
                .padding(TishSpacing.xxl)
                .clickable(enabled = false) {}, // prevent click-through
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(TishSpacing.lg)
        ) {
            Text(
                text = "BPM",
                style = TishTypography.headline,
                color = TishColors.textSecondary
            )

            Text(
                text = "${currentBpm.toInt()}",
                style = TishTypography.monoLarge,
                color = TishColors.accent
            )

            Row(
                horizontalArrangement = Arrangement.spacedBy(TishSpacing.md)
            ) {
                TishButton(
                    text = "- 5",
                    onClick = { onBpmChange((currentBpm - 5).coerceAtLeast(40.0)) }
                )
                TishButton(
                    text = "+ 5",
                    onClick = { onBpmChange((currentBpm + 5).coerceAtMost(300.0)) }
                )
            }
        }
    }
}
