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
import kotlinx.coroutines.launch
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
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

    fun dir(a: android.content.Context): File = File(a.filesDir, "selftest").apply { mkdirs() }

    /** True while the session is being replayed (the screen shows a short note instead of the app). */
    var replaying by androidx.compose.runtime.mutableStateOf(false)
    private var started = false
    /** The emulator self-test is running (no "new version" banner over its screenshots). */
    val active: Boolean get() = started
    private var current: java.lang.ref.WeakReference<Activity>? = null

    /** Runs once per app launch, on the app's own scope: Android may recreate the screen while it runs (the first run was
     *  cancelled half-way by that and raced a second one). Screenshots use whichever screen is showing. */
    fun begin(a: Activity, app: AppState) {
        current = java.lang.ref.WeakReference(a)
        if (started) return
        started = true
        replaying = true
        val ctx = a.applicationContext
        app.scope.launch {
            try { replay(ctx) } finally { replaying = false }
            tour(app)
        }
    }

    /** Phase 1: before the app's own start, so the books are exactly the session's. */
    suspend fun replay(a: android.content.Context) {
        val d = dir(a)
        val f = File(d, "scenario.json")
        if (!f.exists()) { Log.w(TAG, "no scenario.json, replay skipped"); return }
        val steps = JSONArray(f.readText())
        com.local.billbox.engine.NetBridge.offline = true   // as the Mac run it is compared with
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
        com.local.billbox.engine.NetBridge.offline = false
        Log.i(TAG, "replay done: ${steps.length()} steps, $fails server errors")
    }

    /** Phase 2: once the app is up. */
    suspend fun tour(app: AppState) {
        val ctx = current?.get()?.applicationContext ?: return
        val shots = File(dir(ctx), "shots").apply { mkdirs() }
        for (k in 0 until 120) { if (app.ready) break; delay(500) }
        Log.i(TAG, "app ready=${app.ready} error=${app.startError} company=${app.companyName} fy=${app.fy}")
        delay(1500)
        var n = 1
        suspend fun shot(name: String) {
            delay(2200)
            val file = File(shots, "%02d_%s.png".format(n++, name))
            runCatching { current?.get()?.let { capture(it, file) } }.onFailure { Log.e(TAG, "screenshot $name", it) }
        }
        for (p in listOf(Page.Billing, Page.Bills, Page.Stock, Page.Parties, Page.Purchases, Page.DebitNotes, Page.Salesmen, Page.Dashboard, Page.Reports, Page.Settings)) {
            app.section = p
            shot(p.name)
        }
        // the main screens again in dark mode (Settings › Appearance › Dark), then the phone's own setting back
        (ctx as? com.local.billbox.BillBoxApp)?.ui?.let { ui ->
            val was = ui.appearance
            ui.set("appearance", "dark")
            for (p in listOf(Page.Billing, Page.Bills, Page.Parties, Page.Dashboard, Page.Reports)) {
                app.section = p
                shot("dark_" + p.name)
            }
            ui.set("appearance", was)
        }
        // page 1 of a printed bill, as the PDF that goes to the printer
        runCatching {
            var inv: J? = null
            // the bill with the most lines among the first ones
            for (id in 1..20) { val x = runCatching { Api.get("/invoices/$id") }.getOrNull() ?: continue; if (x.list("lines").size > (inv?.list("lines")?.size ?: 0)) inv = x }
            if (inv != null) {
                val marg = app.settings.with("print_style" to "marg")
                val margMono = marg.with("print_marg_colour" to "mono", "print_marg_classes" to "used", "print_marg_font" to "sans")
                for ((tag, pair) in listOf("half" to (PrintLayout.Single to app.settings), "a4" to (PrintLayout.A4FullOriginal to app.settings),
                        "marg_half" to (PrintLayout.Single to marg), "marg_a4" to (PrintLayout.A4FullOriginal to margMono))) {
                    val (layout, co) = pair
                    val bytes = invoicePdf(inv, co, layout).bytes()
                    val pdf = File(dir(ctx), "bill_$tag.pdf").apply { writeBytes(bytes) }
                    renderFirstPage(pdf, File(shots, "%02d_print_%s.png".format(n++, tag)))
                }
            }
        }.onFailure { Log.e(TAG, "print", it) }
        app.section = Page.Billing
        File(dir(ctx), "done").writeText("ok")
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
