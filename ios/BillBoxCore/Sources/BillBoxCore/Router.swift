import Foundation

/// A reply from the router: JSON (status + object/array) or a file (the Excel workbook).
public enum Reply {
    case json(Int, Any)
    case bytes(Int, Data, contentType: String, fileName: String)

    public var status: Int {
        switch self {
        case .json(let s, _): return s
        case .bytes(let s, _, _, _): return s
        }
    }
}

/// The Mac app's server, in process: the same paths, the same bodies, the same replies and the same error texts
/// (backend/src/server.js and routes/*.js). All calls are serialised, as the server's single event loop did.
public final class Router {
    public let engine: Engine
    public let backup: Backup
    /// Reads the text of each page of a PDF (iOS: PDFKit, with Vision OCR for scans). Returns the pages and "text" or "ocr".
    public var pdfText: ((Data) async throws -> (pages: [String], method: String))?

    /// Google Drive backups (Drive.swift). Its network work runs outside the queue; its settings take their turn in it.
    public private(set) lazy var drive = Drive(backup) { [unowned self] work in try await self.exclusive(work) }
    /// Licence and subscription (License.swift); limits nothing unless `License.edition` is set by the app.
    public private(set) lazy var license = License(backup) { [unowned self] work in try await self.exclusive(work) }

    /// Live sync between devices (Sync.swift); the app calls GET /sync/tick every few seconds.
    public private(set) lazy var sync = Sync(engine, backup) { [unowned self] work in try await self.exclusive(work) }

    public init(engine: Engine) {
        self.engine = engine
        self.backup = Backup(engine)
        engine.onOpen = { [unowned self] id, d in self.sync.attach(id, d) }
        engine.onReplace = { [unowned self] id in self.sync.afterReplace(id) }
    }

    public convenience init(dataDir: String) throws { self.init(engine: try Engine(dataDir: dataDir)) }

    static func message(of error: Error) -> String {
        if let h = error as? HttpError { return h.message }
        if let s = error as? SQLiteError { return s.message }
        return error.localizedDescription
    }

    /// Requests run one at a time, as on the Mac (Node runs one request's code at a time). Screens fire several requests at once
    /// (a screen loads parties, items and routes together); without this they would use the same SQLite connection from
    /// several threads at once and the app would crash.
    let gate = AsyncGate()

    /// One request. `path` may start with "/api". Query values are strings, as Express gives them.
    public func handle(_ method: String, _ path: String, query: [String: String] = [:], body: Row = [:], companyId: Int? = nil) async -> Reply {
        let seg = segments(path)
        if seg.count >= 2 && seg[0] == "backup" && seg[1] == "drive" {
            // Google Drive: not queued (an upload can take a while); Drive takes its turn for each settings read and write
            return await answer {
                guard let r = try await self.drive.route(method.uppercased(), seg, JSONNorm.row(body)) else { throw HttpError(404, "Not found") }
                return r
            }
        }
        if seg.first == "sync" {
            // live sync: its network work runs outside the queue; its books work takes its turn in it
            return await answer {
                guard let r = try await self.sync.route(method.uppercased(), seg, JSONNorm.row(body), companyId) else { throw HttpError(404, "Not found") }
                return r
            }
        }
        if seg.first == "update" && method.uppercased() == "GET" {
            // Settings › Updates: the newest release of this edition (Update.swift); no books are touched
            return await answer { .json(200, try await Update.check(version: query["version"] ?? "", edition: query["edition"] ?? "", platform: query["platform"] ?? "")) }
        }
        if seg.first == "license" {
            return await answer {
                guard let r = try await self.license.route(method.uppercased(), seg, JSONNorm.row(body)) else { throw HttpError(404, "Not found") }
                return r
            }
        }
        await gate.enter()
        if !license.allows(method.uppercased(), seg) {
            gate.leave()
            return await answer { throw License.blocked() }
        }
        let reply = await handleNow(method, path, query: query, body: body, companyId: companyId)
        gate.leave()
        return reply
    }

    /// Other work on the books (the backup timer) waits its turn the same way.
    public func exclusive<T>(_ work: () throws -> T) async rethrows -> T {
        await gate.enter()
        defer { gate.leave() }
        return try work()
    }

    private func handleNow(_ method: String, _ path: String, query: [String: String], body: Row, companyId: Int?) async -> Reply {
        await answer { try await self.route(method.uppercased(), path, query, JSONNorm.row(body), companyId) }
    }

