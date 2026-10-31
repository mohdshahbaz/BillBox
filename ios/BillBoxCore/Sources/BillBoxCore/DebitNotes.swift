import Foundation

// backend/src/services/debitNotes.js

/// Debit note (purchase return): goods sent back to a supplier. The pieces go out of stock (from the batch chosen, or the
/// earliest-expiring batches), the supplier's ledger is debited by the note's total, and the GST on it is taken off the input
/// tax credit of its month. Numbered DN/<year>/00001.
enum DebitNotes {
    static let BOX_UNIT = rx("^(BOX|BOXES|BX|CASE|CS|CTN|CARTON)$", "i")

    /// `text(v, max)`: trimmed, single-spaced, at most `max` characters; nil when empty.
    static func text(_ v: Any?, _ max: Int = 200) -> String? {
        let raw = unwrap(v).map { JS.string($0) } ?? ""
        let s = rx("\\s+", "g").replace(JS.trim(raw), " ").jsSlice(0, max)
        return s.isEmpty ? nil : s
    }

    struct Built {
        var party: Row
        var date: String
        var intra: Bool
        var rows: [Row]
        var subtotal, discount, taxable, cgst, sgst, igst, roundOff, total: Double
    }

    /// Pure calculation, no writes.
    static func build(_ db: Database, _ input: Row) throws -> Built {
        if !JS.truthy(input["party_id"]) { throw HttpError(400, "Select the supplier") }
        guard let party = try db.prepare("SELECT * FROM parties WHERE id=?").get(input.v("party_id")) else { throw HttpError(404, "Party not found") }
        guard let lines = input["lines"] as? [Any], !lines.isEmpty else { throw HttpError(400, "Add at least one item") }
        let co = try Billing.settings(db)
        let intra = !JS.truthy(party["state_code"]) || party.s("state_code") == co.s("state_code")
        let date = JS.truthy(input["date"]) ? JS.string(input.v("date")) : today()
        if (JS.truthy(input["date"]) && !(input.v("date") is String)) || !isDateRe.test(date) { throw HttpError(400, "Date must be YYYY-MM-DD") }

        var rows: [Row] = []
        for (i, lnAny) in lines.enumerated() {
            let ln = (lnAny as? Row) ?? [:]
            let n = i + 1
            var item: Row?
            if JS.truthy(ln["item_id"]) { item = try db.prepare("SELECT * FROM items WHERE id=?").get(ln.v("item_id")) }
            guard let item else { throw HttpError(400, "Row \(n): choose the stock item") }
            let name = item.str("name")
            let q = try Purchases.num(ln["qty"] ?? nil, "Row \(n) (\(name)) quantity")
            if !(q > 0) || !JS.isInteger(q) { throw HttpError(400, "Row \(n) (\(name)): quantity must be a whole number of at least 1") }
            let unitText = JS.trim(JS.truthy(ln["unit"]) ? JS.string(ln.v("unit")) : "")
            let unit = BOX_UNIT.test(unitText) ? "BOX" : "PCS"
            let ppbRaw = item.n("pcs_per_box")
            let ppb = max(1, (ppbRaw.isNaN || ppbRaw == 0) ? 1 : ppbRaw)
            let pcs = unit == "BOX" ? q * ppb : q
            let rate = try Purchases.num(ln["rate"] ?? nil, "Row \(n) (\(name)) rate")
            let amount = Purchases.blankNum(ln["amount"] ?? nil) ? r2(q * rate) : r2(try Purchases.num(ln["amount"] ?? nil, "Row \(n) (\(name)) amount"))
            let gst = Purchases.blankNum(ln["gst_rate"] ?? nil) ? item.n("gst_rate") : try Purchases.num(ln["gst_rate"] ?? nil, "Row \(n) (\(name)) GST rate")
            if gst > 40 { throw HttpError(400, "Row \(n) (\(name)): GST rate must be between 0 and 40") }
            let batchId: Any = JS.truthy(ln["batch_id"]) ? JS.number(ln.v("batch_id")) : NSNull()
            rows.append([
                "sno": n, "item_id": item["id"]!, "item_name": item["name"]!, "hsn": JS.truthy(item["hsn"]) ? item.v("hsn")! : NSNull(),
                "pcs_per_box": ppb, "mrp": item["mrp"] ?? NSNull(), "qty": q, "unit": unit, "pcs_qty": pcs, "rate": rate, "amount": amount,
                "gst_rate": gst, "batch_id": batchId,
            ])
        }

        let subtotal = r2(rows.reduce(0.0) { $0 + $1.n("amount") })
        let discount = r2(try Purchases.num(input["discount"] ?? nil, "Discount"))
        if discount > subtotal + 0.005 { throw HttpError(400, "Discount cannot be more than the items total") }
        let taxable = r2(subtotal - discount)
        let share = subtotal > 0 ? taxable / subtotal : 0
        for k in rows.indices {
            let lt = r2(rows[k].n("amount") * share)
            let tax = r2((lt * rows[k].n("gst_rate")) / 100)
            rows[k]["taxable"] = lt
            if intra {
                let c = r2(tax / 2)
                rows[k]["cgst"] = c; rows[k]["sgst"] = r2(tax - c); rows[k]["igst"] = 0.0
            } else {
                rows[k]["cgst"] = 0.0; rows[k]["sgst"] = 0.0; rows[k]["igst"] = tax
            }
        }
        func sum(_ k: String) -> Double { r2(rows.reduce(0.0) { $0 + $1.n(k) }) }
        let cgst = sum("cgst"), sgst = sum("sgst"), igst = sum("igst")
        let grand = r2(taxable + cgst + sgst + igst)
        let roundOff = r2(JS.round(grand) - grand)
        let total = r2(grand + roundOff)
        return Built(party: party, date: date, intra: intra, rows: rows, subtotal: subtotal, discount: discount, taxable: taxable,
                     cgst: cgst, sgst: sgst, igst: igst, roundOff: roundOff, total: total)
    }

