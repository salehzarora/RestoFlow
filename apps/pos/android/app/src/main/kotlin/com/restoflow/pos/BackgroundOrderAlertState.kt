package com.restoflow.pos

import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** Acquire a service/job before FCM releases its callback; never await network here. */
internal object BackgroundOrderAlertCallbackHandoff {
    const val BUDGET_MS = 1_000L
    fun run(post: (() -> Unit) -> Unit, fallback: () -> Unit,
        await: (CountDownLatch) -> Boolean = { it.await(BUDGET_MS, TimeUnit.MILLISECONDS) }, action: () -> Unit) {
        val finished = CountDownLatch(1)
        val cancelled = AtomicBoolean(false)
        try {
            post {
                try { if (!cancelled.get()) action() }
                catch (_: Exception) { fallback() }
                finally { finished.countDown() }
            }
            if (await(finished)) return
        } catch (_: Exception) { /* Failed handoff must acquire an independent job. */ }
        cancelled.set(true)
        fallback()
    }
}

/** Identity-fenced ownership of one JobService invocation, independent from the FGS. */
internal class BackgroundOrderAlertJobOwnership {
    class Work internal constructor(internal val done: () -> Unit)
    var current: Work? = null
        private set
    fun begin(done: () -> Unit): Work? {
        if (current != null) return null
        return Work(done).also { current = it }
    }
    fun complete(work: Work): Boolean {
        if (!cancel(work)) return false
        work.done()
        return true
    }
    fun cancel(work: Work): Boolean {
        if (current !== work) return false
        current = null
        return true
    }
}

/** Batch only obligations acquired BEFORE a read, never arrivals during its snapshot. */
internal class BackgroundOrderAlertJobQueue<T>(private val take: () -> T?, private val complete: (T) -> Unit) {
    private var batch: List<T> = emptyList()
    fun beginRead(): Boolean {
        check(batch.isEmpty())
        val pending = mutableListOf<T>()
        // Bound main-thread work. Additional items remain OS-owned for a later read.
        while (pending.size < 64) pending.add(take() ?: break)
        batch = pending
        return batch.isNotEmpty()
    }
    fun completeRead() {
        val done = batch
        batch = emptyList()
        done.forEach(complete)
    }
}

/** Closed diagnostic vocabulary: no payload, identifier, credential or exception text is accepted. */
internal object BackgroundOrderAlertObservation {
    enum class Event { FCM_ENTER, FCM_RETURN, HINT, AUTHORITY, FGS_REQUEST, FGS_START, FGS_STOP,
        JOB_ENQUEUE, JOB_START, JOB_STOP, STATUS_BEGIN, STATUS_COMPLETE, PENDING_APPLIED, NOTIFY_REQUESTED, AUDIO_START, AUDIO_STOP_REQUEST, AUDIO_STOP }
    enum class Result { ENTER, RETURN, ACCEPTED, REFUSED, REQUESTED, STARTED, STOPPED, APPLIED,
        DENIED, MALFORMED, UNAVAILABLE_OR_INVALID, STALE, TIMEOUT, FAILED, START_DENIED, SECURITY_DENIED,
        FINISHED, POLICY, FOREGROUND, EXPIRED, EMPTY }
    enum class Kind { PENDING, CANCEL, OTHER }
    enum class Authority { VALID, FEATURE_OFF, OPTED_OUT, BINDING_MISSING, ENDPOINT_INVALID, BOOT_CHANGED, EXPIRED }
    enum class Channel { ALLOWED, PERMISSION_DENIED, NOTIFICATIONS_DISABLED, MISSING, LOW_IMPORTANCE, SOUND_MISSING, UNKNOWN }

