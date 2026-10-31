import Foundation

struct APIError: LocalizedError {
    let message: String
    let status: Int
    let code: String?
    var errorDescription: String? { message }
}

/// Owns the books (BillBoxCore) and runs every request one at a time, the way the Mac's server did on its event loop.
actor EngineHost {
    static let shared = EngineHost()
    private var router: Router?
    private(set) var startError: String?

    /// Books live in Application Support/DistributorPro/data, the same layout as on the Mac.
    static var dataFolder: String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("DistributorPro/data").path
    }

    /// Backups go to Files › On My iPhone › BillBox › DistributorProBackups unless another folder is chosen.
    static var defaultBackupFolder: String {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("DistributorProBackups").path
    }

    func get() throws -> Router {
        if let router { return router }
        Backup.defaultDir = EngineHost.defaultBackupFolder
        Backup.accessFolder = { path in FolderAccess.open(path) }
        // BillBox's own backup folder exists from the start, so "On My iPhone › BillBox" shows in the Files app
        try? FileManager.default.createDirectory(atPath: EngineHost.defaultBackupFolder, withIntermediateDirectories: true)
        // which BillBox this is (License.swift): "public" from the App Store / website, "admin" for the owner's test build
        License.edition = (Bundle.main.object(forInfoDictionaryKey: "BillBoxEdition") as? String) ?? "public"
        let r = try Router(dataDir: EngineHost.dataFolder)
        try? r.backup.followAppFolder(documents: (EngineHost.defaultBackupFolder as NSString).deletingLastPathComponent)
        r.pdfText = { data in try await PDFText.read(data) }
        router = r
        return r
    }

    func handle(_ method: String, _ path: String, query: [String: String], body: [String: Any], companyId: Int?) async -> Reply {
        do {
            let r = try get()
            return await r.handle(method, path, query: query, body: body, companyId: companyId)
        } catch {
            return .json(500, ["error": "Could not open the books: \(error)"] as [String: Any])
        }
    }

    /// Runs the daily backup if it is due (called every minute while the app is open, on launch and from the background task).
    func backupTick() async -> String? {
        guard let r = try? get() else { return nil }
        let folder = await r.exclusive { r.backup.tick()?.folder }
        if let folder { await r.drive.afterBackup(folder) }   // to Google Drive too, when connected
        return folder
    }

    func backupIfDue() async -> Bool {
        guard let r = try? get() else { return false }
        let folder = await r.exclusive { r.backup.isDue() ? r.backup.tick()?.folder : nil }
        if let folder { await r.drive.afterBackup(folder) }
        return folder != nil
    }
}

/// The same calls the Mac screens make ("GET /items", "POST /invoices" …), answered inside the app instead of over HTTP.
enum API {
    /// Sent with every request so the right company's books are used.
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
    static func send(_ method: String, _ path: String, query: [String: Any?] = [:], body: [String: Any]? = nil, company: Int? = nil) async throws -> Reply {
        var q: [String: String] = [:]
        for (k, v) in query { if let v { q[k] = "\(v)" } }
        if q["fy"] == nil, let fy { q["fy"] = fy }
        let reply = await EngineHost.shared.handle(method, path, query: q, body: body ?? [:], companyId: company ?? companyId)
        if case .json(let status, let obj) = reply, status >= 400 {
            let o = obj as? [String: Any]
            throw APIError(message: (o?["detail"] as? String) ?? (o?["error"] as? String) ?? "Request failed (\(status))", status: status, code: o?["code"] as? String)
        }
        noteChange(method, path)
        return reply
    }

    /// A JSON object reply.
    static func obj(_ method: String = "GET", _ path: String, query: [String: Any?] = [:], body: [String: Any?]? = nil, company: Int? = nil) async throws -> JSON {
        let r = try await send(method, path, query: query, body: body.map(clean), company: company)
        if case .json(_, let o) = r { return JSON((o as? [String: Any]) ?? [:]) }
        return JSON()
    }

    /// A JSON array reply.
    static func list(_ path: String, query: [String: Any?] = [:], company: Int? = nil) async throws -> [JSON] {
        let r = try await send("GET", path, query: query, company: company)
        if case .json(_, let o) = r { return JSON.rows(o) }
        return []
    }

    /// Body already built as plain JSON (arrays of lines etc.).
    static func objRaw(_ method: String, _ path: String, body: [String: Any]) async throws -> JSON {
        let r = try await send(method, path, body: body)
        if case .json(_, let o) = r { return JSON((o as? [String: Any]) ?? [:]) }
        return JSON()
    }

    /// A file reply (the GST workbook): its bytes and file name.
    static func bytes(_ path: String, query: [String: Any?] = [:]) async throws -> (Data, String) {
        let r = try await send("GET", path, query: query)
        if case .bytes(_, let d, _, let name) = r { return (d, name) }
        throw APIError(message: "No file was produced", status: 500, code: nil)
    }

    /// One path segment (a voucher number like RCT/26-27/00001) made safe to put in a path.
    static func seg(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}
