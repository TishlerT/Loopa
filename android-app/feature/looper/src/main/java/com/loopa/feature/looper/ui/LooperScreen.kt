package com.loopa.feature.looper.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.loopa.app.ui.components.TishButton
import com.loopa.app.ui.theme.TishColors
import com.loopa.app.ui.theme.TishRadius
import com.loopa.app.ui.theme.TishSpacing
import com.loopa.app.ui.theme.TishTypography
import com.loopa.core.model.BarCount
import com.loopa.core.model.Instrument
import com.loopa.feature.looper.LooperViewModel

/**
 * Main looper workstation screen.
 * Ported from iOS LooperView.swift.
 */
@Composable
fun LooperScreen(
    viewModel: LooperViewModel,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .fillMaxSize()
            .background(TishColors.background)
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            // Top Bar
            TopBar(
                bpm = viewModel.bpm,
                barCount = viewModel.barCount,
                isMetronomeOn = viewModel.isMetronomeOn,
                onBpmClick = { viewModel.showingBPMEditor = true },
                onTracksClick = { viewModel.showingTracksSheet = true },
                onSettingsClick = { viewModel.showingSettings = true },
                onMetronomeToggle = { viewModel.isMetronomeOn = !viewModel.isMetronomeOn },
                onBarCountChange = { viewModel.setBarCount(it) }
            )

            // Progress Bar
            LoopProgressBar(
                progressFraction = viewModel.progressFraction,
                totalBeats = viewModel.totalBeats,
                currentBeat = viewModel.currentBeat,
                isRecording = viewModel.isRecording,
                modifier = Modifier.fillMaxWidth().height(24.dp).padding(horizontal = TishSpacing.sm)
            )

            // Instrument Selector
            InstrumentSelector(
                currentInstrument = viewModel.currentInstrument,
                isVocalMode = viewModel.isVocalMode,
                onInstrumentSelect = { viewModel.currentInstrument = it },
                onVocalModeToggle = { viewModel.toggleVocalMode() },
                modifier = Modifier.fillMaxWidth().padding(horizontal = TishSpacing.sm, vertical = TishSpacing.xs)
            )

            // Main content area: Keyboard or Waveform
            Box(modifier = Modifier.weight(1f).fillMaxWidth()) {
                if (viewModel.isVocalMode) {
                    VocalWaveformView(
                        isRecording = viewModel.isRecordingVocals,
                        inputLevel = 0f // TODO: wire to VocalRecorder
                    )
                } else {
                    Column {
                        // Octave controls
                        Row(
                            modifier = Modifier.fillMaxWidth().padding(horizontal = TishSpacing.sm),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            TishButton(text = "◀", onClick = { viewModel.octaveDown() })
                            Text(
                                text = viewModel.currentOctaveName,
                                style = TishTypography.mono,
                                color = TishColors.textSecondary
                            )
                            TishButton(text = "▶", onClick = { viewModel.octaveUp() })
                        }

                        FullKeyboardView(
                            startNote = viewModel.startNote.toInt(),
                            keyCount = viewModel.keyCount,
                            isDrumKit = viewModel.currentInstrument.isDrumKit,
                            onNoteOn = { note, velocity ->
                                // TODO: wire to audio engine
                            },
                            onNoteOff = { note ->
                                // TODO: wire to audio engine
                            },
                            modifier = Modifier.weight(1f)
                        )
                    }
                }
            }

            // Transport Controls
            TransportControls(
                isRecording = viewModel.isRecording,
                isPlaying = viewModel.isPlaying,
                isPaused = viewModel.isPaused,
                isCountingIn = viewModel.isCountingIn,
                countInBeat = viewModel.countInBeat,
                quantizeDivision = viewModel.quantizeDivision,
                hasTracksOrRecording = viewModel.tracks.isNotEmpty() || viewModel.isRecording,
                onRecord = { viewModel.record() },
                onPlayPause = { viewModel.playPause() },
                onRestart = { viewModel.restart() },
                onQuantize = { viewModel.cycleQuantizeDivision() },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(TishSpacing.sm)
                    .wrapContentWidth(Alignment.CenterHorizontally)
            )
        }

        // BPM Editor overlay
        if (viewModel.showingBPMEditor) {
            BPMEditorView(
                currentBpm = viewModel.bpm,
                onBpmChange = { viewModel.setBpm(it) },
                onDismiss = { viewModel.showingBPMEditor = false }
            )
        }
    }
}

@Composable
private fun TopBar(
    bpm: Double,
    barCount: BarCount,
    isMetronomeOn: Boolean,
    onBpmClick: () -> Unit,
    onTracksClick: () -> Unit,
    onSettingsClick: () -> Unit,
    onMetronomeToggle: () -> Unit,
    onBarCountChange: (BarCount) -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = TishSpacing.sm, vertical = TishSpacing.xs),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        // Logo
        Text(
            text = "L∞PA",
            style = TishTypography.title,
            color = TishColors.accent
        )

        Row(
            horizontalArrangement = Arrangement.spacedBy(TishSpacing.sm),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // BPM
            TishButton(
                text = "${bpm.toInt()} BPM",
                onClick = onBpmClick,
                modifier = Modifier.testTag("bpmButton")
            )

            // Tracks
            TishButton(
                text = "TRACKS",
                onClick = onTracksClick,
                modifier = Modifier.testTag("tracksButton")
            )

            // Settings
            TishButton(
                text = "⚙",
                onClick = onSettingsClick,
                modifier = Modifier.testTag("settingsButton")
            )
        }
    }
}

@Composable
private fun LoopProgressBar(
    progressFraction: Double,
    totalBeats: Int,
    currentBeat: Int,
    isRecording: Boolean,
    modifier: Modifier = Modifier
) {
    Box(modifier = modifier.clip(RoundedCornerShape(TishRadius.sm)).background(TishColors.surface)) {
        // Progress fill
        Box(
            modifier = Modifier
                .fillMaxHeight()
                .fillMaxWidth(progressFraction.toFloat().coerceIn(0f, 1f))
                .background(if (isRecording) TishColors.recording.copy(alpha = 0.3f) else TishColors.accent.copy(alpha = 0.2f))
        )
    }
}

@Composable
private fun InstrumentSelector(
    currentInstrument: Instrument,
    isVocalMode: Boolean,
    onInstrumentSelect: (Instrument) -> Unit,
    onVocalModeToggle: () -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Instrument.entries.forEach { instrument ->
            val isSelected = !isVocalMode && currentInstrument == instrument
            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(TishRadius.sm))
                    .background(if (isSelected) TishColors.accent.copy(alpha = 0.2f) else TishColors.surface)
                    .clickable { onInstrumentSelect(instrument) }
                    .padding(horizontal = 8.dp, vertical = 4.dp)
            ) {
                Text(
                    text = instrument.displayName,
                    style = TishTypography.caption,
                    color = if (isSelected) TishColors.accent else TishColors.textSecondary
                )
            }
        }

        // Vocal mode toggle
        Box(
            modifier = Modifier
                .clip(RoundedCornerShape(TishRadius.sm))
                .background(if (isVocalMode) TishColors.accentSecondary.copy(alpha = 0.2f) else TishColors.surface)
                .clickable { onVocalModeToggle() }
                .padding(horizontal = 8.dp, vertical = 4.dp)
        ) {
            Text(
                text = "🎤 Vocal",
                style = TishTypography.caption,
                color = if (isVocalMode) TishColors.accentSecondary else TishColors.textSecondary
            )
        }
    }
}
