@file:Suppress("unused", "UNUSED_PARAMETER")
package androidx.work
import java.util.concurrent.TimeUnit
class WorkerParameters
abstract class ListenableWorker(val applicationContext: android.content.Context, params: WorkerParameters) {
    abstract class Result { companion object { fun success(): Result = TODO(); fun retry(): Result = TODO(); fun failure(): Result = TODO() } }
}
abstract class CoroutineWorker(appContext: android.content.Context, params: WorkerParameters) : ListenableWorker(appContext, params) { abstract suspend fun doWork(): Result }
class PeriodicWorkRequest
class PeriodicWorkRequestBuilder<W : ListenableWorker>(repeatInterval: Long, repeatIntervalTimeUnit: TimeUnit) { fun build(): PeriodicWorkRequest = PeriodicWorkRequest() }
enum class ExistingPeriodicWorkPolicy { KEEP, UPDATE, CANCEL_AND_REENQUEUE }
abstract class WorkManager {
    abstract fun enqueueUniquePeriodicWork(name: String, policy: ExistingPeriodicWorkPolicy, request: PeriodicWorkRequest): Any
    companion object { fun getInstance(context: android.content.Context): WorkManager = TODO() }
}
