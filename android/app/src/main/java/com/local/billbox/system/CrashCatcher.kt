package com.local.billbox.system

import android.content.Context
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * If BillBox ever closes unexpectedly, the next launch shows what happened (with Copy and Share), so the reason can be
 * sent instead of guessed. Nothing leaves the phone unless you share it.
 */
object CrashCatcher {
    private lateinit var report: File

    fun install(context: Context) {
        report = File(context.cacheDir, "last-crash.txt")
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { t, e ->
            try {
                val sw = StringWriter()
                e.printStackTrace(PrintWriter(sw))
                val stamp = SimpleDateFormat("dd-MM-yyyy HH:mm:ss", Locale.US).format(Date())
                report.writeText("BillBox closed unexpectedly on $stamp\nThread: ${t.name}\n\n$sw")
            } catch (_: Throwable) {}
            previous?.uncaughtException(t, e)
        }
    }

    fun pendingReport(): String? = if (::report.isInitialized && report.exists()) report.readText().ifBlank { null } else null
    fun clear() { if (::report.isInitialized) report.delete() }
}
