@file:Suppress("unused", "UNUSED_PARAMETER")
package androidx.compose.ui.focus
import androidx.compose.ui.Modifier
class FocusRequester { fun requestFocus() {} }
interface FocusState { val isFocused: Boolean }
fun Modifier.focusRequester(focusRequester: FocusRequester): Modifier = this
fun Modifier.onFocusChanged(onFocusChanged: (FocusState) -> Unit): Modifier = this
