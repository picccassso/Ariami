package app.ariami.mobile

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Holds the single foreground-service slot for a batch of downloads.
 *
 * Download workers themselves run as plain WorkManager jobs while this
 * service is active; it owns the one persistent "Downloading songs"
 * notification (updated from the Dart queue state), so per-song worker
 * completions can't dismiss and re-post it — that flicker was the problem
 * with tying the notification to individual workers.
 */
class AriamiDownloadNotificationService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                isForegroundActive = false
                stopForeground(STOP_FOREGROUND_REMOVE)
                val completionText = intent.getStringExtra(EXTRA_COMPLETION_TEXT)
                if (!completionText.isNullOrBlank()) {
                    postCompletionNotification(this, completionText)
                }
                stopSelf()
            }
            else -> {
                val notification = buildNotification(
                    this,
                    intent?.getStringExtra(EXTRA_TEXT) ?: "Downloading songs",
                    intent?.getIntExtra(EXTRA_PROGRESS_PERCENT, -1) ?: -1
                )
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    startForeground(
                        NOTIFICATION_ID,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                    )
                } else {
                    startForeground(NOTIFICATION_ID, notification)
                }
                isForegroundActive = true
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        isForegroundActive = false
        super.onDestroy()
    }

    companion object {
        /** True while the batch notification service holds the foreground slot.
         * Download workers check this to skip their own foreground promotion. */
        @Volatile
        var isForegroundActive = false
            private set

        const val NOTIFICATION_ID = 24000
        private const val COMPLETION_NOTIFICATION_ID = 24002
        private const val CHANNEL_ID = "ariami_downloads"
        private const val ACTION_STOP = "app.ariami.mobile.action.STOP_BATCH"
        private const val EXTRA_TEXT = "text"
        private const val EXTRA_PROGRESS_PERCENT = "progressPercent"
        private const val EXTRA_COMPLETION_TEXT = "completionText"

        /** Starts the foreground service. Returns false when the OS rejects
         * the start (e.g. Android 12+ background-start restriction). */
        fun start(context: Context, text: String, progressPercent: Int): Boolean {
            val intent = Intent(context, AriamiDownloadNotificationService::class.java)
                .putExtra(EXTRA_TEXT, text)
                .putExtra(EXTRA_PROGRESS_PERCENT, progressPercent)
            return try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                true
            } catch (_: Exception) {
                false
            }
        }

        /** Updates the notification content without another service start. */
        fun update(context: Context, text: String, progressPercent: Int) {
            if (!isForegroundActive) return
            try {
                val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                manager.notify(NOTIFICATION_ID, buildNotification(context, text, progressPercent))
            } catch (_: Exception) {
                // Missing notification permission — service keeps running silently.
            }
        }

        fun stop(context: Context, completionText: String?) {
            val intent = Intent(context, AriamiDownloadNotificationService::class.java)
                .setAction(ACTION_STOP)
                .putExtra(EXTRA_COMPLETION_TEXT, completionText)
            try {
                context.startService(intent)
            } catch (_: Exception) {
                // Service already gone; nothing to stop.
            }
        }

        private fun buildNotification(
            context: Context,
            text: String,
            progressPercent: Int
        ): android.app.Notification {
            createNotificationChannel(context)
            return NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle("Downloading songs")
                .setContentText(text)
                .setContentIntent(launchAppIntent(context))
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setProgress(100, progressPercent.coerceIn(0, 100), progressPercent < 0)
                .build()
        }

        private fun postCompletionNotification(context: Context, text: String) {
            try {
                val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                val notification = NotificationCompat.Builder(context, CHANNEL_ID)
                    .setSmallIcon(R.drawable.ic_notification)
                    .setContentTitle("Downloads complete")
                    .setContentText(text)
                    .setContentIntent(launchAppIntent(context))
                    .setAutoCancel(true)
                    .build()
                manager.notify(COMPLETION_NOTIFICATION_ID, notification)
            } catch (_: Exception) {
                // Missing notification permission.
            }
        }

        private fun launchAppIntent(context: Context): PendingIntent? {
            val launchIntent = context.packageManager
                .getLaunchIntentForPackage(context.packageName) ?: return null
            return PendingIntent.getActivity(
                context,
                0,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        private fun createNotificationChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (manager.getNotificationChannel(CHANNEL_ID) != null) return
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Downloads",
                    NotificationManager.IMPORTANCE_LOW
                )
            )
        }
    }
}
