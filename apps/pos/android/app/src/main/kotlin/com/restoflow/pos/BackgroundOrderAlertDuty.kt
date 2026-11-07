package com.restoflow.pos

/** A request is owned by the exact activation, employee/device scope and transport generation.
 * Sequence is local to the process; outstanding HTTP callbacks cannot survive process death. */
internal data class DutyScope(val consent: String, val installation: String, val identity: String,
    val shift: String, val registration: String, val transport: String, val policy: String)

internal class DutyReadFence {
    data class Read(val scope: DutyScope, val sequence: Long)
    private var sequence = 0L
    fun begin(scope: DutyScope) = Read(scope, ++sequence)
    fun invalidate() { ++sequence }
    fun current(read: Read, scope: DutyScope?) = read.sequence == sequence && read.scope == scope
}

internal object BackgroundOrderAlertDuty {
    // Reserve room before creating another consent. Never evict an unacknowledged cancellation.
    const val MAX_PENDING_REVOKES = 8
    fun needsRevocation(active: Boolean, enrollmentArmed: Boolean) = active || enrollmentArmed
    fun stopMatches(receipt: String?, activeConsent: String?) = receipt == activeConsent
    fun wakeMatches(consent: String?, transport: String?, scope: DutyScope?) =
        if (scope == null) consent == null && transport == null else consent == scope.consent && transport == scope.transport
    fun predicate(value: Any?, expected: Boolean) = value is Boolean && value == expected
    fun boundFlagsValid(enabled: Any?, optedIn: Any?, unknown: Any?, rotating: Any?) =
        predicate(enabled,true) && predicate(optedIn,true) && unknown is Boolean && rotating is Boolean
    fun mayRead(enabled: Any?, optedIn: Any?, unknown: Any?, rotating: Any?) =
        boundFlagsValid(enabled,optedIn,unknown,rotating) && predicate(rotating,false)
    fun ready(enabled: Any?, optedIn: Any?, unknown: Any?, rotating: Any?) =
        mayRead(enabled,optedIn,unknown,rotating) && predicate(unknown,false)

    fun validReply(ok: Any?, consent: Any?, registration: Any?, generation: Any?, scope: DutyScope,
                   rotating: Boolean = false): Boolean =
        predicate(ok, true) && consent == scope.consent && registration == scope.registration &&
            generation is String && BackgroundOrderAlertProtocol.uuid(generation) &&
            (rotating || generation == scope.transport)

    /** A confirmed absolute end can only shrink. Charge the full request latency. */
    fun remaining(server: Long, end: Long, maxEnd: Long, started: Long, now: Long, previousDeadline: Long?): Long? {
        if (end > maxEnd || end <= server || now < started) return null
        val serverRemaining = end - server - (now - started)
        return minOf(serverRemaining, previousDeadline?.minus(now) ?: serverRemaining).takeIf { it > 0 }
    }

    data class Revocation(val installation: String, val consent: String, val secret: String)
    fun enqueue(queue: List<Revocation>, proof: Revocation): List<Revocation> {
        val existing = queue.find { it.consent == proof.consent }
        if (existing != null) { require(existing == proof); return queue }
        require(queue.size < MAX_PENDING_REVOKES)
        return queue + proof
    }
    fun acknowledge(queue: List<Revocation>, issued: Revocation, ok: Any?, echoedConsent: Any?): List<Revocation> {
        if (!predicate(ok, true) || issued.consent != echoedConsent) return queue
        return queue.filterNot { it == issued }
    }
}
