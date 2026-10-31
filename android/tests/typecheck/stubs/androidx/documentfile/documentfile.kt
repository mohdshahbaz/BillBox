@file:Suppress("unused", "UNUSED_PARAMETER")
package androidx.documentfile.provider
abstract class DocumentFile {
    abstract val name: String?; abstract val uri: android.net.Uri; abstract val isFile: Boolean; abstract val isDirectory: Boolean
    abstract fun listFiles(): Array<DocumentFile>; abstract fun findFile(name: String): DocumentFile?
    abstract fun createDirectory(name: String): DocumentFile?; abstract fun createFile(mime: String, name: String): DocumentFile?; abstract fun delete(): Boolean
    companion object { fun fromTreeUri(context: android.content.Context, uri: android.net.Uri): DocumentFile? = null }
}
