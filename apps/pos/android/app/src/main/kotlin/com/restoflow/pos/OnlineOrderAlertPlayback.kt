package com.restoflow.pos

/** Small platform-free owner of one bounded, asynchronously prepared clip. */
internal class OnlineOrderAlertPlayback(
    private val createClip: () -> Clip,
    private val policyAllowsPlayback: () -> Boolean,
    private val scheduleTimeout: (Long, () -> Unit) -> (() -> Unit),
) {
    internal interface Clip {
        fun prepare(onReady: () -> Unit, onFinished: () -> Unit, onError: () -> Unit)
        fun start()
        fun stop()
        fun release()
    }

    private var clip: Clip? = null
    private var cancelTimeout: (() -> Unit)? = null
    private var foreground = false
    private var detached = false

    fun setForeground(value: Boolean) {
        foreground = value
        if (!value) stop()
    }

    private fun mayPlay(): Boolean = !detached && foreground && try {
        policyAllowsPlayback()
    } catch (_: Exception) {
        false
    }

    fun policyChanged() {
        if (!mayPlay()) stop()
    }

    fun play() {
        if (clip != null || !mayPlay()) return
        try {
            val next = createClip()
            clip = next
            // Includes preparation time. The bundled clip lasts < 2.5 seconds;
            // a broken decoder cannot outlive this bound or the 10s cadence.
            cancelTimeout = scheduleTimeout(5_000L) { stopIfCurrent(next) }
            next.prepare(
                onReady = {
                    // A late onPrepared must never restart a paused/stopped clip
                    // or stop a newer alert which replaced it.
                    if (clip === next) {
                        if (!mayPlay()) {
                            stop()
                        } else {
                            try {
                                next.start()
                            } catch (_: Exception) {
                                stopIfCurrent(next)
                            }
                        }
                    }
                },
                onFinished = { stopIfCurrent(next) },
                onError = { stopIfCurrent(next) },
            )
        } catch (_: Exception) {
            stop()
        }
    }

    private fun stopIfCurrent(expected: Clip) {
        if (clip === expected) stop()
    }

    fun stop() {
        val current = clip
        clip = null
        val cancel = cancelTimeout
        cancelTimeout = null
        try {
            cancel?.invoke()
        } catch (_: Exception) {
            // A scheduler teardown failure must not prevent decoder cleanup.
        }
        try {
            current?.stop()
        } catch (_: Exception) {
            // MediaPlayer can already be invalid after an error or completion.
        }
        try {
            current?.release()
        } catch (_: Exception) {
            // Release is still attempted when stop fails; never escape lifecycle.
        }
    }

    fun detach() {
        detached = true
        foreground = false
        stop()
    }
}
