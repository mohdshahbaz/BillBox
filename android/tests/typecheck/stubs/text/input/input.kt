@file:Suppress("unused", "UNUSED_PARAMETER")
package androidx.compose.ui.text.input
import androidx.compose.ui.text.TextRange
@JvmInline value class KeyboardType(val value: Int) { companion object { val Text = KeyboardType(0); val Number = KeyboardType(1); val Decimal = KeyboardType(2); val Phone = KeyboardType(3); val Email = KeyboardType(4) } }
@JvmInline value class ImeAction(val value: Int) { companion object { val Done = ImeAction(0); val Search = ImeAction(1); val Next = ImeAction(2) } }
@JvmInline value class KeyboardCapitalization(val value: Int) { companion object { val Characters = KeyboardCapitalization(0); val Sentences = KeyboardCapitalization(1); val Words = KeyboardCapitalization(2) } }
class TextFieldValue(val text: String = "", val selection: TextRange = TextRange(0)) { fun copy(text: String = this.text, selection: TextRange = this.selection): TextFieldValue = this }
interface VisualTransformation { companion object { val None: VisualTransformation = object : VisualTransformation {} } }
class PasswordVisualTransformation(val mask: Char = '•') : VisualTransformation
