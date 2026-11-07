package com.restoflow.pos

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.common.GoogleApiAvailabilityLight
import com.google.firebase.FirebaseApp

/** Inspects OS readiness only; never initializes Firebase or reads notification authority. */
internal object BackgroundOrderAlertActivationStatus {
    private fun <T> read(block: () -> T): T? = try { block() } catch (_: Exception) { null }

    fun snapshot(context: Context): Map<String, Any?> {
        val sdk = Build.VERSION.SDK_INT
        val version = read { context.packageManager.getPackageInfo(context.packageName, 0).versionName }
        val permission = read { sdk < 33 || ContextCompat.checkSelfPermission(context,
            Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED }
        val notifications = read { NotificationManagerCompat.from(context).areNotificationsEnabled() }
        // Before API 26 channel checks do not exist. A missing channel is distinct from
        // a failed lookup; importance/sound remain unchecked when there is no channel.
        var present: Boolean? = null
        var importance: Boolean? = null
        var sound: Boolean? = null
        if (sdk >= 26) {
            read {
                val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                val channel = manager.getNotificationChannel(BackgroundOrderAlertCoordinator.CHANNEL_ID)
                present = channel != null
                if (channel != null) {
                    importance = channel.importance >= NotificationManager.IMPORTANCE_HIGH
                    sound = channel.sound != null
                }
            }
        }
        return BackgroundOrderAlertReadiness.snapshot(version, sdk, Build.MODEL, permission,
            notifications, present, importance, sound,
            read { FirebaseApp.getApps(context).isNotEmpty() },
            read { GoogleApiAvailabilityLight.getInstance().isGooglePlayServicesAvailable(context) })
    }

    /** Only an explicit UI action opens this app's settings; it never changes a setting. */
    fun openSettings(activity: Activity, channel: Boolean): Boolean = try {
        val intent = if (Build.VERSION.SDK_INT >= 26) {
            Intent(if (channel) Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS
                else Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
                if (channel) putExtra(Settings.EXTRA_CHANNEL_ID, BackgroundOrderAlertCoordinator.CHANNEL_ID)
            }
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.fromParts("package", activity.packageName, null))
        }
        activity.startActivity(intent)
        true
    } catch (_: Exception) { false }
}
