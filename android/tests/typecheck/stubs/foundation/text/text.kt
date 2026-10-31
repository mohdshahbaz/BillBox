@file:Suppress("unused", "UNUSED_PARAMETER")
package androidx.compose.foundation.text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.TextFieldValue
class KeyboardOptions(val capitalization: KeyboardCapitalization = KeyboardCapitalization.Sentences, val autoCorrectEnabled: Boolean? = null,
                      val keyboardType: KeyboardType = KeyboardType.Text, val imeAction: ImeAction = ImeAction.Done)
interface KeyboardActionScope
class KeyboardActions(val onDone: (KeyboardActionScope.() -> Unit)? = null, val onSearch: (KeyboardActionScope.() -> Unit)? = null, val onNext: (KeyboardActionScope.() -> Unit)? = null)
@Composable fun BasicTextField(value: TextFieldValue, onValueChange: (TextFieldValue) -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, readOnly: Boolean = false,
                               textStyle: TextStyle = TextStyle(), keyboardOptions: KeyboardOptions = KeyboardOptions(), keyboardActions: KeyboardActions = KeyboardActions(),
                               singleLine: Boolean = false, cursorBrush: Brush = androidx.compose.ui.graphics.SolidColor(androidx.compose.ui.graphics.Color.Black),
                               decorationBox: @Composable (innerTextField: @Composable () -> Unit) -> Unit = { it() }) {}
