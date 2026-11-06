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
import com.restoflow.pos.BackgroundOrderAlertRevocationReason as AlertRevocation

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
    private var unreadableVault = false
    private var record = vault.read() ?: JSONObject().also { unreadableVault = vault.hasSealedRecord() }
    @Volatile private var dutyBound = record.has("consent_id")
    private val uiLock = BackgroundOrderAlertUiLock(record.has("ui_inactivity_lock"))
    private val optIn = BackgroundOrderAlertOptIn(record.optBoolean("opt_in"))
    private val generation: Long get() = ownership.generation
    private val foreground: Boolean get() = ownership.foreground
    private var channel: MethodChannel? = null
    private var service: BackgroundOrderAlertService? = null
    private var pendingInboxTap = false
    private var visibilityEpoch = 0L
    private var fallbackWanted = false
    private var readSequence = 0L
    private val dutyReads = DutyReadFence()
    private var validatingDuty: DutyReadFence.Read? = null
    private var revokeInFlight = false
    private var dutyTokenLookup: String? = null
    private var durableStopUncertain = unreadableVault
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
    private val statusEndpoint: String get() = BuildConfig.BIZBOT_SUPABASE_URL.trimEnd('/') + "/functions/v1/pos-order-alert-status"

    init {
        // A process cannot finish a foreground consent dialog from an earlier lifetime. An
        // enrollment might already have committed despite losing its response.
        if (unreadableVault) {
            // Never replace unidentified ciphertext with a fresh apparently OFF installation.
            try { vault.latchDutyStop() } catch (_: Exception) {}
        } else if (record.has(DutyJournal.STAGED) || vault.dutyStopRequested() ||
            (record.has("consent_id") && record.optInt("boot_count", -1) != vault.bootCount())) {
            clearAuthority(reason = AlertRevocation.SECURITY_FAILURE)
        } else {
            if (record.has("consent_id")) {
                record.put("duty_status_unknown",true) // A past process cannot vouch for current pending truth.
                try { persist() } catch (_: Exception) { durableStopUncertain = true }
            }
            if (record.has(DutyJournal.QUEUE)) DutyRevokeJob.enqueue(context)
        }
    }

    fun drainDutyRevokes(fromJob: Boolean = false, done: () -> Unit = {}) {
        if (revokeInFlight || durableStopUncertain || !exactEndpoint(statusEndpoint)) { done(); return }
        val batch = DutyJournal.queue(record)
        if (batch.isEmpty()) { done(); return }
        revokeInFlight = true
        network.execute {
            val acknowledged = mutableListOf<BackgroundOrderAlertDuty.Revocation>()
            for (proof in batch) {
                try {
                    val revoke = JSONObject().put("installation_id", proof.installation).put("consent_id", proof.consent)
                        .put("endpoint", statusEndpoint).put("revoke_secret", proof.secret)
                    val reply = request(revoke, true, 3_000) ?: continue
                    if (BackgroundOrderAlertDuty.acknowledge(listOf(proof), proof, reply.opt("ok"), reply.opt("consent_id")).isEmpty()) {
                        acknowledged.add(proof)
                    }
                } catch (_: Exception) { /* Offline, denied, truncated or unknown is never an ACK. */ }
            }
            handler.post {
                revokeInFlight = false
                if (acknowledged.isNotEmpty()) try {
                    val next = JSONObject(record.toString())
                    DutyJournal.setQueue(next, DutyJournal.queue(next).filterNot { it in acknowledged })
                    vault.write(next, stopped = !next.has("consent_id") && !next.has(DutyJournal.STAGED))
                    record = next
                    durableStopUncertain = false
                } catch (_: Exception) { /* Persisted work retains its original identity for next opportunity. */ }
                // One connectivity-constrained opportunity. A failed job never reschedules itself.
                if (!fromJob && DutyJournal.queue(record).isNotEmpty()) DutyRevokeJob.enqueue(context)
                done()
            }
        }
    }

    fun dutyState(args: Map<*, *>): Map<String, Any?> {
        val identity = args["identity"] as? String
        val matches = !identity.isNullOrBlank() && identity == record.optString("identity")
        val active = record.has("consent_id")
        // An absent UI identity is normal behind the PIN screen. It may neither expose the
        // bound grant nor turn a null projection into a sign-out. Explicit logout uses disable.
        if (active && !identity.isNullOrBlank() && !matches) clearAuthority(reason = AlertRevocation.IDENTITY_OR_PAIRING_CHANGED)
        else if (active && !authorityBound()) {
            val expired = observedAuthority() == AlertAuthority.EXPIRED
            clearAuthority(retainOptIn = expired, reason = if (expired) AlertRevocation.AUTHORITY_EXPIRED else AlertRevocation.SECURITY_FAILURE)
        }
        val ready = matches && record.has("consent_id") && authorityValid() && dutyReady()
        val phase = when {
            ready -> "active"
            record.has(DutyJournal.STAGED) || record.has("consent_id") -> "pending"
            record.has("duty_expired") -> "expired"
            durableStopUncertain || record.has(DutyJournal.QUEUE) -> "revoking"
            else -> "none"
        }
        val result = mutableMapOf<String, Any?>("available" to BuildConfig.BIZBOT_BACKGROUND_ORDER_ALERTS,
            "phase" to phase, "ready" to ready, "opt_in" to (record.opt("opt_in") == true),
            "can_start_consent" to (BuildConfig.BIZBOT_BACKGROUND_ORDER_ALERTS && !identity.isNullOrBlank() &&
                uiLock.activityForeground && !uiLock.inactivityLocked && vault.bootCount() >= 0 &&
                !durableStopUncertain && !vault.dutyStopRequested() && record.opt("enabled") != true &&
                !record.has("consent_id") && !record.has(DutyJournal.STAGED) &&
                DutyJournal.queue(record).size < BackgroundOrderAlertDuty.MAX_PENDING_REVOKES))
        if (ready) {
            result["consent_id"] = record.getString("consent_id")
            result["registration_generation"] = record.getString("registration_generation")
            result["authority_expires_at"] = record.getString("duty_end")
            result["remaining_ms"] = record.getLong("authority_deadline") - SystemClock.elapsedRealtime()
        }
        return result
    }

    private fun dutyReady() = BackgroundOrderAlertDuty.ready(record.opt("enabled"),record.opt("opt_in"),
        record.opt("duty_status_unknown"),record.opt("token_refresh_unconfirmed"))

    fun suspendDutyEffects(args: Map<*,*>): Boolean {
        if (!dutyBound || args["identity"] != record.opt("identity")) return false
        dutyReads.invalidate()
        state.clear()
        stopBackground()
        record.put("duty_status_unknown",true)
        return try { persist(); true } catch (_: Exception) { false }
    }

    private fun restoreVerified(receipt: DutyJournal.Snapshot) {
        check(authorityValid())
        if (record.opt("duty_status_unknown") != false || record.getLong("authority_deadline") != receipt.deadline ||
            record.optString("duty_end") != receipt.absoluteEnd) {
            val next = JSONObject(record.toString()).put("duty_status_unknown",false)
                .put("authority_deadline",receipt.deadline).put("duty_end",receipt.absoluteEnd)
            vault.write(next)
            record = next
        }
    }

    fun revalidateDuty(args: Map<*,*>, done: (Boolean)->Unit) {
        val scope = DutyJournal.scope(record)
        if (scope == null || args["identity"] != scope.identity || !authorityValid() || !uiLock.activityForeground ||
            record.opt("token_refresh_unconfirmed") != false) { done(false); return }
        if (validatingDuty?.let { dutyReads.current(it, scope) } == true) { done(false); return }
        reconciliation.cancel() // A superseded background watchdog cannot clear a newer foreground read.
        val read = dutyReads.begin(scope)
        validatingDuty = read
        val captured = JSONObject(record.toString())
        val started = SystemClock.elapsedRealtime()
        network.execute {
            var denied = false
            val body = try { request(captured,false,3_000) } catch (_: AuthorityDenied) { denied=true; null } catch (_:Exception) { null }
            handler.post completion@{
                if (validatingDuty === read) validatingDuty = null
                if (!dutyReads.current(read,DutyJournal.scope(record)) || !authorityValid()) { done(false); return@completion }
                if (SystemClock.elapsedRealtime() - started >= BackgroundOrderAlertReconciliation.READ_BUDGET_MS) {
                    suspendDutyEffects(args); done(false); return@completion
                }
                if (denied) { clearAuthority(reason=AlertRevocation.SERVER_AUTH_REVOKED); done(false); return@completion }
                try {
                    check(body != null)
                    restoreVerified(DutyJournal.snapshot(body,scope,record,started,SystemClock.elapsedRealtime()))
                    done(true)
                } catch (_: Exception) { suspendDutyEffects(args); done(false) }
            }
        }
    }

    fun prepareDutyPreview(args: Map<*, *>): Map<String, Any?> {
        val identity = args["identity"] as? String ?: return emptyMap()
        val endpoint = args["endpoint"] as? String ?: return emptyMap()
        if (!BuildConfig.BIZBOT_BACKGROUND_ORDER_ALERTS || !uiLock.activityForeground || uiLock.inactivityLocked ||
            identity.isBlank() || identity.length > 512 ||
            !exactEndpoint(endpoint) || vault.bootCount() < 0 || durableStopUncertain || vault.dutyStopRequested() ||
            record.opt("enabled") == true || record.has("consent_id") || record.has(DutyJournal.STAGED) ||
            DutyJournal.queue(record).size >= BackgroundOrderAlertDuty.MAX_PENDING_REVOKES) return emptyMap()
        val installation = record.optString("installation_id").takeIf(::uuid) ?: UUID.randomUUID().toString()
        val staged = DutyJournal.stage(installation, identity, endpoint, vault.bootCount())
        val next = JSONObject(record.toString()).put("installation_id", installation).put(DutyJournal.STAGED, staged)
        vault.write(next)
        record = next
        drainDutyRevokes()
        return mapOf("installation_id" to installation, "consent_id" to staged.getString("consent_id"),
            "revoke_hash" to DutyJournal.hash(staged.getString("revoke_secret")), "generation" to generation)
    }

    private fun matchesDuty(value: JSONObject, args: Map<*, *>): Boolean =
        value.has("consent_id") && value.optString("consent_id") == args["consent_id"] && value.optString("identity") == args["identity"] &&
            (args["generation"] as? Number)?.toLong() == generation

    fun stagedDuty(args: Map<*, *>, requireForeground: Boolean = true): Boolean = record.optJSONObject(DutyJournal.STAGED)?.let {
        (!requireForeground || uiLock.activityForeground) && !uiLock.inactivityLocked && matchesDuty(it, args) && it.optInt("boot_count",-1) == vault.bootCount() &&
            it.optString("endpoint") == args["endpoint"] && !vault.dutyStopRequested()
    } == true

    fun prepareDuty(args: Map<*, *>, callback: (Map<String, Any?>) -> Unit) {
        if (!stagedDuty(args) || !initializeFirebase(context)) { callback(emptyMap()); return }
        createChannel()
        val policy = channelPolicy()
        if (policy == null || policy.failureReason != null) { callback(emptyMap()); return }
        val staged = record.getJSONObject(DutyJournal.STAGED)
        val consent = staged.getString("consent_id")
        if (staged.has("started_tick") || dutyTokenLookup == consent) { callback(emptyMap()); return }
        dutyTokenLookup = consent
        try {
            FirebaseMessaging.getInstance().isAutoInitEnabled = true
            FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                if (dutyTokenLookup == consent) dutyTokenLookup = null
                if (!stagedDuty(args) || !task.isSuccessful || !BackgroundOrderAlertTokenRefresh.validToken(task.result ?: "")) {
                    callback(emptyMap()); return@addOnCompleteListener
                }
                try {
                    // Only this handoff permits Dart to issue enroll. An abandoned OS prompt or
                    // failed SDK lookup leaves a harmless, expiring preview-only reservation.
                    val current = record.getJSONObject(DutyJournal.STAGED)
                    current.put("started_tick",SystemClock.elapsedRealtime()).put("status_secret",DutyJournal.token())
                    persist()
                    callback(mapOf("installation_id" to current.getString("installation_id"), "consent_id" to consent,
                        "generation" to generation, "status_secret" to current.getString("status_secret"), "fcm_token" to task.result))
                } catch (_: Exception) { callback(emptyMap()) }
            }
        } catch (_: Exception) {
            if (dutyTokenLookup == consent) dutyTokenLookup = null
            callback(emptyMap())
        }
    }

    fun bindDuty(args: Map<*, *>): Boolean {
        if (!stagedDuty(args)) return false
        val staged = record.getJSONObject(DutyJournal.STAGED)
        val next = DutyJournal.bind(staged,args,SystemClock.elapsedRealtime(),record) ?: return false
        vault.write(next)
        dutyReads.invalidate()
        reconciliation.cancel()
        hints.clear()
        state.clear()
        stopBackground()
        tokenLane.finishPreparation()
        record = next
        dutyBound = true
        optIn.prepare(true)
        uiLock.confirmedBind()
        applyForeground()
        return true
    }

    fun cancelDuty(args: Map<*, *>): Boolean {
        val staged = record.optJSONObject(DutyJournal.STAGED)
        if (!matchesDuty(staged ?: record, args)) return false
        return disable(AlertRevocation.USER_NOTIFICATION_OFF)
    }

    fun stopFromNotification(consent: String?): Boolean {
        if (record.has(DutyJournal.STAGED) || !BackgroundOrderAlertDuty.stopMatches(consent,DutyJournal.scope(record)?.consent)) return false
        return disable(AlertRevocation.USER_NOTIFICATION_STOP)
    }

    fun currentWake(intent: Intent?): Boolean = intent != null && !foreground && authorityValid() &&
        BackgroundOrderAlertDuty.wakeMatches(intent.getStringExtra("consent_id"),intent.getStringExtra("generation"),DutyJournal.scope(record))

    fun ownsService(value: BackgroundOrderAlertService) = service === value
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
        drainDutyRevokes()
        channel?.setMethodCallHandler(null)
        channel = MethodChannel(messenger, "restoflow.pos/background_order_alert")
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
        uiLock.detachUi()
        applyForeground()
    }
    fun bridge(): MethodChannel? = channel

    fun prepare(activity: Activity, requestPermission: Boolean, callback: (Map<String, Any?>) -> Unit) {
        if (DutyJournal.owns(record) || durableStopUncertain || (!requestPermission && record.has("duty_expired"))) {
            callback(mapOf("available" to true, "enabled" to false)); return
        }
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
        if (DutyJournal.owns(record) || durableStopUncertain) return false
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
        record.remove("ui_inactivity_lock")
        return try {
            persist()
            uiLock.confirmedBind()
            applyForeground()
            true
        } catch (_: Exception) { clearAuthority(); false }
    }

    private fun confirmedInactivityGrant(): BackgroundOrderAlertInactivityGrant? {
        val identity = record.optString("identity")
        val installation = record.optString("installation_id")
        val registration = record.optString("registration_id")
        val registrationGeneration = record.optString("registration_generation")
        if (identity.isBlank() || identity.length > 512 || !uuid(installation) || !uuid(registration) ||
            !uuid(registrationGeneration)) return null
        return BackgroundOrderAlertInactivityGrant(identity, installation, registration, registrationGeneration)
    }

    private fun retainedScopeMatches(): Boolean {
        return try {
            val saved = record.optJSONObject("ui_inactivity_lock") ?: return false
            val current = confirmedInactivityGrant() ?: return false
            val original = BackgroundOrderAlertInactivityGrant(saved.getString("identity"), saved.getString("installation_id"),
                saved.getString("registration_id"), saved.getString("registration_generation"))
            original.matches(current) && optIn.enabled && record.optBoolean("opt_in")
        } catch (_: Exception) { false }
    }

    private fun retainedGrantValid(): Boolean = try { retainedScopeMatches() && authorityBound() } catch (_: Exception) { false }

    /** Called only for the exact identity from the trusted Dart inactivity transition. */
    fun retainInactivity(args: Map<*, *>): Boolean {
        if (AlertRevocation.parse(args["reason"]) != AlertRevocation.INACTIVITY_UI_LOCK) return false
        val grant = confirmedInactivityGrant() ?: return false
        val validAuthority = try { authorityValid() } catch (_: Exception) { false }
        val alreadyRetained = uiLock.inactivityLocked && retainedGrantValid()
        if (!uiLock.retain(args["identity"] as? String, grant.identity, optIn.enabled && record.optBoolean("opt_in"),
                record.optBoolean("enabled"), true, validAuthority, tokenLane.preparing,
                record.optBoolean("token_refresh_unconfirmed"))) return false
        if (alreadyRetained) return true
        record.put("ui_inactivity_lock", JSONObject().put("identity", grant.identity)
            .put("installation_id", grant.installation).put("registration_id", grant.registration)
            .put("registration_generation", grant.registrationGeneration))
        return try {
            persist() // Existing encrypted vault only; no authority deadline or server generation is changed.
            ownership.invalidate() // Fence a delayed pre-lock prepare/bind/status completion.
            tokenLane.finishPreparation()
            reconciliation.cancel()
            applyForeground()
            // A hint may have reached the disappearing Inbox just before this
            // MethodChannel handoff. Acquire one existing bounded status owner
            // even when no local pending projection/FGS was available yet.
            // Idempotent retention above cannot enqueue another obligation.
            if (!foreground) fallbackNotification()
            observe(AlertEvent.AUTHORITY, AlertResult.INACTIVITY_UI_LOCK, authority = observedAuthority(), foreground = foreground)
            true
        } catch (_: Exception) { clearAuthority(reason = AlertRevocation.SECURITY_FAILURE); false }
    }

    private fun authorityBound(): Boolean = authorityState() == AlertAuthority.VALID

    // Keep enough authority to finish the outstanding token CAS or revoke it. Until its exact
    // result is known, even a valid old-generation status response cannot authorize effects.
    private fun authorityValid(): Boolean = authorityBound() && (!dutyBound || BackgroundOrderAlertDuty.mayRead(
        record.opt("enabled"),record.opt("opt_in"),record.opt("duty_status_unknown"),record.opt("token_refresh_unconfirmed")))

    // Extra observation must not introduce a new Settings/vault failure on a stop path.
    private fun observedAuthority(): AlertAuthority? = try { authorityState() } catch (_: Exception) { null }

    // Same short-circuit order as the original guard. No vault contents leave this method.
    private fun authorityState(): AlertAuthority = when {
        durableStopUncertain || vault.dutyStopRequested() -> AlertAuthority.OPTED_OUT
        dutyBound && !BackgroundOrderAlertDuty.boundFlagsValid(record.opt("enabled"),record.opt("opt_in"),
            record.opt("duty_status_unknown"),record.opt("token_refresh_unconfirmed")) -> AlertAuthority.BINDING_MISSING
        !BuildConfig.BIZBOT_BACKGROUND_ORDER_ALERTS -> AlertAuthority.FEATURE_OFF
        !record.optBoolean("enabled") -> AlertAuthority.OPTED_OUT
        !record.has("registration_id") || !record.has("status_secret") -> AlertAuthority.BINDING_MISSING
        !exactEndpoint(record.optString("endpoint")) -> AlertAuthority.ENDPOINT_INVALID
        record.optInt("boot_count", -1) < 0 || record.optInt("boot_count", -1) != vault.bootCount() -> AlertAuthority.BOOT_CHANGED
        record.optLong("authority_deadline") <= SystemClock.elapsedRealtime() -> AlertAuthority.EXPIRED
        record.has("ui_inactivity_lock") && !retainedScopeMatches() -> AlertAuthority.BINDING_MISSING
        else -> AlertAuthority.VALID
    }

    fun pending(args: Map<*, *>): Boolean {
        // This foreground Inbox projection has no consent/generation/read sequence. It must
        // never seed duty audio or notifications after a handoff; only its own status read may.
        if (dutyBound) return false
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
        if (value) drainDutyRevokes()
        uiLock.activity(value)
        // A persisted lock is meaningful only for the exact still-valid original grant.
        if (uiLock.inactivityLocked && !retainedGrantValid()) clearAuthority(reason = AlertRevocation.SECURITY_FAILURE)
        applyForeground()
    }

    private fun applyForeground() {
        val effective = uiLock.effectiveForeground
        if (foreground == effective) return
        ownership.setForeground(effective)
        observe(AlertEvent.AUTHORITY, AlertResult.FOREGROUND, authority = observedAuthority(), foreground = effective)
        visibilityEpoch++
        playback.setForeground(true) // Shared clip eligibility; audio policy and ownership remain independently fenced.
        if (effective) {
            handler.removeCallbacks(tick)
            reconciliation.cancel()
            cancelFallback()
            service?.stopSelf()
            service = null
            playback.stop()
        } else {
            playback.stop()
            if (authorityValid() && state.active(SystemClock.elapsedRealtime()) && channelAllowed()) startBackground()
            else if (dutyBound && authorityValid() && channelAllowed()) fallbackNotification()
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

    fun clearAuthority(retainOptIn: Boolean = false, reason: AlertRevocation = AlertRevocation.SECURITY_FAILURE): Boolean {
        if (unreadableVault) {
            try { vault.latchDutyStop() } catch (_: Exception) {}
            return false
        }
        // A reason string alone cannot retain authority; only retainInactivity may do that.
        val revocation = if (reason == AlertRevocation.INACTIVITY_UI_LOCK) AlertRevocation.SECURITY_FAILURE else reason
        val hadDuty = DutyJournal.owns(record) || durableStopUncertain
        if (hadDuty) {
            val stopped = DutyJournal.stopped(record, retainOptIn, reason == AlertRevocation.AUTHORITY_EXPIRED)
            durableStopUncertain = true
            try { vault.latchDutyStop() } catch (_: Exception) { /* The atomic encrypted swap below also fences cold restore. */ }
            try { vault.write(stopped, stopped = true); durableStopUncertain = false } catch (_: Exception) {}
            record = stopped
            dutyBound = false
        }
        observe(AlertEvent.AUTHORITY, revocation.observation)
        uiLock.revoke()
        tokenLane.finishPreparation()
        ownership.invalidate()
        dutyReads.invalidate()
        state.clear()
        hints.clear()
        playback.stop()
        stopBackground()
        val install = record.optString("installation_id")
        optIn.clear(retainOptIn)
        if (hadDuty) {
            if (!durableStopUncertain && DutyJournal.queue(record).isNotEmpty()) {
                DutyRevokeJob.enqueue(context)
                drainDutyRevokes()
            }
            return !durableStopUncertain
        }
        record = JSONObject().apply {
            if (uuid(install)) put("installation_id", install)
            if (optIn.enabled) put("opt_in", true)
        }
        try { vault.clear(); if (record.length() > 0) persist() } catch (_: Exception) { /* No in-memory authority remains. */ }
        return true
    }

    fun disable(reason: AlertRevocation = AlertRevocation.EXPLICIT_SIGN_OUT): Boolean {
        val old = record.toString()
        val duty = record.has("consent_id")
        val stopped = clearAuthority(reason = reason)
        try { if (initializeFirebase(context)) FirebaseMessaging.getInstance().isAutoInitEnabled = false } catch (_: Exception) { }
        if (!duty) network.execute { try { request(JSONObject(old), true) } catch (_: Exception) { /* Local stop never waits on network. */ } }
        return stopped
    }

    fun tokenChanged(token: String) {
        handler.post {
            if (!BackgroundOrderAlertTokenRefresh.validToken(token)) return@post
            // PIN-locked status-only retention grants no new token ownership. The
            // ordinary authenticated foreground prepare reads the latest SDK token.
            if (!uiLock.authenticatedUiAvailable && !record.has("consent_id")) return@post
            if ((!dutyBound && foreground) || tokenLane.preparing) {
                // Keep the generation/status secret stable while a serialized
                // foreground prepare/bind may be in flight. That owner reads
                // the latest SDK token before registration; logout still revokes.
                channel?.invokeMethod("tokenChanged", null)
                return@post
            }
            if (!authorityBound()) {
                clearAuthority(true, if (observedAuthority() == AlertAuthority.EXPIRED) AlertRevocation.AUTHORITY_EXPIRED else AlertRevocation.SECURITY_FAILURE)
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
            if (dutyBound) {
                dutyReads.invalidate()
                state.clear()
                stopBackground()
            }
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
                    !authorityBound() || snapshot.optString("registration_id") != record.optString("registration_id")) return@completion
                if (foreground && !dutyBound) {
                    // An old background denial must not cancel a foreground
                    // registration that has committed but has not bound yet.
                    tokenLane.complete(work, null)
                    channel?.invokeMethod("tokenChanged", null)
                    return@completion
                }
                var committedGeneration: String? = null
                if (denied) {
                    clearAuthority(true, AlertRevocation.SERVER_AUTH_REVOKED)
                } else if (response != null) {
                    try {
                        val duty = DutyJournal.scope(snapshot)
                        if (duty != null) check(BackgroundOrderAlertDuty.validReply(response.opt("ok"), response.opt("consent_id"),
                            response.opt("registration_id"), response.opt("generation"), duty, rotating = true))
                        check(response.opt("ok") == true &&
                            response.getString("registration_id") == record.getString("registration_id") &&
                            uuid(response.getString("generation")))
                        val serverTime = parseTime(response.getString("server_time")) ?: error("invalid time")
                        val expiry = parseTime(response.getString("authority_expires_at")) ?: error("invalid expiry")
                        if (duty != null) check(expiry <= (parseTime(record.getString("duty_end")) ?: error("unbound")))
                        val now = SystemClock.elapsedRealtime()
                        val remaining = BackgroundOrderAlertTokenRefresh.remaining(serverTime, expiry,
                            startedAt, now, record.getLong("authority_deadline")) ?: error("expired authority")
                        val next = JSONObject(record.toString()).put("authority_deadline", now + remaining)
                            .put("registration_generation", response.getString("generation"))
                        if (duty == null) next.remove("token_refresh_unconfirmed") else next.put("token_refresh_unconfirmed",false)
                        if (duty != null) {
                            next.put("duty_end", response.getString("authority_expires_at"))
                            next.optJSONObject("ui_inactivity_lock")?.put("registration_generation",response.getString("generation"))
                        }
                        vault.write(next)
                        record = next
                        if (duty != null) { dutyReads.invalidate(); reconciliation.cancel(); if (!foreground) fallbackNotification() }
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
            post = { handler.post(it) }, fallback = {
                // A duty wake cannot trigger an unscoped OS job if it never reached the main-thread fence.
                if (dutyBound || data["version"] == "2") false else BackgroundOrderAlertJobService.enqueue(context)
            },
        ) handoff@ {
            val authority = authorityState()
            if (authority != AlertAuthority.VALID || (dutyBound && record.opt("token_refresh_unconfirmed") == true)) {
                observe(AlertEvent.AUTHORITY, AlertResult.REFUSED, authority = authority, foreground = foreground)
                return@handoff
            }
            val accepted = hints.accept(data, record.optString("registration_id"), System.currentTimeMillis(),
                SystemClock.elapsedRealtime(), DutyJournal.scope(record))
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
            post = { handler.post(it) }, fallback = { if (dutyBound) false else BackgroundOrderAlertJobService.enqueue(context) },
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
            DutyJournal.scope(record)?.let { intent.putExtra("consent_id",it.consent).putExtra("generation",it.transport) }
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
        val dutyRead = DutyJournal.scope(snapshot)?.let(dutyReads::begin)
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
                    if ((dutyRead != null && !dutyReads.current(dutyRead, DutyJournal.scope(record))) ||
                        expected != generation || expectedVisibility != visibilityEpoch || foreground ||
                        service !== expectedService || (service == null && !fallbackWanted) || !authorityValid() ||
                        snapshot.optString("registration_id") != record.optString("registration_id")) {
                        if (!foreground && (service != null || fallbackWanted) && authorityValid()) scheduleReconcile()
                        observe(AlertEvent.STATUS_COMPLETE, AlertResult.STALE, read = ordinal)
                        return@completion
                    }
                    if (denied) { observe(AlertEvent.STATUS_COMPLETE, AlertResult.DENIED, read = ordinal); clearAuthority(reason = AlertRevocation.SERVER_AUTH_REVOKED); return@completion }
                    try {
                        check(response != null && response.opt("ok") == true)
                        if (dutyRead != null) {
                            val now = SystemClock.elapsedRealtime()
                            val receipt = DutyJournal.snapshot(response, dutyRead.scope, record, startedAt, now)
                            restoreVerified(receipt)
                            applyStatus(receipt.values, receipt.serverNow, receipt.deadline - now, ordinal)
                            return@completion
                        }
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
                        applyStatus(values, conservativeServerNow, remaining, ordinal)
                    } catch (_: Exception) {
                        // Unknown state is not permission to continue ringing indefinitely.
                        val failure = AlertResult.UNAVAILABLE_OR_INVALID
                        if (dutyRead != null) { record.put("duty_status_unknown",true); try { persist() } catch (_: Exception) {} }
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

    private fun applyStatus(values: Map<String,Long>, conservativeServerNow: Long, remaining: Long, ordinal: Long) {
        observe(AlertEvent.STATUS_COMPLETE, AlertResult.ACCEPTED, read = ordinal)
        if (service == null) showVerifiedFallback(values, conservativeServerNow, remaining)
        else {
            state.replace(values, conservativeServerNow, remaining, SystemClock.elapsedRealtime())
            observe(AlertEvent.PENDING_APPLIED, AlertResult.APPLIED,
                pendingCount = state.count(SystemClock.elapsedRealtime()), read = ordinal)
            handler.removeCallbacks(tick)
            tick.run()
        }
    }

    private fun request(snapshot: JSONObject, disable: Boolean, timeoutMs: Int = 7_000, token: String? = null,
        cancelled: () -> Boolean = { false }, opened: (HttpURLConnection) -> Unit = {}): JSONObject? {
        if (cancelled()) return null
        val endpoint = snapshot.optString("endpoint")
        val duty = snapshot.has("consent_id")
        val secret = if (duty && disable) "revoke_secret" else "status_secret"
        if (!exactEndpoint(endpoint) || !snapshot.has(secret) || !uuid(snapshot.optString("installation_id")) ||
            (duty && !uuid(snapshot.optString("consent_id")))) return null
        if (token != null && (disable || !uuid(snapshot.optString("registration_generation")) ||
            !BackgroundOrderAlertTokenRefresh.validToken(token))) return null
        val path = if (duty) {
            if (disable) "/duty/revoke" else if (token != null) "/duty/token/refresh" else "/duty/status"
        } else if (disable) "/disable" else if (token != null) "/token/refresh" else ""
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
            connection.setRequestProperty("Authorization", "Bearer ${snapshot.getString(secret)}")
            connection.setRequestProperty("Content-Type", "application/json")
            val input = JSONObject().put("installation_id", snapshot.getString("installation_id"))
            if (duty) input.put("consent_id",snapshot.getString("consent_id"))
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
        BackgroundOrderAlertJobService.enqueue(context,DutyJournal.scope(record))
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
        val stopIntent = Intent(context, BackgroundOrderAlertStopReceiver::class.java).setAction(STOP_ALERTS)
        DutyJournal.scope(record)?.let {
            // Extras alone do not participate in PendingIntent identity.
            stopIntent.data = Uri.Builder().scheme("bizbot-duty").authority("stop").appendPath(it.consent).build()
            stopIntent.putExtra("consent_id",it.consent)
        }
        val stop = PendingIntent.getBroadcast(context, 38102, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
        builder.setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(context.getString(R.string.background_order_title))
            .setContentText(context.getString(if (ongoing) R.string.background_order_active else R.string.background_order_open))
            // A foreground PIN screen remains notification-only, with no order/customer details.
            .setContentIntent(tap).setVisibility(if (!uiLock.authenticatedUiAvailable) Notification.VISIBILITY_PRIVATE else Notification.VISIBILITY_PUBLIC)
            .setCategory(Notification.CATEGORY_STATUS)
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
