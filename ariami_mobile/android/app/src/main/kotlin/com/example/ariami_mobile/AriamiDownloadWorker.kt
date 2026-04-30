package com.example.ariami_mobile

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL

class AriamiDownloadWorker(
    appContext: Context,
    params: WorkerParameters
) : CoroutineWorker(appContext, params) {
    override suspend fun doWork(): Result {
        val taskId = inputData.getString(KEY_TASK_ID) ?: return failure("Missing task id")
        val url = inputData.getString(KEY_URL) ?: return failure("Missing URL")
        val destinationPath = inputData.getString(KEY_DESTINATION_PATH)
            ?: return failure("Missing destination path")
        val title = inputData.getString(KEY_TITLE) ?: "Downloading"
        val suppliedTotalBytes = inputData.getLong(KEY_TOTAL_BYTES, 0L)

        setForeground(createForegroundInfo(title, 0, suppliedTotalBytes))

        val finalFile = File(destinationPath)
        val partialFile = File("$destinationPath.partial")
        finalFile.parentFile?.mkdirs()

        var resumeOffset = if (partialFile.exists()) partialFile.length() else 0L
        var connection: HttpURLConnection? = null

        return try {
            connection = (URL(url).openConnection() as HttpURLConnection).apply {
                connectTimeout = 30_000
                readTimeout = 30_000
                requestMethod = "GET"
                instanceFollowRedirects = true
                if (resumeOffset > 0L) {
                    setRequestProperty("Range", "bytes=$resumeOffset-")
                }
            }

            val statusCode = connection.responseCode
            if (statusCode == 416) {
                partialFile.delete()
                return Result.retry()
            }
            if (statusCode != HttpURLConnection.HTTP_OK &&
                statusCode != HttpURLConnection.HTTP_PARTIAL
            ) {
                return failure("Unexpected download status: $statusCode")
            }

            if (resumeOffset > 0L && statusCode == HttpURLConnection.HTTP_OK) {
                partialFile.delete()
                resumeOffset = 0L
            }

            val expectedTotalBytes = parseTotalBytes(connection, resumeOffset)
                ?: suppliedTotalBytes.takeIf { it > 0L }
            var downloaded = resumeOffset

            connection.inputStream.use { input ->
                FileOutputStream(partialFile, resumeOffset > 0L).use { output ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    while (true) {
                        if (isStopped) {
                            return Result.failure(progressData(downloaded, expectedTotalBytes ?: 0L))
                        }
                        val read = input.read(buffer)
                        if (read == -1) break

                        output.write(buffer, 0, read)
                        downloaded += read.toLong()
                        val total = expectedTotalBytes ?: downloaded
                        setProgress(progressData(downloaded, total))
                        setForeground(createForegroundInfo(title, downloaded, total))
                    }
                }
            }

            val finalBytes = partialFile.length()
            if (expectedTotalBytes != null && expectedTotalBytes > 0L && finalBytes != expectedTotalBytes) {
                return failure("Downloaded file size mismatch: expected $expectedTotalBytes got $finalBytes")
            }

            if (finalFile.exists()) {
                finalFile.delete()
            }
            if (!partialFile.renameTo(finalFile)) {
                return failure("Failed to move completed download into place")
            }

            Result.success(progressData(finalBytes, finalBytes))
        } catch (error: Exception) {
            if (runAttemptCount < 3) {
                Result.retry()
            } else {
                failure(error.message ?: error.toString())
            }
        } finally {
            connection?.disconnect()
        }
    }

    override suspend fun getForegroundInfo(): ForegroundInfo {
        val title = inputData.getString(KEY_TITLE) ?: "Downloading"
        val totalBytes = inputData.getLong(KEY_TOTAL_BYTES, 0L)
        return createForegroundInfo(title, 0, totalBytes)
    }

    private fun parseTotalBytes(connection: HttpURLConnection, resumeOffset: Long): Long? {
        val contentRange = connection.getHeaderField("Content-Range")
        if (!contentRange.isNullOrBlank()) {
            val slashIndex = contentRange.lastIndexOf('/')
            if (slashIndex >= 0 && slashIndex < contentRange.length - 1) {
                contentRange.substring(slashIndex + 1).toLongOrNull()?.let { return it }
            }
        }

        val contentLength = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            connection.contentLengthLong
        } else {
            connection.contentLength.toLong()
        }
        if (contentLength <= 0L) return null
        return contentLength + resumeOffset
    }

    private fun progressData(bytesDownloaded: Long, totalBytes: Long) = workDataOf(
        KEY_BYTES_DOWNLOADED to bytesDownloaded,
        KEY_TOTAL_BYTES to totalBytes
    )

    private fun failure(message: String): Result {
        return Result.failure(
            workDataOf(
                KEY_ERROR_MESSAGE to message,
                KEY_BYTES_DOWNLOADED to 0L,
                KEY_TOTAL_BYTES to inputData.getLong(KEY_TOTAL_BYTES, 0L)
            )
        )
    }

    private fun createForegroundInfo(
        title: String,
        bytesDownloaded: Long,
        totalBytes: Long
    ): ForegroundInfo {
        createNotificationChannel()
        val progress = if (totalBytes > 0L) {
            ((bytesDownloaded * 100L) / totalBytes).coerceIn(0L, 100L).toInt()
        } else {
            0
        }

        val notification = NotificationCompat.Builder(applicationContext, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText("Downloading")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setProgress(100, progress, totalBytes <= 0L)
            .build()

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ForegroundInfo(
                NOTIFICATION_ID_BASE + id.hashCode().absoluteValueCompat(),
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            )
        } else {
            ForegroundInfo(
                NOTIFICATION_ID_BASE + id.hashCode().absoluteValueCompat(),
                notification
            )
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = applicationContext.getSystemService(Service.NOTIFICATION_SERVICE)
            as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Downloads",
            NotificationManager.IMPORTANCE_LOW
        )
        manager.createNotificationChannel(channel)
    }

    private fun Int.absoluteValueCompat(): Int = if (this == Int.MIN_VALUE) 0 else kotlin.math.abs(this)

    companion object {
        const val KEY_TASK_ID = "taskId"
        const val KEY_URL = "url"
        const val KEY_DESTINATION_PATH = "destinationPath"
        const val KEY_TITLE = "title"
        const val KEY_TOTAL_BYTES = "totalBytes"
        const val KEY_BYTES_DOWNLOADED = "bytesDownloaded"
        const val KEY_ERROR_MESSAGE = "errorMessage"

        private const val CHANNEL_ID = "ariami_downloads"
        private const val NOTIFICATION_ID_BASE = 24000
    }
}
