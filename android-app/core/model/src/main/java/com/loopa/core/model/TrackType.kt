package com.loopa.core.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
enum class TrackType {
    @SerialName("midi") MIDI,
    @SerialName("audio") AUDIO
}
