package com.local.billbox.data

import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.roundToLong

/** A JSON object from the engine with forgiving reads (as the iPhone's JSON type): missing or null reads as "" / 0 / false. */
class J(val o: JSONObject = JSONObject()) {
    constructor(map: Map<String, Any?>) : this(JSONObject(map))

    fun has(k: String) = o.has(k) && !o.isNull(k)

    fun str(k: String): String {
        if (!has(k)) return ""
        return when (val v = o.get(k)) {
            is Double -> Fmt.plainNumber(v)
            is Float -> Fmt.plainNumber(v.toDouble())
            is Number -> v.toString()
            else -> v.toString()
        }
    }

    fun num(k: String): Double = when (val v = o.opt(k)) {
        is Number -> v.toDouble()
        is String -> v.trim().toDoubleOrNull() ?: 0.0
        is Boolean -> if (v) 1.0 else 0.0
        else -> 0.0
    }

    fun int(k: String): Int = num(k).roundToLong().toInt()
    fun optInt(k: String): Int? = if (has(k)) int(k) else null

    fun bool(k: String): Boolean = when (val v = o.opt(k)) {
        is Boolean -> v
        is Number -> v.toDouble() != 0.0
        is String -> v == "1" || v.equals("true", true)
        else -> false
    }

    fun obj(k: String): J = J(o.optJSONObject(k) ?: JSONObject())
    fun list(k: String): List<J> = rows(o.opt(k))
    fun strings(k: String): List<String> = o.optJSONArray(k)?.let { a -> (0 until a.length()).map { a.opt(it).toString() } } ?: emptyList()

    val id: Int get() = int("id")

    fun with(vararg kv: Pair<String, Any?>): J {
        val c = JSONObject(o.toString())
        for ((k, v) in kv) c.put(k, v ?: JSONObject.NULL)
        return J(c)
    }

    override fun toString() = o.toString()
    override fun equals(other: Any?) = other is J && other.o.toString() == o.toString()
    override fun hashCode() = o.toString().hashCode()

    /** Pretty-printed with sorted keys (files people upload elsewhere, e.g. the e-way bill JSON). */
    fun pretty(): String = prettyOf(o, "")

    companion object {
        private fun prettyOf(v: Any?, ind: String): String {
            val next = "$ind  "
            return when (v) {
                is JSONObject -> if (v.length() == 0) "{}" else v.keys().asSequence().sorted().joinToString(",\n", "{\n", "\n$ind}") { k -> "$next${JSONObject.quote(k)} : ${prettyOf(v.opt(k), next)}" }
                is JSONArray -> if (v.length() == 0) "[]" else (0 until v.length()).joinToString(",\n", "[\n", "\n$ind]") { "$next${prettyOf(v.opt(it), next)}" }
                is String -> JSONObject.quote(v)
                null, JSONObject.NULL -> "null"
                is Number -> JSONObject.numberToString(v)
                else -> v.toString()
            }
        }

        fun rows(v: Any?): List<J> = (v as? JSONArray)?.let { a -> (0 until a.length()).mapNotNull { a.optJSONObject(it)?.let(::J) } } ?: emptyList()
        /** Plain Kotlin values (maps, lists, numbers, strings, null) → JSON for the engine. */
        fun wrap(v: Any?): Any = when (v) {
            null -> JSONObject.NULL
            is J -> v.o
            is Map<*, *> -> JSONObject().also { o -> v.forEach { (k, x) -> o.put(k.toString(), wrap(x)) } }
            is List<*> -> JSONArray().also { a -> v.forEach { a.put(wrap(it)) } }
            is Array<*> -> JSONArray().also { a -> v.forEach { a.put(wrap(it)) } }
            else -> v
        }
    }
}
