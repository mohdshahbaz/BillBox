@file:Suppress("unused", "UNUSED_PARAMETER")
package androidx.compose.foundation.shape
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.Dp
open class CornerBasedShape : Shape
class RoundedCornerShape(size: Dp) : CornerBasedShape()
val CircleShape: RoundedCornerShape = TODO()
val RectangleShape: Shape = TODO()