    static func preview(_ db: Database, _ input: Row) throws -> Row {
        let p = try build(db, input)
        return ["date": p.date, "intra": p.intra, "subtotal": p.subtotal, "discount": p.discount, "taxable": p.taxable, "cgst": p.cgst,
                "sgst": p.sgst, "igst": p.igst, "round_off": p.roundOff, "total": p.total, "supply": p.intra ? "INTRA" : "INTER", "lines": p.rows]
    }

    /// Which batches the pieces of one row come out of: the chosen batch, or the earliest-expiring batches that have stock.
    static func allocate(_ db: Database, _ r: Row) throws -> [(batch: Int, qty: Double)] {
        let pcs = r.n("pcs_qty")
        if JS.truthy(r["batch_id"]) {
            guard let b = try db.prepare("SELECT id, batch_no, qty FROM batches WHERE id=? AND item_id=?").get(r.v("batch_id"), r.v("item_id")) else {
                throw HttpError(400, "Row \(r.i("sno")) (\(r.str("item_name"))): that batch is not one of this item's batches")
            }
            if b.n("qty") < pcs {
                throw HttpError(409, "Row \(r.i("sno")) (\(r.str("item_name"))): batch \(b.str("batch_no")) has only \(JS.numberString(b.n("qty"))) piece(s) in stock", "NO_STOCK")
            }
            return [(b.i("id"), pcs)]
        }
        var out: [(batch: Int, qty: Double)] = []
        var left = pcs
        for b in try db.prepare("SELECT id, qty FROM batches WHERE item_id=? AND qty>0 ORDER BY exp_date, id").all(r.v("item_id")) {
            if left <= 0 { break }
            let take = min(b.n("qty"), left)
            out.append((b.i("id"), take))
            left -= take
        }
        if left > 0 {
            throw HttpError(409, "\(r.str("item_name")): only \(JS.numberString(pcs - left)) piece(s) in stock, \(JS.numberString(pcs)) to return", "NO_STOCK")
        }
        return out
    }

