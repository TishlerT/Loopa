package com.loopa.app.ui.theme

import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

/**
 * Loopa typography — ported from iOS DesignSystem.swift
 * iOS uses system rounded for titles and monospaced for timing displays.
 */
object TishTypography {
    /** Large title — app name, major headers (iOS: system 28 bold rounded) */
    val largeTitle = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Bold,
        fontSize = 28.sp
    )

    /** Title — section headers (iOS: system 20 semibold rounded) */
    val title = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.SemiBold,
        fontSize = 20.sp
    )

    /** Headline — button labels, important text (iOS: system 16 semibold rounded) */
    val headline = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.SemiBold,
        fontSize = 16.sp
    )

    /** Body — regular text (iOS: system 14 regular default) */
    val body = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Normal,
        fontSize = 14.sp
    )

    /** Caption — secondary information (iOS: system 12 regular default) */
    val caption = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Normal,
        fontSize = 12.sp
    )

    /** Mono — BPM, timing displays (iOS: system 16 medium monospaced) */
    val mono = TextStyle(
        fontFamily = FontFamily.Monospace,
        fontWeight = FontWeight.Medium,
        fontSize = 16.sp
    )

    /** Mono large — big BPM display (iOS: system 24 bold monospaced) */
    val monoLarge = TextStyle(
        fontFamily = FontFamily.Monospace,
        fontWeight = FontWeight.Bold,
        fontSize = 24.sp
    )
}
