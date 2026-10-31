import Foundation

/// Multi-company database layer (backend/src/db.js).
///   data/registry.db   -> list of companies + app-level settings (backup config, last company)
///   data/<company>.db  -> one complete SQLite database per company (fully isolated books)
public final class Engine {
    public let dataDir: String
    public let registry: Database
    private var open: [Int: Database] = [:]

    public init(dataDir: String) throws {
        self.dataDir = dataDir
        try FileManager.default.createDirectory(atPath: dataDir, withIntermediateDirectories: true)
        registry = try Database((dataDir as NSString).appendingPathComponent("registry.db"))
        try registry.pragma("journal_mode = WAL")
        try registry.exec("""
        CREATE TABLE IF NOT EXISTS companies (
          id INTEGER PRIMARY KEY, name TEXT NOT NULL, file TEXT NOT NULL,
          active INTEGER NOT NULL DEFAULT 1, created_at TEXT DEFAULT (datetime('now','localtime'))
        );
        CREATE TABLE IF NOT EXISTS app_settings (key TEXT PRIMARY KEY, value TEXT);
        """)
        // v9: each financial year of a company can be its own set of books (Marg style): fy = "2026-27", or NULL for books
        // that hold every year (all books made before v9)
        if !(try registry.prepare("PRAGMA table_info(companies)").all().contains { $0.str("name") == "fy" }) {
            try registry.exec("ALTER TABLE companies ADD COLUMN fy TEXT")
        }
        // First start: adopt a pre-v2 single database as company #1, or create an empty company.
        if try firstCompanyId() == nil {
            let legacy = (dataDir as NSString).appendingPathComponent("distributor.db")
            if FileManager.default.fileExists(atPath: legacy) {
                let id = try registry.prepare("INSERT INTO companies(name,file) VALUES(?,?)").run("My Company", "distributor.db").lastInsertRowid
                if let d = try openCompany(id), let nm = try d.prepare("SELECT value FROM settings WHERE key='company_name'").get(), let v = nm.s("value"), !v.isEmpty {
                    try registry.prepare("UPDATE companies SET name=? WHERE id=?").run(v, id)
                }
            } else {
                _ = try createCompany(name: "My Company")
            }
        }
    }

    public func path(_ file: String) -> String { (dataDir as NSString).appendingPathComponent(file) }

    public func companyRow(_ id: Int) throws -> Row? {
        try registry.prepare("SELECT * FROM companies WHERE id=? AND active=1").get(id)
    }

    /// Pieces-per-box is read from names like "(1X144)"; units are always PCS (boxes are shown from pieces-per-box).
    private func tidyItems(_ d: Database) throws {
        let up = d.prepare("UPDATE items SET pcs_per_box=? WHERE id=?")
        for it in try d.prepare("SELECT id,name,pcs_per_box FROM items").all() {
            if let pk = PDFParser.packFromName(it.str("name")), it.n("pcs_per_box") != Double(pk) { try up.run(pk, it.i("id")) }
        }
        try d.exec("UPDATE items SET unit='PCS' WHERE unit IS NOT 'PCS'")
    }

    /// The open database of a company (opened, upgraded and tidied the first time). nil when no such active company.
    public func openCompany(_ id: Int) throws -> Database? {
        if let d = open[id] { return d }
        guard let row = try companyRow(id) else { return nil }
        let d = try Database(path(row.str("file")))
        try Schema.apply(d)   // also upgrades older databases in place
        try tidyItems(d)
        open[id] = d
        return d
    }

    /// Closes a company's open handle so its file can be replaced (restore). It reopens on the next request.
    public func closeCompany(_ id: Int) {
        if let d = open[id] { d.close(); open[id] = nil }
    }

    public func closeAll() {
        for (_, d) in open { d.close() }
        open = [:]
    }

    public func firstCompanyId() throws -> Int? {
        try registry.prepare("SELECT id FROM companies WHERE active=1 ORDER BY id LIMIT 1").get()?.i("id")
    }

    /// `settings` are written after company_name, in the order given.
    @discardableResult
    public func createCompany(name: String, fy: String? = nil, settings: [(String, String)] = []) throws -> Int {
        // the wall clock, as Date.now() on the Mac (a test that fixes "today" must not make two companies share one file)
        let ms = Int64((Date().timeIntervalSince1970 * 1000).rounded(.down))
        var file = "company_\(ms).db"
        var n = 2
        while FileManager.default.fileExists(atPath: path(file)) { file = "company_\(ms)_\(n).db"; n += 1 }
        let id = try registry.prepare("INSERT INTO companies(name,file,fy) VALUES(?,?,?)").run(name, file, fy).lastInsertRowid
        let d = try Database(path(file))
        try Schema.apply(d, settings: [("company_name", name)] + (fy.map { [("books_fy", $0)] } ?? []) + settings)
        open[id] = d
        return id
    }

    /// The database a request works on: the company asked for, else the first one (the server's middleware).
    func database(for companyId: Int?) throws -> Database {
        let id = (companyId ?? 0) != 0 ? companyId! : (try firstCompanyId() ?? 0)
        guard let d = try openCompany(id) else { throw HttpError(404, "Company not found") }
        return d
    }
}
