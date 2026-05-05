package media.ccc.unlocked.c3_unlocked

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ConcurrentHashMap

class DownloadForegroundService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ensureNotificationChannel()
        startForeground(notificationId, notification("Preparing downloads", true))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startDownload(intent)
            ACTION_CANCEL -> cancelDownload(intent.getStringExtra(EXTRA_ID))
        }
        updateNotification()
        if (tasks.isEmpty()) {
            stopForegroundCompat()
            stopSelf(startId)
        }
        return START_NOT_STICKY
    }

    private fun startDownload(intent: Intent) {
        val request = DownloadRequestArgs(
            id = intent.getStringExtra(EXTRA_ID) ?: return,
            url = intent.getStringExtra(EXTRA_URL) ?: return,
            title = intent.getStringExtra(EXTRA_TITLE) ?: "c3-UNLOCKED",
            fileName = intent.getStringExtra(EXTRA_FILE_NAME) ?: "recording",
            relativeDir = intent.getStringExtra(EXTRA_RELATIVE_DIR) ?: "media.ccc.de",
            mimeType = intent.getStringExtra(EXTRA_MIME_TYPE) ?: "application/octet-stream"
        )
        if (tasks.containsKey(request.id)) return
        canceled.remove(request.id)

        val thread = Thread {
            runDownload(request)
        }
        tasks[request.id] = thread
        thread.start()
    }

    private fun cancelDownload(id: String?) {
        if (id.isNullOrBlank()) return
        canceled.add(id)
        tasks[id]?.interrupt()
    }

    private fun runDownload(request: DownloadRequestArgs) {
        val destination = request.destination(downloadsRoot())
        val part = File("${destination.absolutePath}.part")
        var connection: HttpURLConnection? = null

        try {
            NativeDownloadStore.save(this, snapshot(request.id, "running", 0L, 0L, destination.absolutePath, null))

            connection = (URL(request.url).openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = 20000
                readTimeout = 30000
                setRequestProperty("User-Agent", "c3-UNLOCKED Android")
            }
            val status = connection.responseCode
            if (status < 200 || status >= 300) {
                throw IllegalStateException("HTTP $status")
            }

            val total = connection.contentLengthLong.takeIf { it > 0L } ?: 0L
            var downloaded = 0L
            var lastUpdate = 0L
            connection.inputStream.use { input ->
                FileOutputStream(part).use { output ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    while (true) {
                        if (canceled.contains(request.id) || Thread.currentThread().isInterrupted) {
                            throw DownloadCanceledException()
                        }
                        val read = input.read(buffer)
                        if (read == -1) break
                        output.write(buffer, 0, read)
                        downloaded += read.toLong()
                        val now = System.currentTimeMillis()
                        if (now - lastUpdate >= 500L) {
                            lastUpdate = now
                            NativeDownloadStore.save(
                                this,
                                snapshot(request.id, "running", downloaded, total, destination.absolutePath, null)
                            )
                            updateNotification()
                        }
                    }
                }
            }

            if (destination.exists()) {
                destination.delete()
            }
            part.renameTo(destination)
            NativeDownloadStore.save(
                this,
                snapshot(
                    request.id,
                    "completed",
                    downloaded,
                    if (total > 0L) total else downloaded,
                    destination.absolutePath,
                    null
                )
            )
        } catch (_: DownloadCanceledException) {
            part.delete()
            destination.delete()
            NativeDownloadStore.remove(this, request.id)
        } catch (error: Exception) {
            part.delete()
            NativeDownloadStore.save(
                this,
                snapshot(request.id, "failed", 0L, 0L, destination.absolutePath, error.message)
            )
        } finally {
            connection?.disconnect()
            canceled.remove(request.id)
            tasks.remove(request.id)
            updateNotification()
            if (tasks.isEmpty()) {
                stopForegroundCompat()
                stopSelf()
            }
        }
    }

    private fun snapshot(
        id: String,
        state: String,
        bytesDownloaded: Long,
        totalBytes: Long,
        localPath: String?,
        reason: String?
    ): Map<String, Any?> {
        return mapOf(
            "id" to id,
            "state" to state,
            "bytesDownloaded" to bytesDownloaded,
            "totalBytes" to totalBytes,
            "localPath" to localPath,
            "reason" to reason
        )
    }

    private fun updateNotification() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val count = tasks.size
        val text = if (count == 1) "1 download running" else "$count downloads running"
        manager.notify(notificationId, notification(text, count > 0))
    }

    private fun notification(text: String, ongoing: Boolean): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle("c3-UNLOCKED")
            .setContentText(text)
            .setContentIntent(pendingIntent)
            .setOngoing(ongoing)
            .setOnlyAlertOnce(true)
            .setProgress(0, 0, ongoing)
            .build()
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            channelId,
            "c3-UNLOCKED downloads",
            NotificationManager.IMPORTANCE_LOW
        )
        manager.createNotificationChannel(channel)
    }

    private fun downloadsRoot(): File {
        val directory = File(filesDir, "downloads")
        if (!directory.exists()) {
            directory.mkdirs()
        }
        return directory
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    companion object {
        const val ACTION_START = "dev.chell.c3unlocked.DOWNLOAD_START"
        const val ACTION_CANCEL = "dev.chell.c3unlocked.DOWNLOAD_CANCEL"
        const val EXTRA_ID = "id"
        const val EXTRA_URL = "url"
        const val EXTRA_TITLE = "title"
        const val EXTRA_FILE_NAME = "fileName"
        const val EXTRA_RELATIVE_DIR = "relativeDir"
        const val EXTRA_MIME_TYPE = "mimeType"

        private const val channelId = "c3_unlocked_downloads"
        private const val notificationId = 7310
        private val tasks = ConcurrentHashMap<String, Thread>()
        private val canceled = ConcurrentHashMap.newKeySet<String>()
    }
}

private class DownloadCanceledException : Exception()
