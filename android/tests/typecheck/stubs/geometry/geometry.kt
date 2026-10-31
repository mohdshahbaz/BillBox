@file:Suppress("unused", "UNUSED_PARAMETER")
package androidx.compose.ui.geometry
@JvmInline value class Offset(val packed: Long) { constructor(x: Float, y: Float) : this(0L) }
@JvmInline value class Size(val packed: Long) { constructor(width: Float, height: Float) : this(0L); val width: Float get() = 0f; val height: Float get() = 0f }
@JvmInline value class CornerRadius(val packed: Long) { constructor(x: Float, y: Float = x) : this(0L) }
