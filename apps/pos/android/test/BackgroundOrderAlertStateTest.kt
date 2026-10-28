package com.restoflow.pos

/** Synthetic monotonic state only: no Firebase, HTTP, Android device, order or audio side effects. */
fun main() {
    var passed = 0
    fun scenario(name: String, body: () -> Unit) { body(); passed++; println("PASS $name") }
    fun pending(vararg ids: String) = ids.associateWith { 100_000L }

    scenario("activation channel diagnostics preserve every permission importance and sound gate") {
        val allowed = BackgroundOrderAlertChannelPolicy(true, true, true, true, true)
        check(allowed.failureReason == null)
        for ((policy, expected) in listOf(
            allowed.copy(permissionAllowed = false) to "permission_denied",
            allowed.copy(notificationsEnabled = false) to "notifications_disabled",
            allowed.copy(channelPresent = false) to "channel_missing",
            allowed.copy(channelImportanceAllowed = false) to "channel_importance_low",
            allowed.copy(channelSoundPresent = false) to "channel_sound_missing",
        )) {
            check(policy.failureReason == expected)
            check(policy.diagnostics().keys == setOf("permission_allowed", "notifications_enabled",
                "channel_present", "channel_importance_allowed", "channel_sound_present"))
        }
        check(allowed.copy(channelSoundPresent = false).diagnostics()["channel_sound_present"] == false)
        check(BackgroundOrderAlertChannelPolicy(false, false, false, false, false).failureReason == "permission_denied")
    }

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
    scenario("background periodic full-set reconciliation stops accepted or rejected A without a later order or hint") {
        for (decision in listOf("accept", "reject")) {
            val fixture = ReconciliationFixture()
            fixture.server = pending(decision)
            fixture.loop.request()
            fixture.clock.advanceTo(0)
            check(fixture.state.count(0) == 1 && fixture.reads == 1)
            fixture.server = emptyMap()
            // No audio tick, UI resume, FCM hint or new order drives this read.
            fixture.clock.advanceTo(9_999)
            check(fixture.reads == 1 && fixture.state.active(9_999))
            fixture.clock.advanceTo(10_000)
            check(fixture.reads == 2 && !fixture.state.active(10_000))
        }
    }
    scenario("resolving A in the background preserves B and the retained ten-second cadence") {
        val fixture = ReconciliationFixture()
        fixture.server = pending("A", "B")
        fixture.loop.request()
        fixture.clock.advanceTo(0)
        fixture.state.played(0)
        fixture.server = pending("B")
        fixture.clock.advanceTo(1_000)
        fixture.loop.request() // terminal FCM is only a reason to read ALL pending requests.
        fixture.clock.advanceTo(5_000)
        check(fixture.reads == 2 && fixture.state.count(5_000) == 1)
        check(!fixture.state.shouldPlay(5_000) && fixture.state.shouldPlay(10_000))
    }
    scenario("terminal hint replaces the periodic timer while duplicate hints retain the five-second floor") {
        val fixture = ReconciliationFixture()
        fixture.server = pending("A")
        fixture.loop.request()
        fixture.clock.advanceTo(0)
        fixture.clock.advanceTo(1_000)
        repeat(20) { fixture.loop.request() }
        fixture.clock.advanceTo(4_999)
        check(fixture.reads == 1)
        fixture.clock.advanceTo(5_000)
        check(fixture.reads == 2)
        fixture.clock.advanceTo(14_999)
        check(fixture.reads == 2)
        fixture.clock.advanceTo(15_000)
        check(fixture.reads == 3)
    }
    scenario("queued or stalled status work cannot retain stale ringing past its absolute budget") {
        val fixture = ReconciliationFixture()
        fixture.state.replace(pending("A"), 0, 100_000, 0)
        fixture.holdRead = true
        fixture.loop.request()
        fixture.clock.advanceTo(0)
        val stale = fixture.held.single()
        repeat(50) { fixture.loop.request() }
        fixture.clock.advanceTo(19_999)
        check(fixture.reads == 1 && fixture.state.active(19_999))
        fixture.clock.advanceTo(20_000)
        check(fixture.failed == 1 && fixture.aborted == 1 && !fixture.state.active(20_000))
        check(!fixture.loop.complete(stale) { error("late status must not resurrect A") })
        fixture.clock.advanceTo(90_000)
        check(fixture.reads == 1)
    }
    scenario("an in-flight hint coalesces one fresh read without concurrent reads or duplicate cadence") {
        val fixture = ReconciliationFixture()
        fixture.holdRead = true
        fixture.loop.request()
        fixture.clock.advanceTo(0)
        repeat(20) { fixture.loop.request() }
        fixture.clock.advanceTo(1_000)
        val first = fixture.held.single()
        fixture.loop.complete(first) { }
        fixture.clock.advanceTo(4_999)
        check(fixture.reads == 1)
        fixture.clock.advanceTo(5_000)
        check(fixture.reads == 2)
    }
    scenario("a delayed main looper cannot accept stale completion ahead of its queued watchdog") {
        val fixture = ReconciliationFixture()
        fixture.holdRead = true
        fixture.loop.request()
        fixture.clock.advanceTo(0)
        fixture.clock.now = 20_000 // Simulate looper suspension without executing queued tasks.
        check(!fixture.loop.complete(fixture.held.single()) { error("late full set") })
        check(fixture.failed == 1 && fixture.aborted == 1)
    }
    scenario("malformed completion handling fails closed without escaping or scheduling more reads") {
        val fixture = ReconciliationFixture()
        fixture.holdRead = true
        fixture.loop.request()
        fixture.clock.advanceTo(0)
        check(!fixture.loop.complete(fixture.held.single()) { error("synthetic invalid full set") })
        fixture.clock.advanceTo(120_000)
        check(fixture.failed == 1 && fixture.reads == 1)
    }
    scenario("foreground bind or service replacement invalidates old success without cancelling the new flight") {
        for (transition in listOf("foreground", "new-bind", "service-replaced", "logout")) {
            val fixture = ReconciliationFixture()
            fixture.holdRead = true
            fixture.loop.request()
            fixture.clock.advanceTo(0)
            val old = fixture.held.single()
            fixture.loop.cancel()
            fixture.clock.advanceTo(5_000)
            fixture.loop.request()
            fixture.clock.advanceTo(5_000)
            val newer = fixture.held.last()
            check(old !== newer && fixture.aborted == 1)
            check(!fixture.loop.complete(old) { error("$transition stale result") })
            check(fixture.loop.complete(newer) { fixture.applied++ })
            check(fixture.applied == 1)
        }
    }
    scenario("authority loss rejects a completed status and schedules no new work") {
        val fixture = ReconciliationFixture()
        fixture.holdRead = true
        fixture.loop.request()
        fixture.clock.advanceTo(0)
        fixture.authorized = false
        check(!fixture.loop.complete(fixture.held.single()) { error("expired or revoked PIN") })
        fixture.clock.advanceTo(120_000)
        check(fixture.reads == 1)
    }
    scenario("service destruction cancels the periodic timer and late network work") {
        val fixture = ReconciliationFixture()
        fixture.server = pending("A")
        fixture.loop.request()
        fixture.clock.advanceTo(0)
        fixture.loop.cancel()
        fixture.clock.advanceTo(120_000)
        check(fixture.reads == 1 && fixture.failed == 0)
    }
    scenario("fallback performs one bounded authenticated read and does not create another polling owner") {
        val fixture = ReconciliationFixture()
        fixture.polling = false
        fixture.server = pending("A")
        fixture.loop.request()
        fixture.clock.advanceTo(120_000)
        check(fixture.reads == 1)
    }
    scenario("synchronous network scheduling failure fails closed and leaves no periodic work") {
        val fixture = ReconciliationFixture()
        fixture.throwRead = true
        fixture.loop.request()
        fixture.clock.advanceTo(120_000)
        check(fixture.failed == 1 && fixture.reads == 1)
    }
    scenario("process restart carries no pending authority until its independent fresh status completes") {
        val fixture = ReconciliationFixture()
        fixture.holdRead = true
        fixture.loop.request()
        fixture.clock.advanceTo(0)
        check(!fixture.state.active(0))
        fixture.loop.complete(fixture.held.single()) {
            fixture.state.replace(pending("verified B"), 0, 100_000, 0)
        }
        check(fixture.state.active(0))
    }
    scenario("natural request expiry still stops between independent status reads") {
        val fixture = ReconciliationFixture()
        fixture.server = mapOf("A" to 12_300)
        fixture.loop.request()
        fixture.clock.advanceTo(0)
        check(fixture.state.active(12_299) && !fixture.state.active(12_300))
    }
    scenario("cold FCM callback acquires an OS owner before returning, without awaiting HTTP") {
        var acquired = false
        var callbackReturned = false
        var networkStarted = false
        var queued: (() -> Unit)? = null
        BackgroundOrderAlertCallbackHandoff.run(
            post = { queued = it }, fallback = { error("unexpected fallback") },
            action = { check(!callbackReturned); acquired = true },
            await = { latch -> queued!!(); check(latch.count == 0L); true },
        )
        callbackReturned = true
        check(acquired && !networkStarted)
        // The service/job can safely own the subsequent asynchronous status read.
        networkStarted = true
        check(networkStarted)
    }
    scenario("a delayed main handoff acquires a job before callback return and cancels stale dispatch") {
        var queued: (() -> Unit)? = null
        var jobs = 0
        BackgroundOrderAlertCallbackHandoff.run(
            post = { queued = it }, fallback = { jobs++ },
            action = { error("late FGS start outside FCM callback") }, await = { false },
        )
        check(jobs == 1)
        queued!!()
        check(jobs == 1)
    }
    scenario("failed dispatch or service acquisition falls back without losing callback lifetime") {
        for (failure in listOf("post", "service")) {
            var jobs = 0
            BackgroundOrderAlertCallbackHandoff.run(
                post = { if (failure == "post") error("synthetic scheduling failure") else it() },
                fallback = { jobs++ }, action = { error("synthetic FGS refusal") },
                await = { it.count == 0L },
            )
            check(jobs == 1)
        }
    }
    scenario("one job owner coalesces duplicates and stale completion cannot finish a newer job") {
        val owner = BackgroundOrderAlertJobOwnership()
        var completions = 0
        val first = owner.begin { completions++ }!!
        check(owner.begin { error("duplicate owner") } == null)
        check(owner.complete(first) && completions == 1)
        val next = owner.begin { completions++ }!!
        check(!owner.complete(first) && !owner.cancel(first) && owner.current === next)
        check(owner.complete(next) && completions == 2)
    }
    scenario("OS cancellation releases only its job and does not acknowledge or retry stale work") {
        val owner = BackgroundOrderAlertJobOwnership()
        val cancelled = owner.begin { error("OS-stopped job must not call jobFinished") }!!
        check(owner.cancel(cancelled))
        val next = owner.begin {}!!
        check(!owner.complete(cancelled) && owner.current === next)
        check(owner.cancel(next) && owner.current == null)
    }
    scenario("timed-out callback enqueues a fresh obligation behind an older snapshot") {
        val pendingWork = java.util.ArrayDeque<Int>()
        val completedWork = mutableListOf<Int>()
        pendingWork.add(1)
        val queue = BackgroundOrderAlertJobQueue(take = { pendingWork.pollFirst() }, complete = { id: Int -> completedWork.add(id); Unit })
        check(queue.beginRead()) // Old snapshot is now in flight.
        var delayed: (() -> Unit)? = null
        BackgroundOrderAlertCallbackHandoff.run(
            post = { delayed = it }, fallback = { pendingWork.add(2); Unit },
            await = { false }, action = { error("late FGS acquisition") },
        )
        delayed!!()
        queue.completeRead()
        check(completedWork == listOf(1) && pendingWork.toList() == listOf(2))
        check(queue.beginRead()) // New pending/terminal state requires another full read.
        queue.completeRead()
        check(completedWork == listOf(1, 2) && !queue.beginRead())
    }
    scenario("job queue coalesces queued hints but never consumes an arrival at completion") {
        val pendingWork = java.util.ArrayDeque<Int>()
        val completed = mutableListOf<Int>()
        pendingWork.addAll(listOf(1, 2, 3))
        val queue = BackgroundOrderAlertJobQueue(take = { pendingWork.pollFirst() }, complete = { id: Int -> completed.add(id); Unit })
        check(queue.beginRead())
        pendingWork.add(4)
        queue.completeRead()
        check(completed == listOf(1, 2, 3))
        check(queue.beginRead())
        queue.completeRead()
        check(completed == listOf(1, 2, 3, 4))
        check(!queue.beginRead()) // OS dequeue, rather than jobFinished, owns empty/arrival race.
    }
    scenario("coalesced terminal hint retains the fallback owner through the required follow-up full set") {
        val fixture = ReconciliationFixture()
        fixture.polling = false
        fixture.holdRead = true
        fixture.loop.request()
        fixture.clock.advanceTo(0)
        val first = fixture.held.single()
        fixture.loop.request() // terminal/deleted hint while the earlier snapshot is in flight
        fixture.loop.complete(first) { fixture.state.replace(pending("A", "B"), 0, 100_000, 0) }
        check(fixture.loop.hasWork)
        fixture.clock.advanceTo(5_000)
        fixture.loop.complete(fixture.held.last()) { fixture.state.replace(pending("B"), 5_000, 95_000, 5_000) }
        check(!fixture.loop.hasWork && fixture.state.count(5_000) == 1)
        check(fixture.state.shouldPlay(5_000)) // A resolution cannot silence genuinely pending B.
    }
    scenario("lost terminal hint removes only resolved A at the accelerated read and preserves B cadence") {
        val fixture = ReconciliationFixture()
        fixture.server = pending("A", "B")
        fixture.loop.request()
        fixture.clock.advanceTo(0)
        fixture.state.played(0)
        fixture.server = pending("B")
        fixture.clock.advanceTo(10_000) // Deliberately no FCM, foreground or UI callback.
        check(fixture.reads == 2 && fixture.state.count(10_000) == 1)
        check(fixture.state.shouldPlay(10_000))
        fixture.state.played(10_000)
        check(!fixture.state.shouldPlay(10_001))
        fixture.server = emptyMap()
        fixture.clock.advanceTo(20_000)
        check(!fixture.state.active(20_000) && !fixture.loop.hasWork)
    }
    scenario("an empty verified full set never creates idle periodic polling") {
        val fixture = ReconciliationFixture()
        fixture.loop.request()
        fixture.clock.advanceTo(120_000)
        check(fixture.reads == 1 && !fixture.loop.hasWork)
    }
    scenario("active accelerated reconciliation cannot extend its hard episode or create a new sound owner") {
        val fixture = ReconciliationFixture()
        fixture.authorityUntil = 2_000_000
        fixture.server = mapOf("A" to 2_000_000)
        fixture.loop.request()
        fixture.clock.advanceTo(1_000_000)
        check(!fixture.state.active(1_000_000) && !fixture.loop.hasWork)
        check(fixture.reads <= 91) // Initial read + at most90 periodic reads in15min.
    }
    scenario("closed observation vocabulary cannot serialize payloads credentials or exception messages") {
        val canary = "SECRET_TOKEN_CUSTOMER_CANARY"
        val records = mutableListOf<String>()
        for (event in BackgroundOrderAlertObservation.Event.entries) {
            for (result in BackgroundOrderAlertObservation.Result.entries) {
                records += BackgroundOrderAlertObservation.encode(event, result, 1, 1, 1)
            }
        }
        for (authority in BackgroundOrderAlertObservation.Authority.entries) {
            for (channel in BackgroundOrderAlertObservation.Channel.entries) {
                records += BackgroundOrderAlertObservation.encode(BackgroundOrderAlertObservation.Event.AUTHORITY,
                    BackgroundOrderAlertObservation.Result.REFUSED, 2, 2, 2,
                    authority = authority, channel = channel, pendingCount = 50, foreground = false)
            }
        }
        val fixture = ReconciliationFixture()
        fixture.holdRead = true
        fixture.loop.request()
        fixture.clock.advanceTo(0)
        fixture.loop.complete(fixture.held.single()) { error(canary) }
        records += BackgroundOrderAlertObservation.encode(BackgroundOrderAlertObservation.Event.STATUS_COMPLETE,
            fixture.failureResult!!, 3, 3, 3)
        check(records.none { it.contains(canary) || it.contains("Bearer") || it.contains("Exception") })
        check(records.all { it.length < 450 && it.matches(Regex("[A-Za-z0-9_= ]+")) })
        check(records.first().contains("authority=NULL") && records.first().contains("pending_count=NULL"))
        check(fixture.failureResult == BackgroundOrderAlertObservation.Result.FAILED)
    }
    scenario("invalid diagnostic counters are rejected rather than widened or silently clamped") {
        for (count in listOf(-1, 51)) {
            check(runCatching { BackgroundOrderAlertObservation.encode(BackgroundOrderAlertObservation.Event.PENDING_APPLIED,
                BackgroundOrderAlertObservation.Result.APPLIED, 1, 1, 1, pendingCount = count) }.isFailure)
        }
    }
    println("$passed native background state scenarios passed")
}

