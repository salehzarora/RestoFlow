package com.restoflow.pos

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.app.job.JobWorkItem
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.restoflow.pos.BackgroundOrderAlertObservation.Event as AlertEvent
import com.restoflow.pos.BackgroundOrderAlertObservation.Result as AlertResult

/** OS-owned refresh obligations. Work items contain no credentials, hints or identity. */
class BackgroundOrderAlertJobService : JobService() {
    companion object {
        private const val JOB_ID = 38104
        @Synchronized fun enqueue(context: Context): Boolean {
            val accepted = try {
            if (!BuildConfig.BIZBOT_BACKGROUND_ORDER_ALERTS || Build.VERSION.SDK_INT < 26) false else {
                val scheduler = context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as JobScheduler
                // enqueue preserves a new obligation even while an older snapshot is
                // in flight. schedule/getPendingJob would lose that arrival at finish.
                scheduler.enqueue(
                    JobInfo.Builder(JOB_ID, ComponentName(context, BackgroundOrderAlertJobService::class.java))
                        .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY).build(),
                    JobWorkItem(Intent())
                ) == JobScheduler.RESULT_SUCCESS
            }
            } catch (_: Exception) { false } // No permission to notify without verification.
            BackgroundOrderAlertCoordinator.observe(AlertEvent.JOB_ENQUEUE, if (accepted) AlertResult.ACCEPTED else AlertResult.REFUSED)
            return accepted
        }
    }

    private var cancel: (() -> Unit)? = null
    private val handler = Handler(Looper.getMainLooper())
    private var expire: Runnable? = null
    private var active: JobParameters? = null
    private var queue: BackgroundOrderAlertJobQueue<JobWorkItem>? = null

    override fun onStartJob(params: JobParameters): Boolean {
        BackgroundOrderAlertCoordinator.observe(AlertEvent.JOB_START, AlertResult.ENTER)
        if (!BuildConfig.BIZBOT_BACKGROUND_ORDER_ALERTS || Build.VERSION.SDK_INT < 26) return false
        active = params
        queue = BackgroundOrderAlertJobQueue(
            take = { params.dequeueWork() }, complete = { params.completeWork(it) },
        )
        // A stream of real hints cannot extend this invocation's absolute budget.
        expire = Runnable { stopCurrent(params, cancelScheduledJob = true, result = AlertResult.TIMEOUT) }.also {
            handler.postDelayed(it, BackgroundOrderAlertReconciliation.READ_BUDGET_MS + BackgroundOrderAlertReconciliation.HINT_FLOOR_MS)
        }
        readNext(params)
        return active === params
    }

    private fun readNext(params: JobParameters) {
        if (active !== params) return
        try {
            val work = queue ?: return
            if (!work.beginRead()) {
                // dequeueWork() returning null after completed work atomically finishes
                // the OS job. Do not call jobFinished: it can discard a racing enqueue.
                stopCurrent(params, cancelScheduledJob = false)
                return
            }
            cancel = BackgroundOrderAlertCoordinator.get(this).startFallbackJob {
                if (active !== params) return@startFallbackJob
                cancel = null
                try { work.completeRead(); readNext(params) }
                catch (_: Exception) { stopCurrent(params, cancelScheduledJob = true) }
            }
            if (cancel == null && active === params) {
                // Foreground/FGS ownership, expired authority or policy refusal. No
                // status retry or permission extension; discard only refresh signals.
                stopCurrent(params, cancelScheduledJob = true)
            }
        } catch (_: Exception) {
            stopCurrent(params, cancelScheduledJob = true)
        }
    }

    private fun stopCurrent(params: JobParameters, cancelScheduledJob: Boolean, result: AlertResult = AlertResult.STOPPED) {
        if (active !== params) return
        BackgroundOrderAlertCoordinator.observe(AlertEvent.JOB_STOP, result)
        active = null
        queue = null
        val stop = cancel
        expire?.let { handler.removeCallbacks(it) }
        expire = null
        cancel = null
        try { stop?.invoke() } catch (_: Exception) { }
        if (cancelScheduledJob) {
            try { (getSystemService(Context.JOB_SCHEDULER_SERVICE) as JobScheduler).cancel(JOB_ID) }
            catch (_: Exception) { }
        }
    }

    override fun onStopJob(params: JobParameters): Boolean {
        stopCurrent(params, cancelScheduledJob = false)
        return false // A later real hint can request a fresh read; no automatic replay.
    }

    override fun onDestroy() {
        active?.let { stopCurrent(it, cancelScheduledJob = false) }
        super.onDestroy()
    }
}
