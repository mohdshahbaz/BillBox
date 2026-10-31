package com.local.billbox.engine

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import android.webkit.JavascriptInterface
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import java.io.File
import java.io.FileOutputStream

/**
 * Scanned supplier PDFs: the Mac runs `pdftoppm` then `tesseract`; here the phone does the same two steps.
 * render() writes one PNG per page (at most 12, 200 dpi, like the Mac), recognize() reads one page's text on the phone.
 */
class OcrBridge {
    @JavascriptInterface
    fun render(pdfPath: String, prefix: String): String {
        ParcelFileDescriptor.open(File(pdfPath), ParcelFileDescriptor.MODE_READ_ONLY).use { fd ->
            PdfRenderer(fd).use { r ->
                for (i in 0 until minOf(r.pageCount, 12)) {
                    r.openPage(i).use { page ->
                        val scale = 200f / 72f
                        val bmp = Bitmap.createBitmap((page.width * scale).toInt(), (page.height * scale).toInt(), Bitmap.Config.ARGB_8888)
                        bmp.eraseColor(Color.WHITE)
                        page.render(bmp, null, null, PdfRenderer.Page.RENDER_MODE_FOR_PRINT)
                        FileOutputStream("$prefix-${(i + 1).toString().padStart(2, '0')}.png").use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
                        bmp.recycle()
                    }
                }
            }
        }
        return "ok"
    }

    @JavascriptInterface
    fun recognize(pngPath: String): String {
        val bmp = BitmapFactory.decodeFile(pngPath) ?: return ""
        return Ocr.linesOf(bmp).joinToString("\n")
    }
}

/** On-device text recognition, lines top to bottom and words left to right (also used for photos of payment lists). */
object Ocr {
    private val client by lazy { TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS) }

    /** Blocking: call off the main thread. */
    fun linesOf(bmp: Bitmap): List<String> {
        val result = Tasks.await(client.process(InputImage.fromBitmap(bmp, 0)))
        data class Piece(val x: Int, val y: Int, val h: Int, val s: String)
        val pieces = result.textBlocks.flatMap { b -> b.lines.mapNotNull { l -> l.boundingBox?.let { Piece(it.left, it.centerY(), it.height(), l.text) } } }
        val rows = mutableListOf<MutableList<Piece>>()
        for (p in pieces.sortedBy { it.y }) {
            val row = rows.firstOrNull { r -> kotlin.math.abs(r.first().y - p.y) < maxOf(r.first().h, p.h) / 2 }
            if (row != null) row.add(p) else rows.add(mutableListOf(p))
        }
        return rows.sortedBy { it.first().y }.map { r -> r.sortedBy { it.x }.joinToString(" ") { it.s } }
    }
}
