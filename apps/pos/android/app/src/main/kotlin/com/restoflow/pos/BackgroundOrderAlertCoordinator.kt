package com.restoflow.pos

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import androidx.core.content.ContextCompat
import androidx.core.app.NotificationCompat
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.security.SecureRandom
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import java.util.concurrent.atomic.AtomicLong
import com.restoflow.pos.BackgroundOrderAlertObservation.Event as AlertEvent
import com.restoflow.pos.BackgroundOrderAlertObservation.Result as AlertResult
import com.restoflow.pos.BackgroundOrderAlertObservation.Authority as AlertAuthority
import com.restoflow.pos.BackgroundOrderAlertObservation.Kind as AlertKind
import com.restoflow.pos.BackgroundOrderAlertObservation.Channel as AlertChannel

/** Process singleton: foreground clip transport and bounded background coordinator share ownership. */
internal class BackgroundOrderAlertCoordinator private constructor(context: Context) {
    companion object {
        const val CHANNEL_ID = "bizbot_pickup_requests_v1"
        const val NOTIFICATION_ID = 38101
        const val FALLBACK_NOTIFICATION_ID = 38103
        const val OPEN_INBOX = "com.restoflow.pos.OPEN_ONLINE_INBOX"
        const val STOP_ALERTS = "com.restoflow.pos.STOP_ONLINE_ALERTS"
        private var instance: BackgroundOrderAlertCoordinator? = null
        private val observationSequence = AtomicLong()
        // This sink accepts only a closed vocabulary, booleans and bounded counters.
        // Never pass a message/response/exception object or a credential to logging.
        internal fun observe(event: AlertEvent, result: AlertResult, kind: AlertKind? = null,
            high: Boolean? = null, authority: AlertAuthority? = null, channel: AlertChannel? = null, foreground: Boolean? = null,
            pendingCount: Int? = null, read: Long? = null) {
            try {
                Log.i("BizbotAlertState", BackgroundOrderAlertObservation.encode(event, result,
                    observationSequence.incrementAndGet(), System.currentTimeMillis(), SystemClock.elapsedRealtime(),
                    kind, high, authority, channel, foreground, pendingCount, read))
            } catch (_: Exception) { /* Observation cannot fail normal notification work. */ }
        }
        @Synchronized fun get(context: Context): BackgroundOrderAlertCoordinator =
            instance ?: BackgroundOrderAlertCoordinator(context.applicationContext).also { instance = it }

        fun initializeFirebase(context: Context): Boolean {
            if (!BuildConfig.BIZBOT_BACKGROUND_ORDER_ALERTS) return false
            if (listOf(BuildConfig.BIZBOT_FIREBASE_APP_ID, BuildConfig.BIZBOT_FIREBASE_API_KEY,
                    BuildConfig.BIZBOT_FIREBASE_PROJECT_ID, BuildConfig.BIZBOT_FIREBASE_SENDER_ID).any { it.isBlank() }) return false
            return try {
                if (FirebaseApp.getApps(context).isEmpty()) FirebaseApp.initializeApp(context,
                    FirebaseOptions.Builder().setApplicationId(BuildConfig.BIZBOT_FIREBASE_APP_ID)
                        .setApiKey(BuildConfig.BIZBOT_FIREBASE_API_KEY).setProjectId(BuildConfig.BIZBOT_FIREBASE_PROJECT_ID)
                        .setGcmSenderId(BuildConfig.BIZBOT_FIREBASE_SENDER_ID).build())
                true
            } catch (_: Exception) { false }
        }
    }

    private val context = context.applicationContext
    private val handler = Handler(Looper.getMainLooper())
    private val network = Executors.newSingleThreadExecutor()
    private val vault = BackgroundOrderAlertVault(context)
    private val state = BackgroundOrderAlertState()
    private val ownership = BackgroundOrderAlertOwnership()
    private val hints = BackgroundOrderAlertHints()
    private var record = vault.read() ?: JSONObject()
    private val optIn = BackgroundOrderAlertOptIn(record.optBoolean("opt_in"))
    private val generation: Long get() = ownership.generation
    private val foreground: Boolean get() = ownership.foreground
    private var channel: MethodChannel? = null
    private var service: BackgroundOrderAlertService? = null
    private var pendingInboxTap = false
    private var visibilityEpoch = 0L
    private var fallbackWanted = false
    private var readSequence = 0L
    private val fallbackJobs = BackgroundOrderAlertJobOwnership()
    private val tokenLane = BackgroundOrderAlertTokenLane()
    // Visibility expiry must not invalidate an authenticated read already in flight for B.
    private val expireFallback = Runnable { notifications().cancel(FALLBACK_NOTIFICATION_ID) }
    private val reconciliation = BackgroundOrderAlertReconciliation(
        now = { SystemClock.elapsedRealtime() },
        schedule = { delay, action ->
            val task = Runnable { action() }
            handler.postDelayed(task, delay)
            val cancel: () -> Unit = { handler.removeCallbacks(task) }
            cancel
        },
        eligible = { !foreground && (service != null || fallbackWanted) && authorityValid() },
        keepPolling = { service != null && state.active(SystemClock.elapsedRealtime()) },
        read = { readStatus(it) },
        failClosed = { result -> observe(AlertEvent.STATUS_COMPLETE, result); state.clear(); stopBackground(result) },
    )
    private val playback = OnlineOrderAlertPlayback(
        createClip = { BackgroundAlertClip(context) },
        policyAllowsPlayback = { audioAllowed() },
        scheduleTimeout = { delay, action ->
            val task = Runnable { action() }
            handler.postDelayed(task, delay)
            val cancel: () -> Unit = { handler.removeCallbacks(task) }
            cancel
        },
    )

