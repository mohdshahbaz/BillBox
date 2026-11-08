package com.local.billbox.engine

import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.webkit.ConsoleMessage
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebView
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger

/**
 * The Mac's engine (backend/src, bundled by android/engine/build.mjs) running in a hidden WebView. The app sends one request
 * at a time; the engine answers through AndroidHost.reply. Books live in files/data, backups in files/DistributorProBackups,
 * exactly as on the Mac (company files plus registry.db).
 */
@SuppressLint("StaticFieldLeak")
object Engine {
    private var web: WebView? = null
    private var ready = CompletableDeferred<Unit>()
    private val pending = ConcurrentHashMap<Int, CompletableDeferred<String>>()
    private val ids = AtomicInteger(1)
    private val lock = Mutex()
    lateinit var dataDir: File
    lateinit var homeDir: File
    lateinit var tmpDir: File
    @Volatile var startError: String? = null

    private class Host {
        @JavascriptInterface fun dataDir(): String = Engine.dataDir.absolutePath
        @JavascriptInterface fun edition(): String = Edition.NAME
        @JavascriptInterface fun home(): String = Engine.homeDir.absolutePath
        @JavascriptInterface fun tmp(): String = Engine.tmpDir.absolutePath
        @JavascriptInterface fun ready() { Engine.ready.complete(Unit) }
        @JavascriptInterface fun reply(id: Int, json: String) { pending.remove(id)?.complete(json) }
    }

    /** Starts the engine (main thread). Safe to call more than once. */
    @SuppressLint("SetJavaScriptEnabled", "JavascriptInterface")
    fun start(context: Context) {
        if (web != null) return
        val app = context.applicationContext
        dataDir = File(app.filesDir, "data").apply { mkdirs() }
        homeDir = app.filesDir
        tmpDir = File(app.cacheDir, "engine").apply { mkdirs() }
        val w = WebView(app)
        w.settings.javaScriptEnabled = true
        @Suppress("DEPRECATION")
        w.settings.allowFileAccessFromFileURLs = true
        w.settings.allowFileAccess = true
        w.settings.domStorageEnabled = false
        w.addJavascriptInterface(Host(), "AndroidHost")
        w.addJavascriptInterface(SqlBridge(), "AndroidSQL")
        w.addJavascriptInterface(FsBridge(), "AndroidFS")
        w.addJavascriptInterface(NetBridge(), "AndroidNet")
        w.addJavascriptInterface(OcrBridge(), "AndroidOCR")
        w.webChromeClient = object : WebChromeClient() {
            override fun onConsoleMessage(m: ConsoleMessage): Boolean {
                if (m.messageLevel() == ConsoleMessage.MessageLevel.ERROR) {
                    Log.e("BillBoxEngine", "${m.message()} (${m.sourceId()}:${m.lineNumber()})")
                    if (!ready.isCompleted) startError = m.message()
                }
                return true
            }
        }
        web = w
        w.loadUrl("file:///android_asset/engine/index.html")
    }

    /** Sends one request; the reply is { status, body } or { status, file, type, b64 } or { status, html }. */
    suspend fun call(req: JSONObject): JSONObject = lock.withLock {
        withContext(Dispatchers.Main) { if (web == null) throw IllegalStateException("BillBox engine not started") }
        kotlinx.coroutines.withTimeoutOrNull(60_000) { ready.await() }
            ?: throw IllegalStateException(startError ?: "The BillBox engine did not start.")
        val id = ids.getAndIncrement()
        val d = CompletableDeferred<String>()
        pending[id] = d
        val js = "BillBox.handle($id, ${JSONObject.quote(req.toString())})"
        withContext(Dispatchers.Main) { web?.evaluateJavascript(js, null) }
        // never wait forever: one request that gets no answer would otherwise hold the lock and freeze every screen
        val reply = kotlinx.coroutines.withTimeoutOrNull(if (req.optString("path").let { it.startsWith("/import") || it == "/sync/merge" || it == "/sync/join" } || req.has("op")) 900_000 else 120_000) { d.await() }
        if (reply == null) {
            pending.remove(id)
            Log.e("BillBoxEngine", "no answer for ${req.optString("method")} ${req.optString("path")}")
            return@withLock JSONObject().put("status", 504).put("body", JSONObject().put("error", "BillBox took too long to answer. Try again."))
        }
        JSONObject(reply)
    }

    /** Runs code on the main thread (for callers outside coroutines). */
    fun onMain(f: () -> Unit) = Handler(Looper.getMainLooper()).post(f)
}
