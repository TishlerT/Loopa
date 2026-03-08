package com.loopa.app.ui.theme

import org.junit.jupiter.api.Test
import org.junit.jupiter.api.Assertions.*
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Validates that Android design system values match iOS DesignSystem.swift exactly.
 * Color hex values from memory-bank/io-schema.md.
 */
class DesignSystemTest {

    // Helper to check color matches hex (ignoring alpha for non-alpha colors)
    private fun assertColorHex(expected: Long, actual: Color, name: String) {
        val expectedColor = Color(expected)
        assertEquals(expectedColor.red, actual.red, 0.01f, "$name red mismatch")
        assertEquals(expectedColor.green, actual.green, 0.01f, "$name green mismatch")
        assertEquals(expectedColor.blue, actual.blue, 0.01f, "$name blue mismatch")
    }

    // MARK: - Background Colors

    @Test
    fun `tishBackground matches iOS 0D0D0D`() {
        assertColorHex(0xFF0D0D0D, TishColors.background, "background")
    }

    @Test
    fun `tishSurface matches iOS 1A1A1A`() {
        assertColorHex(0xFF1A1A1A, TishColors.surface, "surface")
    }

    @Test
    fun `tishElevated matches iOS 242424`() {
        assertColorHex(0xFF242424, TishColors.elevated, "elevated")
    }

    // MARK: - Accent Colors

    @Test
    fun `tishAccent matches iOS 00E5FF`() {
        assertColorHex(0xFF00E5FF, TishColors.accent, "accent")
    }

    @Test
    fun `tishAccentSecondary matches iOS FF0080`() {
        assertColorHex(0xFFFF0080, TishColors.accentSecondary, "accentSecondary")
    }

    @Test
    fun `tishAccentTertiary matches iOS FFB800`() {
        assertColorHex(0xFFFFB800, TishColors.accentTertiary, "accentTertiary")
    }

    // MARK: - Semantic Colors

    @Test
    fun `tishRecording matches iOS FF3B3B`() {
        assertColorHex(0xFFFF3B3B, TishColors.recording, "recording")
    }

    @Test
    fun `tishPlaying matches iOS 00FF88`() {
        assertColorHex(0xFF00FF88, TishColors.playing, "playing")
    }

    @Test
    fun `tishOverdub matches iOS B366FF`() {
        assertColorHex(0xFFB366FF, TishColors.overdub, "overdub")
    }

    // MARK: - Text Colors

    @Test
    fun `tishTextPrimary matches iOS F5F5F5`() {
        assertColorHex(0xFFF5F5F5, TishColors.textPrimary, "textPrimary")
    }

    @Test
    fun `tishTextSecondary matches iOS 9E9E9E`() {
        assertColorHex(0xFF9E9E9E, TishColors.textSecondary, "textSecondary")
    }

    @Test
    fun `tishTextTertiary matches iOS 616161`() {
        assertColorHex(0xFF616161, TishColors.textTertiary, "textTertiary")
    }

    // MARK: - Keyboard Colors

    @Test
    fun `tishKeyWhite matches iOS F8F8F8`() {
        assertColorHex(0xFFF8F8F8, TishColors.keyWhite, "keyWhite")
    }

    @Test
    fun `tishKeyBlack matches iOS 1A1A1A`() {
        assertColorHex(0xFF1A1A1A, TishColors.keyBlack, "keyBlack")
    }

    @Test
    fun `tishKeyBorder matches iOS 333333`() {
        assertColorHex(0xFF333333, TishColors.keyBorder, "keyBorder")
    }

    // MARK: - Additional Live Palette

    @Test
    fun `inline palette colors match iOS hex values`() {
        assertColorHex(0xFF0D0D1A, TishColors.deepNavy, "deepNavy")
        assertColorHex(0xFF1A1A2E, TishColors.darkNavy, "darkNavy")
        assertColorHex(0xFF1A1A30, TishColors.midNavy, "midNavy")
        assertColorHex(0xFF2A2A4A, TishColors.purpleNavy, "purpleNavy")
        assertColorHex(0xFF3A2A4A, TishColors.deepPurple, "deepPurple")
        assertColorHex(0xFF00FFCC, TishColors.neonMint, "neonMint")
        assertColorHex(0xFF00CCFF, TishColors.neonBlue, "neonBlue")
        assertColorHex(0xFF34C759, TishColors.systemGreen, "systemGreen")
        assertColorHex(0xFFFF9500, TishColors.systemOrange, "systemOrange")
        assertColorHex(0xFFFF3B30, TishColors.systemRed, "systemRed")
        assertColorHex(0xFF4A4A6A, TishColors.mutedPurple, "mutedPurple")
        assertColorHex(0xFFFFD700, TishColors.gold, "gold")
    }

    // MARK: - Spacing

    @Test
    fun `spacing values match iOS TishSpacing`() {
        assertEquals(4.dp, TishSpacing.xs)
        assertEquals(8.dp, TishSpacing.sm)
        assertEquals(12.dp, TishSpacing.md)
        assertEquals(16.dp, TishSpacing.lg)
        assertEquals(24.dp, TishSpacing.xl)
        assertEquals(32.dp, TishSpacing.xxl)
    }

    // MARK: - Radius

    @Test
    fun `radius values match iOS TishRadius`() {
        assertEquals(4.dp, TishRadius.sm)
        assertEquals(8.dp, TishRadius.md)
        assertEquals(12.dp, TishRadius.lg)
        assertEquals(16.dp, TishRadius.xl)
        assertEquals(9999.dp, TishRadius.full)
    }

    // MARK: - Typography

    @Test
    fun `typography sizes match iOS`() {
        assertEquals(28.sp, TishTypography.largeTitle.fontSize)
        assertEquals(20.sp, TishTypography.title.fontSize)
        assertEquals(16.sp, TishTypography.headline.fontSize)
        assertEquals(14.sp, TishTypography.body.fontSize)
        assertEquals(12.sp, TishTypography.caption.fontSize)
        assertEquals(16.sp, TishTypography.mono.fontSize)
        assertEquals(24.sp, TishTypography.monoLarge.fontSize)
    }
}
