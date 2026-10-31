@file:Suppress("unused", "UNUSED_PARAMETER")
package android.graphics.pdf
import android.graphics.Bitmap
class PdfDocument {
    class PageInfo { class Builder(w: Int, h: Int, n: Int) { fun create(): PageInfo = PageInfo() } }
    class Page { val canvas: android.graphics.Canvas get() = TODO() }
    fun startPage(info: PageInfo): Page = Page()
    fun finishPage(p: Page) {}
    fun writeTo(out: java.io.OutputStream) {}
    fun close() {}
}
class PdfRenderer(fd: android.os.ParcelFileDescriptor) : AutoCloseable {
    val pageCount: Int = 0
    fun openPage(i: Int): Page = Page()
    override fun close() {}
    class Page : AutoCloseable { val width = 0; val height = 0; fun render(b: Bitmap, clip: android.graphics.Rect?, m: android.graphics.Matrix?, mode: Int) {}; override fun close() {}
        companion object { const val RENDER_MODE_FOR_DISPLAY = 1; const val RENDER_MODE_FOR_PRINT = 2 } }
}