private class ReconciliationClock {
    var now = 0L
    private class Task(val at: Long, val action: () -> Unit) { var cancelled = false }
    private val tasks = mutableListOf<Task>()
    fun schedule(delay: Long, action: () -> Unit): () -> Unit {
        val task = Task(now + delay, action)
        tasks.add(task)
        return { task.cancelled = true }
    }
    fun advanceTo(target: Long) {
        check(target >= now)
        var runs = 0
        while (true) {
            val next = tasks.filter { !it.cancelled && it.at <= target }.minByOrNull { it.at } ?: break
            check(++runs < 1_000)
            tasks.remove(next)
            now = next.at
            next.action()
        }
        now = target
    }
}

private class ReconciliationFixture {
    val clock = ReconciliationClock()
    val state = BackgroundOrderAlertState()
    var authorized = true
    var authorityUntil = 100_000L
    var failureResult: BackgroundOrderAlertObservation.Result? = null
    var polling = true
    var holdRead = false
    var throwRead = false
    var reads = 0
    var failed = 0
    var aborted = 0
    var applied = 0
    var server = emptyMap<String, Long>()
    val held = mutableListOf<BackgroundOrderAlertReconciliation.Read>()
    val loop: BackgroundOrderAlertReconciliation = BackgroundOrderAlertReconciliation(
        now = { clock.now },
        schedule = clock::schedule,
        eligible = { authorized },
        keepPolling = { polling && state.active(clock.now) },
        read = { work ->
            reads++
            if (throwRead) error("synthetic executor rejection")
            held.add(work)
            if (!holdRead) clock.schedule(0) {
                loop.complete(work) {
                    state.replace(server, clock.now, authorityUntil - clock.now, clock.now)
                    applied++
                }
            }
            val cancel: () -> Unit = { aborted++ }
            cancel
        },
        failClosed = { result -> failureResult = result; failed++; state.clear(); authorized = false },
    )
}
