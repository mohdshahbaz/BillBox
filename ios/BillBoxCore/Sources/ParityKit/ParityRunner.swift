import Foundation
#if canImport(BillBoxCore)
import BillBoxCore
#endif

/// Replays a parity scenario (a JSON array of steps) against BillBoxCore and returns one JSON object per step.
/// The same scenario runs through the Mac's Node code (ios/tests/parity/run-node.js); the two outputs are compared
/// (ios/tests/parity/compare.py on Linux, ParityCompare in the Xcode unit tests).
///
///   { "method": "POST", "path": "/invoices", "body": {...}, "query": {...}, "company": 1 }   one request
///   { "op": "dump" }                                                                           every table of every company
///   { "op": "parse", "pages": [...], "ctx": {...} }                                             PDF parser only
///   { "op": "pagetext", "pages": [[pdf.js text items]] }                                        text runs -> page text
///   { "op": "autocreate", "pages": [...], "company": 1 }                                        parse + match against the books
///   { "op": "backup" }                                                                          backup service directly
///   a request step may carry "to": "<file>" to save a file reply
public final class ParityRunner {
    public let router: Router

    public init(router: Router) { self.router = router }

    static func intOrNil(_ v: Any) -> Int? { let d = JS.number(v); return d.isFinite ? Int(d) : nil }

    public func dump() throws -> Row {
        var out: Row = [:]
        let reg = router.engine.registry
        out["registry"] = try reg.prepare("SELECT id,name,file,active,fy FROM companies ORDER BY id").all().map { r -> Row in var x = r; x["file"] = nil; return x }
        out["app_settings"] = try reg.prepare("SELECT key,value FROM app_settings WHERE key NOT LIKE 'backup_last%' AND key NOT LIKE 'num_follow_checked%' ORDER BY key").all()
        var comps: Row = [:]
        for c in try reg.prepare("SELECT id FROM companies ORDER BY id").all() {
            let id = c["id"] as! Int
            guard let db = try router.engine.openCompany(id) else { continue }
            var t: Row = [:]
            for tb in try db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name").all() {
                let name = tb["name"] as! String
                t[name] = try db.prepare("SELECT * FROM \(name) ORDER BY 1").all().map { r -> Row in var x = r; x["created_at"] = nil; return x }
            }
            comps[String(id)] = t
        }
        out["companies"] = comps
        return out
    }

    /// Runs every step; `each` receives each output as soon as it is ready.
    public func run(_ steps: [Row], each: (Row) -> Void) async {
        for (i, st) in steps.enumerated() {
            each(await step(i, st))
        }
    }

    public func run(_ steps: [Row]) async -> [Row] {
        var out: [Row] = []
        await run(steps) { out.append($0) }
        return out
    }

    func step(_ i: Int, _ st: Row) async -> Row {
        let op = st["op"] as? String
        do {
            if op == "dump" { return ["step": i, "dump": try dump()] }
            if op == "parse" {
                let ctx = (st["ctx"] as? [String: Any]) ?? [:]
                let r = PDFParser.parseInvoicePages((st["pages"] as? [String]) ?? [], items: (ctx["items"] as? [Row]) ?? [], parties: (ctx["parties"] as? [Row]) ?? [],
                                                    companyGstin: (ctx["companyGstin"] as? String) ?? "", companyName: (ctx["companyName"] as? String) ?? "")
                return ["step": i, "parse": r]
            }
            if op == "pagetext" {
                let pages = (st["pages"] as? [Any] ?? []).map { PageText.fromRuns(PageText.runs(fromPdfJsItems: ($0 as? [Any] ?? []).compactMap { $0 as? Row })) }
                return ["step": i, "text": pages]
            }
            if op == "autocreate" {
                let r = try await router.parseForTest(st["pages"] as? [String] ?? [], companyId: st["company"].flatMap { Self.intOrNil($0) })
                return ["step": i, "parse": r]
            }
            if op == "backup" {
                let r = try router.backup.backupNow(reason: "manual")
                return ["step": i, "folder": r.folder, "files": r.files]
            }
            let method = (st["method"] as? String) ?? "GET"
            let path = (st["path"] as? String) ?? "/"
            var query: [String: String] = [:]
            for (k, v) in (st["query"] as? [String: Any]) ?? [:] { query[k] = JS.string(v) }
            let t0 = Date()
            let reply = await router.handle(method, path, query: query, body: (st["body"] as? Row) ?? [:], companyId: st["company"].flatMap { Self.intOrNil($0) })
            if ProcessInfo.processInfo.environment["BBTIME"] != nil {
                FileHandle.standardError.write("\(Int(Date().timeIntervalSince(t0) * 1000)) ms \(method) \(path) \(query)\n".data(using: .utf8)!)
            }
            switch reply {
            case .json(let s, let b): return ["step": i, "status": s, "body": b]
            case .bytes(let s, let d, _, let name):
                if let to = st["to"] as? String { try d.write(to: URL(fileURLWithPath: to)) }
                return ["step": i, "status": s, "file": name, "bytes": d.count]
            }
        } catch {
            return ["step": i, "exception": "\(error)"]
        }
    }
}
