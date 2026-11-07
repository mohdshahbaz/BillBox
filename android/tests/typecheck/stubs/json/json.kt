@file:Suppress("unused", "UNUSED_PARAMETER")
package org.json
open class JSONException(msg: String) : RuntimeException(msg)
class JSONObject() {
    constructor(json: String) : this()
    constructor(map: Map<*, *>) : this()
    fun put(name: String, value: Any?): JSONObject = this
    fun put(name: String, value: Int): JSONObject = this
    fun put(name: String, value: Long): JSONObject = this
    fun put(name: String, value: Double): JSONObject = this
    fun put(name: String, value: Boolean): JSONObject = this
    fun opt(name: String): Any? = null
    fun has(name: String): Boolean = false
    fun isNull(name: String): Boolean = false
    fun get(name: String): Any = TODO()
    fun getString(name: String): String = ""
    fun getDouble(name: String): Double = 0.0
    fun optString(name: String): String = ""
    fun optString(name: String, fallback: String): String = ""
    fun optInt(name: String): Int = 0
    fun optInt(name: String, fallback: Int): Int = 0
    fun optJSONObject(name: String): JSONObject? = null
    fun optJSONArray(name: String): JSONArray? = null
    fun keys(): Iterator<String> = TODO()
    fun length(): Int = 0
    companion object { @JvmField val NULL: Any = Any(); fun quote(s: String?): String = ""; fun numberToString(n: Number): String = "" }
}
class JSONArray() {
    constructor(json: String) : this()
    constructor(c: Collection<*>) : this()
    fun put(v: Any?): JSONArray = this
    fun length(): Int = 0
    fun opt(i: Int): Any? = null
    fun optString(i: Int): String = ""
    fun optJSONObject(i: Int): JSONObject? = null
    fun getString(i: Int): String = ""
    fun getJSONObject(i: Int): JSONObject = TODO()
}
