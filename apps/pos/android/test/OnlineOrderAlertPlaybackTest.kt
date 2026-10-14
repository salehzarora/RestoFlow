package com.restoflow.pos

// Dependency-free JVM tests. Run via tools/check_online_order_alert_audio.ps1.
private class FakeClip : OnlineOrderAlertPlayback.Clip {
    var starts = 0
    var stops = 0
    var releases = 0
    var prepareFails = false
    var startFails = false
    var stopFails = false
    lateinit var ready: () -> Unit
    lateinit var finished: () -> Unit
    lateinit var error: () -> Unit

    override fun prepare(onReady: () -> Unit, onFinished: () -> Unit, onError: () -> Unit) {
        ready = onReady
        finished = onFinished
        error = onError
        if (prepareFails) throw IllegalStateException("prepare failed")
    }

    override fun start() {
        starts++
        if (startFails) throw IllegalStateException("start failed")
    }

    override fun stop() {
        stops++
        if (stopFails) throw IllegalStateException("stop failed")
    }

    override fun release() {
        releases++
    }
}

private class Harness {
    val clips = mutableListOf<FakeClip>()
    var allowed = true
    var failPolicy = false
    var failCreate = false
    var configure: (FakeClip) -> Unit = {}
    var timeout: (() -> Unit)? = null
    var timeoutDelay = 0L
    var cancellations = 0
    var failCancellation = false
    val playback = OnlineOrderAlertPlayback(
        createClip = {
            if (failCreate) throw IllegalStateException("decoder unavailable")
            FakeClip().also { configure(it); clips.add(it) }
        },
        policyAllowsPlayback = {
            if (failPolicy) throw SecurityException("policy unavailable")
            allowed
        },
        scheduleTimeout = { delay, action ->
            timeoutDelay = delay
            timeout = action
            val cancel: () -> Unit = {
                cancellations++
                timeout = null
                if (failCancellation) throw IllegalStateException("scheduler unavailable")
            }
            cancel
        },
    )

    fun begin(): FakeClip {
        playback.setForeground(true)
        playback.play()
        return clips.last()
    }
}

fun main() {
    var passed = 0
    fun scenario(name: String, body: () -> Unit) {
        body()
        passed++
        println("PASS $name")
    }

    scenario("foreground-only and policy-denied playback allocates nothing") {
        val h = Harness()
        h.playback.play()
        check(h.clips.isEmpty())
        h.playback.setForeground(true)
        h.allowed = false
        h.playback.play()
        check(h.clips.isEmpty())
        h.failPolicy = true
        h.playback.play()
        check(h.clips.isEmpty())
    }
    scenario("one clip during both async preparation and playback") {
        val h = Harness()
        val clip = h.begin()
        h.playback.play()
        check(h.clips.size == 1 && clip.starts == 0)
        clip.ready()
        h.playback.play()
        check(h.clips.size == 1 && clip.starts == 1)
        check(h.timeoutDelay == 5_000L)
    }
    scenario("completion releases once and allows the next cadence") {
        val h = Harness()
        val clip = h.begin()
        clip.ready()
        clip.finished()
        clip.finished()
        clip.error()
        check(clip.releases == 1 && clip.stops == 1 && h.cancellations == 1)
        h.playback.play()
        check(h.clips.size == 2)
    }
    scenario("stop during preparation prevents late start") {
        val h = Harness()
        val clip = h.begin()
        h.playback.stop()
        clip.ready()
        check(clip.starts == 0 && clip.releases == 1)
    }
    scenario("stale preparation completion and error cannot affect a new clip") {
        val h = Harness()
        val old = h.begin()
        val oldTimeout = h.timeout!!
        h.playback.stop()
        h.playback.play()
        val current = h.clips.last()
        old.ready()
        old.finished()
        old.error()
        oldTimeout()
        current.ready()
        check(old.starts == 0 && old.releases == 1)
        check(current.starts == 1 && current.releases == 0)
    }
    scenario("pause releases immediately and late decoder callback stays silent") {
        val h = Harness()
        val clip = h.begin()
        h.playback.setForeground(false)
        clip.ready()
        h.playback.play()
        check(clip.releases == 1 && clip.starts == 0 && h.clips.size == 1)
        h.playback.setForeground(true)
        h.playback.play()
        check(h.clips.size == 2)
    }
    scenario("policy rechecked after preparation") {
        val h = Harness()
        val clip = h.begin()
        h.allowed = false
        clip.ready()
        check(clip.starts == 0 && clip.releases == 1)
    }
    scenario("ringer or DND policy change releases an already playing clip") {
        val h = Harness()
        val clip = h.begin()
        clip.ready()
        h.allowed = false
        h.playback.policyChanged()
        check(clip.starts == 1 && clip.stops == 1 && clip.releases == 1)
    }
    scenario("decoder errors release and later cadence can retry") {
        val h = Harness()
        val clip = h.begin()
        clip.error()
        check(clip.releases == 1)
        h.playback.play()
        check(h.clips.size == 2)
    }
    scenario("preparation exceptions release without escaping") {
        val h = Harness()
        h.configure = { it.prepareFails = true }
        val clip = h.begin()
        check(clip.releases == 1)
        h.playback.play()
        check(h.clips.size == 2 && h.clips.last().releases == 1)
    }
    scenario("start exceptions release without escaping") {
        val h = Harness()
        h.configure = { it.startFails = true }
        val clip = h.begin()
        clip.ready()
        check(clip.releases == 1)
    }
    scenario("stop exceptions never prevent release") {
        val h = Harness()
        h.configure = { it.stopFails = true }
        val clip = h.begin()
        h.playback.stop()
        h.playback.stop()
        check(clip.stops == 1 && clip.releases == 1)
    }
    scenario("scheduler teardown exceptions never prevent decoder release") {
        val h = Harness()
        val clip = h.begin()
        h.failCancellation = true
        h.playback.stop()
        check(clip.stops == 1 && clip.releases == 1)
    }
    scenario("bounded timeout releases a stuck decoder") {
        val h = Harness()
        val clip = h.begin()
        h.timeout!!()
        clip.ready()
        check(clip.releases == 1 && clip.starts == 0 && h.timeout == null)
    }
    scenario("bounded timeout also releases a playing clip") {
        val h = Harness()
        val clip = h.begin()
        clip.ready()
        h.timeout!!()
        check(clip.releases == 1 && clip.stops == 1 && h.timeout == null)
    }
    scenario("detach is terminal idempotent and silences late callbacks") {
        val h = Harness()
        val clip = h.begin()
        h.playback.detach()
        h.playback.detach()
        h.playback.setForeground(true)
        h.playback.play()
        clip.ready()
        check(clip.releases == 1 && clip.starts == 0 && h.clips.size == 1)
    }
    scenario("factory failure leaves room for a later valid clip") {
        val h = Harness()
        h.failCreate = true
        h.playback.setForeground(true)
        h.playback.play()
        check(h.clips.isEmpty())
        h.failCreate = false
        h.playback.play()
        check(h.clips.size == 1)
    }
    println("$passed native audio scenarios passed")
}
