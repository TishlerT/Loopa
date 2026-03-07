package com.loopa.feature.tracks.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.loopa.app.ui.components.TishButton
import com.loopa.app.ui.theme.TishColors
import com.loopa.app.ui.theme.TishSpacing
import com.loopa.app.ui.theme.TishTypography
import com.loopa.feature.tracks.TracksViewModel

@Composable
fun TracksScreen(
    viewModel: TracksViewModel,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .background(TishColors.background)
    ) {
        // Header
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(TishSpacing.sm),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            TishButton(text = "Done", onClick = onDismiss)
            Text("Tracks", style = TishTypography.title, color = TishColors.textPrimary)
            Spacer(modifier = Modifier.width(60.dp))
        }

        if (viewModel.tracks.isEmpty()) {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = "No Tracks Yet",
                    style = TishTypography.title,
                    color = TishColors.textTertiary
                )
            }
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(TishSpacing.sm),
                verticalArrangement = Arrangement.spacedBy(TishSpacing.sm)
            ) {
                itemsIndexed(viewModel.tracks) { index, track ->
                    TrackMixerRow(
                        track = track,
                        index = index,
                        anyTrackSoloed = viewModel.anyTrackSoloed,
                        onMute = { viewModel.toggleMute(track) },
                        onSolo = { viewModel.toggleSolo(track) },
                        onLoop = { viewModel.toggleLoop(track) },
                        onDelete = { viewModel.deleteTrack(track) },
                        onVolumeChange = { viewModel.setVolume(track, it) },
                        onQuantize = { viewModel.requestQuantize(track) },
                        onInstrumentChange = { viewModel.requestInstrumentChange(track) },
                        onTap = {
                            if (!track.isVocal) viewModel.selectTrackForFocus(track)
                        }
                    )
                }
            }
        }
    }
}
