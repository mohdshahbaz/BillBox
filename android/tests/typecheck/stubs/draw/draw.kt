@file:Suppress("unused", "UNUSED_PARAMETER")
package androidx.compose.ui.draw
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.Dp
fun Modifier.clip(shape: Shape): Modifier = this
fun Modifier.shadow(elevation: Dp, shape: Shape, clip: Boolean = true): Modifier = this