    /// A reply, or the error turned into one the way server.js does.
    private func answer(_ work: () async throws -> Reply) async -> Reply {
        do {
            return try await work()
        } catch let e as HttpError {
            var o: Row = ["error": e.status == 500 ? "Server error" : e.message]
            if let c = e.code { o["code"] = c }
            if e.status == 500 { o["detail"] = e.message }   // the reason of a failure the app itself reports
            return .json(e.status, o)
        } catch let e as SQLiteError {
            // a constraint failure (a name or batch that already exists) is answered 409 with a plain reason, as by the server
            if (e.code & 255) == 19 {
                let msg = e.message.contains("UNIQUE") ? "That value already exists (for example a duplicate batch number)." : "Invalid reference or missing value."
                return .json(409, ["error": msg] as Row)
            }
            return .json(500, ["error": "Server error", "code": "ERR_SQLITE_ERROR"] as Row)
        } catch {
            return .json(500, ["error": "Server error"] as Row)
        }
    }

    private func segments(_ path: String) -> [String] {
        var p = path
        if let q = p.firstIndex(of: "?") { p = String(p[..<q]) }
        var segs = p.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        if segs.first == "api" { segs.removeFirst() }
        return segs
    }

    private func route(_ m: String, _ path: String, _ q: [String: String], _ b: Row, _ companyId: Int?) async throws -> Reply {
        let s = segments(path)
        func ok(_ v: Any) -> Reply { .json(200, v) }
        let n = s.count

        // company-independent routes first (companies.js, backup.js)
        if n >= 1 && s[0] == "health" && m == "GET" { return ok(["ok": true] as Row) }
        if n >= 1 && s[0] == "companies" {
            if n == 1 && m == "GET" { return ok(try listCompanies()) }
            if n == 1 && m == "POST" { return try addCompany(b) }
            if n == 2 && m == "PUT" { return ok(try updateCompany(s[1], b)) }
            if n == 3 && s[2] == "activate" && m == "POST" { return ok(try activateCompany(s[1])) }
            if n == 3 && s[2] == "delete" && m == "POST" { return ok(try deleteCompany(s[1], b)) }
            if n == 3 && s[2] == "years" && m == "POST" { return .json(201, try Years.addYear(engine, Int(JS.number(s[1])), b)) }
        }
        if n >= 1 && s[0] == "backup" {
            if n == 1 && m == "GET" { return ok(["config": try backup.config(), "backups": try backup.listBackups()] as Row) }
            if n == 2 && s[1] == "config" && m == "PUT" { return ok(try backup.saveConfig(b)) }
            if n == 2 && s[1] == "run" && m == "POST" {
                let r = try backup.backupNow(reason: "manual")
                let folder = r.folder
                Task { await self.drive.afterBackup(folder) }   // to Google Drive too, when connected
                return ok(["folder": r.folder, "files": r.files.count, "config": try backup.config(), "backups": try backup.listBackups()] as Row)
            }
            if n == 2 && s[1] == "restore" && m == "POST" { return ok(try backup.restore(b)) }
            if n == 2 && m == "DELETE" {
                var r = try backup.deleteBackup(s[1])
                r["backups"] = try backup.listBackups()
                return ok(r)
            }
        }

        // everything else runs inside the selected company's database
        let db = try engine.database(for: companyId)

        switch (m, n, s.first ?? "") {
        // items.js
        case ("GET", 1, "categories"): return ok(try categories(db))
        case ("POST", 1, "categories"): return try addCategory(db, b)
        case ("GET", 1, "items"): return ok(try listItems(db, q))
        case ("POST", 1, "items"): return try await addItem(db, b)
        case ("POST", 2, "items") where s[1] == "auto-categorize": return ok(try await autoCategorize(db))
        case ("POST", 2, "items") where s[1] == "auto-mrp": return ok(try autoMRP(db))
        case ("POST", 2, "items") where s[1] == "bulk-prices": return ok(try bulkPrices(db, b))
        case ("POST", 2, "items") where s[1] == "auto-pack": return ok(try fixPacks(db))
        case ("POST", 2, "items") where s[1] == "set-prices": return ok(try Pricing.setPrices(db, b))
        case ("GET", 2, "items") where s[1] == "mrp-table": return ok(try Pricing.mrpTable(db, q))
        case ("GET", 2, "items") where s[1] == "clean-preview": return ok(try ItemTools.cleanPreview(db, q))
        case ("POST", 2, "items") where s[1] == "clean-names": return ok(try ItemTools.applyClean(db, b))
        case ("POST", 2, "items") where s[1] == "merge": return ok(try ItemTools.mergeItems(db, b))
        case ("POST", 3, "items") where s[1] == "online" && s[2] == "extract": return ok(try ItemTools.extractList(db, b))
        case ("POST", 3, "items") where s[1] == "online" && s[2] == "search": return ok(try await WebList.search(b))
        case ("POST", 3, "items") where s[1] == "online" && s[2] == "fetch": return ok(try await WebList.fetchList(db, b))
        case ("POST", 3, "items") where s[2] == "set-stock": return ok(try setStock(db, s[1], b))
        case ("POST", 2, "items") where s[1] == "bulk-add": return .json(201, try ItemTools.bulkAdd(db, b))
        case ("POST", 2, "items") where s[1] == "bulk-prices-by-mrp": return ok(try bulkPricesByMRP(db, b))
        case ("GET", 2, "items") where s[1] == "mrp-groups": return ok(try mrpGroups(db, q))
        case ("PUT", 2, "items"): return ok(try updateItem(db, s[1], b))
        case ("DELETE", 2, "items"): return ok(try deleteItem(db, s[1], q))
        case ("GET", 3, "items") where s[2] == "batches": return ok(try db.prepare("SELECT * FROM batches WHERE item_id=? ORDER BY exp_date").all(s[1]))
        case ("POST", 1, "batches"): return try addBatch(db, b)
        case ("GET", 1, "schemes"): return ok(try listSchemes(db))
        case ("POST", 1, "schemes"): return try addScheme(db, b)
        case ("DELETE", 2, "schemes"): return ok(try deleteScheme(db, s[1]))

        // parties.js
        case ("GET", 1, "parties"): return ok(try listParties(db, q))
        case ("POST", 1, "parties"): return try addParty(db, b)
        case ("PUT", 2, "parties"): return ok(try updateParty(db, s[1], b))
        case ("DELETE", 2, "parties"): return ok(try deleteParty(db, s[1]))
        case ("GET", 3, "parties") where s[2] == "ledger": return ok(try ledger(db, s[1], q))
        case ("GET", 2, "vouchers"): return ok(try Vouchers.get(db, s[1]))
        case ("POST", 1, "vouchers"): return .json(201, try Vouchers.record(db, b))
        case ("DELETE", 2, "ledger"): return ok(try Vouchers.deleteLedgerEntry(db, s[1]))
        case ("POST", 3, "receipts") where s[1] == "sheet" && s[2] == "parse": return ok(try PaymentSheet.parse(db, b))
        case ("POST", 2, "receipts") where s[1] == "sheet": return .json(201, try PaymentSheet.save(db, b))
        case ("POST", 1, "receipts"):
            var bb = b
            bb["direction"] = "RECEIVED"
            return .json(201, try Vouchers.record(db, bb))
        case ("GET", 1, "receipts"): return ok(try receiptsOn(db, q))

        // salesmen.js
        case ("GET", 1, "salesmen"): return ok(try listSalesmen(db))
        case ("POST", 1, "salesmen"): return try addSalesman(db, b)
        case ("PUT", 2, "salesmen"): return ok(try updateSalesman(db, s[1], b))
        case ("GET", 3, "salesmen") where s[2] == "beat": return ok(try beat(db, s[1], q))
        case ("GET", 3, "salesmen") where s[2] == "performance": return ok(try performance(db, s[1], q))
        case ("GET", 1, "routes"): return ok(try listRoutes(db))
        case ("POST", 1, "routes"): return try addRoute(db, b)
        case ("PUT", 2, "routes"): return ok(try updateRoute(db, s[1], b))
        case ("DELETE", 2, "routes"): return ok(try deleteRoute(db, s[1]))

        // invoices.js
        case ("POST", 2, "invoices") where s[1] == "preview": return ok(try Billing.preview(db, b))
        case ("POST", 2, "invoices") where s[1] == "printed":
            let ids = ((b["ids"] as? [Any]) ?? []).map { JS.number($0) }.filter { JS.isInteger($0) && $0 > 0 }
            if ids.isEmpty { throw HttpError(400, "Choose the bills") }
            let pv = b["printed"] ?? nil
            let isZero = !(pv is Bool) && ((pv as? Int) == 0 || (pv as? Double) == 0)
            let flag = ((pv as? Bool) == false || isZero) ? 0 : 1   // printed === false || printed === 0
            let st = db.prepare("UPDATE invoices SET printed=? WHERE id=?")
            var updated = 0
            try db.transaction { for id in ids { updated += try st.run(flag, id).changes } }
            return ok(["updated": updated, "printed": flag] as Row)
        case ("POST", 1, "invoices"):
            let id = try Billing.create(db, b)
            let inv = try Billing.get(db, id)!
            return .json(201, ["id": id, "invoice_no": inv["invoice_no"]!, "total": inv["total"]!, "paid": inv["paid"]!] as Row)
        case ("PUT", 2, "invoices"):
            let id = try Billing.update(db, Int(JS.number(s[1])), b)
            let inv = try Billing.get(db, id)!
            return ok(["id": id, "invoice_no": inv["invoice_no"]!, "total": inv["total"]!, "paid": inv["paid"]!] as Row)
        case ("DELETE", 2, "invoices"): return ok(try Billing.delete(db, Int(JS.number(s[1]))))
        case ("GET", 1, "invoices"):
            let date = (q["date"]?.isEmpty == false) ? q["date"]! : today()
            return ok(try db.prepare("""
            SELECT i.id,i.invoice_no,i.date,i.total,i.paid,i.pay_mode,i.sale_type, p.name party_name, s.name salesman_name
                 FROM invoices i LEFT JOIN parties p ON p.id=i.party_id LEFT JOIN salesmen s ON s.id=i.salesman_id
                 WHERE i.date=? ORDER BY i.id DESC
            """).all(date))
        case ("GET", 3, "invoices") where s[2] == "ewaybill": return ok(try EwayBill.details(db, s[1]))
        case ("POST", 3, "invoices") where s[2] == "ewaybill": return ok(try EwayBill.build(db, s[1], b))
        case ("PUT", 3, "invoices") where s[2] == "ewaybill": return ok(try EwayBill.saveNumber(db, s[1], b))
        case ("GET", 2, "invoices"):
            guard let inv = try Billing.get(db, s[1]) else { throw HttpError(404, "Invoice not found") }
            return ok(inv)
        case ("GET", 1, "numbering"):
            let date = q["date"]?.isEmpty == false ? q["date"] : nil
            return ok(["series": try numberSeries.map { try peekNo(db, $0.0, date) }] as Row)
        case ("PUT", 1, "numbering"):
            let date = b.str("date").isEmpty ? nil : b.str("date")
            return ok(try db.transaction { try setNext(db, b.str("series"), b["next"] ?? nil, date) })
        case ("GET", 1, "settings"): return ok(try Billing.settings(db))
        case ("PUT", 1, "settings"):
            if b.defined("low_stock_qty") && !(JS.number(b["low_stock_qty"] ?? nil) >= 0) { throw HttpError(400, "Low-stock level must be 0 or more") }
            let up = db.prepare("INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value")
            try db.transaction { try numberingEdited(db, b); for (k, v) in b { try up.run(k, JS.string(v)) } }
            return ok(try Billing.settings(db))

        // purchases.js
        case ("POST", 2, "purchases") where s[1] == "preview": return ok(try Purchases.preview(db, b))
        case ("POST", 2, "purchases") where s[1] == "parse-pdf": return ok(try await parsePDF(db, b))
        case ("POST", 1, "purchases"):
            let id = try Purchases.create(db, b)
            let p = try Purchases.get(db, id)!
            return .json(201, ["id": id, "purchase_no": p["purchase_no"]!, "total": p["total"]!] as Row)
        case ("PUT", 2, "purchases"):
            let id = try Purchases.update(db, Int(JS.number(s[1])), b)
            let p = try Purchases.get(db, id)!
            return ok(["id": id, "purchase_no": p["purchase_no"]!, "total": p["total"]!] as Row)
        case ("DELETE", 2, "purchases"): return ok(try Purchases.delete(db, Int(JS.number(s[1]))))
        case ("GET", 2, "purchases"):
            guard let p = try Purchases.get(db, s[1]) else { throw HttpError(404, "Purchase bill not found") }
            return ok(p)

        // import.js
        case ("POST", 3, "import") where s[1] == "marg" && s[2] == "preview": return ok(try MargImport.preview(db, b["path"] ?? nil))
        case ("POST", 2, "import") where s[1] == "marg": return ok(try MargImport.run(db, b["path"] ?? nil))
        case ("POST", 3, "import") where s[1] == "marg" && s[2] == "prices": return ok(try MargImport.correctPrices(db, b["path"] ?? nil, apply: JS.truthy(b["apply"] ?? nil)))

        // debitNotes.js
        case ("GET", 1, "debit-notes"):
            return ok(try DebitNotes.list(db, fy: q["fy"], from: q["from"], to: q["to"], q: q["q"], partyId: q["party_id"]))
        case ("POST", 2, "debit-notes") where s[1] == "preview": return ok(try DebitNotes.preview(db, b))
        case ("POST", 1, "debit-notes"):
            let id = try DebitNotes.create(db, b)
            let d = try DebitNotes.get(db, id)!
            return .json(201, ["id": id, "note_no": d["note_no"]!, "total": d["total"]!] as Row)
        case ("PUT", 2, "debit-notes"):
            let id = try DebitNotes.update(db, Int(JS.number(s[1])), b)
            let d = try DebitNotes.get(db, id)!
            return ok(["id": id, "note_no": d["note_no"]!, "total": d["total"]!] as Row)
        case ("DELETE", 2, "debit-notes"): return ok(try DebitNotes.delete(db, Int(JS.number(s[1]))))
        case ("GET", 2, "debit-notes"):
            guard let d = try DebitNotes.get(db, s[1]) else { throw HttpError(404, "Debit note not found") }
            return ok(d)

        // reports.js
        case ("GET", 1, "fy"):
            let own = try FY.booksFy(db)
            let cur = try own ?? FY.range(nil).label
            return ok(["current": cur, "years": try FY.list(db).map { $0.json }, "books_fy": own ?? NSNull()] as Row)
        case ("GET", 1, "bills"):
            return ok(try Reports.bills(db, type: (q["type"]?.isEmpty == false ? q["type"]! : "ALL").uppercased(), from: q["from"], to: q["to"], q: q["q"],
                                        unpaid: q["unpaid"] == "1", unprinted: q["unprinted"] == "1", fy: q["fy"]))
        case ("GET", 2, "reports"): return try reports(db, s[1], q)
        case ("GET", 3, "reports") where s[1] == "book": return ok(try Reports.book(db, s[2] == "purchase" ? "purchase" : s[2] == "debit" ? "debit" : "sales", q["from"], q["to"], q["fy"]))
        default: break
        }
        throw HttpError(404, "Not found")
    }

