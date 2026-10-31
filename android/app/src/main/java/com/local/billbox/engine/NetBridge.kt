package com.local.billbox.engine

import android.util.Base64
import android.webkit.JavascriptInterface
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL

/** Internet look-ups for the engine (category guesses, price lists, Google Drive backups): plain HTTPS from the app, any site. */
class NetBridge {
    companion object {
        /** Set by the emulator self-test: the Mac run it is compared with has no internet either. */
        @Volatile var offline = false
    }

    @JavascriptInterface
    fun request(url: String, optsJson: String): String = try {
        android.util.Log.i("BillBoxNet", (if (offline) "blocked " else "") + url.take(140))
        if (offline) throw java.net.UnknownHostException("offline (self-test)")
        val opts = JSONObject(optsJson)
        val c = URL(url).openConnection() as HttpURLConnection
        c.instanceFollowRedirects = true
        c.requestMethod = opts.optString("method", "GET")
        val t = opts.optInt("timeoutMs", 20000)
        c.connectTimeout = t
        c.readTimeout = t
        c.setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36")
        opts.optJSONObject("headers")?.let { h -> h.keys().forEach { k -> c.setRequestProperty(k, h.getString(k)) } }
        // a request body (Google Drive: sign-in forms and backup uploads)
        opts.optString("b64", "").takeIf { it.isNotEmpty() }?.let { b ->
            val bytes = Base64.decode(b, Base64.DEFAULT)
            c.doOutput = true
            c.setFixedLengthStreamingMode(bytes.size)
            c.outputStream.use { it.write(bytes) }
        }
        val status = c.responseCode
        val stream = if (status >= 400) c.errorStream else c.inputStream
        val out = ByteArrayOutputStream()
        stream?.use { s ->
            val buf = ByteArray(64 * 1024)
            while (true) {
                val n = s.read(buf)
                if (n < 0) break
                out.write(buf, 0, n)
                if (out.size() > 13 * 1024 * 1024) break
            }
        }
        val headers = JSONObject()
        c.headerFields.forEach { (k, v) -> if (k != null && v != null) headers.put(k.lowercase(), v.joinToString(", ")) }
        c.disconnect()
        JSONObject().put("status", status).put("headers", headers).put("b64", Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)).toString()
    } catch (e: Throwable) {
        JSONObject().put("error", e.message ?: "network error").toString()
    }
}
