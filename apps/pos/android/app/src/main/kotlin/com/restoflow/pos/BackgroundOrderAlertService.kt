package com.restoflow.pos

import android.app.Service
import android.content.BroadcastReceiver
import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/** No boot restart, sticky restart, exact alarm, printer or Flutter engine. */
class BackgroundOrderAlertService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    private var verifiedWake = false
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!BuildConfig.BIZBOT_BACKGROUND_ORDER_ALERTS) { stopSelf(); return START_NOT_STICKY }
        val coordinator = BackgroundOrderAlertCoordinator.get(this)
        return try {
            val notification = coordinator.notification(true)
            if (Build.VERSION.SDK_INT >= 34) startForeground(BackgroundOrderAlertCoordinator.NOTIFICATION_ID,
                notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            else startForeground(BackgroundOrderAlertCoordinator.NOTIFICATION_ID, notification)
            verificationAwake()
            coordinator.serviceStarted(this)
            START_NOT_STICKY
        } catch (_: Exception) { coordinator.serviceStartRefused(); stopSelf(); START_NOT_STICKY }
    }

    internal fun keepAwake() {
        if (verifiedWake) return
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
            wakeLock = (getSystemService(Context.POWER_SERVICE) as PowerManager)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "$packageName:pickup-alert").apply {
                    setReferenceCounted(false)
                    acquire(BackgroundOrderAlertState.HARD_TIMEOUT_MS)
                }
            verifiedWake = true
        } catch (_: Exception) { /* OEM/battery policy can still delay audio; no delivery guarantee. */ }
    }

    private fun verificationAwake() {
        if (wakeLock?.isHeld == true) return
        try {
            wakeLock = (getSystemService(Context.POWER_SERVICE) as PowerManager)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "$packageName:pickup-verification").apply {
                    setReferenceCounted(false)
                    acquire(20_000L)
                }
        } catch (_: Exception) { }
    }

    override fun onDestroy() {
        BackgroundOrderAlertCoordinator.get(this).serviceDestroyed(this)
        try { if (wakeLock?.isHeld == true) wakeLock?.release() } catch (_: Exception) { }
        wakeLock = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }
}

class BackgroundOrderAlertMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        // Token is retrieved afresh by an authenticated foreground prepare; never logged or passed in an Intent.
        if (BuildConfig.BIZBOT_BACKGROUND_ORDER_ALERTS) BackgroundOrderAlertCoordinator.get(this).tokenChanged()
    }

    override fun onMessageReceived(message: RemoteMessage) {
        if (!BuildConfig.BIZBOT_BACKGROUND_ORDER_ALERTS) return
        BackgroundOrderAlertCoordinator.get(this).hint(message.data, message.priority == RemoteMessage.PRIORITY_HIGH)
    }
}

class BackgroundOrderAlertStopReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action == BackgroundOrderAlertCoordinator.STOP_ALERTS) BackgroundOrderAlertCoordinator.get(context).disable()
    }
}

/** Programmatic public Firebase options, no google-services.json or Google Services Gradle plugin. */
class BackgroundOrderAlertInitProvider : ContentProvider() {
    override fun onCreate(): Boolean { context?.let { BackgroundOrderAlertCoordinator.initializeFirebase(it) }; return true }
    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): Cursor? = null
    override fun getType(uri: Uri): String? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = 0
}