    private func reports(_ db: Database, _ name: String, _ q: [String: String]) throws -> Reply {
        func ok(_ v: Any) -> Reply { .json(200, v) }
        switch name {
        case "dashboard": return ok(try Reports.dashboard(db, q["fy"]))
        case "profit":
            let f = try FY.range(q["fy"])
            return ok(try Reports.profit(db, (q["from"]?.isEmpty == false) ? q["from"]! : f.from, (q["to"]?.isEmpty == false) ? q["to"]! : f.to))
        case "gst-outward.xlsx":
            let (data, month) = try gstWorkbook(db, q["month"], q["fy"])
            return .bytes(200, data, contentType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", fileName: "GST-Outward-\(month).xlsx")
        case "gst-outward": return ok(try Reports.gstOutward(db, q["month"], q["fy"]))
        case "expiry":
            let d = JS.parseInt(q["days"])
            let days = (d.isNaN || d == 0) ? 90 : Int(d)
            return ok(try db.prepare("""
            SELECT b.id, b.batch_no, b.exp_date, b.qty, i.name item_name, i.purchase_price,
                   CAST(julianday(b.exp_date) - julianday(?) AS INTEGER) days_left, ROUND(b.qty * i.purchase_price, 2) stock_value
                 FROM batches b JOIN items i ON i.id=b.item_id WHERE b.qty>0 AND b.exp_date <= ? AND b.exp_date < '2099-01-01' ORDER BY b.exp_date
            """).all(today(), Clock.addDays(days)))
        case "low-stock": return ok(try Reports.lowStock(db).rows)
        case "outstanding":
            return ok(try db.prepare("""
            SELECT p.id, p.name, p.phone, p.type, p.credit_limit, r.name route_name, SUM(l.debit)-SUM(l.credit) balance
                 FROM parties p JOIN ledger l ON l.party_id=p.id AND l.date <= ? LEFT JOIN routes r ON r.id=p.route_id
                 GROUP BY p.id HAVING ABS(balance) > 0.5 ORDER BY balance DESC
            """).all(try FY.range(q["fy"]).to))
        case "gst-summary":
            let from = (q["from"]?.isEmpty == false) ? q["from"]! : today().jsSlice(0, 7) + "-01", to = (q["to"]?.isEmpty == false) ? q["to"]! : today()
            return ok(try db.prepare("""
            SELECT l.gst_rate, ROUND(SUM(l.taxable),2) taxable, ROUND(SUM(l.cgst),2) cgst, ROUND(SUM(l.sgst),2) sgst, ROUND(SUM(l.igst),2) igst
                 FROM invoice_lines l JOIN invoices i ON i.id=l.invoice_id WHERE i.date BETWEEN ? AND ? GROUP BY l.gst_rate ORDER BY l.gst_rate
            """).all(from, to))
        default: throw HttpError(404, "Not found")
        }
    }

    /// The monthly GST workbook: Summary, B2B Bills, B2C Bills, Rate-wise Summary (routes/reports.js).
    func gstWorkbook(_ db: Database, _ month: Any?, _ fy: Any?) throws -> (Data, String) {
        let d = try Reports.gstOutwardDetail(db, month, fy)
        let co = try db.prepare("SELECT value FROM settings WHERE key='company_name'").get()
        func bill(_ rows: [Row]) -> Row {
            func s(_ k: String) -> Double { r2(rows.reduce(0.0) { $0 + $1.n(k) }) }
            return ["invoice_no": "Total", "taxable": s("taxable"), "cgst": s("cgst"), "sgst": s("sgst"), "igst": s("igst"), "round_off": s("round_off"), "total": s("total")]
        }
        func c(_ h: String, _ k: String, _ w: Double, _ t: String = "") -> XLSX.Col { XLSX.Col(h: h, k: k, w: w, t: t) }
        func cols(_ gst: Bool) -> [XLSX.Col] {
            [c("Invoice No", "invoice_no", 16), c("Date", "date", 12), c("Party Name", "party", 32)] + (gst ? [c("GSTIN", "gstin", 20)] : []) + [c("State", "state_code", 8),
             c("GST Rates", "rates", 12), c("Taxable Value", "taxable", 15, "num"), c("CGST", "cgst", 12, "num"), c("SGST", "sgst", 12, "num"), c("IGST (CGST+SGST)", "igst", 18, "num"),
             c("Round Off", "round_off", 10, "num"), c("Invoice Value", "total", 15, "num")]
        }
        let coName = co?.s("value")
        let name = (coName?.isEmpty == false) ? coName! : "Company"
        let month = d.str("month")
        let b2b = (d["b2b_bills"] as? [Row]) ?? [], b2c = (d["b2c_bills"] as? [Row]) ?? []
        let tot = (d["totals"] as? Row) ?? [:]
        let sheets: [XLSX.Sheet] = [
            XLSX.Sheet(name: "Summary", cols: [c("Particulars", "k", 34), c("Taxable Value", "taxable", 16, "num"), c("Tax", "tax", 16, "num")],
                       rows: [["k": "B2B (registered parties)", "taxable": d.obj("b2b").n("taxable"), "tax": d.obj("b2b").n("tax")],
                              ["k": "B2C (unregistered / cash)", "taxable": d.obj("b2c").n("taxable"), "tax": d.obj("b2c").n("tax")],
                              ["k": "Total outward supplies", "taxable": tot.n("taxable"), "tax": tot.n("tax")],
                              ["k": "Less: input tax credit (purchases less debit notes)", "taxable": NSNull(), "tax": d.obj("input_credit").n("total")],
                              ["k": "Net GST payable", "taxable": NSNull(), "tax": d.n("net_payable")]],
                       title: "GST Outward Supply - \(month) - \(name)"),
            XLSX.Sheet(name: "B2B Bills", cols: cols(true), rows: b2b, title: "B2B bills - \(month)", total: bill(b2b)),
            XLSX.Sheet(name: "B2C Bills", cols: cols(false), rows: b2c, title: "B2C bills - \(month)", total: bill(b2c)),
            XLSX.Sheet(name: "Rate-wise Summary", cols: [c("GST Rate %", "rate", 12, "num"), c("Invoices", "invoices", 10, "int"), c("Taxable Value", "taxable", 16, "num"), c("CGST", "cgst", 14, "num"),
                                                         c("SGST", "sgst", 14, "num"), c("IGST (CGST+SGST)", "igst", 18, "num"), c("Total Tax", "tax", 14, "num"), c("Total Value", "value", 16, "num")],
                       rows: (d["rows"] as? [Row]) ?? [], title: "Tax-rate-wise summary - \(month)", total: { var t: Row = ["rate": "Total"]; for (k, v) in tot { t[k] = v }; return t }()),
        ]
        return (XLSX.build(sheets), month)
    }

    /// Body: { pdf_base64, create_missing?, online? }. Suggested bill fields for review; the parser never saves anything.
    func parsePDF(_ db: Database, _ b: Row) async throws -> Row {
        guard let b64 = b.v("pdf_base64") as? String, !b64.isEmpty else { throw HttpError(400, "No PDF received") }
        let buf = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) ?? Data()
        if buf.count < 100 || String(data: buf.prefix(4), encoding: .ascii) != "%PDF" { throw HttpError(422, "That file is not a PDF") }
        guard let extract = pdfText else { throw HttpError(500, "PDF reading is not available on this device.") }
        let (pages, method) = try await extract(buf)
        let co = try Billing.settings(db)
        var result = PDFParser.parseInvoicePages(pages,
                                                 items: try db.prepare("SELECT id,name,hsn,gst_rate FROM items WHERE active=1").all(),
                                                 parties: try db.prepare("SELECT id,name,gstin FROM parties WHERE active=1 AND type='SUPPLIER'").all(),
                                                 companyGstin: co.str("company_gstin"), companyName: co.str("company_name"))
        if JS.truthy(b["create_missing"]) {
            result = try await AutoCreate.createMissing(db, result, online: !((b["online"] as? Bool) == false))
        }
        result["method"] = method
        result["raw_text"] = pages.joined(separator: "\n---- page ----\n").jsSlice(0, 8000)
        return result
    }

