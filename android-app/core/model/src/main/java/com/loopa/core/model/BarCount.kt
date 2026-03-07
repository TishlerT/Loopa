package com.loopa.core.model

enum class BarCount(val rawValue: Int) {
    ONE(1),
    TWO(2),
    FOUR(4),
    EIGHT(8),
    SIXTEEN(16);

    val displayName: String
        get() = if (rawValue == 1) "1 bar" else "$rawValue bars"

    companion object {
        fun fromRawValue(rawValue: Int): BarCount? =
            entries.find { it.rawValue == rawValue }
    }
}
