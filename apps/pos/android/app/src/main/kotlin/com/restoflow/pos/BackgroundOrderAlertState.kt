package com.restoflow.pos

import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import java.util.UUID

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
        if (expiry <= wallNow || expiry - wallNow > BackgroundOrderAlertState.HARD_TIMEOUT_MS) return false
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
