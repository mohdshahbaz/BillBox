package com.local.billbox.system

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.local.billbox.engine.Engine
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * Daily backup, as on the Mac: while BillBox is open the engine checks every minute (and shortly after launch); when it is
 * closed Android wakes this worker about every hour and it makes the backup once the backup time has passed.
 */
class BackupWork(ctx: Context, params: WorkerParameters) : CoroutineWorker(ctx, params) {
    override suspend fun doWork(): Result {
        withContext(Dispatchers.Main) { Engine.start(applicationContext) }
        return try { tick(); Result.success() } catch (_: Exception) { Result.retry() }
    }

    companion object {
        fun schedule(context: Context) {
            val req = PeriodicWorkRequestBuilder<BackupWork>(1, TimeUnit.HOURS).build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork("billbox-backup", ExistingPeriodicWorkPolicy.KEEP, req)
        }

        /** Runs the daily backup when it is due; the backup folder's path when one was made. */
        suspend fun tick(): String? {
            val r = Engine.call(JSONObject().put("op", "tick"))
            return if (r.has("folder") && !r.isNull("folder")) r.optString("folder") else null
        }
    }
}
