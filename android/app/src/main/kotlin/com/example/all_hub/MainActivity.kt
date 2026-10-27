package com.example.all_hub

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import androidx.core.content.FileProvider
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "allhub/launcher"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveMediaToDownloads" -> {
                        val path = call.argument<String>("path")
                        val filename = call.argument<String>("name")
                        try {
                            val source = path?.let { File(it) }
                            if (source == null || !source.isFile || filename.isNullOrBlank() ||
                                filename.contains('/') || filename.contains(92.toChar()) ||
                                !Regex("^[A-Za-z0-9._-]+$").matches(filename)) {
                                result.error("MEDIA", "Invalid media file", null)
                            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                val extension = filename.substringAfterLast('.', "").lowercase()
                                val mime = when (extension) {
                                    "jpg", "jpeg" -> "image/jpeg"
                                    "png" -> "image/png"
                                    "gif" -> "image/gif"
                                    "webp" -> "image/webp"
                                    "mp4" -> "video/mp4"
                                    "webm" -> "video/webm"
                                    "mov" -> "video/quicktime"
                                    else -> "application/octet-stream"
                                }
                                val values = ContentValues().apply {
                                    put(MediaStore.Downloads.DISPLAY_NAME, filename)
                                    put(MediaStore.Downloads.MIME_TYPE, mime)
                                    put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/All Hub")
                                    put(MediaStore.Downloads.IS_PENDING, 1)
                                }
                                val resolver = contentResolver
                                val target = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                                    ?: throw IllegalStateException("Cannot create Downloads item")
                                try {
                                    resolver.openOutputStream(target)?.use { output ->
                                        source.inputStream().use { it.copyTo(output) }
                                    } ?: throw IllegalStateException("Cannot open Downloads item")
                                    val done = ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }
                                    resolver.update(target, done, null, null)
                                    result.success("Downloads/All Hub/$filename")
                                } catch (e: Exception) {
                                    resolver.delete(target, null, null)
                                    throw e
                                }
                            } else {
                                val downloads = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                                val folder = File(downloads, "All Hub")
                                if (!folder.exists() && !folder.mkdirs()) throw IllegalStateException("Cannot create Downloads folder")
                                source.copyTo(File(folder, filename), overwrite = false)
                                result.success("Downloads/All Hub/$filename")
                            }
                        } catch (e: Exception) {
                            result.error("MEDIA_SAVE", e.message, null)
                        }
                    }
                    "installApk" -> {
                        val apkPath = call.argument<String>("path")
                        try {
                            val apk = if (apkPath == null) null else File(apkPath)
                            if (apk == null || !apk.isFile || !apk.name.endsWith(".apk")) {
                                result.error("APK", "APK file is missing", null)
                            } else {
                                val uri = FileProvider.getUriForFile(
                                    this, "${applicationContext.packageName}.fileprovider", apk)
                                val intent = Intent(Intent.ACTION_VIEW).apply {
                                    setDataAndType(uri, "application/vnd.android.package-archive")
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                startActivity(intent)
                                result.success(true)
                            }
                        } catch (e: Exception) {
                            result.error("APK_INSTALL", e.message, null)
                        }
                    }
                    "installedPackageVersion" -> {
                        val packageName = call.argument<String>("packageName")
                        if (packageName.isNullOrBlank()) {
                            result.success(null)
                        } else {
                            try {
                                val info = packageManager.getPackageInfo(packageName, 0)
                                val version = info.versionName
                                // Include the CI build number for All Hub itself.
                                // Rolling releases share a stable version name,
                                // so versionName alone cannot detect an update.
                                if (packageName == "com.example.all_hub" && !version.isNullOrBlank()) {
                                    result.success("$version+${info.longVersionCode}")
                                } else {
                                    result.success(version ?: info.longVersionCode.toString())
                                }
                            } catch (e: PackageManager.NameNotFoundException) {
                                result.success(null)
                            } catch (e: Exception) {
                                result.error("PACKAGE_VERSION", e.message, null)
                            }
                        }
                    }
                    "isPackageInstalled" -> {
                        val packageName = call.argument<String>("packageName")
                        if (packageName.isNullOrBlank()) {
                            result.success(false)
                        } else {
                            result.success(packageManager.getLaunchIntentForPackage(packageName) != null)
                        }
                    }

                    "launchPackage" -> {
                        val packageName = call.argument<String>("packageName")
                        if (packageName.isNullOrBlank()) {
                            result.error("ARGUMENT", "Missing package name", null)
                        } else {
                            try {
                                val intent: Intent? = packageManager.getLaunchIntentForPackage(packageName)
                                if (intent == null) {
                                    result.success(false)
                                } else {
                                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    startActivity(intent)
                                    result.success(true)
                                }
                            } catch (e: Exception) {
                                result.error("LAUNCH_FAILED", e.message, null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
