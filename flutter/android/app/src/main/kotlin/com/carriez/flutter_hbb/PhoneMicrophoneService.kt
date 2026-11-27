package com.carriez.flutter_hbb

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.ResultReceiver

class PhoneMicrophoneService : Service() {
    companion object { const val READY = "rustdesk.phoneMicrophoneReady" }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            val channel = "phone_microphone"
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(channel, "Phone microphone", NotificationManager.IMPORTANCE_LOW)
            )
            Notification.Builder(this, channel)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        packageManager.getLaunchIntentForPackage(packageName)?.let { launch ->
            builder.setContentIntent(PendingIntent.getActivity(this, 4317, launch,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
        }
        val notification = builder.setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle(applicationInfo.loadLabel(packageManager))
            .setContentText("Phone microphone session")
            .setOngoing(true)
            .build()
        @Suppress("DEPRECATION")
        val ready = intent?.getParcelableExtra<ResultReceiver>(READY)
        try {
            if (Build.VERSION.SDK_INT >= 30) {
                startForeground(4317, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
            } else {
                startForeground(4317, notification)
            }
            ready?.send(Activity.RESULT_OK, null)
        } catch (error: RuntimeException) {
            ready?.send(Activity.RESULT_CANCELED, null)
            stopSelfResult(startId)
        }
        return START_NOT_STICKY
    }
}