    /// The parse-pdf steps after text extraction, for tests: parse with this company's stock and suppliers, then create what is missing (offline).
    public func parseForTest(_ pages: [String], companyId: Int?) async throws -> Row {
        let db = try engine.database(for: companyId)
        let co = try Billing.settings(db)
        let parsed = PDFParser.parseInvoicePages(pages, items: try db.prepare("SELECT id,name,hsn,gst_rate FROM items WHERE active=1").all(),
                                                 parties: try db.prepare("SELECT id,name,gstin FROM parties WHERE active=1 AND type='SUPPLIER'").all(),
                                                 companyGstin: co.str("company_gstin"), companyName: co.str("company_name"))
        return try await AutoCreate.createMissing(db, parsed, online: false)
    }

    // MARK: companies.js

    static let COMPANY_FIELDS = ["company_gstin", "state_code", "company_address", "company_phone", "invoice_terms"]
    static let COMPANY_GSTIN = rx("^\\d{2}[A-Z]{5}\\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$")

    func profile(_ c: Row) throws -> Row {
        var o: Row = ["id": c["id"]!, "name": c["name"]!]
        guard let d = try engine.openCompany(c.i("id")) else { throw HttpError(500, "Company \(c.i("id")) not found") }
        for r in try d.prepare("SELECT key,value FROM settings").all() { o[r.str("key")] = r["value"] ?? NSNull() }
        o["fy"] = JS.truthy(c["fy"]) ? c["fy"]! : NSNull()
        return o
    }

