import Foundation

struct APIError: LocalizedError {
    let message: String
    let status: Int
    let code: String?
    var errorDescription: String? { message }
}

/// Talks to the local Node/SQLite backend (same server the Flutter version used).
enum API {
    static let root = "http://127.0.0.1:3000/api"
    /// Sent on every request so the backend opens the right company's database.
    static var companyId: Int?
    /// Financial year being viewed (e.g. "2026-27"); sent with every request so each screen shows that year only.
    static var fy: String?

    private static func clean(_ d: [String: Any?]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (k, v) in d { if let v { out[k] = v } }
        return out
    }

    /// Called after a successful change that can alter items, prices or stock, so the billing screen reloads its item list.
    static var onItemsChanged: (() -> Void)?
    static func noteChange(_ method: String, _ path: String) {
        guard method != "GET", !path.contains("/preview"), !path.hasPrefix("/items/online") else { return }
        let watched = ["/items", "/batches", "/purchases", "/schemes", "/debit-notes", "/debit_notes", "/marg", "/import", "/backup", "/categories", "/parties", "/companies"]
        if watched.contains(where: { path.hasPrefix($0) }) { onItemsChanged?() }
    }

    /// `company`: another company's books for this one request (an earlier year kept in its own file); nil = the open one.
    static func send(_ method: String, _ path: String, query: [String: Any?] = [:], body: Any? = nil, company: Int? = nil) async throws -> (Data, Any?) {
        guard var comps = URLComponents(string: root + path) else { throw APIError(message: "Bad address \(path)", status: 0, code: nil) }
        var q = query
        if q["fy"] == nil, let fy { q["fy"] = fy }
        let items = q.compactMap { (k, v) -> URLQueryItem? in
            guard let v else { return nil }
            return URLQueryItem(name: k, value: "\(v)")
        }
        if !items.isEmpty { comps.queryItems = items }
        guard let url = comps.url else { throw APIError(message: "Bad address \(path)", status: 0, code: nil) }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 180
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        if let id = company ?? companyId { req.setValue("\(id)", forHTTPHeaderField: "x-company-id") }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw APIError(message: "Cannot reach the server. Start it from the screen that appears at launch, or run \"npm start\" in the backend folder.", status: 0, code: nil)
        }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let parsed: Any? = data.isEmpty ? nil : (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]))
        if status >= 400 {
            let o = parsed as? [String: Any]
            throw APIError(message: (o?["detail"] as? String) ?? (o?["error"] as? String) ?? "Request failed (\(status))", status: status, code: o?["code"] as? String)
        }
        noteChange(method, path)
        return (data, parsed)
    }

    /// A JSON object reply.
    static func obj(_ method: String = "GET", _ path: String, query: [String: Any?] = [:], body: [String: Any?]? = nil, company: Int? = nil) async throws -> JSON {
        let (_, p) = try await send(method, path, query: query, body: body.map(clean), company: company)
        return JSON((p as? [String: Any]) ?? [:])
    }

    /// A JSON array reply.
    static func list(_ path: String, query: [String: Any?] = [:], company: Int? = nil) async throws -> [JSON] {
        let (_, p) = try await send("GET", path, query: query, company: company)
        return JSON.rows(p)
    }

    /// Body already built as plain JSON (arrays of lines etc.).
    static func objRaw(_ method: String, _ path: String, body: [String: Any]) async throws -> JSON {
        let (_, p) = try await send(method, path, body: body)
        return JSON((p as? [String: Any]) ?? [:])
    }

    static func bytes(_ path: String, query: [String: Any?] = [:]) async throws -> Data {
        let (d, _) = try await send("GET", path, query: query)
        return d
    }

    static func healthy() async -> Bool {
        guard let url = URL(string: root + "/health") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 2
        guard let (_, r) = try? await URLSession.shared.data(for: req) else { return false }
        return (r as? HTTPURLResponse)?.statusCode == 200
    }
}
