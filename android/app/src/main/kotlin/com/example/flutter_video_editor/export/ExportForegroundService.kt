package com.example.flutter_video_editor.export

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat

/**
 * Keeps the export alive while the app is in the background.
 * Controlled only through intents (see companion helpers) – no Binder needed.
 */
class ExportForegroundService : Service() {

    private var isForeground = false
    private var lastProgress = -1
    private var lastStage = ""
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        val progress = (intent?.getIntExtra(EXTRA_PROGRESS, 0) ?: 0).coerceIn(0, 100)
        val stage = intent?.getStringExtra(EXTRA_STAGE) ?: "Processing video clips and effects..."

        // A service started with startForegroundService() MUST call startForeground()
        // within ~5 seconds, whatever the action is, otherwise the app crashes.
        if (!isForeground) {
            enterForeground(buildProgressNotification(progress, stage))
        }

        when (action) {
            ACTION_CANCEL -> cancelHandler?.invoke()

            ACTION_STOP -> shutdown(removeNotification = true)

            ACTION_FINISH -> {
                val ok = intent.getBooleanExtra(EXTRA_SUCCESS, true)
                val msg = intent.getStringExtra(EXTRA_STAGE) ?: if (ok) "Export complete" else "Export failed"
                shutdown(removeNotification = true)
                showResultNotification(ok, msg)
            }

            else -> { // ACTION_START / ACTION_PROGRESS
                acquireWakeLock()
                if (progress != lastProgress || stage != lastStage) {
                    lastProgress = progress
                    lastStage = stage
                    notificationManager().notify(NOTIFICATION_ID, buildProgressNotification(progress, stage))
                }
            }
        }
        return START_NOT_STICKY
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        try {
            cancelHandler?.invoke()
            shutdown(removeNotification = true)
        } catch (_: Exception) {}
    }

    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }

    // ---------------------------------------------------------------------------------------

    private fun enterForeground(n: android.app.Notification) {
        val type = when {
            Build.VERSION.SDK_INT >= 35 -> ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROCESSING
            Build.VERSION.SDK_INT >= 29 -> ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            else -> 0
        }
        try {
            ServiceCompat.startForeground(this, NOTIFICATION_ID, n, type)
            isForeground = true
        } catch (_: Exception) {
            // Not allowed to run as foreground right now: export still runs, just without protection.
            stopSelf()
        }
    }

    private fun shutdown(removeNotification: Boolean) {
        releaseWakeLock()
        if (isForeground) {
            ServiceCompat.stopForeground(
                this,
                if (removeNotification) ServiceCompat.STOP_FOREGROUND_REMOVE else ServiceCompat.STOP_FOREGROUND_DETACH
            )
            isForeground = false
        }
        stopSelf()
    }

    private fun buildProgressNotification(progress: Int, stage: String) =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(if (progress > 0) "Rendering Video ($progress%)" else "Rendering Video")
            .setContentText(stage)
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setProgress(100, progress, progress <= 0)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setContentIntent(openAppIntent())
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Cancel",
                PendingIntent.getService(
                    this, 1,
                    Intent(this, ExportForegroundService::class.java).setAction(ACTION_CANCEL),
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                )
            )
            .build()

    private fun showResultNotification(success: Boolean, message: String) {
        val n = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(if (success) "Export finished" else "Export failed")
            .setContentText(message)
            .setSmallIcon(if (success) android.R.drawable.stat_sys_download_done else android.R.drawable.stat_notify_error)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setContentIntent(openAppIntent())
            .build()
        notificationManager().notify(RESULT_NOTIFICATION_ID, n)
    }

    private fun openAppIntent(): PendingIntent? {
        val launch = packageManager.getLaunchIntentForPackage(packageName) ?: return null
        return PendingIntent.getActivity(this, 0, launch, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "MotionGr:export").apply {
            setReferenceCounted(false)
            acquire(2 * 60 * 60 * 1000L) // safety timeout: 2 hours
        }
    }

    private fun releaseWakeLock() {
        try { if (wakeLock?.isHeld == true) wakeLock?.release() } catch (_: Exception) {}
        wakeLock = null
    }

    private fun notificationManager() = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notificationManager().createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Video Export Service", NotificationManager.IMPORTANCE_LOW)
            )
        }
    }

    // ---------------------------------------------------------------------------------------

    companion object {
        const val CHANNEL_ID = "export_channel"
        const val NOTIFICATION_ID = 1001
        private const val RESULT_NOTIFICATION_ID = 1002

        private const val ACTION_START = "motiongr.export.START"
        private const val ACTION_PROGRESS = "motiongr.export.PROGRESS"
        private const val ACTION_FINISH = "motiongr.export.FINISH"
        private const val ACTION_STOP = "motiongr.export.STOP"
        private const val ACTION_CANCEL = "motiongr.export.CANCEL"

        private const val EXTRA_PROGRESS = "progress"
        private const val EXTRA_STAGE = "stage"
        private const val EXTRA_SUCCESS = "success"

        /** Set by ExportPlugin; invoked when the user taps "Cancel" in the notification. */
        @Volatile
        var cancelHandler: (() -> Unit)? = null

        fun start(ctx: Context) = send(ctx, ACTION_START, 0, "Preparing export...")

        fun progress(ctx: Context, percent: Int, stage: String) = send(ctx, ACTION_PROGRESS, percent, stage)

        fun finish(ctx: Context, success: Boolean, message: String) =
            send(ctx, ACTION_FINISH, 100, message) { putExtra(EXTRA_SUCCESS, success) }

        /** Silent stop, no result notification (cancel / engine detached). */
        fun stop(ctx: Context) = send(ctx, ACTION_STOP, 0, "")

        private fun send(
            ctx: Context,
            action: String,
            percent: Int,
            stage: String,
            extra: Intent.() -> Unit = {}
        ) {
            try {
                val i = Intent(ctx, ExportForegroundService::class.java).setAction(action)
                    .putExtra(EXTRA_PROGRESS, percent)
                    .putExtra(EXTRA_STAGE, stage)
                i.extra()
                ContextCompat.startForegroundService(ctx, i)
            } catch (_: Exception) {
                // e.g. background start restriction – export continues without the service
            }
        }
    }
}