    private val tick = object : Runnable {
        override fun run() {
            if (foreground || service == null) return
            val now = SystemClock.elapsedRealtime()
            if (!authorityValid() || !state.active(now) || !audioAllowed()) {
                stopBackground()
                return
            }
            if (state.shouldPlay(now)) {
                playShared()
                state.played(now)
            }
            service?.keepAwake()
            state.nextWake(now)?.let { handler.postDelayed(this, it) }
        }
    }

    private fun persist() = vault.write(record)
    private fun notifications(): NotificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    private fun permissionAllowed(): Boolean = Build.VERSION.SDK_INT < 33 ||
        ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    private fun channelPolicy(): BackgroundOrderAlertChannelPolicy? = try {
        val channel = if (Build.VERSION.SDK_INT >= 26) notifications().getNotificationChannel(CHANNEL_ID) else null
        BackgroundOrderAlertChannelPolicy(
            permissionAllowed(), notifications().areNotificationsEnabled(),
            Build.VERSION.SDK_INT < 26 || channel != null,
            Build.VERSION.SDK_INT < 26 || (channel?.importance ?: 0) >= NotificationManager.IMPORTANCE_HIGH,
            Build.VERSION.SDK_INT < 26 || channel?.sound != null,
        )
    } catch (_: Exception) { null }

    private fun channelAllowed(): Boolean = channelPolicy()?.let { it.failureReason == null } ?: false

    private fun channelState(): AlertChannel = channelPolicy()?.let {
        when (it.failureReason) {
            null -> AlertChannel.ALLOWED
            "permission_denied" -> AlertChannel.PERMISSION_DENIED
            "notifications_disabled" -> AlertChannel.NOTIFICATIONS_DISABLED
            "channel_missing" -> AlertChannel.MISSING
            "channel_importance_low" -> AlertChannel.LOW_IMPORTANCE
            "channel_sound_missing" -> AlertChannel.SOUND_MISSING
            else -> AlertChannel.UNKNOWN
        }
    } ?: AlertChannel.UNKNOWN

    private fun preparationResult(available: Boolean, enabled: Boolean, reason: String? = null,
        policy: BackgroundOrderAlertChannelPolicy? = null, firebaseInitialized: Boolean? = null,
        tokenAcquired: Boolean? = null): Map<String, Any?> {
        val diagnostics = mutableMapOf<String, Boolean>()
        policy?.let { diagnostics.putAll(it.diagnostics()) }
        firebaseInitialized?.let { diagnostics["firebase_initialized"] = it }
        tokenAcquired?.let { diagnostics["token_acquired"] = it }
        return mapOf("available" to available, "enabled" to enabled,
            "failure_reason" to reason, "diagnostics" to diagnostics)
    }

    fun permissionRefused(): Map<String, Any?> = preparationResult(true, false, "permission_denied", channelPolicy())

    private fun audioAllowed(): Boolean = try {
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audio.ringerMode == AudioManager.RINGER_MODE_NORMAL && audio.getStreamVolume(AudioManager.STREAM_NOTIFICATION) > 0 &&
            notifications().currentInterruptionFilter == NotificationManager.INTERRUPTION_FILTER_ALL &&
            (!BuildConfig.BIZBOT_BACKGROUND_ORDER_ALERTS || !optIn.enabled || channelAllowed())
    } catch (_: Exception) { false }

    fun createChannel() {
        if (Build.VERSION.SDK_INT < 26) return
        val attributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
        val sound = Uri.parse("android.resource://${context.packageName}/${R.raw.bizbot_online_order_alert}")
        notifications().createNotificationChannel(NotificationChannel(CHANNEL_ID,
            context.getString(R.string.background_order_channel), NotificationManager.IMPORTANCE_HIGH).apply {
            description = context.getString(R.string.background_order_channel_description)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            setSound(sound, attributes)
        })
    }

