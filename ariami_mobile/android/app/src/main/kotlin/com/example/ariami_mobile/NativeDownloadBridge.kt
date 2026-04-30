package com.example.ariami_mobile

import android.content.Context
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.workDataOf
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

class NativeDownloadBridge(
    private val context: Context
) : MethodChannel.MethodCallHandler {
    private val workManager = WorkManager.getInstance(context)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(true)
            "startDownload" -> startDownload(call, result)
            "queryDownload" -> queryDownload(call, result)
            "cancelDownload" -> cancelDownload(call, result)
            else -> result.notImplemented()
        }
    }

    private fun startDownload(call: MethodCall, result: MethodChannel.Result) {
        val taskId = call.argument<String>("taskId")
        val url = call.argument<String>("url")
        val destinationPath = call.argument<String>("destinationPath")
        val title = call.argument<String>("title") ?: "Downloading"
        val totalBytes = call.argument<Number>("totalBytes")?.toLong() ?: 0L

        if (taskId.isNullOrBlank() || url.isNullOrBlank() || destinationPath.isNullOrBlank()) {
            result.error("invalid_args", "Missing taskId, url, or destinationPath", null)
            return
        }

        val request = OneTimeWorkRequestBuilder<AriamiDownloadWorker>()
            .setConstraints(
                Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .build()
            )
            .setInputData(
                workDataOf(
                    AriamiDownloadWorker.KEY_TASK_ID to taskId,
                    AriamiDownloadWorker.KEY_URL to url,
                    AriamiDownloadWorker.KEY_DESTINATION_PATH to destinationPath,
                    AriamiDownloadWorker.KEY_TITLE to title,
                    AriamiDownloadWorker.KEY_TOTAL_BYTES to totalBytes
                )
            )
            .addTag(taskId)
            .build()

        workManager.enqueueUniqueWork(taskId, ExistingWorkPolicy.REPLACE, request)
        result.success(
            mapOf(
                "backend" to "android_workmanager",
                "nativeTaskId" to request.id.toString()
            )
        )
    }

    private fun queryDownload(call: MethodCall, result: MethodChannel.Result) {
        val taskId = call.argument<String>("taskId")
        val nativeTaskId = call.argument<String>("nativeTaskId")
        if (taskId.isNullOrBlank()) {
            result.error("invalid_args", "Missing taskId", null)
            return
        }

        val info = try {
            if (nativeTaskId.isNullOrBlank()) {
                workManager.getWorkInfosForUniqueWork(taskId).get().firstOrNull()
            } else {
                workManager.getWorkInfoById(UUID.fromString(nativeTaskId)).get()
            }
        } catch (_: Exception) {
            null
        }
        if (info == null) {
            result.success(mapOf("state" to "unavailable"))
            return
        }

        val data = if (info.state.isFinished) info.outputData else info.progress
        result.success(
            mapOf(
                "state" to info.state.toNativeState(),
                "bytesDownloaded" to data.getLong(AriamiDownloadWorker.KEY_BYTES_DOWNLOADED, 0L),
                "totalBytes" to data.getLong(AriamiDownloadWorker.KEY_TOTAL_BYTES, 0L),
                "errorMessage" to data.getString(AriamiDownloadWorker.KEY_ERROR_MESSAGE)
            )
        )
    }

    private fun cancelDownload(call: MethodCall, result: MethodChannel.Result) {
        val taskId = call.argument<String>("taskId")
        if (taskId.isNullOrBlank()) {
            result.error("invalid_args", "Missing taskId", null)
            return
        }
        workManager.cancelUniqueWork(taskId)
        result.success(null)
    }

    private fun WorkInfo.State.toNativeState(): String {
        return when (this) {
            WorkInfo.State.ENQUEUED -> "enqueued"
            WorkInfo.State.RUNNING -> "running"
            WorkInfo.State.SUCCEEDED -> "completed"
            WorkInfo.State.FAILED -> "failed"
            WorkInfo.State.BLOCKED -> "paused"
            WorkInfo.State.CANCELLED -> "cancelled"
        }
    }
}
