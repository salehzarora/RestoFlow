package com.restoflow.pos

/** Synthetic monotonic state only: no Firebase, HTTP, Android device, order or audio side effects. */
fun main() {
    var passed = 0
    fun scenario(name: String, body: () -> Unit) { body(); passed++; println("PASS $name") }
    fun pending(vararg ids: String) = ids.associateWith { 100_000L }

    scenario("first confirmed pending request alerts immediately and repeats at ten seconds") {
        val state = BackgroundOrderAlertState()
        state.replace(pending("one"), 0, 100_000, 0)
        check(state.shouldPlay(0))
        state.played(0)
        check(!state.shouldPlay(9_999) && state.shouldPlay(10_000))
    }
    scenario("multiple requests have one schedule; resolving one does not silence the other") {
        val state = BackgroundOrderAlertState()
        state.replace(pending("one", "two"), 0, 100_000, 0)
        state.played(0)
        state.replace(pending("two"), 1_000, 99_000, 1_000)
        check(state.count(1_000) == 1 && !state.shouldPlay(1_000) && state.shouldPlay(10_000))
    }
    scenario("duplicate and reordered server snapshots do not start a second cadence") {
        val state = BackgroundOrderAlertState()
        state.replace(pending("one", "two"), 0, 100_000, 0)
        state.played(0)
        state.replace(pending("two", "one"), 500, 99_500, 500)
        check(state.nextWake(500) == 9_500L && !state.shouldPlay(500))
    }
    scenario("confirmed empty set stops immediately after final accept or reject") {
        val state = BackgroundOrderAlertState()
        state.replace(pending("one"), 0, 100_000, 0)
        state.replace(emptyMap(), 1_000, 99_000, 1_000)
        check(!state.active(1_000) && state.nextWake(1_000) == null)
    }
    scenario("exact expiry between cadence ticks removes the final request") {
        val state = BackgroundOrderAlertState()
        state.replace(mapOf("one" to 12_300L), 0, 100_000, 0)
        state.played(10_000)
        check(state.nextWake(10_000) == 2_300L && state.active(12_299) && !state.active(12_300))
    }
    scenario("server time offset supplies deadlines without trusting local wall time") {
        val state = BackgroundOrderAlertState()
        state.replace(mapOf("one" to 4_000_030_000L), 4_000_000_000L, 50_000, 77)
        check(state.active(30_076) && !state.active(30_077))
    }
    scenario("authority expiry stops an otherwise pending request") {
        val state = BackgroundOrderAlertState()
        state.replace(pending("one"), 0, 7_000, 0)
        check(state.active(6_999) && !state.active(7_000))
    }
    scenario("expired and reordered terminal hints cannot manufacture actionable requests") {
        val state = BackgroundOrderAlertState()
        state.replace(mapOf("old" to 5L), 10, 100_000, 0)
        check(!state.active(0) && !state.shouldPlay(0))
    }
    scenario("hard fifteen-minute episode cannot be extended by delayed network completion") {
        val state = BackgroundOrderAlertState()
        state.replace(mapOf("one" to Long.MAX_VALUE), 0, Long.MAX_VALUE, 0)
        check(state.active(899_999) && !state.active(900_000))
        state.replace(mapOf("new" to Long.MAX_VALUE), 900_001, Long.MAX_VALUE, 900_001)
        check(!state.active(900_001))
    }
    scenario("logout offline revocation and failed status reads clear all schedule state") {
        for (boundary in listOf("logout", "offline", "revocation", "unknown-network", "dispose")) {
            val state = BackgroundOrderAlertState()
            state.replace(pending(boundary), 0, 100_000, 0)
            state.clear()
            check(!state.active(1) && !state.shouldPlay(1) && state.nextWake(1) == null)
        }
    }
    scenario("new explicit episode starts only after the previous state is cleared") {
        val state = BackgroundOrderAlertState()
        state.replace(mapOf("one" to Long.MAX_VALUE), 0, 1_000_000, 0)
        state.clear()
        state.replace(mapOf("two" to 2_000_000L), 1_000_000, 100_000, 1_000_000)
        check(state.active(1_000_000) && state.shouldPlay(1_000_000))
    }
    scenario("foreground to background to foreground transfer preserves a single playback reservation") {
        val owner = BackgroundOrderAlertOwnership()
        owner.setForeground(true)
        check(owner.reservePlayback(0))
        owner.setForeground(false)
        check(!owner.reservePlayback(50))
        owner.setForeground(true)
        check(!owner.reservePlayback(100) && owner.reservePlayback(10_000))
    }
    scenario("logout invalidates a delayed bind even when the same identity later returns") {
        val owner = BackgroundOrderAlertOwnership()
        val before = owner.generation
        owner.invalidate()
        owner.setForeground(true)
        check(!owner.current(before) && owner.current(owner.generation))
    }
    scenario("no independent request can reserve a second simultaneous clip") {
        val owner = BackgroundOrderAlertOwnership()
        check(owner.reservePlayback(12_000))
        repeat(20) { check(!owner.reservePlayback(12_000)) }
        check(!owner.reservePlayback(21_999) && owner.reservePlayback(22_000))
    }
    scenario("automatic prepare cannot enable default-OFF or override notification Stop") {
        val optIn = BackgroundOrderAlertOptIn(false)
        check(!optIn.prepare(false))
        check(optIn.prepare(true))
        optIn.clear(false)
        check(!optIn.prepare(false))
    }
    scenario("token rotation and transient offline retain opt-in, but logout clears it") {
        val optIn = BackgroundOrderAlertOptIn(true)
        optIn.clear(true)
        check(optIn.prepare(false))
        optIn.clear(false)
        check(!optIn.prepare(false))
    }
    val registration = "3d152b3e-5573-4467-adbd-164a53f386b8"
    fun hint(kind: String = "pending") = mapOf("version" to "1", "kind" to kind,
        "request_id" to "5b8842c6-0bfc-4bd1-821f-62149163f467", "registration_id" to registration,
        "expires_at" to "2026-10-17T00:01:00Z")
    val epoch = BackgroundOrderAlertProtocol.timestamp("2026-10-17T00:00:00Z")!!
    scenario("duplicate hint is coalesced and cancellation remains a meaningful separate hint") {
        val gate = BackgroundOrderAlertHints()
        check(gate.accept(hint(), registration, epoch, 0))
        check(!gate.accept(hint(), registration, epoch, 1))
        check(gate.accept(hint("cancel"), registration, epoch, 2))
        check(!gate.accept(hint(), registration, epoch, 3))
    }
    scenario("reordered pending after cancellation cannot resurrect an alert") {
        val gate = BackgroundOrderAlertHints()
        check(gate.accept(hint("cancel"), registration, epoch, 0))
        check(!gate.accept(hint(), registration, epoch, 1))
    }
    scenario("stale foreign malformed and extra-data notifications fail closed") {
        val gate = BackgroundOrderAlertHints()
        check(!gate.accept(hint(), "7622ef6c-e564-4ec4-bfaf-2f4edacc053a", epoch, 0))
        check(!gate.accept(hint(), registration, epoch + 60_000, 0))
        check(!gate.accept(hint() + ("request_id" to "not-an-id"), registration, epoch, 0))
        check(!gate.accept(hint() + ("customer_name" to "synthetic forbidden field"), registration, epoch, 0))
        check(!gate.accept(hint() + ("expires_at" to "2026-99-17T00:01:00Z"), registration, epoch, 0))
    }
    scenario("normal process restart has no sound authority before a fresh confirmed status read") {
        val restarted = BackgroundOrderAlertState()
        check(!restarted.active(0) && !restarted.shouldPlay(0))
        restarted.replace(pending("verified"), 0, 100_000, 0)
        check(restarted.shouldPlay(0))
    }
    scenario("downgraded messages cannot start services but still reconcile an existing service") {
        check(backgroundOrderAlertHintAction(false, false, false, true) == BackgroundOrderAlertHintAction.fallback)
        check(backgroundOrderAlertHintAction(false, true, false, true) == BackgroundOrderAlertHintAction.reconcile)
        check(backgroundOrderAlertHintAction(false, false, true, true) == BackgroundOrderAlertHintAction.start)
    }
    scenario("notification policy denial never starts service and foreground hint never owns a second poller") {
        check(backgroundOrderAlertHintAction(false, false, true, false) == BackgroundOrderAlertHintAction.none)
        check(backgroundOrderAlertHintAction(true, false, true, false) == BackgroundOrderAlertHintAction.foreground)
    }
    println("$passed native background state scenarios passed")
}
