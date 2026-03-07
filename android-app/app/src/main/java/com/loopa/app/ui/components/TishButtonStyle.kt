package com.loopa.app.ui.components

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.loopa.app.ui.theme.TishColors
import com.loopa.app.ui.theme.TishRadius
import com.loopa.app.ui.theme.TishSpacing
import com.loopa.app.ui.theme.TishTypography

/**
 * Standard Loopa button — ported from iOS TishButtonStyle
 */
@Composable
fun TishButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    isActive: Boolean = false,
    color: Color = TishColors.accent
) {
    val interactionSource = remember { MutableInteractionSource() }
    val isPressed by interactionSource.collectIsPressedAsState()
    val scale by animateFloatAsState(if (isPressed) 0.95f else 1.0f, label = "scale")

    val shape = RoundedCornerShape(TishRadius.md)

    Box(
        modifier = modifier
            .scale(scale)
            .clip(shape)
            .background(if (isActive) color else TishColors.surface)
            .border(
                width = 1.dp,
                color = if (isActive) Color.Transparent else color.copy(alpha = 0.5f),
                shape = shape
            )
            .clickable(interactionSource = interactionSource, indication = null, onClick = onClick)
            .padding(horizontal = TishSpacing.lg, vertical = TishSpacing.sm),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = text,
            style = TishTypography.headline,
            color = if (isActive) TishColors.background else TishColors.textPrimary
        )
    }
}

/**
 * Transport button (circular) — ported from iOS TishTransportButtonStyle
 */
@Composable
fun TishTransportButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    isActive: Boolean = false,
    activeColor: Color = TishColors.accent,
    content: @Composable () -> Unit
) {
    val interactionSource = remember { MutableInteractionSource() }
    val isPressed by interactionSource.collectIsPressedAsState()
    val scale by animateFloatAsState(if (isPressed) 0.9f else 1.0f, label = "scale")

    val glowModifier = if (isActive) {
        Modifier.shadow(6.dp, CircleShape, ambientColor = activeColor.copy(alpha = 0.5f))
    } else {
        Modifier
    }

    Box(
        modifier = modifier
            .scale(scale)
            .then(glowModifier)
            .clip(CircleShape)
            .background(if (isActive) activeColor.copy(alpha = 0.2f) else TishColors.surface)
            .border(
                width = 1.dp,
                color = if (isActive) activeColor else TishColors.keyBorder,
                shape = CircleShape
            )
            .clickable(interactionSource = interactionSource, indication = null, onClick = onClick)
            .padding(TishSpacing.sm),
        contentAlignment = Alignment.Center
    ) {
        content()
    }
}
