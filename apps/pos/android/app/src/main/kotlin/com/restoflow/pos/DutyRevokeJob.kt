package com.restoflow.pos

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context

/** A nonperiodic cancellation-only job. The scheduler stores no credentials or identifiers. */
class DutyRevokeJob : JobService() {
    companion object {
        private const val ID = 38105
        internal fun enqueue(context: Context) {
            try {
                val jobs = context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as JobScheduler
                if (jobs.getPendingJob(ID) == null) jobs.schedule(JobInfo.Builder(ID, ComponentName(context, DutyRevokeJob::class.java))
                    .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY).build())
            } catch (_: Exception) { /* The vault keeps the receipt for the next genuine opportunity. */ }
        }
    }
    override fun onStartJob(params: JobParameters): Boolean {
        var completed = false
        var starting = true
        BackgroundOrderAlertCoordinator.get(this).drainDutyRevokes(fromJob = true) {
            completed = true
            if (!starting) jobFinished(params,false)
        }
        starting = false
        return !completed
    }
    override fun onStopJob(params: JobParameters) = false
}
