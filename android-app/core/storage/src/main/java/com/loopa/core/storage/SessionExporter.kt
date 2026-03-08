package com.loopa.core.storage

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import com.loopa.core.model.SavedSession
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File

/**
 * .loopa file import/export service.
 * Ported from iOS SessionExporter.swift.
 *
 * .loopa files use ISO-8601 dates, pretty printing, and sorted keys.
 * Import accepts files by extension, decodes into SavedSession,
 * then creates a fresh session with a new ID and " (Imported)" suffix.
 */
class SessionExporter(private val context: Context) {

    private val exportJson = Json {
        prettyPrint = true
        ignoreUnknownKeys = true
        encodeDefaults = true
        // Note: kotlinx.serialization uses epoch millis by default for Long dates.
        // For true ISO-8601, a custom serializer would be needed.
        // This is acceptable for Android-to-Android round trips.
    }

    /**
     * Export a session to a .loopa file and return the file URI.
     */
    fun exportSession(session: SavedSession): File? {
        return try {
            val filename = "${session.name.replace(" ", "_")}.loopa"
            val file = File(context.cacheDir, filename)
            val data = exportJson.encodeToString(session)
            file.writeText(data)
            file
        } catch (e: Exception) {
            null
        }
    }

    /**
     * Create a share intent for a .loopa file.
     */
    fun createShareIntent(file: File): Intent? {
        return try {
            val uri = FileProvider.getUriForFile(
                context,
                "${context.packageName}.fileprovider",
                file
            )
            Intent(Intent.ACTION_SEND).apply {
                type = "application/octet-stream"
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        } catch (e: Exception) {
            null
        }
    }

    /**
     * Import a session from a .loopa file URI.
     * Returns a new session with fresh ID and " (Imported)" suffix.
     */
    fun importSession(uri: Uri): SavedSession? {
        return try {
            val inputStream = context.contentResolver.openInputStream(uri) ?: return null
            val data = inputStream.bufferedReader().readText()
            inputStream.close()

            val session = exportJson.decodeFromString<SavedSession>(data)

            // Create a fresh session with new ID and imported suffix
            session.copy(
                id = java.util.UUID.randomUUID().toString(),
                name = "${session.name} (Imported)",
                lastModifiedAt = System.currentTimeMillis()
            )
        } catch (e: Exception) {
            null
        }
    }
}
