@file:Suppress("unused", "UNUSED_PARAMETER")
package androidx.compose.runtime.saveable
@androidx.compose.runtime.Composable fun <T : Any> rememberSaveable(vararg inputs: Any?, init: () -> T): T = init()