    fun encode(event: Event, result: Result, sequence: Long, utcMs: Long, elapsedMs: Long,
        kind: Kind? = null, high: Boolean? = null, authority: Authority? = null, channel: Channel? = null,
        foreground: Boolean? = null, pendingCount: Int? = null, read: Long? = null): String {
        require(sequence >= 0 && utcMs >= 0 && elapsedMs >= 0 && (read == null || read >= 0))
        require(pendingCount == null || pendingCount in 0..50)
        return "v=1 seq=$sequence utc_ms=$utcMs elapsed_ms=$elapsedMs event=${event.name} result=${result.name}" +
            " kind=${kind?.name ?: "NULL"} high=${high?.toString() ?: "NULL"}" +
            " authority=${authority?.name ?: "NULL"} channel=${channel?.name ?: "NULL"} foreground=${foreground?.toString() ?: "NULL"}" +
            " pending_count=${pendingCount?.toString() ?: "NULL"} read=${read?.toString() ?: "NULL"}"
    }
}

/** Non-sensitive channel policy; never contains IDs, sound URIs or credentials. */
internal data class BackgroundOrderAlertChannelPolicy(
    val permissionAllowed: Boolean,
    val notificationsEnabled: Boolean,
    val channelPresent: Boolean,
    val channelImportanceAllowed: Boolean,
    val channelSoundPresent: Boolean,
) {
    val failureReason: String? get() = when {
        !permissionAllowed -> "permission_denied"
        !notificationsEnabled -> "notifications_disabled"
        !channelPresent -> "channel_missing"
        !channelImportanceAllowed -> "channel_importance_low"
        !channelSoundPresent -> "channel_sound_missing"
        else -> null
    }

    fun diagnostics(): Map<String, Boolean> = mapOf(
        "permission_allowed" to permissionAllowed,
        "notifications_enabled" to notificationsEnabled,
        "channel_present" to channelPresent,
        "channel_importance_allowed" to channelImportanceAllowed,
        "channel_sound_present" to channelSoundPresent,
    )
}

/** Platform-free, monotonic single cadence. Only confirmed full server sets enter here. */
internal class BackgroundOrderAlertState {
    companion object {
        const val CADENCE_MS = 10_000L
        const val HARD_TIMEOUT_MS = 15 * 60_000L
    }

    private val deadlines = linkedMapOf<String, Long>()
    private var authorityDeadline = 0L
    private var hardDeadline = 0L
    private var nextSound = 0L

    fun replace(
        requests: Map<String, Long>,
        serverTime: Long,
        authorityRemaining: Long,
        monotonicNow: Long,
    ) {
        val wasActive = active(monotonicNow)
        if (hardDeadline == 0L) hardDeadline = monotonicNow + HARD_TIMEOUT_MS
        authorityDeadline = monotonicNow + authorityRemaining.coerceIn(0, HARD_TIMEOUT_MS)
        deadlines.clear()
        requests.forEach { (id, expiry) ->
            val remaining = (expiry - serverTime).coerceIn(0, HARD_TIMEOUT_MS)
            if (remaining > 0) deadlines[id] = monotonicNow + remaining
        }
        if (!wasActive) nextSound = monotonicNow
        prune(monotonicNow)
    }

    fun prune(now: Long) {
        deadlines.entries.removeAll { it.value <= now }
        if (authorityDeadline <= now || hardDeadline <= now) deadlines.clear()
    }

    fun active(now: Long): Boolean {
        prune(now)
        return deadlines.isNotEmpty()
    }

    fun shouldPlay(now: Long): Boolean = active(now) && nextSound <= now

    fun played(now: Long) {
        nextSound = now + CADENCE_MS
    }

    fun nextWake(now: Long): Long? {
        if (!active(now)) return null
        return minOf(nextSound, deadlines.values.min(), authorityDeadline, hardDeadline)
            .minus(now).coerceAtLeast(1)
    }

    fun count(now: Long): Int {
        prune(now)
        return deadlines.size
    }

    fun clear() {
        deadlines.clear()
        authorityDeadline = 0
        hardDeadline = 0
        nextSound = 0
    }
}

