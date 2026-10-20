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
    scenario("expired cancel is a bounded refresh signal, never a new pending request") {
        val gate = BackgroundOrderAlertHints()
        check(gate.accept(hint("cancel"), registration, epoch + 60_001, 0))
        check(!gate.accept(hint(), registration, epoch + 60_001, 1))
        check(!BackgroundOrderAlertHints().accept(hint("cancel"), registration, epoch + 180_001, 0))
    }
    scenario("verified fallback requests one sound, bounded visibility and no repeating schedule") {
        var reservations = 0
        val first = BackgroundOrderAlertFallback.plan(pending("A"), 0, 100_000, 0, emptyMap(), true) { reservations++; true }
        check(first.audible && first.timeoutMs == 60_000L && reservations == 1)
        val duplicate = BackgroundOrderAlertFallback.plan(pending("A"), 61_000, 39_000, 61_000, first.heard, true) { error("duplicate sound") }
        check(!duplicate.audible && duplicate.timeoutMs == 39_000L)
    }
    scenario("heard fences survive process recreation, notification expiry and delayed duplicate hints") {
        val first = BackgroundOrderAlertFallback.plan(pending("A"), 0, 100_000, 0, emptyMap(), true) { true }
        val restoredVault = first.heard.toMap()
        val restarted = BackgroundOrderAlertFallback.plan(pending("A"), 70_000, 30_000, 70_000, restoredVault, true) { error("restarted duplicate") }
        check(!restarted.audible && restarted.timeoutMs == 30_000L)
    }
    scenario("fresh B can alert once while A notification remains, without re-alerting A or B") {
        val owner = BackgroundOrderAlertOwnership()
        val first = BackgroundOrderAlertFallback.plan(pending("A"), 0, 100_000, 0, emptyMap(), true) { owner.reservePlayback(0) }
        check(first.audible)
        val next = BackgroundOrderAlertFallback.plan(pending("A", "B"), 11_000, 89_000, 11_000, first.heard, true) { owner.reservePlayback(11_000) }
        check(next.audible && next.timeoutMs == 60_000L)
        val duplicate = BackgroundOrderAlertFallback.plan(pending("A", "B"), 22_000, 78_000, 22_000, next.heard, true) { error("already alerted") }
        check(!duplicate.audible)
    }
    scenario("authoritative final acceptance rejection and expiry each cancel fallback coverage") {
        for (terminal in listOf("accepted", "rejected", "expired")) {
            val first = BackgroundOrderAlertFallback.plan(pending(terminal), 0, 100_000, 0, emptyMap(), true) { true }
            val result = BackgroundOrderAlertFallback.plan(emptyMap(), 1_000, 99_000, 1_000, first.heard, true) { error("terminal sound") }
            check(result.timeoutMs == 0L && !result.audible)
        }
    }
    scenario("cancel A cannot remove B; only full server truth selects fallback coverage") {
        val first = BackgroundOrderAlertFallback.plan(pending("A", "B"), 0, 100_000, 0, emptyMap(), true) { true }
        val remaining = BackgroundOrderAlertFallback.plan(pending("B"), 1_000, 99_000, 1_000, first.heard, true) { error("B already covered") }
        check(!remaining.audible && remaining.timeoutMs == 60_000L && "B" in remaining.heard)
        val falseCancel = BackgroundOrderAlertFallback.plan(pending("A", "B"), 2_000, 98_000, 2_000, remaining.heard, true) { error("hint is not authority") }
        check(falseCancel.timeoutMs > 0 && !falseCancel.audible)
    }
    scenario("fallback expiry is capped by earliest request and real authority, including clock offset") {
        val offset = 4_000_000_000L
        val request = BackgroundOrderAlertFallback.plan(mapOf("A" to offset + 4_000), offset, 99_000, 500, emptyMap(), true) { true }
        check(request.timeoutMs == 4_000L)
        val authority = BackgroundOrderAlertFallback.plan(pending("A"), 0, 1_500, 0, emptyMap(), true) { true }
        check(authority.timeoutMs == 1_500L)
        val expired = BackgroundOrderAlertFallback.plan(mapOf("A" to offset), offset + 1, 99_000, 500, emptyMap(), true) { error("expired") }
        check(expired.timeoutMs == 0L)
    }
    scenario("denied sound policy stays silent and a delayed duplicate cannot ring after unmuting") {
        for (policy in listOf("permission", "channel-muted", "DND", "silent", "vibrate", "zero-volume")) {
            val first = BackgroundOrderAlertFallback.plan(pending(policy), 0, 100_000, 0, emptyMap(), false) { error("policy denied") }
            check(!first.audible)
            val retry = BackgroundOrderAlertFallback.plan(pending(policy), 10_000, 90_000, 10_000, first.heard, true) { error("no late ring") }
            check(!retry.audible)
        }
    }
    scenario("fallback foreground and FGS share one playback reservation during handoff") {
        val owner = BackgroundOrderAlertOwnership()
        val first = BackgroundOrderAlertFallback.plan(pending("A"), 0, 100_000, 0, emptyMap(), true) { owner.reservePlayback(0) }
        check(first.audible)
        owner.setForeground(true)
        check(!owner.reservePlayback(1))
        owner.setForeground(false)
        check(!owner.reservePlayback(9_999) && owner.reservePlayback(10_000))
        val next = BackgroundOrderAlertFallback.plan(pending("B"), 10_000, 90_000, 10_000, first.heard, true) { owner.reservePlayback(10_000) }
        check(!next.audible)
    }
    scenario("bounded deduplication never evicts a live fence to sound another duplicate") {
        val heard = (0 until BackgroundOrderAlertFallback.MAX_HEARD).associate { "heard-$it" to 100_000L }
        val full = BackgroundOrderAlertFallback.plan(pending("new"), 0, 100_000, 0, heard, true) { error("capacity must fail silent") }
        check(!full.audible && full.heard == heard)
    }
    scenario("token refresh preserves existing delegation cutoff even if a response requests longer authority") {
        check(BackgroundOrderAlertTokenRefresh.remaining(1_000, 999_000, 100, 200, 5_000) == 4_800L)
        check(BackgroundOrderAlertTokenRefresh.remaining(1_000, 2_000, 100, 200, 5_000) == 900L)
    }
    scenario("token refresh cannot recover expired authority or manufacture time after a clock reversal") {
        check(BackgroundOrderAlertTokenRefresh.remaining(1_000, 1_000, 100, 200, 5_000) == null)
        check(BackgroundOrderAlertTokenRefresh.remaining(1_000, 2_000, 100, 200, 200) == null)
        check(BackgroundOrderAlertTokenRefresh.remaining(1_000, 1_050, 100, 200, 5_000) == null)
        check(BackgroundOrderAlertTokenRefresh.remaining(1_000, 2_000, 200, 100, 5_000) == null)
    }
    scenario("token refresh accepts opaque SDK tokens while rejecting oversized whitespace or control input") {
        check(BackgroundOrderAlertTokenRefresh.validToken("synthetic-firebase-token:1234567890"))
        for (bad in listOf("", "short", "a".repeat(4097), "a".repeat(20) + " ", "a".repeat(20) + "\n")) {
            check(!BackgroundOrderAlertTokenRefresh.validToken(bad))
        }
    }
    scenario("foreground preparation fences old token success and denial before native bind") {
        val lane = BackgroundOrderAlertTokenLane()
        val oldRequest = lane.offer("A", "G0")!!
        check(lane.canComplete(oldRequest, "G0"))
        lane.prepare()
        check(lane.preparing && !lane.canComplete(oldRequest, "G0"))
        check(lane.offer("B", "G0") == null)
        lane.finishPreparation()
        check(!lane.preparing && !lane.canComplete(oldRequest, "G0"))
        check(lane.canComplete(lane.offer("B", "G1")!!, "G1"))
    }
    scenario("bind or clear invalidates in-flight token completions without enabling another audio owner") {
        val lane = BackgroundOrderAlertTokenLane()
        val oldRequest = lane.offer("A", "G0")!!
        lane.finishPreparation()
        check(!lane.canComplete(oldRequest, "G0"))
        val newerRequest = lane.offer("B", "G1")!!
        check(lane.canComplete(newerRequest, "G1") && !lane.canComplete(oldRequest, "G0"))
    }
    scenario("back-to-back background tokens serialize with the successfully committed generation") {
        val lane = BackgroundOrderAlertTokenLane()
        val first = lane.offer("A", "G0")!!
        check(lane.offer("B", "G0") == null)
        check(lane.canComplete(first, "G0"))
        val second = lane.complete(first, "G1")!!
        check(second.token == "B" && second.generation == "G1")
        check(!lane.canComplete(second, "G0") && lane.canComplete(second, "G1"))
        check(lane.complete(second, "G2") == null)
    }
    scenario("background rotation coalesces to the latest token without invalidating the active result") {
        val lane = BackgroundOrderAlertTokenLane()
        val first = lane.offer("A", "G0")!!
        check(lane.offer("B", "G0") == null && lane.offer("C", "G0") == null)
        val latest = lane.complete(first, "G1")!!
        check(latest.token == "C" && latest.generation == "G1")
        check(lane.offer("C", "G1") == null)
        check(lane.complete(latest, "G2") == null)
    }
    scenario("an unknown background commit never starts another token write with an uncertain generation") {
        val lane = BackgroundOrderAlertTokenLane()
        val first = lane.offer("A", "G0")!!
        check(lane.offer("B", "G0") == null)
        check(lane.complete(first, null) == null)
        check(lane.offer("B", "G0") == null && lane.offer("C", "G1") == null)
        lane.prepare()
        lane.finishPreparation()
        check(lane.canComplete(lane.offer("C", "G2")!!, "G2"))
    }
    scenario("process recreation retains the unconfirmed-write fence until a genuine foreground bind") {
        val original = BackgroundOrderAlertTokenLane()
        val first = original.offer("A", "G0")!!
        check(original.offer("B", "G0", true) == null)
        check(original.canComplete(first, "G0"))
        val restarted = BackgroundOrderAlertTokenLane()
        check(restarted.offer("B", "G0", true) == null)
        check(restarted.offer("B", "G0") == null)
        restarted.prepare()
        restarted.finishPreparation()
        check(restarted.canComplete(restarted.offer("B", "G1", false)!!, "G1"))
    }
    println("$passed native background state scenarios passed")
}
