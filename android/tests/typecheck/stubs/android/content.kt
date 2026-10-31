@file:Suppress("unused", "UNUSED_PARAMETER")
package android.content
import android.net.Uri
import java.io.File
abstract class Context {
    open val filesDir: File get() = TODO()
    open val cacheDir: File get() = TODO()
    open val packageName: String get() = TODO()
    open val packageManager: android.content.pm.PackageManager get() = TODO()
    open val contentResolver: ContentResolver get() = TODO()
    open val applicationContext: Context get() = TODO()
    open fun getExternalFilesDir(type: String?): File? = null
    open fun getSharedPreferences(name: String, mode: Int): SharedPreferences = TODO()
    open fun getSystemService(name: String): Any? = null
    open fun startActivity(intent: Intent) {}
    companion object { const val MODE_PRIVATE = 0; const val PRINT_SERVICE = "print"; const val CLIPBOARD_SERVICE = "clipboard" }
}
abstract class ContentResolver {
    fun openInputStream(uri: Uri): java.io.InputStream? = null
    fun openOutputStream(uri: Uri, mode: String): java.io.OutputStream? = null
    fun query(uri: Uri, projection: Array<String>?, selection: String?, selectionArgs: Array<String>?, sortOrder: String?): android.database.Cursor? = null
}
open class ContextWrapper : Context()
interface SharedPreferences {
    fun getString(key: String, defValue: String?): String?
    fun getBoolean(key: String, defValue: Boolean): Boolean
    fun edit(): Editor
    interface Editor { fun putString(k: String, v: String?): Editor; fun putBoolean(k: String, v: Boolean): Editor; fun remove(k: String): Editor; fun apply() }
}
open class Intent(action: String? = null) {
    constructor(action: String, uri: Uri) : this(action)
    var clipData: ClipData? = null
    fun setType(type: String?): Intent = this
    fun setPackage(p: String?): Intent = this
    fun putExtra(name: String, value: String?): Intent = this
    fun putExtra(name: String, value: android.os.Parcelable?): Intent = this
    fun addFlags(flags: Int): Intent = this
    fun getBooleanExtra(name: String, defaultValue: Boolean): Boolean = defaultValue
    companion object {
        const val ACTION_SEND = "send"; const val ACTION_VIEW = "view"; const val EXTRA_STREAM = "stream"; const val EXTRA_TEXT = "text"
        const val FLAG_GRANT_READ_URI_PERMISSION = 1; const val FLAG_ACTIVITY_NEW_TASK = 2
        fun createChooser(target: Intent, title: CharSequence?): Intent = target
    }
}
class ClipData { companion object { fun newRawUri(label: CharSequence?, uri: Uri): ClipData = ClipData(); fun newPlainText(label: CharSequence?, text: CharSequence?): ClipData = ClipData() } }
class ClipboardManager { fun setPrimaryClip(clip: ClipData) {} }
class ActivityNotFoundException : RuntimeException()
