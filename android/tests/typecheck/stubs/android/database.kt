@file:Suppress("unused", "UNUSED_PARAMETER")
package android.database
interface Cursor : java.io.Closeable {
    val columnCount: Int
    fun moveToFirst(): Boolean; fun moveToNext(): Boolean
    fun getColumnName(i: Int): String; fun getType(i: Int): Int
    fun getLong(i: Int): Long; fun getDouble(i: Int): Double; fun getString(i: Int): String?; fun getBlob(i: Int): ByteArray
    companion object { const val FIELD_TYPE_NULL = 0; const val FIELD_TYPE_INTEGER = 1; const val FIELD_TYPE_FLOAT = 2; const val FIELD_TYPE_STRING = 3; const val FIELD_TYPE_BLOB = 4 }
}
