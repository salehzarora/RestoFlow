package com.restoflow.pos

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * One bounded double chime for the foreground POS inbox. Dart owns the single
 * repeating cadence; this transport cannot run a background notification loop.
 * Uses notification volume, never changes volume/ringer/DND or requests policy
 * access. Any DND mode (including priority/unknown) suppresses this chime.
 */
internal class OnlineOrderAlertAudioChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) {
    private val channel = MethodChannel(messenger, "restoflow.pos/online_order_alert")
    private val handler = Handler(Looper.getMainLooper())
    private var generator: ToneGenerator? = null
    private var foreground = false
    private var detached = false
    private var receiverRegistered = false

    private val policyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (!mayPlay()) stop()
        }
    }

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "play" -> play()
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
        foreground = value
        if (!value) stop()
    }

    private fun mayPlay(): Boolean {
        if (detached || !foreground) return false
        return try {
            val audio = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                ?: return false
            if (audio.ringerMode != AudioManager.RINGER_MODE_NORMAL ||
                audio.getStreamVolume(AudioManager.STREAM_NOTIFICATION) == 0
            ) return false
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val notifications = context.getSystemService(Context.NOTIFICATION_SERVICE)
                    as? NotificationManager ?: return false
                if (notifications.currentInterruptionFilter != NotificationManager.INTERRUPTION_FILTER_ALL) {
                    return false
                }
            }
            true
        } catch (_: Exception) {
            // Includes SecurityException: fail silent without broader permissions.
            false
        }
    }

    private fun play() {
        if (generator != null || !mayPlay()) return
        try {
            val tone = ToneGenerator(AudioManager.STREAM_NOTIFICATION, 80)
            generator = tone
            if (!tone.startTone(ToneGenerator.TONE_PROP_BEEP, 160)) {
                stop()
                return
            }
            handler.postDelayed({
                if (generator !== tone || !mayPlay()) {
                    stop()
                } else {
                    try {
                        if (!tone.startTone(ToneGenerator.TONE_PROP_BEEP, 160)) stop()
                    } catch (_: Exception) {
                        stop()
                    }
                }
            }, 240L)
            handler.postDelayed({ stop() }, 450L)
        } catch (_: Exception) {
            stop()
        }
    }

    fun stop() {
        handler.removeCallbacksAndMessages(null)
        val tone = generator
        generator = null
        try {
            tone?.stopTone()
        } catch (_: Exception) {
            // Cleanup is best-effort even if Android already invalidated audio.
        }
        try {
            tone?.release()
        } catch (_: Exception) {
            // No native error may escape the channel or Activity lifecycle.
        }
    }

    fun detach() {
        if (detached) return
        detached = true
        foreground = false
        stop()
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
