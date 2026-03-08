package com.loopa.audio

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

/**
 * Haptic feedback manager mirroring iOS HapticManager.
 */
class HapticManager(context: Context) {

    private val vibrator: Vibrator? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        val manager = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
        manager?.defaultVibrator
    } else {
        @Suppress("DEPRECATION")
        context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
    }

    /** Light tap for key presses */
    fun keyPress() {
        vibrate(duration = 10, amplitude = 40)
    }

    /** Medium tap for selection changes */
    fun selectionChange() {
        vibrate(duration = 15, amplitude = 60)
    }

    /** Recording transition feedback */
    fun recordingTransition() {
        vibrate(duration = 25, amplitude = 100)
    }

    /** Warning feedback */
    fun warning() {
        vibrate(duration = 30, amplitude = 120)
    }

    /** Success feedback */
    fun success() {
        vibrate(duration = 20, amplitude = 80)
    }

    private fun vibrate(duration: Long, amplitude: Int) {
        vibrator?.vibrate(
            VibrationEffect.createOneShot(duration, amplitude.coerceIn(1, 255))
        )
    }
}
