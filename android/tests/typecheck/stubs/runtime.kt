// Stubs of the Jetpack Compose runtime: only the signatures BillBox uses (see ../check.sh).
@file:Suppress("unused", "UNUSED_PARAMETER")
package androidx.compose.runtime

import kotlin.reflect.KProperty

@Target(AnnotationTarget.FUNCTION, AnnotationTarget.TYPE, AnnotationTarget.TYPE_PARAMETER, AnnotationTarget.PROPERTY_GETTER)
annotation class Composable
annotation class Stable
annotation class Immutable

interface State<out T> { val value: T }
interface MutableState<T> : State<T> { override var value: T }
interface IntState : State<Int> { val intValue: Int }
interface MutableIntState : IntState, MutableState<Int> { override var intValue: Int }
operator fun <T> State<T>.getValue(thisObj: Any?, property: KProperty<*>): T = value
operator fun <T> MutableState<T>.setValue(thisObj: Any?, property: KProperty<*>, value: T) { this.value = value }
operator fun IntState.getValue(thisObj: Any?, property: KProperty<*>): Int = intValue
operator fun MutableIntState.setValue(thisObj: Any?, property: KProperty<*>, value: Int) { intValue = value }
fun <T> mutableStateOf(value: T): MutableState<T> = TODO()
fun mutableIntStateOf(value: Int): MutableIntState = TODO()
fun <T> derivedStateOf(calculation: () -> T): State<T> = TODO()

class SnapshotStateList<T> : MutableList<T> by ArrayList() { fun toList(): List<T> = TODO() }
class SnapshotStateMap<K, V> : MutableMap<K, V> by HashMap()
fun <T> mutableStateListOf(vararg elements: T): SnapshotStateList<T> = TODO()
fun <K, V> mutableStateMapOf(): SnapshotStateMap<K, V> = TODO()

@Composable inline fun <T> remember(calculation: () -> T): T = calculation()
@Composable inline fun <T> remember(key1: Any?, calculation: () -> T): T = calculation()
@Composable inline fun <T> remember(key1: Any?, key2: Any?, calculation: () -> T): T = calculation()
@Composable inline fun <T> key(vararg keys: Any?, block: @Composable () -> T): T = block()
@Composable fun LaunchedEffect(key1: Any?, block: suspend kotlinx.coroutines.CoroutineScope.() -> Unit) {}
@Composable fun LaunchedEffect(key1: Any?, key2: Any?, block: suspend kotlinx.coroutines.CoroutineScope.() -> Unit) {}
@Composable fun LaunchedEffect(vararg keys: Any?, block: suspend kotlinx.coroutines.CoroutineScope.() -> Unit) {}
@Composable fun rememberCoroutineScope(): kotlinx.coroutines.CoroutineScope = TODO()

abstract class CompositionLocal<T> { val current: T @Composable get() = TODO() }
abstract class ProvidableCompositionLocal<T> : CompositionLocal<T>() { infix fun provides(value: T): ProvidedValue<T> = TODO() }
class ProvidedValue<T>
fun <T> staticCompositionLocalOf(defaultFactory: () -> T): ProvidableCompositionLocal<T> = TODO()
fun <T> compositionLocalOf(defaultFactory: () -> T): ProvidableCompositionLocal<T> = TODO()
@Composable fun CompositionLocalProvider(vararg values: ProvidedValue<*>, content: @Composable () -> Unit) {}
