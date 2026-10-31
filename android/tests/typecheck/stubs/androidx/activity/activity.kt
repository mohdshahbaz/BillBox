@file:Suppress("unused", "UNUSED_PARAMETER")
package androidx.activity
open class ComponentActivity : android.app.Activity() {
    open fun onCreate(savedInstanceState: android.os.Bundle?) {}
    open fun onResume() {}
    open fun onPause() {}
    val activityResultRegistry: androidx.activity.result.ActivityResultRegistry get() = TODO()
}
fun ComponentActivity.enableEdgeToEdge() {}
