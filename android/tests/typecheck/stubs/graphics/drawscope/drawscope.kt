@file:Suppress("unused", "UNUSED_PARAMETER")
package androidx.compose.ui.graphics.drawscope
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
interface DrawScope : androidx.compose.ui.unit.Density {
    val size: Size
    fun drawRect(color: Color, topLeft: Offset = Offset(0L), size: Size = this.size, alpha: Float = 1f) {}
    fun drawRoundRect(color: Color, topLeft: Offset = Offset(0L), size: Size = this.size, cornerRadius: CornerRadius = CornerRadius(0L), alpha: Float = 1f) {}
}
