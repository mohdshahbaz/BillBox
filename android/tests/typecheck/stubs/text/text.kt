@file:Suppress("unused", "UNUSED_PARAMETER")
package androidx.compose.ui.text
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.TextUnit
class TextStyle {
    fun copy(color: Color = Color.Unspecified, fontSize: TextUnit = TextUnit(0), fontWeight: FontWeight? = null, fontFamily: FontFamily? = null,
             textAlign: TextAlign = TextAlign.Start, textDecoration: TextDecoration? = null): TextStyle = this
}
@JvmInline value class TextRange(val packed: Long) { constructor(index: Int) : this(0L) }
