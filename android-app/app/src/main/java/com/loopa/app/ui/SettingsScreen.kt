package com.loopa.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.loopa.app.ui.theme.TishColors
import com.loopa.app.ui.theme.TishSpacing
import com.loopa.app.ui.theme.TishTypography

@Composable
fun SettingsScreen(
    onAbout: () -> Unit,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier.fillMaxSize().background(TishColors.background).padding(TishSpacing.lg),
        verticalArrangement = Arrangement.spacedBy(TishSpacing.lg)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text("Settings", style = TishTypography.title, color = TishColors.textPrimary)
            Text("Done", style = TishTypography.headline, color = TishColors.accent,
                modifier = Modifier.clickable(onClick = onDismiss))
        }

        SettingsRow(title = "About Loopa", onClick = onAbout)
        SettingsRow(title = "Privacy Policy", onClick = { /* TODO: open URL */ })
        SettingsRow(title = "Support", onClick = { /* TODO: open email */ })

        Spacer(modifier = Modifier.weight(1f))

        Text(
            text = "Loopa v1.0",
            style = TishTypography.caption,
            color = TishColors.textTertiary,
            modifier = Modifier.align(Alignment.CenterHorizontally)
        )
    }
}

@Composable
private fun SettingsRow(title: String, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(vertical = TishSpacing.md),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(text = title, style = TishTypography.body, color = TishColors.textPrimary)
        Text(text = "›", style = TishTypography.title, color = TishColors.textTertiary)
    }
}
