package com.example.diary_app

import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException

class MainActivity : FlutterFragmentActivity() {
    private var pendingGalleryPick: MethodChannel.Result? = null
    private var pendingAllowMultiple: Boolean = false

    /** Play 정책: READ_MEDIA_IMAGES 없이 시스템 Photo Picker만 사용 */
    private val pickVisualMedia = registerForActivityResult(
        ActivityResultContracts.PickVisualMedia(),
    ) { uri: Uri? ->
        val result = pendingGalleryPick
        pendingGalleryPick = null
        pendingAllowMultiple = false
        if (result == null) return@registerForActivityResult
        if (uri == null) {
            result.success(null)
            return@registerForActivityResult
        }
        try {
            result.success(copyUriToCache(uri))
        } catch (e: Exception) {
            result.error("PICK_FAILED", e.message, null)
        }
    }

    private val pickMultipleVisualMedia = registerForActivityResult(
        ActivityResultContracts.PickMultipleVisualMedia(),
    ) { uris: List<Uri> ->
        val result = pendingGalleryPick
        pendingGalleryPick = null
        pendingAllowMultiple = false
        if (result == null) return@registerForActivityResult
        if (uris.isEmpty()) {
            result.success(emptyList<String>())
            return@registerForActivityResult
        }
        try {
            result.success(uris.map { copyUriToCache(it) })
        } catch (e: Exception) {
            result.error("PICK_FAILED", e.message, null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveToDownloads" -> {
                        val name = call.argument<String>("name")
                        val mime = call.argument<String>("mime") ?: "application/octet-stream"
                        val bytes = when (val raw = call.argument<Any>("bytes")) {
                            is ByteArray -> raw
                            is List<*> -> ByteArray(raw.size) { i -> (raw[i] as Number).toByte() }
                            else -> null
                        }
                        if (name.isNullOrBlank() || bytes == null) {
                            result.error("BAD_ARGS", "name/bytes required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val path = saveToDownloads(name, mime, bytes)
                            result.success(path)
                        } catch (e: Exception) {
                            result.error("SAVE_FAILED", e.message, null)
                        }
                    }
                    "openSavedFile" -> {
                        val location = call.argument<String>("uri")
                        val mime = call.argument<String>("mime") ?: "application/octet-stream"
                        if (location.isNullOrBlank()) {
                            result.error("BAD_ARGS", "uri required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            openSavedFile(location, mime)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("OPEN_FAILED", e.message, null)
                        }
                    }
                    "pickGalleryImage" -> {
                        if (pendingGalleryPick != null) {
                            result.error("BUSY", "picker already open", null)
                            return@setMethodCallHandler
                        }
                        val allowMultiple = call.argument<Boolean>("allowMultiple") == true
                        pendingGalleryPick = result
                        pendingAllowMultiple = allowMultiple
                        val request = PickVisualMediaRequest(
                            ActivityResultContracts.PickVisualMedia.ImageOnly,
                        )
                        try {
                            if (allowMultiple) {
                                pickMultipleVisualMedia.launch(request)
                            } else {
                                pickVisualMedia.launch(request)
                            }
                        } catch (e: Exception) {
                            pendingGalleryPick = null
                            pendingAllowMultiple = false
                            result.error("PICK_FAILED", e.message, null)
                        }
                    }
                    // 재설치에도 유지되는 ANDROID_ID — 설치 무료 AI 서버 키
                    "getInstallDeviceKey" -> {
                        val id = Settings.Secure.getString(
                            contentResolver,
                            Settings.Secure.ANDROID_ID,
                        )
                        if (id.isNullOrBlank()) {
                            result.error("NO_ID", "ANDROID_ID unavailable", null)
                        } else {
                            result.success("a:$id")
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun copyUriToCache(uri: Uri): String {
        val resolver = contentResolver
        val mime = resolver.getType(uri) ?: "image/jpeg"
        val ext = when {
            mime.contains("png") -> "png"
            mime.contains("webp") -> "webp"
            mime.contains("gif") -> "gif"
            mime.contains("heic") || mime.contains("heif") -> "heic"
            else -> "jpg"
        }
        val out = File(cacheDir, "gallery_pick_${System.currentTimeMillis()}.$ext")
        resolver.openInputStream(uri)?.use { input ->
            out.outputStream().use { output -> input.copyTo(output) }
        } ?: throw IOException("Cannot open gallery uri")
        if (!out.exists() || out.length() == 0L) {
            throw IOException("Empty gallery file")
        }
        return out.absolutePath
    }

    private fun saveToDownloads(name: String, mime: String, bytes: ByteArray): String {
        val safeName = name.replace(Regex("""[\\/:*?"<>|]"""), "_")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, safeName)
                put(MediaStore.Downloads.MIME_TYPE, mime)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("Downloads insert failed")
            contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: throw IllegalStateException("Downloads stream failed")
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            contentResolver.update(uri, values, null, null)
            return uri.toString()
        }

        @Suppress("DEPRECATION")
        val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        if (!dir.exists()) dir.mkdirs()
        val file = File(dir, safeName)
        file.writeBytes(bytes)
        return file.absolutePath
    }

    private fun openSavedFile(location: String, mime: String) {
        val uri = if (location.startsWith("content:") || location.startsWith("file:")) {
            Uri.parse(location)
        } else {
            val file = File(location)
            FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        }
        val view = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mime)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            startActivity(view)
        } catch (_: ActivityNotFoundException) {
            startActivity(Intent(android.app.DownloadManager.ACTION_VIEW_DOWNLOADS))
        }
    }

    companion object {
        private const val CHANNEL = "diary/files"
    }
}
