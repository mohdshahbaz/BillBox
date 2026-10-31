@file:Suppress("unused", "UNUSED_PARAMETER")
package androidx.compose.foundation
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.Dp
@RequiresOptIn annotation class ExperimentalFoundationApi
class BorderStroke(val width: Dp, val brush: Brush) { constructor(width: Dp, color: Color) : this(width, androidx.compose.ui.graphics.SolidColor(color)) }
fun Modifier.background(color: Color, shape: Shape = androidx.compose.foundation.shape.RectangleShape): Modifier = this
fun Modifier.background(brush: Brush, shape: Shape = androidx.compose.foundation.shape.RectangleShape, alpha: Float = 1f): Modifier = this
fun Modifier.border(border: BorderStroke, shape: Shape = androidx.compose.foundation.shape.RectangleShape): Modifier = this
fun Modifier.border(width: Dp, color: Color, shape: Shape = androidx.compose.foundation.shape.RectangleShape): Modifier = this
fun Modifier.clickable(enabled: Boolean = true, onClickLabel: String? = null, onClick: () -> Unit): Modifier = this
@ExperimentalFoundationApi fun Modifier.combinedClickable(enabled: Boolean = true, onLongClick: (() -> Unit)? = null, onDoubleClick: (() -> Unit)? = null, onClick: () -> Unit): Modifier = this
class ScrollState { val value: Int = 0; val maxValue: Int = 0 }
@Composable fun rememberScrollState(initial: Int = 0): ScrollState = ScrollState()
fun Modifier.verticalScroll(state: ScrollState, enabled: Boolean = true): Modifier = this
fun Modifier.horizontalScroll(state: ScrollState, enabled: Boolean = true): Modifier = this
@Composable fun Canvas(modifier: Modifier, onDraw: DrawScope.() -> Unit) {}
@Composable fun Image(bitmap: ImageBitmap, contentDescription: String?, modifier: Modifier = Modifier, alignment: Alignment = Alignment.Center, contentScale: ContentScale = ContentScale.Fit) {}
@Composable fun isSystemInDarkTheme(): Boolean = false
