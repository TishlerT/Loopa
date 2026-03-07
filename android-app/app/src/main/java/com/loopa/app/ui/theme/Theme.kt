package com.loopa.app.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable

private val LoopaDarkColorScheme = darkColorScheme(
    primary = TishColors.accent,
    secondary = TishColors.accentSecondary,
    tertiary = TishColors.accentTertiary,
    background = TishColors.background,
    surface = TishColors.surface,
    onPrimary = TishColors.background,
    onSecondary = TishColors.background,
    onTertiary = TishColors.background,
    onBackground = TishColors.textPrimary,
    onSurface = TishColors.textPrimary,
    error = TishColors.recording,
    onError = TishColors.textPrimary,
    surfaceVariant = TishColors.elevated,
    onSurfaceVariant = TishColors.textSecondary,
    outline = TishColors.keyBorder
)

@Composable
fun LoopaTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = LoopaDarkColorScheme,
        content = content
    )
}
