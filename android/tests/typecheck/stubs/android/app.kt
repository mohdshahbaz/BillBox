package android.app
open class Application : android.content.ContextWrapper() { open fun onCreate() {} }
open class Activity : android.content.ContextWrapper() {
    val application: Application get() = TODO()
    val intent: android.content.Intent? get() = null
    val window: android.view.Window get() = TODO()
    val applicationInfo: android.content.pm.ApplicationInfo get() = TODO()
}
