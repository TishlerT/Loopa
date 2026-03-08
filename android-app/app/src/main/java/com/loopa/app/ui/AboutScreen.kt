package com.loopa.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.loopa.app.ui.theme.TishColors
import com.loopa.app.ui.theme.TishSpacing
import com.loopa.app.ui.theme.TishTypography

@Composable
fun AboutScreen(
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .background(TishColors.background)
            .padding(TishSpacing.lg)
            .verticalScroll(rememberScrollState()),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(TishSpacing.lg)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.End
        ) {
            Text("Done", style = TishTypography.headline, color = TishColors.accent,
                modifier = Modifier.clickable(onClick = onDismiss))
        }

        Text("L∞PA", style = TishTypography.largeTitle, color = TishColors.accent)
        Text("Version 1.0 (1)", style = TishTypography.caption, color = TishColors.textTertiary)

        Text(
            text = "Loop-based music creation studio",
            style = TishTypography.title,
            color = TishColors.textPrimary
        )

        Column(verticalArrangement = Arrangement.spacedBy(TishSpacing.sm)) {
            FeatureItem("🎹 9 instruments with SoundFont synthesis")
            FeatureItem("🥁 Drum pads with step sequencer")
            FeatureItem("🎤 Vocal recording")
            FeatureItem("📝 Piano roll editor")
            FeatureItem("🔄 Multi-track loop recording")
            FeatureItem("💾 Session save/load/export")
        }

        Spacer(modifier = Modifier.height(TishSpacing.xl))

        Text("Credits", style = TishTypography.headline, color = TishColors.textSecondary)
        Text("Built with ❤️", style = TishTypography.body, color = TishColors.textTertiary)
    }
}

@Composable
private fun FeatureItem(text: String) {
    Text(text = text, style = TishTypography.body, color = TishColors.textSecondary)
}
