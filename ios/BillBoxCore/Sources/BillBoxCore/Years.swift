import Foundation

// backend/src/services/years.js — financial years as separate books (Marg style). A company's year books share its name;
// each has its own file and registry row with fy = "2026-27".
//   carry: true  -> settings and every master copied, each party's balance before the year's first day becomes its opening
//                   balance, and the stock on hand becomes the opening stock.
//   carry: false -> empty books with the company's settings (e.g. for that year's Marg data).
enum Years {
    static let MASTERS = ["categories", "salesmen", "routes", "parties", "party_routes", "items", "schemes"]

    /// Rows of `table` from one database into another, same ids, columns matched by name.
    static func copyRows(_ src: Database, _ dst: Database, _ table: String, _ whereSQL: String = "") throws -> Int {
        let have = Set(try dst.prepare("PRAGMA table_info(\(table))").all().map { $0.str("name") })
        let cols = try src.prepare("PRAGMA table_info(\(table))").all().map { $0.str("name") }.filter { have.contains($0) }
        let ins = dst.prepare("INSERT INTO \(table)(\(cols.joined(separator: ","))) VALUES(\(cols.map { _ in "?" }.joined(separator: ",")))")
        var n = 0
        for r in try src.prepare("SELECT \(cols.joined(separator: ",")) FROM \(table) \(whereSQL) ORDER BY id").all() {
            let args: [Any?] = cols.map { r[$0] ?? nil }
            _ = try ins.runArgs(args)
            n += 1
        }
        return n
    }

    static func addYear(_ engine: Engine, _ id: Int, _ b: Row) throws -> Row {
        guard let src = try engine.companyRow(id) else { throw HttpError(404, "Company not found") }
        if !JS.truthy(b["fy"]) { throw HttpError(400, "Choose the financial year") }
        let fy = try FY.range(b["fy"] ?? nil)
        let siblings = try engine.registry.prepare("SELECT * FROM companies WHERE active=1").all().filter { Backup.norm($0["name"] ?? nil) == Backup.norm(src["name"] ?? nil) }
        if siblings.contains(where: { $0.str("fy") == fy.label && JS.truthy($0["fy"]) }) {
            throw HttpError(409, "\(src.str("name")) already has books for \(fy.label).", "YEAR_EXISTS")
        }
        let cv = b["carry"] ?? nil
        let carry = !((cv as? Bool) == false || (!(cv is Bool) && ((cv as? Int) == 0 || (cv as? Double) == 0)))
        guard let raw = try engine.openCompany(src.i("id")) else { throw HttpError(404, "Company not found") }
        var settings: [(String, String)] = []
        for r in try raw.prepare("SELECT key,value FROM settings").all() where r.str("key") != "company_name" && r.str("key") != "books_fy" {
            settings.append((r.str("key"), JS.string(r["value"] ?? nil)))
        }
        let newId = try engine.createCompany(name: src.str("name"), fy: fy.label, settings: settings)
        guard let dst = try engine.openCompany(newId) else { throw HttpError(500, "The new books could not be opened") }
        var masters = 0, opening = 0, batches = 0
        if carry {
            try dst.transaction {
                for t in MASTERS { masters += try copyRows(raw, dst, t) }
                batches = try copyRows(raw, dst, "batches", "WHERE qty <> 0")
                let lg = dst.prepare("INSERT INTO ledger(party_id,date,type,ref_no,debit,credit,narration) VALUES(?,?,'OPENING','OPENING',?,?,?)")
                let from = JS.truthy(src["fy"]) ? src.str("fy") : "the earlier books"
                for p in try raw.prepare("SELECT party_id, SUM(debit)-SUM(credit) b FROM ledger WHERE date < ? GROUP BY party_id ORDER BY party_id").all(fy.from) {
                    let bal = r2(p.n("b"))
                    if abs(bal) < 0.005 { continue }
                    try lg.run(p.v("party_id"), fy.from, bal > 0 ? bal : 0, bal < 0 ? -bal : 0, "Opening balance (carried from \(from))")
                    opening += 1
                }
            }
        }
        let carried: Any = carry ? ["masters": masters, "opening_balances": opening, "stock_batches": batches] as Row : NSNull()
        return ["id": newId, "name": src["name"]!, "fy": fy.label, "carried": carried]
    }

    /// A company renamed: every year's books keep the same name.
    static func renameAll(_ engine: Engine, _ oldName: String, _ newName: String) throws {
        for c in try engine.registry.prepare("SELECT * FROM companies").all() where Backup.norm(c["name"] ?? nil) == Backup.norm(oldName) {
            try engine.registry.prepare("UPDATE companies SET name=? WHERE id=?").run(newName, c.v("id"))
            if let d = try engine.openCompany(c.i("id")) {
                try d.prepare("INSERT INTO settings(key,value) VALUES('company_name',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value").run(newName)
            }
        }
    }
}
