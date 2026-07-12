package com.rotem.quicksign

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// Receives ACTION_VIEW intents ("Open with…" from WhatsApp, file managers,
/// mail apps) and hands the file to Flutter. ACTION_SEND (the share sheet) is
/// handled separately by the receive_sharing_intent plugin.
///
/// Also hosts the "default save folder" feature: apps like Google Drive,
/// OneDrive and Dropbox each register themselves as a Storage Access
/// Framework document provider, so the system folder picker (SAF) lets the
/// user pick a folder *inside those apps' own storage* — writes through it
/// land straight in Drive/OneDrive and sync normally. No OAuth, no API keys,
/// no server: it's the same mechanism as "Save to…", just remembered.
class MainActivity : FlutterActivity() {
    private var viewChannel: MethodChannel? = null
    private var folderChannel: MethodChannel? = null
    private var pendingPath: String? = null
    private var pendingFolderResult: MethodChannel.Result? = null

    private val folderPrefs by lazy {
        getSharedPreferences("default_folder", Context.MODE_PRIVATE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        viewChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "quick_sign/view_intent",
        )
        viewChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialViewFile" -> {
                    result.success(pendingPath)
                    pendingPath = null
                }
                else -> result.notImplemented()
            }
        }
        handleViewIntent(intent, initial = true)

        folderChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "quick_sign/default_folder",
        )
        folderChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "pickFolder" -> pickFolder(result)
                "folderName" -> result.success(currentFolderName())
                "clearFolder" -> {
                    clearFolder()
                    result.success(null)
                }
                "saveFile" -> {
                    val fileName = call.argument<String>("fileName")
                    val bytes = call.argument<ByteArray>("bytes")
                    if (fileName == null || bytes == null) {
                        result.error("bad_args", "fileName/bytes required", null)
                    } else {
                        saveFileToFolder(fileName, bytes, result)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleViewIntent(intent, initial = false)
    }

    private fun handleViewIntent(intent: Intent?, initial: Boolean) {
        if (intent?.action != Intent.ACTION_VIEW) return
        val uri = intent.data ?: return
        val path = copyToCache(uri) ?: return
        val ch = viewChannel
        if (initial || ch == null) {
            pendingPath = path
        } else {
            ch.invokeMethod("viewFile", path)
        }
    }

    /** Content URIs are only readable while the grant lasts — copy to cache. */
    private fun copyToCache(uri: Uri): String? {
        return try {
            val mime = contentResolver.getType(uri) ?: ""
            val fromName =
                uri.lastPathSegment?.substringAfterLast('.', "")?.lowercase()
            val ext = when {
                mime == "application/pdf" -> "pdf"
                mime == "image/png" -> "png"
                mime.startsWith("image/") -> "jpg"
                fromName in listOf("pdf", "png", "jpg", "jpeg") -> fromName!!
                else -> "pdf"
            }
            val out = File(cacheDir, "view_${System.currentTimeMillis()}.$ext")
            val stream = contentResolver.openInputStream(uri) ?: return null
            stream.use { input ->
                out.outputStream().use { output -> input.copyTo(output) }
            }
            out.absolutePath
        } catch (_: Exception) {
            null
        }
    }

    // ── Default folder (SAF) ────────────────────────────────────────────────

    private fun pickFolder(result: MethodChannel.Result) {
        pendingFolderResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
            )
        }
        try {
            startActivityForResult(intent, REQUEST_CODE_OPEN_TREE)
        } catch (_: Exception) {
            result.success(null)
            pendingFolderResult = null
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_CODE_OPEN_TREE) return
        val result = pendingFolderResult
        pendingFolderResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result?.success(null)
            return
        }
        contentResolver.takePersistableUriPermission(
            uri,
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
        )
        folderPrefs.edit().putString(KEY_FOLDER_URI, uri.toString()).apply()
        result?.success(folderDisplayName(uri))
    }

    private fun currentFolderName(): String? {
        val uri = persistedFolderUri() ?: return null
        return folderDisplayName(uri)
    }

    private fun folderDisplayName(uri: Uri): String {
        val doc = DocumentFile.fromTreeUri(this, uri)
        return doc?.name ?: uri.lastPathSegment ?: uri.toString()
    }

    private fun persistedFolderUri(): Uri? {
        val stored = folderPrefs.getString(KEY_FOLDER_URI, null) ?: return null
        val uri = Uri.parse(stored)
        // The grant can be revoked externally (app uninstalled, storage
        // reset) — verify it is still valid before trusting it.
        val stillGranted = contentResolver.persistedUriPermissions.any {
            it.uri == uri && it.isWritePermission
        }
        if (!stillGranted) {
            folderPrefs.edit().remove(KEY_FOLDER_URI).apply()
            return null
        }
        return uri
    }

    private fun clearFolder() {
        val uri = persistedFolderUri()
        if (uri != null) {
            try {
                contentResolver.releasePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                )
            } catch (_: Exception) {
                // Already released — fine.
            }
        }
        folderPrefs.edit().remove(KEY_FOLDER_URI).apply()
    }

    private fun saveFileToFolder(fileName: String, bytes: ByteArray, result: MethodChannel.Result) {
        val treeUri = persistedFolderUri()
        if (treeUri == null) {
            result.error("no_folder", "No default folder set", null)
            return
        }
        try {
            val dir = DocumentFile.fromTreeUri(this, treeUri)
            if (dir == null || !dir.canWrite()) {
                result.error("unwritable", "Folder is not writable", null)
                return
            }
            // Overwrite: SAF has no atomic "replace", so drop any same-named
            // file first.
            dir.findFile(fileName)?.delete()
            val newFile = dir.createFile("application/pdf", fileName)
            if (newFile == null) {
                result.error("create_failed", "Could not create file", null)
                return
            }
            contentResolver.openOutputStream(newFile.uri)?.use { it.write(bytes) }
                ?: run {
                    result.error("stream_failed", "Could not open output stream", null)
                    return
                }
            result.success(newFile.uri.toString())
        } catch (e: Exception) {
            result.error("save_failed", e.message, null)
        }
    }

    companion object {
        private const val REQUEST_CODE_OPEN_TREE = 4242
        private const val KEY_FOLDER_URI = "folder_uri"
    }
}
