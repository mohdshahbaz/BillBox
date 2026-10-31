@file:Suppress("unused", "UNUSED_PARAMETER")
package android.database.sqlite
import android.database.Cursor
open class SQLiteException(msg: String? = null) : RuntimeException(msg)
class SQLiteConstraintException : SQLiteException()
abstract class SQLiteProgram : java.io.Closeable { fun bindNull(i: Int) {}; fun bindDouble(i: Int, v: Double) {}; fun bindString(i: Int, v: String) {}; fun bindBlob(i: Int, v: ByteArray) {}; override fun close() {} }
class SQLiteStatement : SQLiteProgram() { fun executeUpdateDelete(): Int = 0 }
class SQLiteQuery : SQLiteProgram()
interface SQLiteCursorDriver
class SQLiteCursor(driver: SQLiteCursorDriver, editTable: String?, query: SQLiteQuery) : Cursor {
    override val columnCount = 0
    override fun moveToFirst() = false; override fun moveToNext() = false; override fun getColumnName(i: Int) = ""; override fun getType(i: Int) = 0
    override fun getLong(i: Int) = 0L; override fun getDouble(i: Int) = 0.0; override fun getString(i: Int): String? = null; override fun getBlob(i: Int) = ByteArray(0); override fun close() {}
}
class SQLiteDatabase {
    fun interface CursorFactory { fun newCursor(db: SQLiteDatabase, masterQuery: SQLiteCursorDriver, editTable: String?, query: SQLiteQuery): Cursor }
    fun rawQuery(sql: String, args: Array<String>?): Cursor = TODO()
    fun rawQueryWithFactory(f: CursorFactory, sql: String, args: Array<String>?, editTable: String?): Cursor = TODO()
    fun execSQL(sql: String) {}
    fun compileStatement(sql: String): SQLiteStatement = SQLiteStatement()
    fun close() {}
    companion object {
        const val OPEN_READONLY = 1; const val OPEN_READWRITE = 0; const val CREATE_IF_NECESSARY = 0x10000000; const val NO_LOCALIZED_COLLATORS = 0x10
        fun openDatabase(path: String, factory: CursorFactory?, flags: Int): SQLiteDatabase = SQLiteDatabase()
    }
}
