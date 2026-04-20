package com.example.fluxdrop

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity: FlutterActivity() {
    private val CHANNEL = "fluxdrop/storage"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getFreeSpace" -> {
                    try {
                        val stat = StatFs(Environment.getDataDirectory().path)
                        val bytesAvailable = stat.availableBlocksLong * stat.blockSizeLong
                        result.success(bytesAvailable)
                    } catch (e: Exception) {
                        result.error("UNAVAILABLE", "Storage info not available.", null)
                    }
                }
                "saveToGallery" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("INVALID_ARGS", "path is required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val file = File(path)
                        val mimeType = getMimeType(file.extension)
                        val isVideo = mimeType.startsWith("video/")

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            // Android 10+ — use MediaStore (scoped storage)
                            val collection = if (isVideo)
                                MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                            else
                                MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)

                            val values = ContentValues().apply {
                                put(if (isVideo) MediaStore.Video.Media.DISPLAY_NAME else MediaStore.Images.Media.DISPLAY_NAME, file.name)
                                put(if (isVideo) MediaStore.Video.Media.MIME_TYPE else MediaStore.Images.Media.MIME_TYPE, mimeType)
                                put(if (isVideo) MediaStore.Video.Media.RELATIVE_PATH else MediaStore.Images.Media.RELATIVE_PATH,
                                    if (isVideo) Environment.DIRECTORY_MOVIES + "/FluxDrop" else Environment.DIRECTORY_PICTURES + "/FluxDrop")
                                put(if (isVideo) MediaStore.Video.Media.IS_PENDING else MediaStore.Images.Media.IS_PENDING, 1)
                            }

                            val uri = contentResolver.insert(collection, values)
                            if (uri != null) {
                                contentResolver.openOutputStream(uri)?.use { os ->
                                    FileInputStream(file).use { it.copyTo(os) }
                                }
                                values.clear()
                                values.put(if (isVideo) MediaStore.Video.Media.IS_PENDING else MediaStore.Images.Media.IS_PENDING, 0)
                                contentResolver.update(uri, values, null, null)
                                result.success(uri.toString())
                            } else {
                                result.error("SAVE_FAILED", "MediaStore insert returned null", null)
                            }
                        } else {
                            // Android < 10 — copy to public Pictures/Movies
                            val destDir = File(
                                if (isVideo) Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES)
                                else Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES),
                                "FluxDrop"
                            )
                            destDir.mkdirs()
                            val dest = File(destDir, file.name)
                            file.copyTo(dest, overwrite = true)
                            result.success(dest.absolutePath)
                        }
                    } catch (e: Exception) {
                        result.error("SAVE_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun getMimeType(extension: String): String = when (extension.lowercase()) {
        "jpg", "jpeg" -> "image/jpeg"
        "png" -> "image/png"
        "gif" -> "image/gif"
        "webp" -> "image/webp"
        "heic", "heif" -> "image/heic"
        "mp4" -> "video/mp4"
        "mov" -> "video/quicktime"
        "avi" -> "video/x-msvideo"
        "mkv" -> "video/x-matroska"
        "webm" -> "video/webm"
        "3gp" -> "video/3gpp"
        else -> "application/octet-stream"
    }
}
