package com.local.billbox.data

import com.local.billbox.engine.Engine
import org.json.JSONObject

class ApiError(override val message: String, val status: Int, val code: String?) : Exception(message)

/** Requests to the engine, the same routes the Mac app sends to its server (and the iPhone to its engine). */
object Api {
    @Volatile var companyId: Int? = null
    /** Financial year being viewed (e.g. "2026-27"); sent with every request so each screen shows that year only. */
    @Volatile var fy: String? = null
    /** Called after a change that can alter items, prices, stock or parties (the billing screen reloads its lists then). */
    @Volatile var onItemsChanged: (() -> Unit)? = null
    /** Called after any successful change, so list screens reload themselves (also the hook for changes arriving from other devices). */
    @Volatile var onDataChanged: (() -> Unit)? = null

    private val watched = listOf("/items", "/batches", "/purchases", "/schemes", "/debit-notes", "/import", "/backup", "/categories", "/parties", "/companies")

    /** `company`: another company's books for this one request (an earlier year kept in its own file); null = the open one. */
    suspend fun send(method: String, path: String, query: Map<String, Any?> = emptyMap(), body: Any? = null, company: Int? = null): JSONObject {
        val q = JSONObject()
        for ((k, v) in query) if (v != null) q.put(k, v.toString())
        if (!q.has("fy")) fy?.let { q.put("fy", it) }
        val req = JSONObject().put("method", method).put("path", path.substringBefore('?')).put("query", q)
            .put("body", if (body == null) JSONObject() else J.wrap(body))
        (company ?: companyId)?.let { req.put("company", it) }
        val r = Engine.call(req)
        val status = r.optInt("status", 200)
        if (status >= 400) {
            val o = r.optJSONObject("body") ?: JSONObject()
            val msg = o.optString("detail").ifEmpty { o.optString("error") }.ifEmpty { "Request failed ($status)" }
            throw ApiError(msg, status, if (o.has("code") && !o.isNull("code")) o.optString("code") else null)
        }
        if (method != "GET" && !path.contains("/preview") && !path.startsWith("/items/online") && watched.any { path.startsWith(it) }) onItemsChanged?.invoke()
        if (method != "GET" && !path.contains("/preview") && !path.startsWith("/items/online")) onDataChanged?.invoke()
        return r
    }

    /** A JSON object reply. */
    suspend fun obj(method: String, path: String, query: Map<String, Any?> = emptyMap(), body: Any? = null, company: Int? = null): J =
        J(send(method, path, query, body, company).optJSONObject("body") ?: JSONObject())

    suspend fun get(path: String, query: Map<String, Any?> = emptyMap(), company: Int? = null): J = obj("GET", path, query, company = company)

    /** A JSON array reply. */
    suspend fun list(path: String, query: Map<String, Any?> = emptyMap(), company: Int? = null): List<J> = J.rows(send("GET", path, query, company = company).opt("body"))

    /** A file reply (Excel): name and bytes. */
    suspend fun file(path: String, query: Map<String, Any?> = emptyMap()): Pair<String, ByteArray> {
        val r = send("GET", path, query)
        return (r.optString("file").ifEmpty { "file" }) to android.util.Base64.decode(r.optString("b64"), android.util.Base64.NO_WRAP)
    }

    fun seg(s: String): String = java.net.URLEncoder.encode(s, "UTF-8").replace("+", "%20")
}
