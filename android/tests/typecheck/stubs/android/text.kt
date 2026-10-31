@file:Suppress("unused", "UNUSED_PARAMETER")
package android.text
class TextPaint(flags: Int = 0) : android.graphics.Paint(flags)
abstract class Layout { val height: Int = 0; fun draw(c: android.graphics.Canvas) {}; enum class Alignment { ALIGN_NORMAL, ALIGN_CENTER, ALIGN_OPPOSITE } }
class StaticLayout : Layout() {
    class Builder {
        fun setAlignment(a: Layout.Alignment): Builder = this; fun setMaxLines(n: Int): Builder = this; fun setEllipsize(t: TextUtils.TruncateAt?): Builder = this
        fun setIncludePad(b: Boolean): Builder = this; fun setLineSpacing(add: Float, mult: Float): Builder = this; fun build(): StaticLayout = StaticLayout()
        companion object { fun obtain(source: CharSequence, start: Int, end: Int, paint: TextPaint, width: Int): Builder = Builder() }
    }
}
object TextUtils { enum class TruncateAt { END, START }; fun ellipsize(text: CharSequence, p: TextPaint, avail: Float, where: TruncateAt): CharSequence = text }