    func validateCompany(_ b: Row, creating: Bool) throws {
        if creating && JS.blank(b["name"] ?? nil) == nil { throw HttpError(400, "Company name is required") }
        if JS.blank(b["company_gstin"] ?? nil) != nil && !Router.COMPANY_GSTIN.test(JS.string(b.v("company_gstin")).uppercased()) { throw HttpError(400, "GSTIN format is not valid") }
        if JS.blank(b["state_code"] ?? nil) != nil && !rx("^\\d{2}$").test(JS.string(b.v("state_code"))) { throw HttpError(400, "State code must be 2 digits, e.g. 09") }
    }

    func listCompanies() throws -> Any {
        let rows = try engine.registry.prepare("SELECT * FROM companies WHERE active=1 ORDER BY id").all()
        let last = try engine.registry.prepare("SELECT value FROM app_settings WHERE key='last_company'").get()
        return ["last_used": last != nil ? JS.number(last!["value"] ?? nil) as Any : NSNull(), "companies": try rows.map(profile)] as Row
    }

    func addCompany(_ b: Row) throws -> Reply {
        try validateCompany(b, creating: true)
        var s: [(String, String)] = []
        for f in Router.COMPANY_FIELDS where JS.blank(b[f] ?? nil) != nil {
            s.append((f, f == "company_gstin" ? JS.string(b.v(f)).uppercased() : JS.string(b.v(f))))
        }
        let id = try engine.createCompany(name: JS.trim(JS.string(b.v("name"))), settings: s)
        return .json(201, ["id": id] as Row)
    }

