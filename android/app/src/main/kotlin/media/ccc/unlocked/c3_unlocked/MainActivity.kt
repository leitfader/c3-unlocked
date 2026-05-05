package media.ccc.unlocked.c3_unlocked

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val downloadsChannelName = "c3_unlocked/downloads"
    private val linksChannelName = "c3_unlocked/links"
    private var pendingDownload: PendingDownload? = null
    private var linksChannel: MethodChannel? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, downloadsChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enqueueDownload" -> enqueueDownload(call, result)
                    "queryDownload" -> queryDownload(call, result)
                    "queryDownloads" -> queryDownloads(call, result)
                    "removeDownload" -> removeDownload(call, result)
                    "downloadsDirectory" -> result.success(downloadsRoot().absolutePath)
                    "openFile" -> result.success(false)
                    else -> result.notImplemented()
                }
            }
        linksChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, linksChannelName)
        linksChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "initialLink" -> result.success(extractLink(intent))
                "shareText" -> shareText(call, result)
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val link = extractLink(intent)
        if (!link.isNullOrBlank()) {
            linksChannel?.invokeMethod("openLink", link)
        }
    }

    private fun enqueueDownload(call: MethodCall, result: MethodChannel.Result) {
        val request = DownloadRequestArgs.from(call)
        if (request == null) {
            result.error("bad_download", "Download arguments are incomplete.", null)
            return
        }

        if (needsNotificationPermission()) {
            pendingDownload = PendingDownload(request, result)
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), notificationRequestCode)
            return
        }

        startDownload(request, result)
    }

    private fun queryDownload(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("id")
        if (id.isNullOrBlank()) {
            result.error("bad_id", "Download id is missing.", null)
            return
        }
        result.success(NativeDownloadStore.get(this, id))
    }

    private fun queryDownloads(call: MethodCall, result: MethodChannel.Result) {
        val ids = call.argument<List<String>>("ids") ?: emptyList()
        result.success(NativeDownloadStore.getAll(this, ids))
    }

    private fun removeDownload(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("id")
        if (id.isNullOrBlank()) {
            result.error("bad_id", "Download id is missing.", null)
            return
        }
        val intent = Intent(this, DownloadForegroundService::class.java)
            .setAction(DownloadForegroundService.ACTION_CANCEL)
            .putExtra(DownloadForegroundService.EXTRA_ID, id)
        startService(intent)
        NativeDownloadStore.remove(this, id)
        result.success(null)
    }

    private fun shareText(call: MethodCall, result: MethodChannel.Result) {
        val text = call.argument<String>("text")
        val title = call.argument<String>("title") ?: "Share"
        if (text.isNullOrBlank()) {
            result.error("bad_share", "Nothing to share.", null)
            return
        }
        val intent = Intent(Intent.ACTION_SEND)
            .setType("text/plain")
            .putExtra(Intent.EXTRA_TEXT, text)
        startActivity(Intent.createChooser(intent, title))
        result.success(null)
    }

    private fun startDownload(request: DownloadRequestArgs, result: MethodChannel.Result) {
        try {
            val snapshot = request.initialSnapshot(downloadsRoot())
            NativeDownloadStore.save(this, snapshot)

            val intent = Intent(this, DownloadForegroundService::class.java)
                .setAction(DownloadForegroundService.ACTION_START)
                .putExtra(DownloadForegroundService.EXTRA_ID, request.id)
                .putExtra(DownloadForegroundService.EXTRA_URL, request.url)
                .putExtra(DownloadForegroundService.EXTRA_TITLE, request.title)
                .putExtra(DownloadForegroundService.EXTRA_FILE_NAME, request.fileName)
                .putExtra(DownloadForegroundService.EXTRA_RELATIVE_DIR, request.relativeDir)
                .putExtra(DownloadForegroundService.EXTRA_MIME_TYPE, request.mimeType)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }

            result.success(snapshot)
        } catch (error: Exception) {
            result.error("enqueue_failed", error.message, null)
        }
    }

    private fun extractLink(intent: Intent?): String? {
        if (intent == null) return null
        if (intent.action == Intent.ACTION_VIEW) return intent.dataString
        if (intent.action == Intent.ACTION_SEND && intent.type == "text/plain") {
            return intent.getStringExtra(Intent.EXTRA_TEXT)
        }
        return null
    }

    private fun downloadsRoot(): File {
        val directory = File(filesDir, "downloads")
        if (!directory.exists()) {
            directory.mkdirs()
        }
        return directory
    }

    private fun needsNotificationPermission(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED &&
            pendingDownload == null
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != notificationRequestCode) return
        val pending = pendingDownload ?: return
        pendingDownload = null
        startDownload(pending.request, pending.result)
    }

    private data class PendingDownload(
        val request: DownloadRequestArgs,
        val result: MethodChannel.Result
    )

    private companion object {
        const val notificationRequestCode = 4317
    }
}

data class DownloadRequestArgs(
    val id: String,
    val url: String,
    val title: String,
    val fileName: String,
    val relativeDir: String,
    val mimeType: String
) {
    fun destination(root: File): File {
        val directory = File(root, cleanPathSegment(relativeDir))
        if (!directory.exists()) {
            directory.mkdirs()
        }
        return File(directory, "${id}_${cleanFileName(fileName)}")
    }

    fun initialSnapshot(root: File): Map<String, Any?> {
        return mapOf(
            "id" to id,
            "state" to "running",
            "bytesDownloaded" to 0L,
            "totalBytes" to 0L,
            "localPath" to destination(root).absolutePath,
            "reason" to null
        )
    }

    companion object {
        fun from(call: MethodCall): DownloadRequestArgs? {
            val id = call.argument<String>("id")
            val url = call.argument<String>("url")
            if (id.isNullOrBlank() || url.isNullOrBlank()) return null
            return DownloadRequestArgs(
                id = id,
                url = url,
                title = call.argument<String>("title") ?: "c3-UNLOCKED",
                fileName = call.argument<String>("fileName") ?: "recording",
                relativeDir = call.argument<String>("relativeDir") ?: "media.ccc.de",
                mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
            )
        }
    }
}

fun cleanPathSegment(value: String): String {
    return value
        .split("/")
        .filter { it.isNotBlank() }
        .joinToString("/") { cleanFileName(it) }
        .ifBlank { "media.ccc.de" }
}

fun cleanFileName(value: String): String {
    return value
        .replace(Regex("[\\\\/:*?\"<>|]+"), " ")
        .replace(Regex("\\s+"), " ")
        .trim()
        .ifBlank { "recording" }
}
