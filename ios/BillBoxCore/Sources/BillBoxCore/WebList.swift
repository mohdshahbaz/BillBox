import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// backend/src/services/webList.js — a company's price list on the internet: a web search (DuckDuckGo's plain HTML page,
// no account or key), then the chosen page is read into items by ItemTools.extractList. A PDF comes back to the app as
// data (the app reads PDF text itself) and is then sent to /items/online/extract.
enum WebList {
    static let UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    static func offline() -> HttpError { HttpError(503, "Could not reach the internet. Check the connection and try again.", "OFFLINE") }

    static func get(_ url: URL, _ seconds: Double) async throws -> (Data, String) {
        guard Category.internetAllowed else { throw offline() }
        var req = URLRequest(url: url, timeoutInterval: seconds)
        req.setValue(UA, forHTTPHeaderField: "User-Agent")
        req.setValue("text/html,application/pdf,*/*", forHTTPHeaderField: "Accept")
        let (data, resp): (Data, URLResponse?) = try await withCheckedThrowingContinuation { c in
            URLSession.shared.dataTask(with: req) { d, r, e in
                if e != nil { c.resume(throwing: offline()) } else { c.resume(returning: (d ?? Data(), r)) }
            }.resume()
        }
        let http = resp as? HTTPURLResponse
        if let code = http?.statusCode, !(200..<300).contains(code) { throw HttpError(502, "That page answered with an error (\(code)).") }
        if data.count > 12 * 1024 * 1024 { throw HttpError(413, "That file is too large to read (12 MB at most).") }
        return (data, (http?.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased())
    }

    static func between(_ s: String, _ a: String, _ b: String) -> String? {
        guard let i = s.range(of: a), let j = s.range(of: b, range: i.upperBound..<s.endIndex) else { return nil }
        return String(s[i.upperBound..<j.lowerBound])
    }

    static func search(_ b: Row) async throws -> Row {
        var q = JS.truthy(b["q"]) ? JS.string(b.v("q")) : ["company", "category"].compactMap { JS.truthy(b[$0]) ? JS.string(b.v($0)) : nil }.joined(separator: " ")
        q = JS.trim(q.isEmpty ? "" : (JS.truthy(b["q"]) ? q : q + " price list MRP"))
        if q.isEmpty { throw HttpError(400, "Type the company (and category) to search for") }
        var comps = URLComponents(string: "https://html.duckduckgo.com/html/")!
        comps.queryItems = [URLQueryItem(name: "q", value: q)]
        let (data, _) = try await get(comps.url!, 12)
        let html = String(decoding: data, as: UTF8.self)
        var results: [Row] = []
        for chunk in html.components(separatedBy: "class=\"result__a\"").dropFirst() {
            guard var href = between(chunk, "href=\"", "\"") else { continue }
            href = href.replacingOccurrences(of: "&amp;", with: "&")
            if let r = href.range(of: "uddg=") {
                let enc = String(href[r.upperBound...]).components(separatedBy: "&")[0]
                guard let dec = enc.removingPercentEncoding else { continue }
                href = dec
            }
            if href.hasPrefix("//") { href = "https:" + href }
            let low = href.lowercased()
            if !(low.hasPrefix("http://") || low.hasPrefix("https://")) || href.contains("duckduckgo.com/y.js") { continue }
            var title = href
            if let a = chunk.firstIndex(of: ">"), let z = chunk.range(of: "</a>"), a < z.lowerBound {
                let t = ItemTools.htmlLines(String(chunk[chunk.index(after: a)..<z.lowerBound])).map(ItemTools.str).joined(separator: " ")
                if !t.isEmpty { title = t }
            }
            if results.contains(where: { $0.str("url") == href }) { continue }
            let path = low.components(separatedBy: "?")[0]
            results.append(["title": title, "url": href, "pdf": path.hasSuffix(".pdf")])
            if results.count >= 10 { break }
        }
        return ["query": q, "results": results]
    }

    static func fetchList(_ db: Database, _ b: Row) async throws -> Row {
        let url = JS.trim(JS.truthy(b["url"]) ? JS.string(b.v("url")) : "")
        let low = url.lowercased()
        guard low.hasPrefix("http://") || low.hasPrefix("https://"), let u = URL(string: url) else {
            throw HttpError(400, "Paste a web address starting with http:// or https://")
        }
        let (data, type) = try await get(u, 20)
        if type.contains("pdf") || data.prefix(5) == Data("%PDF-".utf8) {
            return ["url": url, "source": "pdf", "pdf_base64": data.base64EncodedString()]
        }
        var r = try ItemTools.extractList(db, ["html": String(decoding: data, as: UTF8.self), "company": b["company"] ?? nil, "case": b["case"] ?? nil])
        r["url"] = url
        r["source"] = "page"
        return r
    }
}