    /// Shared by create and edit.
    static func write(_ db: Database, _ input: Row, _ existing: (id: Int, noteNo: String)?) throws -> Int {
        let p = try build(db, input)
        var purchase: Row?
        if JS.truthy(input["purchase_id"]) {
            purchase = try db.prepare("SELECT id, purchase_no, supplier_invoice_no FROM purchases WHERE id=?").get(input.v("purchase_id"))
            if purchase == nil { throw HttpError(404, "Purchase bill not found") }
        }
        let against = text(input["against_bill"] ?? nil, 60)
            ?? purchase.map { JS.truthy($0["supplier_invoice_no"]) ? $0.str("supplier_invoice_no") : $0.str("purchase_no") }
        let reason = text(input["reason"] ?? nil)
        let vals: [Any?] = [p.date, p.party.v("id"), purchase?.v("id"), against, reason, p.subtotal, p.discount, p.taxable,
                            p.cgst, p.sgst, p.igst, p.roundOff, p.total, text(input["notes"] ?? nil, 500)]
        let id: Int, noteNo: String
        if let existing {
            id = existing.id; noteNo = existing.noteNo
            try db.prepare("UPDATE debit_notes SET date=?,party_id=?,purchase_id=?,against_bill=?,reason=?,subtotal=?,discount=?,taxable=?,cgst=?,sgst=?,igst=?,round_off=?,total=?,notes=? WHERE id=?")
                .run(vals[0], vals[1], vals[2], vals[3], vals[4], vals[5], vals[6], vals[7], vals[8], vals[9], vals[10], vals[11], vals[12], vals[13], id)
        } else {
            noteNo = try nextNo(db, "DN", p.date)
            id = try db.prepare("""
            INSERT INTO debit_notes(date,party_id,purchase_id,against_bill,reason,subtotal,discount,taxable,cgst,sgst,igst,round_off,total,notes,note_no)
                   VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """).run(vals[0], vals[1], vals[2], vals[3], vals[4], vals[5], vals[6], vals[7], vals[8], vals[9], vals[10], vals[11], vals[12], vals[13], noteNo).lastInsertRowid
        }
        let insLine = db.prepare("INSERT INTO debit_note_lines(note_id,item_id,batch_id,qty,unit,pcs_qty,rate,amount,taxable,gst_rate,cgst,sgst,igst) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)")
        let insStock = db.prepare("INSERT INTO debit_note_stock(line_id,batch_id,qty) VALUES(?,?,?)")
        for r in p.rows {
            let parts = try allocate(db, r)
            let lineId = try insLine.run(id, r.v("item_id"), parts.count == 1 ? parts[0].batch : nil, r.n("qty"), r.v("unit"), r.n("pcs_qty"), r.n("rate"),
                                         r.n("amount"), r.n("taxable"), r.n("gst_rate"), r.n("cgst"), r.n("sgst"), r.n("igst")).lastInsertRowid
            for s in parts {
                try db.prepare("UPDATE batches SET qty = qty - ? WHERE id = ?").run(s.qty, s.batch)
                try insStock.run(lineId, s.batch, s.qty)
            }
        }
        let why = [against.map { "against \($0)" } ?? "", reason.map { "(\($0))" } ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
        try db.prepare("INSERT INTO ledger(party_id,date,type,ref_no,debit,credit,narration) VALUES(?,?,?,?,?,?,?)")
            .run(p.party.v("id"), p.date, "DEBIT_NOTE", noteNo, p.total, 0, "Debit note \(noteNo)\(why.isEmpty ? "" : " " + why)")
        return id
    }

    /// Puts the returned pieces back into their batches and removes the note's lines and ledger entry.
    static func reverse(_ db: Database, _ old: Row) throws {
        for s in try db.prepare("SELECT s.batch_id, s.qty FROM debit_note_stock s JOIN debit_note_lines l ON l.id=s.line_id WHERE l.note_id=?").all(old.v("id")) {
            try db.prepare("UPDATE batches SET qty = qty + ? WHERE id = ?").run(s.n("qty"), s.v("batch_id"))
        }
        try db.prepare("DELETE FROM debit_note_stock WHERE line_id IN (SELECT id FROM debit_note_lines WHERE note_id=?)").run(old.v("id"))
        try db.prepare("DELETE FROM debit_note_lines WHERE note_id=?").run(old.v("id"))
        try db.prepare("DELETE FROM ledger WHERE type='DEBIT_NOTE' AND ref_no=?").run(old.v("note_no"))
    }

    static func create(_ db: Database, _ input: Row) throws -> Int {
        try db.transaction { try write(db, input, nil) }
    }

    static func update(_ db: Database, _ id: Int, _ input: Row) throws -> Int {
        try db.transaction {
            guard let old = try db.prepare("SELECT * FROM debit_notes WHERE id=?").get(id) else { throw HttpError(404, "Debit note not found") }
            try reverse(db, old)
            return try write(db, input, (id, old.str("note_no")))
        }
    }

    static func delete(_ db: Database, _ id: Int) throws -> Row {
        try db.transaction {
            guard let old = try db.prepare("SELECT * FROM debit_notes WHERE id=?").get(id) else { throw HttpError(404, "Debit note not found") }
            try reverse(db, old)
            try db.prepare("DELETE FROM debit_notes WHERE id=?").run(id)
            return ["id": id, "note_no": old["note_no"]!, "total": old["total"]!]
        }
    }

    /// The note with its lines, and the same fields a printed bill uses (so it prints on the bill layouts as a DEBIT NOTE).
    static func get(_ db: Database, _ id: Any?) throws -> Row? {
        guard var d = try db.prepare("""
        SELECT d.*, p.name party_name, p.gstin party_gstin, p.address party_address, p.state_code party_state, p.phone party_phone, p.mobiles party_mobiles,
                    p.tel party_tel, p.email party_email, p.pan party_pan, p.fssai party_fssai, u.purchase_no
             FROM debit_notes d JOIN parties p ON p.id=d.party_id LEFT JOIN purchases u ON u.id=d.purchase_id WHERE d.id=?
        """).get(id) else { return nil }
        var lines = try db.prepare("""
        SELECT l.*, it.name item_name, COALESCE(it.hsn,'') hsn, it.pcs_per_box, it.mrp,
                    (SELECT GROUP_CONCAT(b.batch_no, ', ') FROM debit_note_stock s JOIN batches b ON b.id=s.batch_id WHERE s.line_id=l.id) batch_no
             FROM debit_note_lines l JOIN items it ON it.id=l.item_id WHERE l.note_id=? ORDER BY l.id
        """).all(id)
        for i in lines.indices {
            lines[i]["sno"] = i + 1
            if !JS.truthy(lines[i]["batch_no"]) { lines[i]["batch_no"] = "" }
        }
        d["lines"] = lines
        d["supply"] = d.n("igst") > 0 ? "INTER" : "INTRA"
        d["amount_words"] = Words.rupees(d.n("total"))
        var rates: [Double] = []
        var g: [Double: Row] = [:]
        for l in lines {
            let rate = l.n("gst_rate")
            var x = g[rate] ?? ["rate": l["gst_rate"]!, "rows": 0, "taxable": 0.0, "cgst": 0.0, "sgst": 0.0, "igst": 0.0]
            if g[rate] == nil { rates.append(rate) }
            x["rows"] = x.i("rows") + 1
            x["taxable"] = r2(x.n("taxable") + l.n("taxable"))
            x["cgst"] = r2(x.n("cgst") + l.n("cgst"))
            x["sgst"] = r2(x.n("sgst") + l.n("sgst"))
            x["igst"] = r2(x.n("igst") + l.n("igst"))
            g[rate] = x
        }
        d["gst_summary"] = stableSorted(rates.map { g[$0]! }) { $0.n("rate") < $1.n("rate") }
        // for the print layouts: the number, the heading and one line per row in pieces, like a sale bill
        d["invoice_no"] = d["note_no"]!
        d["doc_title"] = "DEBIT NOTE"
        d["doc_no_label"] = "Debit note no"
        d["doc_line"] = [JS.truthy(d["against_bill"]) ? "Against bill \(d.str("against_bill"))" : "", JS.truthy(d["reason"]) ? d.str("reason") : ""]
            .filter { !$0.isEmpty }.joined(separator: "  ·  ")
        d["print_lines"] = lines.map { l -> Row in
            ["item_name": l["item_name"]!, "hsn": l["hsn"]!, "qty": l["pcs_qty"]!, "free_qty": 0, "pcs_per_box": l["pcs_per_box"]!, "mrp": l["mrp"]!,
             "rate": l.n("pcs_qty") > 0 ? r2(l.n("amount") / l.n("pcs_qty")) : 0, "disc_pct": 0, "taxable": l["taxable"]!, "gst_rate": l["gst_rate"]!,
             "amount": r2(l.n("taxable") + l.n("cgst") + l.n("sgst") + l.n("igst"))]
        }
        return d
    }

    /// Debit notes of the selected year (optionally a date range, a supplier, or a search), newest first, with totals.
    static func list(_ db: Database, fy fyLabel: Any?, from: String?, to: String?, q: String?, partyId: String?) throws -> Row {
        let fy = try FY.range(fyLabel)
        let f = (from.map { !$0.isEmpty && $0 > fy.from } ?? false) ? from! : fy.from
        let t = (to.map { !$0.isEmpty && $0 < fy.to } ?? false) ? to! : fy.to
        let pid: Any = (partyId?.isEmpty == false) ? JS.number(partyId!) : NSNull()
        let rows = try db.prepare("""
        SELECT d.id, d.note_no, d.date, COALESCE(d.against_bill,'') against_bill, COALESCE(d.reason,'') reason, d.party_id, p.name party, COALESCE(p.gstin,'') gstin,
                    d.taxable, d.cgst, d.sgst, d.igst, d.round_off, d.total
             FROM debit_notes d JOIN parties p ON p.id=d.party_id
             WHERE d.date BETWEEN @f AND @t AND (@pid IS NULL OR d.party_id=@pid)
               AND (d.note_no LIKE @q OR p.name LIKE @q OR COALESCE(d.against_bill,'') LIKE @q)
             ORDER BY d.date DESC, d.id DESC
        """).all(["f": f, "t": t, "q": "%\(JS.trim(q ?? ""))%", "pid": pid] as [String: Any])
        func sum(_ k: String) -> Double { r2(rows.reduce(0.0) { $0 + $1.n(k) }) }
        return ["from": f, "to": t, "rows": rows,
                "totals": ["count": rows.count, "taxable": sum("taxable"), "cgst": sum("cgst"), "sgst": sum("sgst"), "igst": sum("igst"), "total": sum("total")] as Row]
    }
}
