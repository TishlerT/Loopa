package com.loopa.core.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
enum class Instrument(
    val displayName: String,
    val programNumber: UByte,
    val isDrumKit: Boolean,
    val icon: String
) {
    @SerialName("Piano")
    PIANO("Piano", 0u, false, "pianokeys"),

    @SerialName("E-Piano")
    ELECTRIC_PIANO("E-Piano", 4u, false, "pianokeys.inverse"),

    @SerialName("Organ")
    ORGAN("Organ", 16u, false, "music.note.house"),

    @SerialName("Guitar")
    GUITAR("Guitar", 24u, false, "guitars"),

    @SerialName("Strings")
    STRINGS("Strings", 48u, false, "music.quarternote.3"),

    @SerialName("Lead")
    LEAD("Lead", 80u, false, "waveform"),

    @SerialName("Pad")
    PAD("Pad", 88u, false, "waveform.path"),

    @SerialName("Drums")
    DRUMS("Drums", 0u, true, "cylinder.split.1x2.fill"),

    @SerialName("Bass")
    BASS("Bass", 32u, false, "speaker.wave.2");

    companion object {
        fun fromRawValue(rawValue: String): Instrument? =
            entries.find { it.displayName == rawValue }
    }
}
