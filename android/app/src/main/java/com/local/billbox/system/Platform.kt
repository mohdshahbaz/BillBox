package com.local.billbox.system

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.print.PageRange
import android.print.PrintAttributes
import android.print.PrintDocumentAdapter
import android.print.PrintDocumentInfo
import android.print.PrintManager
import androidx.activity.ComponentActivity
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContract
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.FileProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.lang.ref.WeakReference
import java.util.concurrent.atomic.AtomicInteger
import kotlin.coroutines.resume

/**
 * Android services as plain suspend calls: pick or save a file (Storage Access Framework), take or choose a photo,
 * the share sheet, the print service, open a web page.
 */
object Platform {
    private var ref = WeakReference<ComponentActivity>(null)
    private val keys = AtomicInteger(1)
    val activity: ComponentActivity? get() = ref.get()
    val context: Context get() = activity ?: error("BillBox is not open")

    fun attach(a: ComponentActivity) { ref = WeakReference(a) }

    private suspend fun <I, O> launch(contract: ActivityResultContract<I, O>, input: I): O? {
        val a = activity ?: return null
        return withContext(Dispatchers.Main) {
            suspendCancellableCoroutine { c ->
                val holder = arrayOfNulls<androidx.activity.result.ActivityResultLauncher<I>>(1)
                val launcher = a.activityResultRegistry.register("bb-${keys.getAndIncrement()}", contract) { r ->
                    holder[0]?.unregister()
                    if (c.isActive) c.resume(r)
                }
                holder[0] = launcher
                try { launcher.launch(input) } catch (e: ActivityNotFoundException) { launcher.unregister(); if (c.isActive) c.resume(null) }
            }
        }
    }

    /** Opens one file (any of the types); its bytes and name, or null when cancelled. */
    suspend fun openFile(vararg mimes: String): Pair<String, ByteArray>? {
        val uri = launch(ActivityResultContracts.OpenDocument(), arrayOf(*mimes.ifEmpty { arrayOf("*/*") })) ?: return null
        return withContext(Dispatchers.IO) { nameOf(uri) to (context.contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: ByteArray(0)) }
    }

    /** Several files at once. */
    suspend fun openFiles(vararg mimes: String): List<Pair<String, ByteArray>> {
        val uris = launch(ActivityResultContracts.OpenMultipleDocuments(), arrayOf(*mimes.ifEmpty { arrayOf("*/*") })) ?: return emptyList()
        return withContext(Dispatchers.IO) { uris.map { u -> nameOf(u) to (context.contentResolver.openInputStream(u)?.use { it.readBytes() } ?: ByteArray(0)) } }
    }

    /** A folder chosen with the system picker (for restoring a whole backup folder): every file in it, by name. */
    suspend fun openFolder(): List<Pair<String, ByteArray>>? {
        val tree = launch(ActivityResultContracts.OpenDocumentTree(), null) ?: return null
        return withContext(Dispatchers.IO) {
            val folder = androidx.documentfile.provider.DocumentFile.fromTreeUri(context, tree) ?: return@withContext emptyList()
            folder.listFiles().filter { it.isFile }.map { f -> (f.name ?: "file") to (context.contentResolver.openInputStream(f.uri)?.use { it.readBytes() } ?: ByteArray(0)) }
        }
    }

    /** Saves bytes where the user chooses ("Save to…"). True when saved. */
    suspend fun saveFile(name: String, mime: String, bytes: ByteArray): Boolean {
        val uri = launch(ActivityResultContracts.CreateDocument(mime), name) ?: return false
        withContext(Dispatchers.IO) { context.contentResolver.openOutputStream(uri, "wt")?.use { it.write(bytes) } }
        return true
    }

    /** Saves a folder's files into a folder the user chooses (backups to a USB drive, Drive, Downloads). */
    suspend fun saveFolder(name: String, files: List<File>): Boolean {
        val tree = launch(ActivityResultContracts.OpenDocumentTree(), null) ?: return false
        withContext(Dispatchers.IO) {
            val root = androidx.documentfile.provider.DocumentFile.fromTreeUri(context, tree) ?: return@withContext
            val dir = root.findFile(name) ?: root.createDirectory(name) ?: return@withContext
            for (f in files) {
                dir.findFile(f.name)?.delete()
                val d = dir.createFile("application/octet-stream", f.name) ?: continue
                context.contentResolver.openOutputStream(d.uri, "wt")?.use { out -> FileInputStream(f).use { it.copyTo(out) } }
            }
        }
        return true
    }

