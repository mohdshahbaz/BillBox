@file:Suppress("unused", "UNUSED_PARAMETER")
package androidx.compose.ui.input.pointer
import androidx.compose.ui.Modifier
interface PointerInputChange
interface PointerInputScope : androidx.compose.ui.unit.Density
fun Modifier.pointerInput(key1: Any?, block: suspend PointerInputScope.() -> Unit): Modifier = this
