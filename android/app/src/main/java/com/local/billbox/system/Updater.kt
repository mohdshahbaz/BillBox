package com.local.billbox.system

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/** Settings › Updates: downloads a newer BillBox APK from the releases and hands it to Android's installer. */
object Updater {
    /** This app's version (from the release build, e.g. 16.2.12 or 16.2.12-admin). */
    val version: String
        get() = try {
            val c = Platform.context
            c.packageManager.getPackageInfo(c.packageName, 0).versionName ?: ""
        } catch (_: Exception) { "" }

    /** Downloads `url` to the app's cache (progress 0…1), then returns the file. */
    suspend fun download(url: String, name: String, progress: (Float) -> Unit): File = withContext(Dispatchers.IO) {
        val dir = File(Platform.context.cacheDir, "updates").apply { mkdirs() }
        dir.listFiles()?.forEach { it.delete() }
        val out = File(dir, name.replace(Regex("[^A-Za-z0-9._-]"), "-"))
        var link = url
        var conn: HttpURLConnection
        var hops = 0
        while (true) {   // GitHub sends the file from another host
            conn = (URL(link).openConnection() as HttpURLConnection).apply {
                instanceFollowRedirects = false; connectTimeout = 20000; readTimeout = 60000
                setRequestProperty("User-Agent", "BillBox")
            }
            val code = conn.responseCode
            if (code in 300..399 && hops < 5) { link = conn.getHeaderField("Location") ?: break; conn.disconnect(); hops++; continue }
            if (code != 200) throw IllegalStateException("The download answered $code.")
            break
        }
        val total = conn.contentLengthLong.takeIf { it > 0 } ?: -1L
        conn.inputStream.use { inp ->
            out.outputStream().use { o ->
                val buf = ByteArray(64 * 1024)
                var got = 0L
                while (true) {
                    val n = inp.read(buf)
                    if (n < 0) break
                    o.write(buf, 0, n); got += n
                    if (total > 0) withContext(Dispatchers.Main) { progress((got.toFloat() / total).coerceIn(0f, 1f)) }
                }
            }
        }
        conn.disconnect()
        out
    }

    /** False when Android still needs "Install unknown apps" allowed for BillBox (it opens that setting). */
    fun canInstall(): Boolean {
        val c = Platform.context
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !c.packageManager.canRequestPackageInstalls()) {
            try { c.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${c.packageName}"))) } catch (_: Exception) {}
            return false
        }
        return true
    }

    /** Android's installer for the downloaded APK (it updates BillBox in place and keeps the books). */
    fun install(apk: File) {
        val uri = Platform.uriOf(apk)
        val i = Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        Platform.context.startActivity(i)
    }
}
