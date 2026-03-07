package com.loopa.feature.tracks.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.loopa.app.ui.theme.TishColors
import com.loopa.app.ui.theme.TishRadius
import com.loopa.app.ui.theme.TishSpacing
import com.loopa.app.ui.theme.TishTypography
import com.loopa.core.model.Track

@Composable
fun TrackMixerRow(
    track: Track,
    index: Int,
    anyTrackSoloed: Boolean,
    onMute: () -> Unit,
    onSolo: () -> Unit,
    onLoop: () -> Unit,
    onDelete: () -> Unit,
    onVolumeChange: (Float) -> Unit,
    onQuantize: () -> Unit,
    onInstrumentChange: () -> Unit,
    onTap: () -> Unit,
    modifier: Modifier = Modifier
) {
    val isAudible = track.isAudible(anyTrackSoloed)
    val alphaValue = if (isAudible) 1f else 0.4f

    Row(
        modifier = modifier
            .fillMaxWidth()
            .alpha(alphaValue)
            .clip(RoundedCornerShape(TishRadius.md))
            .background(TishColors.surface)
            .clickable(onClick = onTap)
            .padding(TishSpacing.sm),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(TishSpacing.sm)
    ) {
        // Delete
        Box(
            modifier = Modifier
                .clip(RoundedCornerShape(TishRadius.sm))
                .background(TishColors.recording.copy(alpha = 0.2f))
                .clickable(onClick = onDelete)
                .padding(TishSpacing.xs)
                .testTag("deleteButton_${track.id}")
        ) {
            Text("✕", style = TishTypography.caption, color = TishColors.recording)
        }

        // Track info
        Column(modifier = Modifier.width(60.dp)) {
            Text(
                text = "${index + 1}. ${track.instrumentName}",
                style = TishTypography.caption,
                color = TishColors.textPrimary,
                maxLines = 1
            )
        }

        // Mute
        MixerButton(
            text = "M",
            isActive = track.isMuted,
            activeColor = TishColors.accentTertiary,
            onClick = onMute,
            modifier = Modifier.testTag("muteButton_${track.id}")
        )

        // Solo
        MixerButton(
            text = "S",
            isActive = track.isSolo,
            activeColor = TishColors.accent,
            onClick = onSolo,
            modifier = Modifier.testTag("soloButton_${track.id}")
        )

        // Quantize (MIDI only)
        if (!track.isVocal) {
            MixerButton(
                text = "Q",
                isActive = false,
                activeColor = TishColors.accent,
                onClick = onQuantize,
                modifier = Modifier.testTag("quantizeButton_${track.id}")
            )
        }

        // Loop
        MixerButton(
            text = "L",
            isActive = track.isLooping,
            activeColor = TishColors.playing,
            onClick = onLoop,
            modifier = Modifier.testTag("loopButton_${track.id}")
        )

        // Volume
        Slider(
            value = track.volume,
            onValueChange = onVolumeChange,
            modifier = Modifier
                .weight(1f)
                .testTag("volumeSlider_${track.id}"),
            colors = SliderDefaults.colors(
                thumbColor = TishColors.accent,
                activeTrackColor = TishColors.accent
            )
        )

        // Instrument button (non-drum MIDI only)
        if (!track.isVocal && !track.isDrumKit) {
            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(TishRadius.sm))
                    .background(TishColors.elevated)
                    .clickable(onClick = onInstrumentChange)
                    .padding(horizontal = TishSpacing.sm, vertical = TishSpacing.xs)
                    .testTag("instrumentButton_${track.id}")
            ) {
                Text(track.instrumentName, style = TishTypography.caption, color = TishColors.textSecondary)
            }
        }
    }
}

@Composable
private fun MixerButton(
    text: String,
    isActive: Boolean,
    activeColor: androidx.compose.ui.graphics.Color,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(TishRadius.sm))
            .background(if (isActive) activeColor.copy(alpha = 0.3f) else TishColors.elevated)
            .clickable(onClick = onClick)
            .padding(horizontal = TishSpacing.sm, vertical = TishSpacing.xs),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = text,
            style = TishTypography.caption,
            color = if (isActive) activeColor else TishColors.textTertiary
        )
    }
}