    /**
     * Copies a picked file (or every file of a picked folder) into a private import folder; a .zip is unpacked there.
     * Returns the folder and the picked name, or null when cancelled.
     */
    suspend fun importPicked(folder: Boolean, vararg mimes: String): Pair<File, String>? {
        val dir = File(context.cacheDir, "import-${System.currentTimeMillis()}").apply { mkdirs() }
        if (folder) {
            val tree = launch(ActivityResultContracts.OpenDocumentTree(), null) ?: return null
            withContext(Dispatchers.IO) {
                val root = androidx.documentfile.provider.DocumentFile.fromTreeUri(context, tree)
                fun copy(d: androidx.documentfile.provider.DocumentFile?, to: File, depth: Int) {
                    if (d == null || depth > 4) return
                    to.mkdirs()
                    for (f in d.listFiles()) {
                        val n = f.name ?: continue
                        if (f.isDirectory) copy(f, File(to, n), depth + 1)
                        else context.contentResolver.openInputStream(f.uri)?.use { i -> File(to, n).outputStream().use { i.copyTo(it) } }
                    }
                }
                copy(root, File(dir, root?.name ?: "picked"), 0)
            }
            return dir to (androidx.documentfile.provider.DocumentFile.fromTreeUri(context, tree)?.name ?: "folder")
        }
        val uri = launch(ActivityResultContracts.OpenDocument(), arrayOf(*mimes.ifEmpty { arrayOf("*/*") })) ?: return null
        val name = nameOf(uri)
        withContext(Dispatchers.IO) {
            val dest = File(dir, name)
            context.contentResolver.openInputStream(uri)?.use { i -> dest.outputStream().use { i.copyTo(it) } }
            if (name.lowercase().endsWith(".zip")) { unzip(dest, File(dir, "unzipped")); dest.delete() }
        }
        return dir to name
    }

    /** Unpacks a .zip (names that try to leave the folder are skipped). */
    fun unzip(zip: File, to: File) {
        to.mkdirs()
        val base = to.canonicalPath + File.separator
        java.util.zip.ZipInputStream(zip.inputStream().buffered()).use { z ->
            while (true) {
                val e = z.nextEntry ?: break
                val out = File(to, e.name)
                if (!out.canonicalPath.startsWith(base)) continue
                if (e.isDirectory) out.mkdirs() else { out.parentFile?.mkdirs(); out.outputStream().use { z.copyTo(it) } }
            }
        }
    }

    /** A BillBox backup inside a picked folder: the folder with manifest.json, or the one company .db file. */
    fun locateBackup(root: File): Pair<File?, File?> {
        var level = listOf(root)
        val dbs = mutableListOf<File>()
        repeat(4) {
            val next = mutableListOf<File>()
            for (d in level) {
                if (File(d, "manifest.json").exists()) return d to null
                for (f in (d.listFiles() ?: emptyArray()).sortedBy { it.name }) {
                    if (f.name.startsWith(".") || f.name == "__MACOSX") continue
                    if (f.isDirectory) next.add(f) else if (f.name.lowercase().endsWith(".db") && f.name != "registry.db") dbs.add(f)
                }
            }
            level = next
        }
        return null to (if (dbs.size == 1) dbs[0] else null)
    }

