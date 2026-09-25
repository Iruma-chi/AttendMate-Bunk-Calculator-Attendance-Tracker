package com.ytfl.attendmate

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.OpenableColumns
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.attendmate.app/update"
    private val BUILD_CONFIG_CHANNEL = "com.attendmate.app/build_config"
    private val BATTERY_OPTIMIZATION_CHANNEL = "com.attendmate.app/battery_optimization"

    private val FILE_PICKER_REQUEST_CODE = 1001
    private val DIRECTORY_PICKER_REQUEST_CODE = 1002

    private var pendingFilePickerResult: MethodChannel.Result? = null
    private var pendingDirectoryPickerResult: MethodChannel.Result? = null

    private var initialOpenedFilePayload: Map<String, Any?>? = null
    private var fileImportChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureOpenedFileIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        fileImportChannel = FileImportHandler.register(
            flutterEngine.dartExecutor.binaryMessenger,
            this
        ) { this }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BUILD_CONFIG_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getGoogleClientId" -> result.success(BuildConfig.GOOGLE_CLIENT_ID)
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BATTERY_OPTIMIZATION_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isIgnoringBatteryOptimizations" -> {
                    try {
                        result.success(isIgnoringBatteryOptimizations())
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }

                "requestIgnoreBatteryOptimizations" -> {
                    try {
                        result.success(requestIgnoreBatteryOptimizations())
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }

                "openBatteryOptimizationSettings" -> {
                    try {
                        result.success(openBatteryOptimizationSettings())
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "installAPK" -> {
                    val apkPath = call.argument<String>("apkPath")
                    if (apkPath != null) {
                        try {
                            result.success(installAPK(apkPath))
                        } catch (e: Exception) {
                            result.error("INSTALL_ERROR", e.message, null)
                        }
                    } else {
                        result.error(
                            "INVALID_ARGUMENTS",
                            "APK path is required",
                            null
                        )
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)

        val payload = readOpenedFilePayload(intent)
        if (payload != null) {
            initialOpenedFilePayload = payload
            fileImportChannel?.invokeMethod("onFileOpened", payload)
        }
    }

    fun openImportFilePickerForResult(result: MethodChannel.Result) {
        if (pendingFilePickerResult != null) {
            result.error(
                "PICKER_BUSY",
                "Another file picker request is already running.",
                null
            )
            return
        }

        pendingFilePickerResult = result

        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
                putExtra(
                    Intent.EXTRA_MIME_TYPES,
                    arrayOf(
                        "application/json",
                        "text/json",
                        "text/plain",
                        "text/csv",
                        "application/octet-stream",
                        "*/*"
                    )
                )
            }

            startActivityForResult(intent, FILE_PICKER_REQUEST_CODE)
        } catch (e: Exception) {
            pendingFilePickerResult = null
            result.error("PICKER_ERROR", e.message, null)
        }
    }

    fun openDirectoryPickerForResult(result: MethodChannel.Result) {
        if (pendingDirectoryPickerResult != null) {
            result.error(
                "PICKER_BUSY",
                "Another directory picker request is already running.",
                null
            )
            return
        }

        pendingDirectoryPickerResult = result

        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
            }

            startActivityForResult(intent, DIRECTORY_PICKER_REQUEST_CODE)
        } catch (e: Exception) {
            pendingDirectoryPickerResult = null
            result.error("PICKER_ERROR", e.message, null)
        }
    }

    fun consumeInitialOpenedFilePayload(): Map<String, Any?>? {
        val payload = initialOpenedFilePayload
        initialOpenedFilePayload = null
        return payload
    }

    fun shareFileNative(fileName: String, content: String): Boolean {
        return try {
            val safeName = File(fileName).name.ifBlank {
                "attendmate_share.json"
            }

            val shareFile = File(cacheDir, safeName)
            shareFile.writeText(content, Charsets.UTF_8)

            val uri = FileProvider.getUriForFile(
                this,
                "${packageName}.fileprovider",
                shareFile
            )

            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                type = "application/json"
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                clipData = ClipData.newRawUri("file", uri)
            }

            val chooser = Intent.createChooser(
                shareIntent,
                "Share $safeName"
            ).apply {
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }

            startActivity(chooser)
            true
        } catch (e: ActivityNotFoundException) {
            false
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    private fun captureOpenedFileIntent(intent: Intent?) {
        val payload = readOpenedFilePayload(intent)
        if (payload != null) {
            initialOpenedFilePayload = payload
        }
    }

    private fun readOpenedFilePayload(intent: Intent?): Map<String, Any?>? {
        if (intent == null) return null

        return try {
            val uri: Uri? = when (intent.action) {
                Intent.ACTION_VIEW -> intent.data
                Intent.ACTION_SEND -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        intent.getParcelableExtra(Intent.EXTRA_STREAM)
                    }
                }
                else -> null
            }

            if (uri != null) {
                val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                    ?: return null

                val name = getDisplayName(uri)
                    ?: uri.lastPathSegment
                    ?: "opened_file.json"

                return mapOf(
                    "name" to name,
                    "bytes" to bytes
                )
            }

            if (intent.action == Intent.ACTION_SEND) {
                val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                if (!text.isNullOrEmpty()) {
                    return mapOf(
                        "name" to "shared_file.json",
                        "content" to text
                    )
                }
            }

            null
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    private fun getDisplayName(uri: Uri): String? {
        if (uri.scheme == "file") {
            return uri.path?.let { File(it).name }
        }

        var cursor: Cursor? = null
        return try {
            cursor = contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null
            )

            if (cursor != null && cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) cursor.getString(index) else null
            } else {
                null
            }
        } catch (_: Exception) {
            null
        } finally {
            cursor?.close()
        }
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?
    ) {
        super.onActivityResult(requestCode, resultCode, data)

        when (requestCode) {
            FILE_PICKER_REQUEST_CODE -> {
                val result = pendingFilePickerResult
                pendingFilePickerResult = null

                if (result == null) return

                if (resultCode != Activity.RESULT_OK || data?.data == null) {
                    result.success(null)
                    return
                }

                val uri = data.data!!

                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                        val takeFlags = data.flags and
                            (Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                Intent.FLAG_GRANT_WRITE_URI_PERMISSION)

                        if (takeFlags != 0) {
                            try {
                                contentResolver.takePersistableUriPermission(
                                    uri,
                                    takeFlags and Intent.FLAG_GRANT_READ_URI_PERMISSION
                                )
                            } catch (_: Exception) {
                                // Some providers do not support persistable permissions.
                            }
                        }
                    }

                    val bytes = contentResolver.openInputStream(uri)
                        ?.use { it.readBytes() }

                    if (bytes == null) {
                        result.error(
                            "READ_ERROR",
                            "Unable to read the selected file.",
                            null
                        )
                        return
                    }

                    result.success(
                        mapOf(
                            "name" to (getDisplayName(uri) ?: "selected_file"),
                            "bytes" to bytes
                        )
                    )
                } catch (e: Exception) {
                    result.error(
                        "READ_ERROR",
                        e.message ?: "Unable to read the selected file.",
                        null
                    )
                }
            }

            DIRECTORY_PICKER_REQUEST_CODE -> {
                val result = pendingDirectoryPickerResult
                pendingDirectoryPickerResult = null

                if (result == null) return

                if (resultCode != Activity.RESULT_OK || data?.data == null) {
                    result.success(null)
                    return
                }

                val uri = data.data!!

                try {
                    val takeFlags = data.flags and
                        (Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION)

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT &&
                        takeFlags != 0
                    ) {
                        try {
                            contentResolver.takePersistableUriPermission(
                                uri,
                                takeFlags
                            )
                        } catch (_: Exception) {
                            // Provider may not support persistable permissions.
                        }
                    }

                    result.success(uri.toString())
                } catch (e: Exception) {
                    result.error(
                        "DIRECTORY_ERROR",
                        e.message ?: "Unable to access selected directory.",
                        null
                    )
                }
            }
        }
    }

    private fun installAPK(apkPath: String): String {
        val file = File(apkPath)

        if (!file.exists()) {
            throw Exception("APK file not found: $apkPath")
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (!packageManager.canRequestPackageInstalls()) {
                val intent = Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES
                ).apply {
                    data = Uri.parse("package:$packageName")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }

                startActivity(intent)
                return "permission_required"
            }
        }

        val uri: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            FileProvider.getUriForFile(
                this,
                "${packageName}.fileprovider",
                file
            )
        } else {
            Uri.fromFile(file)
        }

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(
                uri,
                "application/vnd.android.package-archive"
            )
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        return try {
            val chooser = Intent.createChooser(intent, "Install update")
            chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(chooser)
            "installer_started"
        } catch (e: ActivityNotFoundException) {
            "installer_not_found"
        }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager =
                getSystemService(Context.POWER_SERVICE) as? PowerManager

            val isIgnoring =
                powerManager?.isIgnoringBatteryOptimizations(packageName) ?: true

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val activityManager =
                    getSystemService(Context.ACTIVITY_SERVICE)
                        as? android.app.ActivityManager

                val isRestricted =
                    activityManager?.isBackgroundRestricted ?: false

                return isIgnoring && !isRestricted
            }

            return isIgnoring
        }

        return true
    }

    private fun requestIgnoreBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (isIgnoringBatteryOptimizations()) {
                return true
            }

            return try {
                val intent = Intent(
                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
                ).apply {
                    data = Uri.parse("package:$packageName")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }

                startActivity(intent)
                true
            } catch (e: Exception) {
                e.printStackTrace()
                openBatteryOptimizationSettings()
            }
        }

        return true
    }

    private fun openBatteryOptimizationSettings(): Boolean {
        return try {
            val intent = Intent(
                Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS
            ).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }

            startActivity(intent)
            true
        } catch (e: Exception) {
            e.printStackTrace()

            try {
                val intent = Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS
                ).apply {
                    data = Uri.parse("package:$packageName")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }

                startActivity(intent)
                true
            } catch (ex: Exception) {
                ex.printStackTrace()
                false
            }
        }
    }
}