    fun attach(messenger: BinaryMessenger) {
        channel?.setMethodCallHandler(null)
        channel = MethodChannel(messenger, "restoflow.pos/background_order_alert")
    }

    fun detach() { channel?.setMethodCallHandler(null); channel = null }
    fun bridge(): MethodChannel? = channel

    fun prepare(activity: Activity, requestPermission: Boolean, callback: (Map<String, Any?>) -> Unit) {
        if (!initializeFirebase(context)) { callback(preparationResult(false, false, "firebase_unavailable", firebaseInitialized = false)); return }
        createChannel()
        val policy = channelPolicy()
        if (policy == null || policy.failureReason != null) {
            callback(preparationResult(true, false, policy?.failureReason ?: "native_unavailable", policy, true)); return
        }
        if (!optIn.prepare(requestPermission)) { callback(preparationResult(true, false, "opt_in_required", policy, true)); return }
        try {
            if (!record.has("installation_id")) record.put("installation_id", UUID.randomUUID().toString())
            if (!record.has("status_secret")) {
                val bytes = ByteArray(32).also { SecureRandom().nextBytes(it) }
                record.put("status_secret", bytes.joinToString("") { "%02x".format(it.toInt() and 255) })
            }
            record.put("enabled", true).put("opt_in", true)
            persist()
            tokenLane.prepare()
            FirebaseMessaging.getInstance().isAutoInitEnabled = true
            val expected = generation
            FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                if (expected != generation) {
                    callback(preparationResult(true, false, "preparation_cancelled", policy, true)); return@addOnCompleteListener
                }
                if (!record.optBoolean("enabled") || !task.isSuccessful || task.result.isNullOrBlank()) {
                    tokenLane.finishPreparation()
                    callback(preparationResult(true, false, "token_unavailable", policy, true, false)); return@addOnCompleteListener
                }
                callback(preparationResult(true, true, policy = policy, firebaseInitialized = true, tokenAcquired = true) + mapOf(
                    "installation_id" to record.getString("installation_id"), "fcm_token" to task.result,
                    "status_secret" to record.getString("status_secret"), "generation" to generation))
            }
        } catch (_: Exception) { clearAuthority(); callback(preparationResult(true, false, "native_unavailable", policy, true)) }
    }

    private fun exactEndpoint(value: String): Boolean = try {
        val configured = URI(BuildConfig.BIZBOT_SUPABASE_URL)
        val supplied = URI(value)
        configured.scheme == "https" && configured.host?.endsWith(".supabase.co") == true &&
            supplied.scheme == "https" && supplied.host == configured.host && supplied.port == -1 &&
            supplied.rawPath == "/functions/v1/pos-order-alert-status" && supplied.rawQuery == null &&
            supplied.rawFragment == null && supplied.rawUserInfo == null
    } catch (_: Exception) { false }

    fun bind(args: Map<*, *>): Boolean {
        val identity = args["identity"] as? String ?: return false
        val endpoint = args["endpoint"] as? String ?: return false
        val registration = args["registration_id"] as? String ?: return false
        val registrationGeneration = args["registration_generation"] as? String ?: return false
        val expires = parseTime(args["authority_expires_at"] as? String ?: return false) ?: return false
        if (!record.optBoolean("enabled") || !record.has("status_secret") || identity.isBlank() || identity.length > 512 ||
            (args["generation"] as? Number)?.toLong() != generation || !uuid(registration) ||
            !uuid(registrationGeneration) || !exactEndpoint(endpoint)) return false
        val remaining = expires - System.currentTimeMillis()
        if (remaining <= 0) return false
        // A fresh foreground bind supersedes every older native HTTP completion,
        // including a same-token renewal with a later genuine PIN deadline.
        tokenLane.finishPreparation()
        reconciliation.cancel()
        record.put("identity", identity).put("endpoint", endpoint).put("registration_id", registration)
            .put("registration_generation", registrationGeneration)
            .put("authority_deadline", SystemClock.elapsedRealtime() + remaining.coerceAtMost(8 * 60 * 60_000L))
            .put("boot_count", vault.bootCount())
        record.remove("token_refresh_unconfirmed")
        return try { persist(); true } catch (_: Exception) { clearAuthority(); false }
    }

    private fun authorityValid(): Boolean = authorityState() == AlertAuthority.VALID

    // Extra observation must not introduce a new Settings/vault failure on a stop path.
    private fun observedAuthority(): AlertAuthority? = try { authorityState() } catch (_: Exception) { null }

    // Same short-circuit order as the original guard. No vault contents leave this method.
    private fun authorityState(): AlertAuthority = when {
        !BuildConfig.BIZBOT_BACKGROUND_ORDER_ALERTS -> AlertAuthority.FEATURE_OFF
        !record.optBoolean("enabled") -> AlertAuthority.OPTED_OUT
        !record.has("registration_id") || !record.has("status_secret") -> AlertAuthority.BINDING_MISSING
        !exactEndpoint(record.optString("endpoint")) -> AlertAuthority.ENDPOINT_INVALID
        record.optInt("boot_count", -1) < 0 || record.optInt("boot_count", -1) != vault.bootCount() -> AlertAuthority.BOOT_CHANGED
        record.optLong("authority_deadline") <= SystemClock.elapsedRealtime() -> AlertAuthority.EXPIRED
        else -> AlertAuthority.VALID
    }

    fun pending(args: Map<*, *>): Boolean {
        if (!foreground || !authorityValid() || args["identity"] != record.optString("identity")) return false
        val serverTime = parseTime(args["server_time"] as? String ?: return false) ?: return false
        val requests = args["requests"] as? List<*> ?: return false
        val values = linkedMapOf<String, Long>()
        if (requests.size > 50) return false
        for (raw in requests) {
            val row = raw as? Map<*, *> ?: return false
            val id = row["request_id"] as? String ?: return false
            val expiry = parseTime(row["expires_at"] as? String ?: return false) ?: return false
            if (!uuid(id) || values.put(id, expiry) != null) return false
        }
        state.clear() // Foreground projection seeds a new bounded handoff; shared playback cadence remains retained.
        state.replace(values, serverTime, record.optLong("authority_deadline") - SystemClock.elapsedRealtime(), SystemClock.elapsedRealtime())
        return true
    }

    fun foreground(value: Boolean) {
        if (foreground == value) return
        ownership.setForeground(value)
        observe(AlertEvent.AUTHORITY, AlertResult.FOREGROUND, authority = observedAuthority(), foreground = value)
        visibilityEpoch++
        playback.setForeground(true) // Shared clip eligibility; audio policy and ownership remain independently fenced.
        if (value) {
            handler.removeCallbacks(tick)
            reconciliation.cancel()
            cancelFallback()
            service?.stopSelf()
            service = null
            playback.stop()
        } else {
            playback.stop()
            if (authorityValid() && state.active(SystemClock.elapsedRealtime()) && channelAllowed()) startBackground()
        }
    }

    fun playForeground() { if (foreground) playShared() }
    fun stopForeground() { if (foreground) playback.stop() }
    fun policyChanged() { playback.policyChanged(); if (!audioAllowed()) stopBackground() }
    private fun playShared() {
        val now = SystemClock.elapsedRealtime()
        if (!audioAllowed() || !ownership.reservePlayback(now)) return
        playback.setForeground(true)
        playback.play()
    }

    fun consumeTap(): Boolean = pendingInboxTap.also { pendingInboxTap = false }
    fun onIntent(intent: Intent?) { if (intent?.action == OPEN_INBOX) pendingInboxTap = true }

    fun clearAuthority(retainOptIn: Boolean = false) {
        tokenLane.finishPreparation()
        ownership.invalidate()
        state.clear()
        hints.clear()
        playback.stop()
        stopBackground()
        val install = record.optString("installation_id")
        optIn.clear(retainOptIn)
        record = JSONObject().apply {
            if (uuid(install)) put("installation_id", install)
            if (optIn.enabled) put("opt_in", true)
        }
        try { vault.clear(); if (record.length() > 0) persist() } catch (_: Exception) { /* No in-memory authority remains. */ }
    }

    fun disable() {
        val old = record.toString()
        clearAuthority()
        try { if (initializeFirebase(context)) FirebaseMessaging.getInstance().isAutoInitEnabled = false } catch (_: Exception) { }
        network.execute { try { request(JSONObject(old), true) } catch (_: Exception) { /* Local stop never waits on network. */ } }
    }

    fun tokenChanged(token: String) {
        handler.post {
            if (!BackgroundOrderAlertTokenRefresh.validToken(token)) return@post
            if (foreground || tokenLane.preparing) {
                // Keep the generation/status secret stable while a serialized
                // foreground prepare/bind may be in flight. That owner reads
                // the latest SDK token before registration; logout still revokes.
                channel?.invokeMethod("tokenChanged", null)
                return@post
            }
            if (!authorityValid()) {
                clearAuthority(true)
                channel?.invokeMethod("tokenChanged", null)
                return@post
            }
            tokenLane.offer(token, record.optString("registration_generation"),
                record.optBoolean("token_refresh_unconfirmed"))?.let { refreshToken(it) }
            // Also retain the latest SDK change for ordinary foreground
            // reconciliation if this process loses a response or is stopped.
            channel?.invokeMethod("tokenChanged", null)
        }
    }

    private fun refreshToken(work: BackgroundOrderAlertTokenLane.Work) {
        try {
            // A lost response/process must not recreate permission to write
            // another token against an unconfirmed server generation.
            record.put("token_refresh_unconfirmed", true)
            persist()
        } catch (_: Exception) {
            tokenLane.complete(work, null)
            clearAuthority(true)
            channel?.invokeMethod("tokenChanged", null)
            return
        }
        val expected = generation
        val startedAt = SystemClock.elapsedRealtime()
        val snapshot = JSONObject(record.toString())
        network.execute {
            var denied = false
            val response = try { request(snapshot, false, 3_000, work.token) }
                catch (_: AuthorityDenied) { denied = true; null } catch (_: Exception) { null }
            handler.post completion@ {
                if (expected != generation || !tokenLane.canComplete(work, record.optString("registration_generation")) ||
                    !authorityValid() || snapshot.optString("registration_id") != record.optString("registration_id")) return@completion
                if (foreground) {
                    // An old background denial must not cancel a foreground
                    // registration that has committed but has not bound yet.
                    tokenLane.complete(work, null)
                    channel?.invokeMethod("tokenChanged", null)
                    return@completion
                }
                var committedGeneration: String? = null
                if (denied) {
                    clearAuthority(true)
                } else if (response != null) {
                    try {
                        check(response.getBoolean("ok") &&
                            response.getString("registration_id") == record.getString("registration_id") &&
                            uuid(response.getString("generation")))
                        val serverTime = parseTime(response.getString("server_time")) ?: error("invalid time")
                        val expiry = parseTime(response.getString("authority_expires_at")) ?: error("invalid expiry")
                        val now = SystemClock.elapsedRealtime()
                        val remaining = BackgroundOrderAlertTokenRefresh.remaining(serverTime, expiry,
                            startedAt, now, record.getLong("authority_deadline")) ?: error("expired authority")
                        record.put("authority_deadline", now + remaining)
                            .put("registration_generation", response.getString("generation"))
                        record.remove("token_refresh_unconfirmed")
                        persist()
                        committedGeneration = response.getString("generation")
                    } catch (_: Exception) {
                        // Unknown writes block this lane until foreground
                        // reconciliation. Never send the next token with stale CAS.
                    }
                }
                tokenLane.complete(work, committedGeneration)?.let { refreshToken(it) }
                channel?.invokeMethod("tokenChanged", null)
            }
        }
    }

    fun hint(data: Map<String, String>, highPriority: Boolean) {
        BackgroundOrderAlertCallbackHandoff.run(
            post = { handler.post(it) }, fallback = { BackgroundOrderAlertJobService.enqueue(context) },
        ) handoff@ {
            val authority = authorityState()
            if (authority != AlertAuthority.VALID) {
                observe(AlertEvent.AUTHORITY, AlertResult.REFUSED, authority = authority, foreground = foreground)
                return@handoff
            }
            val accepted = hints.accept(data, record.optString("registration_id"), System.currentTimeMillis(), SystemClock.elapsedRealtime())
            observe(AlertEvent.HINT, if (accepted) AlertResult.ACCEPTED else AlertResult.REFUSED,
                authority = authority, channel = channelState(), foreground = foreground)
            if (!accepted) return@handoff
            // Cancellation is only a reason to read the FULL set, including when no FGS exists.
            if (!foreground && service == null && data["kind"] == "cancel") {
                fallbackNotification()
                return@handoff
            }
            when (backgroundOrderAlertHintAction(foreground, service != null, highPriority, channelAllowed())) {
                BackgroundOrderAlertHintAction.foreground -> channel?.invokeMethod("pendingHint", null)
                BackgroundOrderAlertHintAction.reconcile -> {
                    scheduleReconcile()
                }
                BackgroundOrderAlertHintAction.start -> startBackground()
                BackgroundOrderAlertHintAction.fallback -> fallbackNotification()
                BackgroundOrderAlertHintAction.none -> policyChanged()
            }
        }
    }

    fun messagesDeleted() {
        BackgroundOrderAlertCallbackHandoff.run(
            post = { handler.post(it) }, fallback = { BackgroundOrderAlertJobService.enqueue(context) },
        ) {
            if (foreground) channel?.invokeMethod("pendingHint", null)
            else fallbackNotification() // A lost hint grants no authority; read the full set.
        }
    }

    private fun startBackground() {
        if (!authorityValid() || !channelAllowed()) {
            observe(AlertEvent.FGS_REQUEST, AlertResult.REFUSED, authority = observedAuthority(), channel = channelState(), foreground = foreground)
            return
        }
        observe(AlertEvent.FGS_REQUEST, AlertResult.REQUESTED, authority = observedAuthority(), channel = channelState(), foreground = foreground)
        try {
            val intent = Intent(context, BackgroundOrderAlertService::class.java)
            ContextCompat.startForegroundService(context, intent)
        } catch (error: Exception) {
            // Includes Android 12+ ForegroundServiceStartNotAllowedException and permission failures.
            observe(AlertEvent.FGS_REQUEST, when {
                Build.VERSION.SDK_INT >= 31 && error is android.app.ForegroundServiceStartNotAllowedException -> AlertResult.START_DENIED
                error is SecurityException -> AlertResult.SECURITY_DENIED
                else -> AlertResult.FAILED
            })
            fallbackNotification()
            playback.stop()
        }
    }

    fun serviceStarted(value: BackgroundOrderAlertService) {
        observe(AlertEvent.FGS_START, AlertResult.STARTED, authority = observedAuthority(), foreground = foreground)
        if (foreground || !authorityValid() || !channelAllowed()) { value.stopSelf(); return }
        if (service === value) { scheduleReconcile(); return }
        service = value
        cancelFallback()
        state.clear()
        playback.setForeground(true)
        scheduleReconcile() // Fresh authenticated truth before any background clip, including handoff.
    }

    fun serviceStartRefused(result: AlertResult = AlertResult.REFUSED) { observe(AlertEvent.FGS_START, result); if (service == null) playback.stop(); fallbackNotification() }

    fun serviceDestroyed(value: BackgroundOrderAlertService) {
        if (service !== value) return
        service = null
        handler.removeCallbacks(tick)
        reconciliation.cancel()
        playback.stop()
    }

    private fun stopBackground(reason: AlertResult = AlertResult.STOPPED) {
        observe(AlertEvent.AUDIO_STOP_REQUEST, reason)
        handler.removeCallbacks(tick)
        reconciliation.cancel()
        service?.stopSelf()
        service = null
        playback.stop()
        notifications().cancel(NOTIFICATION_ID)
        cancelFallback()
    }

    private fun scheduleReconcile() {
        reconciliation.request()
    }

    private fun readStatus(work: BackgroundOrderAlertReconciliation.Read): () -> Unit {
        val ordinal = ++readSequence
        observe(AlertEvent.STATUS_BEGIN, AlertResult.ENTER, read = ordinal)
        val expected = generation
        val expectedVisibility = visibilityEpoch
        val expectedService = service
        val expectedJob = fallbackJobs.current
        val startedAt = SystemClock.elapsedRealtime()
        val snapshot = JSONObject(record.toString())
        val cancelled = AtomicBoolean(false)
        val connection = AtomicReference<HttpURLConnection?>(null)
        val future = network.submit {
            var denied = false
            val response = try {
                request(snapshot, false, if (expectedService == null) 3_000 else 7_000,
                    cancelled = { cancelled.get() }, opened = {
                        connection.set(it)
                        if (cancelled.get()) it.disconnect()
                    })
            } catch (_: AuthorityDenied) { denied = true; null } catch (_: Exception) { null }
            handler.post {
                val completed = reconciliation.complete(work) completion@ {
                    if (expected != generation || expectedVisibility != visibilityEpoch || foreground ||
                        service !== expectedService || (service == null && !fallbackWanted) || !authorityValid() ||
                        snapshot.optString("registration_id") != record.optString("registration_id")) {
                        if (!foreground && (service != null || fallbackWanted) && authorityValid()) scheduleReconcile()
                        observe(AlertEvent.STATUS_COMPLETE, AlertResult.STALE, read = ordinal)
                        return@completion
                    }
                    if (denied) { observe(AlertEvent.STATUS_COMPLETE, AlertResult.DENIED, read = ordinal); clearAuthority(); return@completion }
                    try {
                        check(response != null && response.getBoolean("ok"))
                        check(response.getString("registration_id") == record.optString("registration_id"))
                        val serverTime = parseTime(response.getString("server_time")) ?: error("invalid time")
                        val expiry = parseTime(response.getString("authority_expires_at")) ?: error("invalid expiry")
                        val array = response.getJSONArray("requests")
                        check(array.length() <= 50)
                        val values = linkedMapOf<String, Long>()
                        for (i in 0 until array.length()) {
                            val row = array.getJSONObject(i)
                            val id = row.getString("request_id")
                            val deadline = parseTime(row.getString("expires_at")) ?: error("invalid deadline")
                            check(uuid(id) && values.put(id, deadline) == null)
                        }
                        val conservativeServerNow = serverTime + (SystemClock.elapsedRealtime() - startedAt)
                        val remaining = minOf(expiry - conservativeServerNow, record.optLong("authority_deadline") - SystemClock.elapsedRealtime())
                        observe(AlertEvent.STATUS_COMPLETE, AlertResult.ACCEPTED, read = ordinal)
                        if (service == null) showVerifiedFallback(values, conservativeServerNow, remaining)
                        else {
                            state.replace(values, conservativeServerNow, remaining, SystemClock.elapsedRealtime())
                            observe(AlertEvent.PENDING_APPLIED, AlertResult.APPLIED,
                                pendingCount = state.count(SystemClock.elapsedRealtime()), read = ordinal)
                            handler.removeCallbacks(tick)
                            tick.run()
                        }
                    } catch (_: Exception) {
                        // Unknown state is not permission to continue ringing indefinitely.
                        val failure = AlertResult.UNAVAILABLE_OR_INVALID
                        observe(AlertEvent.STATUS_COMPLETE, failure, read = ordinal)
                        state.clear()
                        stopBackground(failure)
                    }
                }
                if (!completed) observe(AlertEvent.STATUS_COMPLETE, AlertResult.STALE, read = ordinal)
                if (expectedService == null && expectedJob != null && !reconciliation.hasWork) finishFallbackJob(expectedJob)
            }
        }
        return {
            cancelled.set(true)
            try { connection.get()?.disconnect() } catch (_: Exception) { }
            future.cancel(true)
        }
    }

    private fun request(snapshot: JSONObject, disable: Boolean, timeoutMs: Int = 7_000, token: String? = null,
        cancelled: () -> Boolean = { false }, opened: (HttpURLConnection) -> Unit = {}): JSONObject? {
        if (cancelled()) return null
        val endpoint = snapshot.optString("endpoint")
        if (!exactEndpoint(endpoint) || !snapshot.has("status_secret") || !uuid(snapshot.optString("installation_id"))) return null
        if (token != null && (disable || !uuid(snapshot.optString("registration_generation")) ||
            !BackgroundOrderAlertTokenRefresh.validToken(token))) return null
        val path = if (disable) "/disable" else if (token != null) "/token/refresh" else ""
        val connection = URL(endpoint + path).openConnection() as HttpURLConnection
        val startedAt = SystemClock.elapsedRealtime()
        return try {
            opened(connection)
            check(!cancelled())
            connection.instanceFollowRedirects = false
            connection.requestMethod = "POST"
            connection.connectTimeout = timeoutMs
            connection.readTimeout = timeoutMs
            connection.doOutput = true
            connection.setRequestProperty("Authorization", "Bearer ${snapshot.getString("status_secret")}")
            connection.setRequestProperty("Content-Type", "application/json")
            val input = JSONObject().put("installation_id", snapshot.getString("installation_id"))
            if (token != null) input.put("fcm_token", token).put("generation", snapshot.getString("registration_generation"))
            val body = input.toString().toByteArray(Charsets.UTF_8)
            connection.setFixedLengthStreamingMode(body.size)
            connection.outputStream.use { it.write(body) }
            if (connection.responseCode in setOf(401, 403)) throw AuthorityDenied()
            if (connection.responseCode !in 200..299) null else connection.inputStream.use {
                val output = java.io.ByteArrayOutputStream()
                val buffer = ByteArray(1024)
                while (output.size() <= 16_384) {
                    check(!cancelled())
                    check(SystemClock.elapsedRealtime() - startedAt <= timeoutMs * 2L)
                    val read = it.read(buffer, 0, minOf(buffer.size, 16_385 - output.size()))
                    if (read < 0) break
                    output.write(buffer, 0, read)
                }
                val bytes = output.toByteArray()
                check(bytes.size <= 16_384)
                JSONObject(String(bytes, Charsets.UTF_8))
            }
        } finally { connection.disconnect() }
    }

    private class AuthorityDenied : Exception()

    private fun fallbackNotification() {
        if (foreground || !authorityValid() || !channelAllowed()) return
        if (service != null) { scheduleReconcile(); return }
        // API 24/25 cannot enforce notification expiry after process death. Fail silent there.
        if (Build.VERSION.SDK_INT < 26) return
        if (fallbackJobs.current != null) { scheduleReconcile(); return }
        BackgroundOrderAlertJobService.enqueue(context)
    }

    /** Called only by the OS JobService, on main; status authority is never renewed here. */
    fun startFallbackJob(done: () -> Unit): (() -> Unit)? {
        if (foreground || service != null || !authorityValid() || !channelAllowed() || Build.VERSION.SDK_INT < 26) return null
        val work = fallbackJobs.begin(done) ?: return null
        fallbackWanted = true
        scheduleReconcile()
        return {
            if (fallbackJobs.cancel(work)) {
                fallbackWanted = false
                reconciliation.cancel()
                cancelFallback()
            }
        }
    }

    private fun finishFallbackJob(work: BackgroundOrderAlertJobOwnership.Work) {
        if (fallbackJobs.current !== work) return
        fallbackWanted = false
        fallbackJobs.complete(work)
    }

    private fun cancelFallback() {
        fallbackWanted = false
        fallbackJobs.current?.let { finishFallbackJob(it) }
        handler.removeCallbacks(expireFallback)
        notifications().cancel(FALLBACK_NOTIFICATION_ID)
    }

    private fun showVerifiedFallback(values: Map<String, Long>, serverTime: Long, authorityRemaining: Long) {
        if (foreground || service != null || !authorityValid() || !channelAllowed()) { cancelFallback(); return }
        val now = SystemClock.elapsedRealtime()
        val saved = if (record.has("fallback_heard")) record.getJSONObject("fallback_heard") else JSONObject()
        check(saved.length() <= BackgroundOrderAlertFallback.MAX_HEARD)
        val heard = saved.keys().asSequence().associateWith { id ->
            check(uuid(id))
            saved.getLong(id).also { check(it <= now + BackgroundOrderAlertState.HARD_TIMEOUT_MS) }
        }
        val plan = BackgroundOrderAlertFallback.plan(values, serverTime, authorityRemaining, now, heard,
            audioAllowed(), { ownership.reservePlayback(now) })
        observe(AlertEvent.PENDING_APPLIED, AlertResult.APPLIED,
            pendingCount = if (authorityRemaining > 0) values.values.count { it > serverTime } else 0)
        if (plan.timeoutMs == 0L) { cancelFallback(); return }
        // Durable fence BEFORE asking the OS to alert. A failed/uncertain notify is never retried audibly.
        record.put("fallback_heard", JSONObject(plan.heard))
        persist()
        handler.removeCallbacks(expireFallback)
        notifications().notify(FALLBACK_NOTIFICATION_ID, notification(false, plan.audible, plan.timeoutMs))
        observe(AlertEvent.NOTIFY_REQUESTED, AlertResult.REQUESTED)
        handler.postDelayed(expireFallback, plan.timeoutMs)
    }

    fun notification(ongoing: Boolean, audible: Boolean = false, timeoutMs: Long = 0): Notification {
        createChannel()
        val open = Intent(context, MainActivity::class.java).setAction(OPEN_INBOX)
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val tap = PendingIntent.getActivity(context, 38101, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getBroadcast(context, 38102, Intent(context, BackgroundOrderAlertStopReceiver::class.java).setAction(STOP_ALERTS),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
        builder.setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(context.getString(R.string.background_order_title))
            .setContentText(context.getString(if (ongoing) R.string.background_order_active else R.string.background_order_open))
            .setContentIntent(tap).setVisibility(Notification.VISIBILITY_PUBLIC).setCategory(Notification.CATEGORY_STATUS)
            .setOngoing(ongoing).setOnlyAlertOnce(ongoing || !audible)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .addAction(NotificationCompat.Action.Builder(android.R.drawable.ic_media_pause, context.getString(R.string.background_order_stop), stop).build())
        // FGS is always silent: its singleton owns repeats. Only a verified fallback may ask
        // the OS channel for one sound/heads-up; Android permission, channel and DND still win.
        builder.setSilent(ongoing || !audible)
        if (!ongoing) builder.setTimeoutAfter(timeoutMs)
        return builder.build()
    }

    private fun uuid(value: String): Boolean = BackgroundOrderAlertProtocol.uuid(value)
    private fun parseTime(value: String): Long? = BackgroundOrderAlertProtocol.timestamp(value)
}

private class BackgroundAlertClip(context: Context) : OnlineOrderAlertPlayback.Clip {
    private val player = MediaPlayer()
    init {
        try {
            player.setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
            player.isLooping = false
            context.resources.openRawResourceFd(R.raw.bizbot_online_order_alert).use {
                player.setDataSource(it.fileDescriptor, it.startOffset, it.length)
            }
        } catch (error: Exception) { player.release(); throw error }
    }
    override fun prepare(onReady: () -> Unit, onFinished: () -> Unit, onError: () -> Unit) {
        player.setOnPreparedListener { onReady() }
        player.setOnCompletionListener { onFinished() }
        player.setOnErrorListener { _, _, _ -> onError(); true }
        player.prepareAsync()
    }
    override fun start() {
        player.start()
        BackgroundOrderAlertCoordinator.observe(AlertEvent.AUDIO_START, AlertResult.STARTED)
    }
    override fun stop() {
        player.stop()
        BackgroundOrderAlertCoordinator.observe(AlertEvent.AUDIO_STOP, AlertResult.STOPPED)
    }
    override fun release() = player.release()
}