/** One epoch and cadence fence shared across Activity/Service ownership and asynchronous registration. */
internal class BackgroundOrderAlertOwnership {
    var generation = 0L
        private set
    var foreground = false
        private set
    private var lastPlaybackAt = -BackgroundOrderAlertState.CADENCE_MS

    fun setForeground(value: Boolean) { foreground = value }
    fun invalidate() { generation++ }
    fun current(expected: Long): Boolean = expected == generation
    fun reservePlayback(monotonicNow: Long): Boolean {
        if (monotonicNow - lastPlaybackAt < BackgroundOrderAlertState.CADENCE_MS) return false
        lastPlaybackAt = monotonicNow
        return true
    }
}

/** Full-set freshness is independent of sound cadence and UI callbacks. Main-thread owned. */
internal class BackgroundOrderAlertReconciliation(
    private val now: () -> Long,
    private val schedule: (Long, () -> Unit) -> (() -> Unit),
    private val eligible: () -> Boolean,
    private val keepPolling: () -> Boolean,
    private val read: (Read) -> (() -> Unit),
    private val failClosed: (BackgroundOrderAlertObservation.Result) -> Unit,
) {
    companion object {
        const val HINT_FLOOR_MS = 5_000L
        // Only the existing verified, actively ringing FGS may keep this timer.
        // Six full-set reads/minute at most without hints, never idle polling.
        const val PERIOD_MS = 10_000L
        // Includes executor queueing, headers, body and main-thread completion.
        const val READ_BUDGET_MS = 20_000L
    }

    class Read internal constructor(internal val startedAt: Long)
    private var flight: Read? = null
    private var cancelRead: (() -> Unit)? = null
    private var cancelWatchdog: (() -> Unit)? = null
    private var cancelScheduled: (() -> Unit)? = null
    private var lastReadAt = -PERIOD_MS
    private var again = false
    val hasWork: Boolean get() = flight != null || cancelScheduled != null

    fun request() {
        if (!eligible()) { cancel(); return }
        if (flight != null) { again = true; return }
        // A terminal hint replaces a later periodic wake, but never bypasses the floor.
        queue((HINT_FLOOR_MS - (now() - lastReadAt)).coerceAtLeast(0))
    }

    private fun queue(delay: Long) {
        cancelScheduled?.invoke()
        cancelScheduled = schedule(delay) {
            cancelScheduled = null
            if (!eligible()) { cancel(); return@schedule }
            val work = Read(now())
            flight = work
            lastReadAt = now()
            again = false
            cancelWatchdog = schedule(READ_BUDGET_MS) {
                if (flight === work) { cancel(); failClosed(BackgroundOrderAlertObservation.Result.TIMEOUT) }
            }
            try {
                val cancellation = read(work)
                if (flight === work) cancelRead = cancellation else cancellation()
            } catch (_: Exception) {
                if (flight === work) { cancel(); failClosed(BackgroundOrderAlertObservation.Result.FAILED) }
            }
        }
    }

    /** Stale completions cannot apply state, cancel a newer read or revive an old service. */
    fun complete(work: Read, apply: () -> Unit): Boolean {
        if (flight !== work) return false
        // A delayed main looper may deliver the completion before its queued watchdog.
        if (now() - work.startedAt >= READ_BUDGET_MS) { cancel(); failClosed(BackgroundOrderAlertObservation.Result.TIMEOUT); return false }
        cancelWatchdog?.invoke()
        cancelWatchdog = null
        cancelRead = null
        flight = null
        if (!eligible()) { cancel(); return false }
        val followUp = again
        again = false
        try { apply() } catch (_: Exception) { cancel(); failClosed(BackgroundOrderAlertObservation.Result.FAILED); return false }
        if (!eligible()) { cancel(); return true }
        if (cancelScheduled != null) return true
        if (followUp) request()
        else if (keepPolling()) queue((PERIOD_MS - (now() - lastReadAt)).coerceAtLeast(0))
        return true
    }

    fun cancel() {
        flight = null
        again = false
        cancelScheduled?.invoke()
        cancelScheduled = null
        cancelWatchdog?.invoke()
        cancelWatchdog = null
        val abort = cancelRead
        cancelRead = null
        abort?.invoke()
    }
}

