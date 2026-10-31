package com.local.billbox.system

import android.app.Activity
import android.content.pm.ApplicationInfo
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.util.Base64
import android.util.Log
import android.view.PixelCopy
import com.local.billbox.data.Api
import com.local.billbox.data.AppState
import com.local.billbox.data.J
import com.local.billbox.data.Page
import com.local.billbox.engine.Engine
import com.local.billbox.print.PrintLayout
import com.local.billbox.print.invoicePdf
import kotlinx.coroutines.delay
import kotlinx.coroutines.suspendCancellableCoroutine
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import kotlin.coroutines.resume

/**
 * On-device check, for the GitHub emulator run (.github/workflows/android-selftest.yml); only in debuggable builds and only
 * when started with `--ez selftest true`. It never runs on a phone in normal use.
 *  1. Replays the parity working session (selftest/scenario.json, pushed by the workflow) through the real engine on this
 *     device's WebView and SQLite, writing selftest/android.jsonl in the same format as the Mac's run, for compare.py.
 *  2. Walks every screen with the books that session made and saves a screenshot of each, plus page 1 of a printed bill.
 * Everything goes to files/selftest inside the app (the workflow reads it with run-as), then a "done" file.
 */
object SelfTest {
    private const val TAG = "SELFTEST"

    fun wanted(a: Activity): Boolean =
        a.intent?.getBooleanExtra("selftest", false) == true && (a.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0

    fun dir(a: Activity): File = File(a.filesDir, "selftest").apply { mkdirs() }

    /** Phase 1: before the app's own start, so the books are exactly the session's. */
    suspend fun replay(a: Activity) {
        val d = dir(a)
        val f = File(d, "scenario.json")
        if (!f.exists()) { Log.w(TAG, "no scenario.json, replay skipped"); return }
        val steps = JSONArray(f.readText())
        val out = File(d, "android.jsonl").bufferedWriter()
        var fails = 0
        for (i in 0 until steps.length()) {
            val st = steps.getJSONObject(i)
            val line = JSONObject().put("step", i)
            try {
                val r = Engine.call(st)
                when {
                    r.has("b64") -> {
                        val bytes = Base64.decode(r.optString("b64"), Base64.NO_WRAP)
                        if (st.has("to")) File(d, File(st.getString("to")).name).writeBytes(bytes)
                        line.put("status", r.optInt("status")).put("file", r.opt("file") ?: JSONObject.NULL).put("bytes", bytes.size)
                    }
                    r.has("status") && !st.has("op") -> line.put("status", r.optInt("status")).put("body", r.opt("body") ?: JSONObject.NULL)
                    else -> { for (k in r.keys()) line.put(k, r.get(k)) }
                }
                if (r.optInt("status", 200) >= 500) { fails++; Log.e(TAG, "step $i ${st.optString("method")} ${st.optString("path")}: ${r.optJSONObject("body")}") }
            } catch (e: Throwable) {
                fails++
                line.put("exception", e.toString())
                Log.e(TAG, "step $i failed", e)
            }
            out.write(line.toString()); out.write("\n")
            if (i % 50 == 0) out.flush()
        }
        out.close()
        Log.i(TAG, "replay done: ${steps.length()} steps, $fails server errors")
    }

    /** Phase 2: once the app is up. */
    suspend fun tour(a: Activity, app: AppState) {
        val shots = File(dir(a), "shots").apply { mkdirs() }
        for (k in 0 until 120) { if (app.ready) break; delay(500) }
        Log.i(TAG, "app ready=${app.ready} error=${app.startError} company=${app.companyName} fy=${app.fy}")
        delay(1500)
        var n = 1
        suspend fun shot(name: String) {
            delay(2200)
            val file = File(shots, "%02d_%s.png".format(n++, name))
            runCatching { capture(a, file) }.onFailure { Log.e(TAG, "screenshot $name", it) }
        }
        for (p in listOf(Page.Billing, Page.Bills, Page.Stock, Page.Parties, Page.Purchases, Page.DebitNotes, Page.Salesmen, Page.Dashboard, Page.Reports, Page.Settings)) {
            app.section = p
            shot(p.name)
        }
        // page 1 of a printed bill, as the PDF that goes to the printer
        runCatching {
            var inv: J? = null
            for (id in 1..8) { inv = runCatching { Api.get("/invoices/$id") }.getOrNull(); if (inv != null && inv.list("lines").isNotEmpty()) break }
            if (inv != null) {
                for ((tag, layout) in listOf("half" to PrintLayout.Single, "a4" to PrintLayout.A4FullOriginal)) {
                    val bytes = invoicePdf(inv, app.settings, layout).bytes()
                    val pdf = File(dir(a), "bill_$tag.pdf").apply { writeBytes(bytes) }
                    renderFirstPage(pdf, File(shots, "%02d_print_%s.png".format(n++, tag)))
                }
            }
        }.onFailure { Log.e(TAG, "print", it) }
        app.section = Page.Billing
        File(dir(a), "done").writeText("ok")
        Log.i(TAG, "tour done")
    }

    private suspend fun capture(a: Activity, file: File) {
        val v = a.window.decorView
        val bmp = Bitmap.createBitmap(v.width.coerceAtLeast(1), v.height.coerceAtLeast(1), Bitmap.Config.ARGB_8888)
        val ok = suspendCancellableCoroutine { c ->
            PixelCopy.request(a.window, bmp, { r -> c.resume(r == PixelCopy.SUCCESS) }, Handler(Looper.getMainLooper()))
        }
        if (ok) file.outputStream().use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }

    private fun renderFirstPage(pdf: File, png: File) {
        ParcelFileDescriptor.open(pdf, ParcelFileDescriptor.MODE_READ_ONLY).use { fd ->
            PdfRenderer(fd).use { r ->
                r.openPage(0).use { pg ->
                    val bmp = Bitmap.createBitmap(pg.width * 2, pg.height * 2, Bitmap.Config.ARGB_8888)
                    bmp.eraseColor(Color.WHITE)
                    pg.render(bmp, null, null, PdfRenderer.Page.RENDER_MODE_FOR_PRINT)
                    png.outputStream().use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
                }
            }
        }
    }

}
