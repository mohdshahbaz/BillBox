@file:Suppress("unused", "UNUSED_PARAMETER")
package androidx.compose.ui

interface Modifier {
    infix fun then(other: Modifier): Modifier = this
    companion object : Modifier
}
interface Alignment {
    interface Horizontal
    interface Vertical
    companion object {
        val TopStart: Alignment = TODO(); val TopCenter: Alignment = TODO(); val TopEnd: Alignment = TODO()
        val CenterStart: Alignment = TODO(); val Center: Alignment = TODO(); val CenterEnd: Alignment = TODO()
        val BottomStart: Alignment = TODO(); val BottomCenter: Alignment = TODO(); val BottomEnd: Alignment = TODO()
        val Top: Vertical = TODO(); val CenterVertically: Vertical = TODO(); val Bottom: Vertical = TODO()
        val Start: Horizontal = TODO(); val CenterHorizontally: Horizontal = TODO(); val End: Horizontal = TODO()
    }
}
fun Modifier.zIndex(zIndex: Float): Modifier = this
