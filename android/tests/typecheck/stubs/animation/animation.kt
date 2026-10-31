@file:Suppress("unused", "UNUSED_PARAMETER")
package androidx.compose.animation
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
class EnterTransition { operator fun plus(e: EnterTransition) = this }
class ExitTransition { operator fun plus(e: ExitTransition) = this }
interface AnimatedVisibilityScope
fun fadeIn(): EnterTransition = EnterTransition()
fun fadeOut(): ExitTransition = ExitTransition()
fun slideInVertically(initialOffsetY: (fullHeight: Int) -> Int = { -it / 2 }): EnterTransition = EnterTransition()
fun slideOutVertically(targetOffsetY: (fullHeight: Int) -> Int = { -it / 2 }): ExitTransition = ExitTransition()
@Composable fun AnimatedVisibility(visible: Boolean, modifier: Modifier = Modifier, enter: EnterTransition = fadeIn(), exit: ExitTransition = fadeOut(), label: String = "", content: @Composable AnimatedVisibilityScope.() -> Unit) {}
@Composable fun androidx.compose.foundation.layout.ColumnScope.AnimatedVisibility(visible: Boolean, modifier: Modifier = Modifier, enter: EnterTransition = fadeIn(), exit: ExitTransition = fadeOut(), label: String = "", content: @Composable AnimatedVisibilityScope.() -> Unit) {}
