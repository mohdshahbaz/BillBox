@file:Suppress("unused", "UNUSED_PARAMETER")
package androidx.compose.foundation.lazy
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
interface LazyItemScope
interface LazyListScope {
    fun item(key: Any? = null, contentType: Any? = null, content: @Composable LazyItemScope.() -> Unit)
    fun items(count: Int, key: ((Int) -> Any)? = null, contentType: (Int) -> Any? = { null }, itemContent: @Composable LazyItemScope.(Int) -> Unit)
    @androidx.compose.foundation.ExperimentalFoundationApi fun stickyHeader(key: Any? = null, contentType: Any? = null, content: @Composable LazyItemScope.() -> Unit)
}
inline fun <T> LazyListScope.items(items: List<T>, noinline key: ((T) -> Any)? = null, crossinline itemContent: @Composable LazyItemScope.(T) -> Unit) {}
inline fun <T> LazyListScope.itemsIndexed(items: List<T>, noinline key: ((Int, T) -> Any)? = null, crossinline itemContent: @Composable LazyItemScope.(Int, T) -> Unit) {}
@Composable fun LazyColumn(modifier: Modifier = Modifier, contentPadding: PaddingValues = PaddingValues(), verticalArrangement: Arrangement.Vertical = Arrangement.Top, content: LazyListScope.() -> Unit) {}
