package com.loopa.app.ui.theme

import androidx.compose.ui.graphics.Color

/**
 * Loopa design system colors — ported from iOS DesignSystem.swift
 * Plus additional inline palette colors from shipped screens.
 */
object TishColors {
    // Background Colors
    val background = Color(0xFF0D0D0D)
    val surface = Color(0xFF1A1A1A)
    val elevated = Color(0xFF242424)

    // Accent Colors
    val accent = Color(0xFF00E5FF)
    val accentSecondary = Color(0xFFFF0080)
    val accentTertiary = Color(0xFFFFB800)

    // Semantic Colors
    val recording = Color(0xFFFF3B3B)
    val playing = Color(0xFF00FF88)
    val overdub = Color(0xFFB366FF)
    val beat = Color(0xFFFFFFFF).copy(alpha = 0.9f)
    val downbeat = Color(0xFF00E5FF)

    // Text Colors
    val textPrimary = Color(0xFFF5F5F5)
    val textSecondary = Color(0xFF9E9E9E)
    val textTertiary = Color(0xFF616161)

    // Keyboard Colors
    val keyWhite = Color(0xFFF8F8F8)
    val keyWhitePressed = Color(0xFF00E5FF).copy(alpha = 0.3f)
    val keyBlack = Color(0xFF1A1A1A)
    val keyBlackPressed = Color(0xFF00E5FF).copy(alpha = 0.5f)
    val keyBorder = Color(0xFF333333)

    // Additional live palette from shipped screens
    val deepNavy = Color(0xFF0D0D1A)
    val darkNavy = Color(0xFF1A1A2E)
    val midNavy = Color(0xFF1A1A30)
    val purpleNavy = Color(0xFF2A2A4A)
    val deepPurple = Color(0xFF3A2A4A)
    val neonMint = Color(0xFF00FFCC)
    val neonBlue = Color(0xFF00CCFF)
    val systemGreen = Color(0xFF34C759)
    val systemOrange = Color(0xFFFF9500)
    val systemRed = Color(0xFFFF3B30)
    val mutedPurple = Color(0xFF4A4A6A)
    val gold = Color(0xFFFFD700)

    // Gradient color lists
    val backgroundGradient = listOf(
        Color(0xFF0D0D0D),
        Color(0xFF141418),
        Color(0xFF0D0D0D)
    )
    val accentGradient = listOf(
        Color(0xFF00E5FF),
        Color(0xFF00B8D4)
    )
    val recordingGradient = listOf(
        Color(0xFFFF3B3B),
        Color(0xFFCC0000)
    )
}
