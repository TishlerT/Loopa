package com.loopa.core.storage

import android.content.Context
import com.loopa.core.model.SavedSession
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File

/**
 * Manages saving and loading of loop sessions.
 * Ported from iOS SessionStorage.swift.
 *
 * Date encoding note:
 * - Named sessions (sessions.json) use default epoch milliseconds
 * - Working session (working_session.json) uses default epoch milliseconds
 * - .loopa export uses ISO-8601 (handled by SessionExporter)
 */
class SessionStorage(private val context: Context) {

    private val json = Json {
        prettyPrint = false
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    private val sessionsFile: File
        get() = File(context.filesDir, "sessions.json")

    private val workingSessionFile: File
        get() = File(context.filesDir, "working_session.json")

    // MARK: - Named Sessions

    /** Get all saved sessions, sorted by lastModifiedAt descending */
    fun loadSessions(): List<SavedSession> {
        if (!sessionsFile.exists()) return emptyList()
        return try {
            val data = sessionsFile.readText()
            val sessions = json.decodeFromString<List<SavedSession>>(data)
            sessions.sortedByDescending { it.lastModifiedAt }
        } catch (e: Exception) {
            emptyList()
        }
    }

    /** Save a new session or update existing */
    fun saveSession(session: SavedSession) {
        val sessions = loadSessions().toMutableList()
        val index = sessions.indexOfFirst { it.id == session.id }
        if (index >= 0) {
            sessions[index] = session.copy(lastModifiedAt = System.currentTimeMillis())
        } else {
            sessions.add(0, session)
        }
        writeSessions(sessions)
    }

    /** Delete a session */
    fun deleteSession(session: SavedSession) {
        val sessions = loadSessions().toMutableList()
        sessions.removeAll { it.id == session.id }
        writeSessions(sessions)
    }

    /** Rename a session */
    fun renameSession(session: SavedSession, newName: String) {
        val sessions = loadSessions().toMutableList()
        val index = sessions.indexOfFirst { it.id == session.id }
        if (index >= 0) {
            sessions[index] = sessions[index].copy(
                name = newName,
                lastModifiedAt = System.currentTimeMillis()
            )
            writeSessions(sessions)
        }
    }

    // MARK: - Working Session (Auto-Save)

    /** Save the current working session for auto-restore */
    fun saveWorkingSession(session: SavedSession) {
        try {
            val data = json.encodeToString(session)
            workingSessionFile.writeText(data)
        } catch (e: Exception) {
            // Log error
        }
    }

    /** Load the auto-saved working session (if any) */
    fun loadWorkingSession(): SavedSession? {
        if (!workingSessionFile.exists()) return null
        return try {
            val data = workingSessionFile.readText()
            json.decodeFromString<SavedSession>(data)
        } catch (e: Exception) {
            null
        }
    }

    /** Clear the auto-saved working session */
    fun clearWorkingSession() {
        if (workingSessionFile.exists()) {
            workingSessionFile.delete()
        }
    }

    // MARK: - Private

    private fun writeSessions(sessions: List<SavedSession>) {
        try {
            val data = json.encodeToString(sessions)
            sessionsFile.writeText(data)
        } catch (e: Exception) {
            // Log error
        }
    }
}
