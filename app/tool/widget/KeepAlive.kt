package com.mttlhub.mttl_hub

import android.app.Notification
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
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** Keeps the process alive while an update downloads/uploads with the app in the background, with a progress notification. */
class KeepAliveService : Service() {
    private var lock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra("title") ?: "Fisha"
        val text = intent?.getStringExtra("text") ?: ""
        val n = KeepAlive.progressNotification(this, title, text, -1)
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(KeepAlive.ID_PROGRESS, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(KeepAlive.ID_PROGRESS, n)
        }
        if (lock == null) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            lock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "fisha:update")
            lock?.acquire(30 * 60 * 1000L)
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        try { if (lock?.isHeld == true) lock?.release() } catch (e: Exception) {}
        lock = null
        super.onDestroy()
    }
}

object KeepAlive {
    const val ID_PROGRESS = 4712
    const val ID_DONE = 4713
    private const val CH_PROGRESS = "fisha_update"
    private const val CH_DONE = "fisha_update_done"

    private fun channels(ctx: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(NotificationChannel(CH_PROGRESS, "Fisha update", NotificationManager.IMPORTANCE_LOW))
        nm.createNotificationChannel(NotificationChannel(CH_DONE, "Fisha update ready", NotificationManager.IMPORTANCE_HIGH))
    }

    private fun builder(ctx: Context, channel: String): Notification.Builder =
        if (Build.VERSION.SDK_INT >= 26) Notification.Builder(ctx, channel) else Notification.Builder(ctx)

    fun progressNotification(ctx: Context, title: String, text: String, pct: Int): Notification {
        channels(ctx)
        val open = PendingIntent.getActivity(ctx, 0, Intent(ctx, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val b = builder(ctx, CH_PROGRESS)
            .setSmallIcon(ctx.applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(open)
        if (pct in 0..100) b.setProgress(100, pct, false) else b.setProgress(0, 0, true)
        return b.build()
    }

    fun handle(ctx: Context, call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "start" -> {
                    val i = Intent(ctx, KeepAliveService::class.java)
                    i.putExtra("title", call.argument<String>("title") ?: "Fisha")
                    i.putExtra("text", call.argument<String>("text") ?: "")
                    if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(i) else ctx.startService(i)
                    result.success(true)
                }
                "progress" -> {
                    val pct = call.argument<Int>("pct") ?: -1
                    val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    nm.notify(ID_PROGRESS, progressNotification(ctx, call.argument<String>("title") ?: "Fisha", call.argument<String>("text") ?: "", pct))
                    result.success(true)
                }
                "stop" -> {
                    ctx.stopService(Intent(ctx, KeepAliveService::class.java))
                    result.success(true)
                }
                "installReady" -> {
                    // the app is in the background: Android won't let it open the installer by itself, so a tap on this does
                    val path = call.argument<String>("path") ?: ""
                    val file = File(path)
                    val uri = FileProvider.getUriForFile(ctx, ctx.packageName + ".fileProvider.com.crazecoder.openfile", file)
                    val i = Intent(Intent.ACTION_VIEW)
                    i.setDataAndType(uri, "application/vnd.android.package-archive")
                    i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                    val pi = PendingIntent.getActivity(ctx, 1, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                    channels(ctx)
                    val n = builder(ctx, CH_DONE)
                        .setSmallIcon(ctx.applicationInfo.icon)
                        .setContentTitle(call.argument<String>("title") ?: "Fisha")
                        .setContentText(call.argument<String>("text") ?: "")
                        .setContentIntent(pi)
                        .setAutoCancel(true)
                        .build()
                    val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    nm.notify(ID_DONE, n)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.success(false)
        }
    }
}