    func updateCompany(_ idS: String, _ b: Row) throws -> Any {
        guard let c = try engine.companyRow(Int(JS.number(idS))) else { throw HttpError(404, "Company not found") }
        try validateCompany(b, creating: false)
        guard let d = try engine.openCompany(c.i("id")) else { throw HttpError(404, "Company not found") }
        let up = d.prepare("INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value")
        if JS.blank(b["name"] ?? nil) != nil { try up.run("company_name", JS.trim(JS.string(b.v("name")))) }
        for f in Router.COMPANY_FIELDS where b.defined(f) {
            try up.run(f, f == "company_gstin" ? JS.string(b[f] ?? nil).uppercased() : JS.string(b[f] ?? nil))
        }
        // every year's books keep the same name
        if JS.blank(b["name"] ?? nil) != nil { try Years.renameAll(engine, c.str("name"), JS.trim(JS.string(b.v("name")))) }
        return ["ok": true] as Row
    }

    /// Deletes a company (one set of books): hidden (active=0), its file kept. Body { confirm: "<company name>" }.
    func deleteCompany(_ idS: String, _ b: Row) throws -> Any {
        guard let c = try engine.companyRow(Int(JS.number(idS))) else { throw HttpError(404, "Company not found") }
        let typed = JS.trim(JS.string(b["confirm"] ?? nil)).lowercased()
        if typed != JS.trim(c.str("name")).lowercased() { throw HttpError(400, "Type the company name \"\(c.str("name"))\" to confirm") }
        let others = try engine.registry.prepare("SELECT COUNT(*) AS n FROM companies WHERE active=1 AND id<>?").get(c.i("id"))?.i("n") ?? 0
        if others == 0 { throw HttpError(409, "This is the only company. Make another company first, then delete this one.") }
        try engine.registry.prepare("UPDATE companies SET active=0 WHERE id=?").run(c.i("id"))
        engine.closeCompany(c.i("id"))
        let last = try engine.registry.prepare("SELECT value FROM app_settings WHERE key='last_company'").get()
        var lastUsed: Int? = last.map { Int(JS.number($0["value"] ?? nil)) }
        if lastUsed == c.i("id") || lastUsed == nil || lastUsed == 0 {
            lastUsed = try engine.firstCompanyId()
            try engine.registry.prepare("INSERT INTO app_settings(key,value) VALUES('last_company',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value").run(String(lastUsed ?? 0))
        }
        return ["ok": true, "last_used": lastUsed.map { $0 as Any } ?? NSNull()] as Row
    }

    func activateCompany(_ idS: String) throws -> Any {
        if try engine.companyRow(Int(JS.number(idS))) == nil { throw HttpError(404, "Company not found") }
        try engine.registry.prepare("INSERT INTO app_settings(key,value) VALUES('last_company',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value").run(idS)
        return ["ok": true] as Row
    }
}

extension Dictionary where Key == String, Value == Any {
    /// A nested object, or empty.
    func obj(_ k: String) -> Row { (self[k] as? Row) ?? [:] }
}

/// A first-come, first-served turn for async work (Swift 5.7 compatible; no actor needed).
final class AsyncGate: @unchecked Sendable {
    private let lock = NSLock()
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func enter() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            lock.lock()
            if busy {
                waiting.append(c)
                lock.unlock()
            } else {
                busy = true
                lock.unlock()
                c.resume()
            }
        }
    }

    func leave() {
        lock.lock()
        if waiting.isEmpty {
            busy = false
            lock.unlock()
        } else {
            let next = waiting.removeFirst()
            lock.unlock()
            next.resume()
        }
    }
}
