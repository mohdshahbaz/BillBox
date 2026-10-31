@file:Suppress("unused", "UNUSED_PARAMETER")
package androidx.compose.ui.window
import androidx.compose.runtime.Composable
class DialogProperties(val dismissOnBackPress: Boolean = true, val dismissOnClickOutside: Boolean = true, val usePlatformDefaultWidth: Boolean = true, val decorFitsSystemWindows: Boolean = true)
@Composable fun Dialog(onDismissRequest: () -> Unit, properties: DialogProperties = DialogProperties(), content: @Composable () -> Unit) {}
