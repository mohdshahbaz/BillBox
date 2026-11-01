@file:Suppress("unused", "UNUSED_PARAMETER")
package android.graphics
class Bitmap {
    val width: Int = 0; val height: Int = 0
    fun eraseColor(c: Int) {}
    fun recycle() {}
    fun compress(format: CompressFormat, quality: Int, stream: java.io.OutputStream): Boolean = true
    enum class CompressFormat { PNG, JPEG }
    enum class Config { ARGB_8888 }
    companion object { fun createBitmap(width: Int, height: Int, config: Config): Bitmap = Bitmap() }
}
object BitmapFactory { fun decodeFile(path: String): Bitmap? = null; fun decodeByteArray(data: ByteArray, offset: Int, length: Int): Bitmap? = null }
open class Paint(flags: Int = 0) {
    enum class Style { FILL, STROKE }
    var style: Style = Style.FILL; var color: Int = 0; var strokeWidth: Float = 0f; var textSize: Float = 0f
    var typeface: Typeface? = null; var pathEffect: PathEffect? = null
    fun measureText(text: String): Float = 0f
    val fontMetrics: FontMetrics get() = FontMetrics()
    class FontMetrics { @JvmField var ascent = 0f; @JvmField var descent = 0f }
    companion object { const val ANTI_ALIAS_FLAG = 1; const val FILTER_BITMAP_FLAG = 2; const val LINEAR_TEXT_FLAG = 64; const val SUBPIXEL_TEXT_FLAG = 128 }
}
open class PathEffect
class DashPathEffect(intervals: FloatArray, phase: Float) : PathEffect()
class RectF(left: Float, top: Float, right: Float, bottom: Float)
class Rect(l: Int = 0, t: Int = 0, r: Int = 0, b: Int = 0) { val left = 0; val top = 0; fun centerY(): Int = 0; fun height(): Int = 0 }
class Typeface { companion object { const val NORMAL = 0; const val BOLD = 1; val DEFAULT: Typeface = Typeface(); val SERIF: Typeface = Typeface(); fun create(family: Typeface?, style: Int): Typeface = Typeface(); fun create(family: String?, style: Int): Typeface = Typeface() } }
object Color { const val WHITE = -1; const val BLACK = -16777216; fun argb(a: Int, r: Int, g: Int, b: Int): Int = 0 }
class Canvas {
    fun drawColor(c: Int) {}
    fun drawText(text: String, x: Float, y: Float, paint: Paint) {}
    fun drawLine(x1: Float, y1: Float, x2: Float, y2: Float, paint: Paint) {}
    fun drawRect(r: RectF, paint: Paint) {}
    fun save(): Int = 0; fun restore() {}; fun translate(dx: Float, dy: Float) {}
    fun rotate(degrees: Float) {}; fun drawBitmap(b: Bitmap, src: Rect?, dst: RectF, paint: Paint?) {}
}
class ImageDecoder {
    class Source
    class ImageInfo { val size: android.util.Size get() = TODO() }
    fun interface OnHeaderDecodedListener { fun onHeaderDecoded(decoder: ImageDecoder, info: ImageInfo, source: Source) }
    fun setTargetSize(w: Int, h: Int) {}
    var allocator: Int = 0
    companion object {
        const val ALLOCATOR_SOFTWARE = 1
        fun createSource(cr: android.content.ContentResolver, uri: android.net.Uri): Source = Source()
        fun decodeBitmap(src: Source, listener: OnHeaderDecodedListener): Bitmap = Bitmap()
    }
}
class Matrix
