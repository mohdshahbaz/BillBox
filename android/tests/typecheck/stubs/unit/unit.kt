@file:Suppress("unused", "UNUSED_PARAMETER")
package androidx.compose.ui.unit
@JvmInline value class Dp(val value: Float) : Comparable<Dp> {
    override fun compareTo(other: Dp): Int = 0
    operator fun times(other: Float): Dp = this; operator fun times(other: Int): Dp = this
    operator fun plus(other: Dp): Dp = this; operator fun minus(other: Dp): Dp = this; operator fun div(other: Float): Dp = this
}
@JvmInline value class TextUnit(val raw: Long)
val Int.dp: Dp get() = Dp(0f)
val Double.dp: Dp get() = Dp(0f)
val Float.dp: Dp get() = Dp(0f)
val Int.sp: TextUnit get() = TextUnit(0)
val Double.sp: TextUnit get() = TextUnit(0)
interface Density { val density: Float; val fontScale: Float; fun Float.toDp(): Dp = Dp(0f); fun Dp.toPx(): Float = 0f }
fun Density(density: Float, fontScale: Float = 1f): Density = TODO()
@JvmInline value class IntSize(val packed: Long) { val width: Int get() = 0; val height: Int get() = 0 }
