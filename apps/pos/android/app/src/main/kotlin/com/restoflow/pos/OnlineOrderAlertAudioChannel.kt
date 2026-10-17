package com.restoflow.pos

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioManager
import android.os.Build
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Foreground method-channel transport. The process singleton owns the one clip
 * across the unchanged Dart cadence and an explicitly enabled background handoff.
 * Uses notification volume, never changes volume/ringer/DND or requests policy
 * access. Any DND mode (including priority/unknown) suppresses this alert.
 */
internal class OnlineOrderAlertAudioChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) {
    private val channel = MethodChannel(messenger, "restoflow.pos/online_order_alert")
    private var detached = false
    private var receiverRegistered = false
    private val coordinator = BackgroundOrderAlertCoordinator.get(context)

    private val policyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            coordinator.policyChanged()
        }
    }

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "play" -> coordinator.playForeground()
                "stop", "dispose" -> stop()
                else -> {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
            }
            result.success(null)
        }
        try {
            val filter = IntentFilter(AudioManager.RINGER_MODE_CHANGED_ACTION)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                filter.addAction(NotificationManager.ACTION_INTERRUPTION_FILTER_CHANGED)
            }
            ContextCompat.registerReceiver(
                context,
                policyReceiver,
                filter,
                ContextCompat.RECEIVER_NOT_EXPORTED,
            )
            receiverRegistered = true
        } catch (_: Exception) {
            // Each play still checks current policy if broadcasts are unavailable.
        }
    }

    fun setForeground(value: Boolean) {
        coordinator.foreground(value)
    }

    fun stop() {
        coordinator.stopForeground()
    }

    fun detach() {
        if (detached) return
        detached = true
        coordinator.stopForeground()
        channel.setMethodCallHandler(null)
        if (receiverRegistered) {
            receiverRegistered = false
            try {
                context.unregisterReceiver(policyReceiver)
            } catch (_: Exception) {
                // Activity/engine teardown may already have unregistered it.
            }
        }
    }
}
