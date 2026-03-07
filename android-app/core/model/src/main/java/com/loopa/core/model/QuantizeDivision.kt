package com.loopa.core.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
enum class QuantizeDivision(val rawValue: String) {
    @SerialName("Off") OFF("Off"),
    @SerialName("1/4") QUARTER("1/4"),
    @SerialName("1/8") EIGHTH("1/8"),
    @SerialName("1/16") SIXTEENTH("1/16"),
    @SerialName("1/32") THIRTY_SECOND("1/32");

    /** Returns the fraction of a beat this division represents (null for off) */
    val beatFraction: Double?
        get() = when (this) {
            OFF -> null
            QUARTER -> 1.0
            EIGHTH -> 0.5
            SIXTEENTH -> 0.25
            THIRTY_SECOND -> 0.125
        }
}
