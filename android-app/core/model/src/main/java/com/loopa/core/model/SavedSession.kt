package com.loopa.core.model

import kotlinx.serialization.Serializable

/**
 * A saved session containing tracks and settings.
 * Ported from iOS SavedSession.
 *
 * Date handling note:
 * - .loopa export uses ISO-8601 dates
 * - Local storage (sessions.json, working_session.json) uses epoch milliseconds
 * The serialization format is chosen at the encoder/decoder level, not here.
 */
@Serializable
data class SavedSession(
    val id: String = java.util.UUID.randomUUID().toString(),
    var name: String,
    val createdAt: Long = System.currentTimeMillis(),
    var lastModifiedAt: Long = System.currentTimeMillis(),
    val bpm: Double,
    val barCount: Int,
    var tracks: List<Track>
)
