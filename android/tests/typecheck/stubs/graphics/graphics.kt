@file:Suppress("unused", "UNUSED_PARAMETER")
package androidx.compose.ui.graphics
@JvmInline value class Color(val value: ULong) {
    fun copy(alpha: Float = 1f): Color = this
    companion object { val Unspecified = Color(0UL); val Transparent = Color(0UL); val White = Color(0UL); val Black = Color(0UL); val Red = Color(0UL) }
}
fun Color(color: Int): Color = Color(0UL)
fun Color(color: Long): Color = Color(0UL)
fun Color(red: Int, green: Int, blue: Int, alpha: Int = 0xFF): Color = Color(0UL)
abstract class Brush { companion object { fun linearGradient(colors: List<Color>): Brush = TODO(); fun verticalGradient(colors: List<Color>): Brush = TODO() } }
class SolidColor(val value: Color) : Brush()
interface Shape
interface ImageBitmap
fun android.graphics.Bitmap.asImageBitmap(): ImageBitmap = TODO()