/** Native Stop is authoritative; automatic prepare can only retain an existing explicit opt-in. */
internal class BackgroundOrderAlertOptIn(initial: Boolean) {
    var enabled = initial
        private set
    fun prepare(explicit: Boolean): Boolean { if (explicit) enabled = true; return enabled }
    fun clear(retain: Boolean) { if (!retain) enabled = false }
}

internal object BackgroundOrderAlertProtocol {
    fun uuid(value: String): Boolean = try { UUID.fromString(value).toString() == value.lowercase(Locale.ROOT) } catch (_: Exception) { false }
    fun timestamp(value: String): Long? = try {
        if (!Regex("\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(\\.\\d{1,6})?(Z|[+-]\\d{2}:\\d{2})").matches(value)) null else {
            val normalized = value.replace(Regex("\\.(\\d{1,6})")) { "." + it.groupValues[1].padEnd(3, '0').take(3) }
            val pattern = if (normalized.contains('.')) "yyyy-MM-dd'T'HH:mm:ss.SSSXXX" else "yyyy-MM-dd'T'HH:mm:ssXXX"
            SimpleDateFormat(pattern, Locale.ROOT).apply { isLenient = false; timeZone = TimeZone.getTimeZone("UTC") }.parse(normalized)?.time
        }
    } catch (_: Exception) { null }
}

/** One background write at a time; foreground ownership supersedes the lane. */
internal class BackgroundOrderAlertTokenLane {
    private var epoch = 0L
    private var inFlight: Work? = null
    private var pending: String? = null
    private var uncertain = false
    var preparing = false
        private set

    // Deliberately not a data class: toString must not disclose an FCM token.
    class Work internal constructor(val token: String, val generation: String, internal val epoch: Long)

    private fun reset() { epoch++; inFlight = null; pending = null; uncertain = false }
    fun prepare() { reset(); preparing = true }
    fun finishPreparation() { reset(); preparing = false }

    fun offer(token: String, generation: String, unconfirmedWrite: Boolean = false): Work? {
        // The encrypted status record preserves this fence across process death.
        // An in-memory owner may coalesce a newer token behind its own write;
        // a restarted process must instead reconcile through foreground auth.
        if (unconfirmedWrite && inFlight == null) { uncertain = true; return null }
        if (preparing || uncertain) return null
        if (inFlight != null) { pending = token; return null }
        return Work(token, generation, epoch).also { inFlight = it }
    }

    fun canComplete(work: Work, currentGeneration: String): Boolean = !preparing && !uncertain &&
        work === inFlight && work.epoch == epoch && work.generation == currentGeneration

    /** Null generation means UNKNOWN: no later write until foreground reconciliation. */
    fun complete(work: Work, generation: String?): Work? {
        if (!canComplete(work, work.generation)) return null
        inFlight = null
        val next = pending
        pending = null
        if (generation == null) { uncertain = true; return null }
        if (next == null || next == work.token) return null
        return Work(next, generation, epoch).also { inFlight = it }
    }
}

/** Token maintenance may shrink a delegation, never mint or extend one. */
internal object BackgroundOrderAlertTokenRefresh {
    fun validToken(value: String): Boolean = value.length in 20..4096 &&
        value.none { it.isWhitespace() || it.isISOControl() }

    fun remaining(serverTime: Long, expiry: Long, startedAt: Long, now: Long, currentDeadline: Long): Long? {
        if (expiry <= serverTime || now < startedAt || currentDeadline <= now) return null
        val remaining = minOf(expiry - serverTime - (now - startedAt), currentDeadline - now)
        return remaining.takeIf { it > 0 }
    }
}

