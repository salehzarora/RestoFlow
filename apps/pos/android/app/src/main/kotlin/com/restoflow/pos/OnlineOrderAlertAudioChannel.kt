package com.restoflow.pos

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * One bundled, bounded clip for the foreground POS inbox. Dart owns the single
 * repeating cadence; this transport cannot run a background notification loop.
 * Uses notification volume, never changes volume/ringer/DND or requests policy
 * access. Any DND mode (including priority/unknown) suppresses this alert.
 */
internal class OnlineOrderAlertAudioChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) {
    private val channel = MethodChannel(messenger, "restoflow.pos/online_order_alert")
    private val handler = Handler(Looper.getMainLooper())
    private var detached = false
    private var receiverRegistered = false
    private val playback = OnlineOrderAlertPlayback(
        createClip = { BundledAlertClip(context) },
        policyAllowsPlayback = { policyAllowsPlayback() },
        scheduleTimeout = { delay, action ->
            val task = Runnable { action() }
            handler.postDelayed(task, delay)
            val cancel: () -> Unit = { handler.removeCallbacks(task) }
            cancel
        },
    )

    private val policyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            playback.policyChanged()
        }
    }

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "play" -> playback.play()
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
        playback.setForeground(value)
    }

    private fun policyAllowsPlayback(): Boolean {
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

    fun stop() {
        playback.stop()
    }

    fun detach() {
        if (detached) return
        detached = true
        playback.detach()
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

/** Android decoder adapter; no network, looping, volume changes or audio focus. */
private class BundledAlertClip(context: Context) : OnlineOrderAlertPlayback.Clip {
    private val player = MediaPlayer()

    init {
        try {
            player.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            player.isLooping = false
            context.resources.openRawResourceFd(R.raw.bizbot_online_order_alert).use { asset ->
                player.setDataSource(asset.fileDescriptor, asset.startOffset, asset.length)
            }
        } catch (error: Exception) {
            player.release()
            throw error
        }
    }

    override fun prepare(onReady: () -> Unit, onFinished: () -> Unit, onError: () -> Unit) {
        player.setOnPreparedListener { onReady() }
        player.setOnCompletionListener { onFinished() }
        player.setOnErrorListener { _, _, _ ->
            onError()
            true // Handled, including release; no second completion cleanup.
        }
        player.prepareAsync()
    }

    override fun start() = player.start()
    override fun stop() = player.stop()
    override fun release() = player.release()
}