    private fun nameOf(uri: Uri): String {
        context.contentResolver.query(uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) return c.getString(0) ?: "file"
        }
        return uri.lastPathSegment ?: "file"
    }

    /** A photo from the camera, upright and at most 2,400 pixels on the long side. */
    suspend fun takePhoto(): Bitmap? {
        val dir = File(context.cacheDir, "camera").apply { mkdirs() }
        val f = File(dir, "photo-${System.currentTimeMillis()}.jpg")
        val uri = FileProvider.getUriForFile(context, context.packageName + ".files", f)
        val ok = launch(ActivityResultContracts.TakePicture(), uri) ?: false
        if (!ok || !f.exists()) return null
        return withContext(Dispatchers.IO) { decode(Uri.fromFile(f)).also { f.delete() } }
    }

    /** A photo from the gallery (the system photo picker: no permission needed). */
    suspend fun pickPhoto(): Bitmap? {
        val uri = launch(ActivityResultContracts.PickVisualMedia(), PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) ?: return null
        return withContext(Dispatchers.IO) { decode(uri) }
    }

    val hasCamera: Boolean get() = activity?.packageManager?.hasSystemFeature(android.content.pm.PackageManager.FEATURE_CAMERA_ANY) == true

    private fun decode(uri: Uri): Bitmap? = try {
        val src = ImageDecoder.createSource(context.contentResolver, uri)
        ImageDecoder.decodeBitmap(src) { d, info, _ ->
            val s = info.size
            val k = minOf(1.0, 2400.0 / maxOf(s.width, s.height))
            d.setTargetSize((s.width * k).toInt().coerceAtLeast(1), (s.height * k).toInt().coerceAtLeast(1))
            d.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
        }
    } catch (_: Exception) { null }

    /** A file in the cache that can be shared or printed. */
    fun cacheFile(name: String, bytes: ByteArray): File {
        val dir = File(context.cacheDir, "share").apply { mkdirs() }
        val safe = name.replace(Regex("[\\\\/:*?\"<>|]"), "-")
        return File(dir, safe).also { it.writeBytes(bytes) }
    }

    fun uriOf(f: File): Uri = FileProvider.getUriForFile(context, context.packageName + ".files", f)

    /** The Android share sheet for a file (or text). */
    fun share(file: File, mime: String, text: String? = null, title: String = "Share") {
        val uri = uriOf(file)
        val i = Intent(Intent.ACTION_SEND).setType(mime).putExtra(Intent.EXTRA_STREAM, uri)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        i.clipData = ClipData.newRawUri(file.name, uri)
        if (text != null) i.putExtra(Intent.EXTRA_TEXT, text)
        context.startActivity(Intent.createChooser(i, title))
    }

    fun shareText(text: String, title: String = "Share") {
        context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text), title))
    }

    fun openUrl(url: String) {
        try { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) } catch (_: Exception) {}
    }

    /**
     * A landscape bill (half sheet) turned a quarter onto portrait pages, for printing: many printers print a landscape
     * page upright on A5 paper and cut off the right half of the bill. Drawn at 300 dpi, so the print stays sharp.
     */
    private fun portraitForPrint(pdf: File): File {
        val fd = ParcelFileDescriptor.open(pdf, ParcelFileDescriptor.MODE_READ_ONLY)
        val r = android.graphics.pdf.PdfRenderer(fd)
        try {
            if (r.pageCount == 0) return pdf
            val first = r.openPage(0); val landscape = first.width > first.height; first.close()
            if (!landscape) return pdf
            val out = android.graphics.pdf.PdfDocument()
            for (i in 0 until r.pageCount) {
                val pg = r.openPage(i)
                val w = pg.width; val h = pg.height                      // points
                val k = 300f / 72f
                val bmp = Bitmap.createBitmap((w * k).toInt(), (h * k).toInt(), Bitmap.Config.ARGB_8888)
                bmp.eraseColor(android.graphics.Color.WHITE)
                pg.render(bmp, null, null, android.graphics.pdf.PdfRenderer.Page.RENDER_MODE_FOR_PRINT)
                pg.close()
                val op = out.startPage(android.graphics.pdf.PdfDocument.PageInfo.Builder(h, w, i + 1).create())
                val c = op.canvas
                c.translate(h.toFloat(), 0f)
                c.rotate(90f)
                c.drawBitmap(bmp, android.graphics.Rect(0, 0, bmp.width, bmp.height), android.graphics.RectF(0f, 0f, w.toFloat(), h.toFloat()), android.graphics.Paint(android.graphics.Paint.FILTER_BITMAP_FLAG))
                out.finishPage(op)
                bmp.recycle()
            }
            val f = File(pdf.parentFile, "print-" + pdf.name)
            FileOutputStream(f).use { out.writeTo(it) }
            out.close()
            return f
        } catch (_: Exception) {
            return pdf
        } finally { r.close(); fd.close() }
    }

    /** Sends a ready PDF to Android's print service (any printer, or Save as PDF). */
    fun print(source: File, jobName: String) {
        val pdf = portraitForPrint(source)
        val pm = context.getSystemService(Context.PRINT_SERVICE) as PrintManager
        // half-sheet bills ask for A5 paper (one copy per sheet, the bill landscape across it); the rest A4
        val a5 = pdf != source   // a landscape half sheet was turned onto portrait pages
        val attrs = PrintAttributes.Builder().setMediaSize(if (a5) PrintAttributes.MediaSize.ISO_A5 else PrintAttributes.MediaSize.ISO_A4).build()
        pm.print(jobName, object : PrintDocumentAdapter() {
            override fun onLayout(old: PrintAttributes?, new: PrintAttributes?, cancel: CancellationSignal?, cb: LayoutResultCallback, extras: android.os.Bundle?) {
                if (cancel?.isCanceled == true) { cb.onLayoutCancelled(); return }
                cb.onLayoutFinished(PrintDocumentInfo.Builder(pdf.name).setContentType(PrintDocumentInfo.CONTENT_TYPE_DOCUMENT).build(), true)
            }
            override fun onWrite(pages: Array<out PageRange>?, dest: ParcelFileDescriptor, cancel: CancellationSignal?, cb: WriteResultCallback) {
                try {
                    FileInputStream(pdf).use { i -> FileOutputStream(dest.fileDescriptor).use { o -> i.copyTo(o) } }
                    cb.onWriteFinished(arrayOf(PageRange.ALL_PAGES))
                } catch (e: Exception) { cb.onWriteFailed(e.message) }
            }
        }, attrs)
    }

    fun bitmapOf(bytes: ByteArray): Bitmap? = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
}
