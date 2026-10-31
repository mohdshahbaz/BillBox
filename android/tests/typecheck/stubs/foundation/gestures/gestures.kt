@file:Suppress("unused", "UNUSED_PARAMETER")
package androidx.compose.foundation.gestures
import androidx.compose.ui.input.pointer.PointerInputChange
import androidx.compose.ui.input.pointer.PointerInputScope
suspend fun PointerInputScope.detectHorizontalDragGestures(onDragStart: (Any) -> Unit = {}, onDragEnd: () -> Unit = {}, onDragCancel: () -> Unit = {},
                                                          onHorizontalDrag: (change: PointerInputChange, dragAmount: Float) -> Unit) {}
