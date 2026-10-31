@file:Suppress("unused", "UNUSED_PARAMETER")
package androidx.compose.foundation.layout
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Dp

@RequiresOptIn annotation class ExperimentalLayoutApi
object Arrangement {
    interface Horizontal; interface Vertical; interface HorizontalOrVertical : Horizontal, Vertical
    val Start: Horizontal = TODO(); val End: Horizontal = TODO(); val Top: Vertical = TODO(); val Bottom: Vertical = TODO()
    val Center: HorizontalOrVertical = TODO(); val SpaceBetween: HorizontalOrVertical = TODO()
    fun spacedBy(space: Dp): HorizontalOrVertical = TODO()
    fun spacedBy(space: Dp, alignment: Alignment.Vertical): Vertical = TODO()
    fun spacedBy(space: Dp, alignment: Alignment.Horizontal): Horizontal = TODO()
}
class PaddingValues(all: Dp) { constructor(horizontal: Dp = Dp(0f), vertical: Dp = Dp(0f)) : this(Dp(0f)) }

interface RowScope { fun Modifier.weight(weight: Float, fill: Boolean = true): Modifier = this; fun Modifier.align(alignment: Alignment.Vertical): Modifier = this }
interface ColumnScope { fun Modifier.weight(weight: Float, fill: Boolean = true): Modifier = this; fun Modifier.align(alignment: Alignment.Horizontal): Modifier = this }
interface BoxScope { fun Modifier.align(alignment: Alignment): Modifier = this; fun Modifier.matchParentSize(): Modifier = this }
interface FlowRowScope : RowScope

@Composable inline fun Row(modifier: Modifier = Modifier, horizontalArrangement: Arrangement.Horizontal = Arrangement.Start, verticalAlignment: Alignment.Vertical = Alignment.Top, content: @Composable RowScope.() -> Unit) {}
@Composable inline fun Column(modifier: Modifier = Modifier, verticalArrangement: Arrangement.Vertical = Arrangement.Top, horizontalAlignment: Alignment.Horizontal = Alignment.Start, content: @Composable ColumnScope.() -> Unit) {}
@Composable inline fun Box(modifier: Modifier = Modifier, contentAlignment: Alignment = Alignment.TopStart, propagateMinConstraints: Boolean = false, content: @Composable BoxScope.() -> Unit) {}
@Composable fun Box(modifier: Modifier) {}
@Composable fun Spacer(modifier: Modifier) {}
@ExperimentalLayoutApi @Composable inline fun FlowRow(modifier: Modifier = Modifier, horizontalArrangement: Arrangement.Horizontal = Arrangement.Start, verticalArrangement: Arrangement.Vertical = Arrangement.Top, maxItemsInEachRow: Int = Int.MAX_VALUE, content: @Composable FlowRowScope.() -> Unit) {}

fun Modifier.padding(all: Dp): Modifier = this
fun Modifier.padding(horizontal: Dp = Dp(0f), vertical: Dp = Dp(0f)): Modifier = this
fun Modifier.padding(start: Dp = Dp(0f), top: Dp = Dp(0f), end: Dp = Dp(0f), bottom: Dp = Dp(0f)): Modifier = this
fun Modifier.padding(paddingValues: PaddingValues): Modifier = this
fun Modifier.fillMaxWidth(fraction: Float = 1f): Modifier = this
fun Modifier.fillMaxHeight(fraction: Float = 1f): Modifier = this
fun Modifier.fillMaxSize(fraction: Float = 1f): Modifier = this
fun Modifier.width(width: Dp): Modifier = this
fun Modifier.height(height: Dp): Modifier = this
fun Modifier.size(size: Dp): Modifier = this
fun Modifier.size(width: Dp, height: Dp): Modifier = this
fun Modifier.widthIn(min: Dp = Dp(0f), max: Dp = Dp(0f)): Modifier = this
fun Modifier.heightIn(min: Dp = Dp(0f), max: Dp = Dp(0f)): Modifier = this
fun Modifier.imePadding(): Modifier = this
fun Modifier.navigationBarsPadding(): Modifier = this
fun Modifier.windowInsetsPadding(insets: WindowInsets): Modifier = this
class WindowInsets { companion object { val statusBars: WindowInsets get() = WindowInsets() } }
fun WindowInsets(all: Int): WindowInsets = WindowInsets()
@ExperimentalLayoutApi val WindowInsets.Companion.isImeVisible: Boolean @Composable get() = false
interface BoxWithConstraintsScope : BoxScope { val maxWidth: Dp; val maxHeight: Dp }
@Composable fun BoxWithConstraints(modifier: Modifier = Modifier, contentAlignment: Alignment = Alignment.TopStart, content: @Composable BoxWithConstraintsScope.() -> Unit) {}
enum class IntrinsicSize { Min, Max }
fun Modifier.height(intrinsicSize: IntrinsicSize): Modifier = this
