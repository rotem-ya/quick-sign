package com.example.quick_sign

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// Receives ACTION_VIEW intents ("Open with…" from WhatsApp, file managers,
/// mail apps) and hands the file to Flutter. ACTION_SEND (the share sheet) is
/// handled separately by the receive_sharing_intent plugin.
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pendingPath: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "quick_sign/view_intent",
        )
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialViewFile" -> {
                    result.success(pendingPath)
                    pendingPath = null
                }
                else -> result.notImplemented()
            }
        }
        handleViewIntent(intent, initial = true)
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
        val ch = channel
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
}
