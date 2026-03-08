package com.loopa.feature.looper.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp
import com.loopa.app.ui.theme.TishColors
import com.loopa.app.ui.theme.TishRadius
import com.loopa.app.ui.theme.TishTypography

/**
 * Multi-touch piano keyboard and drum pad surface.
 * Ported from iOS FullKeyboardView.swift.
 */
@Composable
fun FullKeyboardView(
    startNote: Int,
    keyCount: Int,
    isDrumKit: Boolean,
    onNoteOn: (Int, Int) -> Unit, // (note, velocity)
    onNoteOff: (Int) -> Unit,
    modifier: Modifier = Modifier
) {
    if (isDrumKit) {
        DrumPadGrid(onNoteOn = onNoteOn, onNoteOff = onNoteOff, modifier = modifier)
    } else {
        PianoKeyboard(
            startNote = startNote,
            keyCount = keyCount,
            onNoteOn = onNoteOn,
            onNoteOff = onNoteOff,
            modifier = modifier
        )
    }
}

@Composable
private fun PianoKeyboard(
    startNote: Int,
    keyCount: Int,
    onNoteOn: (Int, Int) -> Unit,
    onNoteOff: (Int) -> Unit,
    modifier: Modifier = Modifier
) {
    val whiteNotes = remember(startNote, keyCount) {
        (startNote until startNote + keyCount).filter { !isBlackKey(it) }
    }

    Box(modifier = modifier.fillMaxWidth()) {
        Row(modifier = Modifier.fillMaxSize()) {
            whiteNotes.forEach { note ->
                WhiteKey(
                    note = note,
                    onNoteOn = onNoteOn,
                    onNoteOff = onNoteOff,
                    modifier = Modifier.weight(1f).fillMaxHeight()
                )
            }
        }
    }
}

@Composable
private fun WhiteKey(
    note: Int,
    onNoteOn: (Int, Int) -> Unit,
    onNoteOff: (Int) -> Unit,
    modifier: Modifier = Modifier
) {
    var isPressed by remember { mutableStateOf(false) }

    Box(
        modifier = modifier
            .padding(horizontal = 1.dp)
            .clip(RoundedCornerShape(bottomStart = 4.dp, bottomEnd = 4.dp))
            .background(if (isPressed) TishColors.keyWhitePressed else TishColors.keyWhite)
            .border(0.5.dp, TishColors.keyBorder, RoundedCornerShape(bottomStart = 4.dp, bottomEnd = 4.dp))
            .pointerInput(note) {
                detectTapGestures(
                    onPress = {
                        isPressed = true
                        onNoteOn(note, 100)
                        tryAwaitRelease()
                        isPressed = false
                        onNoteOff(note)
                    }
                )
            },
        contentAlignment = Alignment.BottomCenter
    ) {
        // Note label for C notes
        if (note % 12 == 0) {
            Text(
                text = "C${note / 12 - 1}",
                style = TishTypography.caption,
                color = TishColors.textTertiary,
                modifier = Modifier.padding(bottom = 4.dp)
            )
        }
    }
}

@Composable
private fun DrumPadGrid(
    onNoteOn: (Int, Int) -> Unit,
    onNoteOff: (Int) -> Unit,
    modifier: Modifier = Modifier
) {
    val drumLayout = listOf(
        listOf(36 to "Kick", 38 to "Snare", 42 to "HiHat", 46 to "Open HH"),
        listOf(39 to "Clap", 41 to "Tom1", 43 to "Tom2", 37 to "Rim"),
        listOf(49 to "Crash", 51 to "Ride", 44 to "Pedal", 56 to "Bell")
    )

    Column(
        modifier = modifier.fillMaxSize().padding(4.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        drumLayout.forEach { row ->
            Row(
                modifier = Modifier.weight(1f).fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                row.forEach { (note, label) ->
                    DrumPad(
                        note = note,
                        label = label,
                        onNoteOn = onNoteOn,
                        onNoteOff = onNoteOff,
                        modifier = Modifier.weight(1f).fillMaxHeight()
                    )
                }
            }
        }
    }
}

@Composable
private fun DrumPad(
    note: Int,
    label: String,
    onNoteOn: (Int, Int) -> Unit,
    onNoteOff: (Int) -> Unit,
    modifier: Modifier = Modifier
) {
    var isPressed by remember { mutableStateOf(false) }

    Box(
        modifier = modifier
            .clip(RoundedCornerShape(TishRadius.md))
            .background(if (isPressed) TishColors.accent.copy(alpha = 0.3f) else TishColors.elevated)
            .border(1.dp, if (isPressed) TishColors.accent else TishColors.keyBorder, RoundedCornerShape(TishRadius.md))
            .pointerInput(note) {
                detectTapGestures(
                    onPress = {
                        isPressed = true
                        onNoteOn(note, 120)
                        tryAwaitRelease()
                        isPressed = false
                        onNoteOff(note)
                    }
                )
            },
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = label,
            style = TishTypography.caption,
            color = if (isPressed) TishColors.accent else TishColors.textSecondary
        )
    }
}

private fun isBlackKey(note: Int): Boolean {
    return when (note % 12) {
        1, 3, 6, 8, 10 -> true
        else -> false
    }
}