/** Bounded opaque hint deduplication; terminal hints cannot be reordered into a fresh arrival. */
internal class BackgroundOrderAlertHints {
    private val recent = linkedMapOf<String, Long>()
    private val terminal = linkedSetOf<String>()
    fun clear() { recent.clear(); terminal.clear() }
    fun accept(data: Map<String, String>, registration: String, wallNow: Long, monotonicNow: Long): Boolean {
        if (data.keys != setOf("version", "kind", "request_id", "expires_at", "registration_id") ||
            data["version"] != "1" || data["kind"] !in setOf("pending", "cancel") ||
            !BackgroundOrderAlertProtocol.uuid(data["request_id"].orEmpty()) ||
            !BackgroundOrderAlertProtocol.uuid(data["registration_id"].orEmpty()) || data["registration_id"] != registration) return false
        val expiry = BackgroundOrderAlertProtocol.timestamp(data["expires_at"].orEmpty()) ?: return false
        // Expiry cancellation arrives after the request deadline. It is only a refresh hint,
        // never authority to remove that request (or another request) from notification coverage.
        val age = wallNow - expiry
        if (expiry - wallNow > BackgroundOrderAlertState.HARD_TIMEOUT_MS ||
            (data["kind"] == "pending" && age >= 0) ||
            (data["kind"] == "cancel" && age > 120_000)) return false
        val id = data.getValue("request_id")
        if (data["kind"] == "pending" && id in terminal) return false
        val key = "$registration|$id|${data["kind"]}|$expiry"
        if (recent[key]?.let { monotonicNow - it < 60_000 } == true) return false
        recent[key] = monotonicNow
        if (data["kind"] == "cancel") terminal.add(id)
        while (recent.size > 64) recent.remove(recent.keys.first())
        while (terminal.size > 64) terminal.remove(terminal.first())
        return true
    }
}

internal enum class BackgroundOrderAlertHintAction { foreground, reconcile, start, fallback, none }
internal fun backgroundOrderAlertHintAction(foreground: Boolean, running: Boolean, high: Boolean, allowed: Boolean): BackgroundOrderAlertHintAction = when {
    foreground -> BackgroundOrderAlertHintAction.foreground
    !allowed -> BackgroundOrderAlertHintAction.none
    running -> BackgroundOrderAlertHintAction.reconcile
    high -> BackgroundOrderAlertHintAction.start
    else -> BackgroundOrderAlertHintAction.fallback
}

/** One-shot fallback policy, fed only a fresh authoritative FULL set; no ringing timer. */
internal object BackgroundOrderAlertFallback {
    const val VISIBILITY_MS = 60_000L
    const val MAX_HEARD = 64

    data class Plan(val timeoutMs: Long, val audible: Boolean, val heard: Map<String, Long>)

    fun plan(
        requests: Map<String, Long>,
        serverTime: Long,
        authorityRemaining: Long,
        now: Long,
        heard: Map<String, Long>,
        audioAllowed: Boolean,
        reserveSound: () -> Boolean,
    ): Plan {
        val retained = heard.filterValues { it > now }.toMutableMap()
        val deadlines = requests.mapValues { (_, expiry) ->
            now + (expiry - serverTime).coerceIn(0, BackgroundOrderAlertState.HARD_TIMEOUT_MS)
        }.filterValues { it > now }
        val timeout = minOf(VISIBILITY_MS, authorityRemaining,
            (deadlines.values.minOrNull() ?: now) - now).coerceAtLeast(0)
        if (timeout == 0L) return Plan(0, false, retained)
        val fresh = deadlines.keys.any { it !in retained }
        // Never evict a live heard fence to make space: that could re-sound a delayed duplicate.
        val capacity = (retained.keys + deadlines.keys).size <= MAX_HEARD
        val audible = fresh && capacity && audioAllowed && reserveSound()
        // Once observed, a pending ID cannot acquire a late sound merely because policy changes.
        if (capacity) deadlines.forEach { (id, expiry) -> retained[id] = maxOf(retained[id] ?: 0, expiry) }
        return Plan(timeout, audible, retained)
    }
}
