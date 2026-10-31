package com.local.billbox.engine

import android.database.Cursor
import android.database.sqlite.SQLiteConstraintException
import android.database.sqlite.SQLiteCursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteException
import android.database.sqlite.SQLiteProgram
import android.util.Base64
import android.webkit.JavascriptInterface
import org.json.JSONArray
import org.json.JSONObject

/**
 * Android's SQLite for the engine (android/engine/shims/sqlite.js), behaving like Node's node:sqlite on the Mac:
 *  - one statement per call (the shim splits scripts), parameters bound by number: numbers as REAL, text, NULL, BLOB;
 *  - BEGIN / COMMIT / ROLLBACK [TO] / SAVEPOINT run as plain SQL (a leading comment keeps Android's own transaction
 *    handling out of the way, so savepoints nest exactly as on the Mac);
 *  - no android_metadata table (NO_LOCALIZED_COLLATORS), so the books stay byte-for-byte the Mac's format.
 * Every call arrives on the WebView's bridge thread, one at a time.
 */
class SqlBridge {
    private val dbs = HashMap<Int, SQLiteDatabase>()
    private var next = 1

    private fun fail(e: Throwable): String {
        val raw = e.message ?: e.toString()
        val code = Regex("\\(code (\\d+)").find(raw)?.groupValues?.get(1)?.toIntOrNull()
            ?: if (e is SQLiteConstraintException) 19 else 1
        val msg = raw.substringBefore(" (code ").substringBefore(", while compiling").trim()
        return JSONObject().put("error", JSONObject().put("message", msg).put("errcode", code)).toString()
    }

    @JavascriptInterface
    fun open(path: String, readOnly: Boolean): String = try {
        val flags = (if (readOnly) SQLiteDatabase.OPEN_READONLY else SQLiteDatabase.OPEN_READWRITE or SQLiteDatabase.CREATE_IF_NECESSARY) or
            SQLiteDatabase.NO_LOCALIZED_COLLATORS
        val db = SQLiteDatabase.openDatabase(path, null, flags)
        val h = next++
        dbs[h] = db
        JSONObject().put("handle", h).toString()
    } catch (e: Throwable) { fail(e) }

    @JavascriptInterface
    fun exec(h: Int, sql: String): String = try {
        val db = dbs[h] ?: throw SQLiteException("database is closed")
        if (sql.trimStart().startsWith("PRAGMA", ignoreCase = true)) {
            db.rawQuery(sql, null).use { it.moveToFirst() }      // a PRAGMA may answer with a row
        } else {
            db.execSQL("/**/ $sql")
        }
        "{}"
    } catch (e: Throwable) { fail(e) }

    private fun bind(p: SQLiteProgram, args: JSONArray) {
        for (i in 0 until args.length()) {
            val v = args.opt(i)
            val idx = i + 1
            when {
                v == null || v == JSONObject.NULL -> p.bindNull(idx)
                v is Number -> p.bindDouble(idx, v.toDouble())
                v is String -> p.bindString(idx, v)
                v is JSONObject && v.has("\$b64") -> p.bindBlob(idx, Base64.decode(v.getString("\$b64"), Base64.NO_WRAP))
                else -> p.bindString(idx, v.toString())
            }
        }
    }

    private fun rowOf(c: Cursor): JSONObject {
        val o = JSONObject()
        for (i in 0 until c.columnCount) {
            val name = c.getColumnName(i)
            when (c.getType(i)) {
                Cursor.FIELD_TYPE_NULL -> o.put(name, JSONObject.NULL)
                Cursor.FIELD_TYPE_INTEGER -> o.put(name, c.getLong(i))
                Cursor.FIELD_TYPE_FLOAT -> o.put(name, c.getDouble(i))
                Cursor.FIELD_TYPE_BLOB -> o.put(name, JSONObject().put("\$b64", Base64.encodeToString(c.getBlob(i), Base64.NO_WRAP)))
                else -> o.put(name, c.getString(i))
            }
        }
        return o
    }

    @JavascriptInterface
    fun query(h: Int, sql: String, argsJson: String, mode: String): String = try {
        val db = dbs[h] ?: throw SQLiteException("database is closed")
        val args = JSONArray(argsJson)
        if (mode == "run") {
            val first = sql.trimStart().take(9).uppercase()
            val text = if (first.startsWith("BEGIN") || first.startsWith("COMMIT") || first.startsWith("ROLLBACK") || first.startsWith("END")) "/**/ $sql" else sql
            db.compileStatement(text).use { st ->
                bind(st, args)
                val changes = st.executeUpdateDelete()
                val last = db.rawQuery("SELECT last_insert_rowid()", null).use { c -> if (c.moveToFirst()) c.getLong(0) else 0L }
                JSONObject().put("changes", changes).put("lastInsertRowid", last).toString()
            }
        } else {
            val factory = SQLiteDatabase.CursorFactory { _, driver, table, q -> bind(q, args); SQLiteCursor(driver, table, q) }
            db.rawQueryWithFactory(factory, sql, null, null).use { c ->
                val rows = JSONArray()
                while (c.moveToNext()) {
                    rows.put(rowOf(c))
                    if (mode == "get") break
                }
                JSONObject().put("rows", rows).toString()
            }
        }
    } catch (e: Throwable) { fail(e) }

    @JavascriptInterface
    fun close(h: Int): String = try {
        dbs.remove(h)?.close()
        "{}"
    } catch (e: Throwable) { fail(e) }
}
