package android.app
open class Application : android.content.ContextWrapper() { open fun onCreate() {} }
open class Activity : android.content.ContextWrapper() { val application: Application get() = TODO() }
