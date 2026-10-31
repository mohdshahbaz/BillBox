package com.local.billbox.engine

import android.util.Base64
import android.webkit.JavascriptInterface
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileNotFoundException
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/** The engine's file calls (android/engine/shims/fs.js): replies {"ok": value} or {"error": {code, message}} like Node's errors. */
class FsBridge {
    private fun ok(v: Any?): String = JSONObject().put("ok", v ?: JSONObject.NULL).toString()
    private fun err(code: String, message: String): String =
        JSONObject().put("error", JSONObject().put("code", code).put("message", message)).toString()

    private inline fun io(path: String, f: () -> Any?): String = try {
        ok(f())
    } catch (e: FileNotFoundException) {
        err("ENOENT", "no such file or directory")
    } catch (e: FsError) {
        err(e.code, e.message ?: e.code)
    } catch (e: Throwable) {
        err("EIO", e.message ?: "i/o error")
    }

    private class FsError(val code: String, msg: String) : Exception(msg)
    private fun need(f: File) { if (!f.exists()) throw FsError("ENOENT", "no such file or directory") }

    @JavascriptInterface fun exists(p: String): String = io(p) { File(p).exists() }

    @JavascriptInterface fun stat(p: String): String = io(p) {
        val f = File(p); need(f)
        JSONObject().put("size", if (f.isDirectory) 4096 else f.length()).put("mtime", f.lastModified()).put("dir", f.isDirectory)
    }

    @JavascriptInterface fun read(p: String): String = io(p) {
        val f = File(p); need(f)
        if (f.isDirectory) throw FsError("EISDIR", "illegal operation on a directory")
        Base64.encodeToString(f.readBytes(), Base64.NO_WRAP)
    }

    @JavascriptInterface fun write(p: String, b64: String): String = io(p) {
        val f = File(p)
        if (f.parentFile?.exists() == false) throw FsError("ENOENT", "no such file or directory")
        f.writeBytes(Base64.decode(b64, Base64.NO_WRAP)); null
    }

    @JavascriptInterface fun mkdir(p: String, recursive: String): String = io(p) {
        val f = File(p)
        if (recursive == "true") { if (!f.exists() && !f.mkdirs()) throw FsError("EACCES", "permission denied") }
        else {
            if (f.exists()) throw FsError("EEXIST", "file already exists")
            if (!f.mkdir()) throw FsError("ENOENT", "no such file or directory")
        }
        null
    }

    @JavascriptInterface fun readdir(p: String): String = io(p) {
        val f = File(p); need(f)
        if (!f.isDirectory) throw FsError("ENOTDIR", "not a directory")
        JSONArray((f.list() ?: emptyArray()).sorted())
    }

    @JavascriptInterface fun rm(p: String, recursive: String, force: String): String = io(p) {
        val f = File(p)
        if (!f.exists()) { if (force != "true") throw FsError("ENOENT", "no such file or directory"); return@io null }
        if (f.isDirectory) {
            if (recursive != "true") throw FsError("ERR_FS_EISDIR", "is a directory")
            f.deleteRecursively()
        } else f.delete()
        null
    }

    @JavascriptInterface fun rename(a: String, b: String): String = io(a) {
        val from = File(a); need(from)
        Files.move(from.toPath(), File(b).toPath(), StandardCopyOption.REPLACE_EXISTING); null
    }

    @JavascriptInterface fun copy(a: String, b: String): String = io(a) {
        val from = File(a); need(from)
        Files.copy(from.toPath(), File(b).toPath(), StandardCopyOption.REPLACE_EXISTING); null
    }

    @JavascriptInterface fun mkdtemp(prefix: String): String = io(prefix) {
        val parent = File(prefix).parentFile ?: File("/")
        val name = File(prefix).name
        var dir: File
        do { dir = File(parent, name + java.lang.Long.toString(System.nanoTime(), 36).takeLast(6)) } while (dir.exists())
        dir.mkdirs(); dir.absolutePath
    }
}
