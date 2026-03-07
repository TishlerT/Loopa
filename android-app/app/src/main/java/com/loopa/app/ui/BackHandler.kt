package com.loopa.app.ui

import androidx.activity.compose.BackHandler
import androidx.compose.runtime.Composable

/**
 * Loopa back handler — manages back navigation for sheets and overlays.
 * Compose BackHandler for Android back button/gesture.
 */
@Composable
fun LoopaBackHandler(
    showingTracksSheet: Boolean,
    showingBPMEditor: Boolean,
    showingSettings: Boolean,
    showingSaveSheet: Boolean,
    showingLoadSheet: Boolean,
    onDismissTracksSheet: () -> Unit,
    onDismissBPMEditor: () -> Unit,
    onDismissSettings: () -> Unit,
    onDismissSaveSheet: () -> Unit,
    onDismissLoadSheet: () -> Unit
) {
    BackHandler(enabled = showingTracksSheet) {
        onDismissTracksSheet()
    }
    BackHandler(enabled = showingBPMEditor) {
        onDismissBPMEditor()
    }
    BackHandler(enabled = showingSettings) {
        onDismissSettings()
    }
    BackHandler(enabled = showingSaveSheet) {
        onDismissSaveSheet()
    }
    BackHandler(enabled = showingLoadSheet) {
        onDismissLoadSheet()
    }
}
