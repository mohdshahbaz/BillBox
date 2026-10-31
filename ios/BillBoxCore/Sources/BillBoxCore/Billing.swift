import Foundation

// backend/src/services/billing.js

/// `v !== undefined && v !== null && v !== ''`
func present(_ v: Any?) -> Bool {
    guard let u = unwrap(v) else { return false }
    if let s = u as? String, s.isEmpty { return false }
    return true
}

enum Billing {
    static func settings(_ db: Database) throws -> Row {
        var o: Row = [:]
        for r in try db.prepare("SELECT key,value FROM settings").all() { o[r.str("key")] = r["value"] ?? NSNull() }
        return o
    }

    static func partyBalance(_ db: Database, _ id: Any?) throws -> Double {
        try db.prepare("SELECT COALESCE(SUM(debit)-SUM(credit),0) b FROM ledger WHERE party_id=?").get(id)!.n("b")
    }

    /// Selling rates are ex-GST. MRP is GST-inclusive, so back the tax out for the MRP tier (not rounded: a whole box must add up exactly).
    static func priceFor(_ item: Row, _ tier: String) -> Double {
        // no wholesale price set for this item (0): bill it at the retail price rather than at nothing
        if tier == "WHOLESALE" { return item.n("wholesale_price") > 0 ? item.n("wholesale_price") : item.n("retail_price") }
        if tier == "MRP" { return item.n("mrp") / (1 + item.n("gst_rate") / 100) }
        return item.n("retail_price")
    }

    struct Built {
        var date: String
        var party: Row?
        var tier: String
        var intra: Bool
        var rows: [Row]
        var display: [Row]
        var subtotal, discount, taxable, cgst, sgst, igst, roundOff, total: Double
    }

    /// Pure calculation (no writes): price tier -> schemes -> FEFO batch allocation -> GST. Used by preview and save alike.
    static func build(_ db: Database, _ input: Row) throws -> Built {
        guard let lines = input["lines"] as? [Any], !lines.isEmpty else { throw HttpError(400, "Add at least one item to the bill") }
        let co = try settings(db)
        var party: Row?
        if JS.truthy(input["party_id"]) {
            party = try db.prepare("SELECT * FROM parties WHERE id=?").get(input.v("party_id"))
            if party == nil { throw HttpError(404, "Party not found") }
        }
        let tier = party?.str("price_tier") ?? "RETAIL"
        let intra = party == nil || !JS.truthy(party!["state_code"]) || party!.s("state_code") == co.s("state_code")
        let date = JS.truthy(input["date"]) ? JS.string(input.v("date")) : today()
        if !isDateRe.test(date) { throw HttpError(400, "Bill date must be YYYY-MM-DD") }

        var reserved: [Int: Double] = [:]   // batch_id -> qty already taken by earlier lines of this bill
        var rows: [Row] = []
        var display: [Row] = []

        for (idx, lnAny) in lines.enumerated() {
            let ln = (lnAny as? Row) ?? [:]
            guard let item = try db.prepare("SELECT * FROM items WHERE id=? AND active=1").get(ln.v("item_id")) else {
                throw HttpError(404, "Item \(JS.string(ln["item_id"])) not found")
            }
            // Dual unit: the operator may enter Boxes and loose Pieces. Everything below works in pieces.
            let ppbRaw = JS.parseInt(item["pcs_per_box"] ?? nil)
            let ppb = max(1, (ppbRaw.isNaN || ppbRaw == 0) ? 1 : ppbRaw)
            let hasUnits = ln.defined("boxes") || ln.defined("pcs")
            let qty: Double
            if hasUnits {
                let b = JS.parseInt(ln["boxes"] ?? nil), p = JS.parseInt(ln["pcs"] ?? nil)
                qty = max(0, (b.isNaN || b == 0) ? 0 : b) * ppb + max(0, (p.isNaN || p == 0) ? 0 : p)
            } else {
                qty = JS.parseInt(ln["qty"] ?? nil)
            }
            if !(qty > 0) { throw HttpError(400, "Enter a quantity for \(item.str("name"))") }

            let rate = present(ln["rate"]) ? JS.number(ln.v("rate")) : priceFor(item, tier)
            let md = JS.number(ln["disc_pct"] ?? nil)
            let manualPct = min(100, max(0, (md.isNaN || md == 0) ? 0 : md))

            let schemes = try db.prepare("""
            SELECT * FROM schemes WHERE item_id=? AND active=1
                   AND (valid_from IS NULL OR valid_from<=?) AND (valid_to IS NULL OR valid_to>=?)
            """).all(item.v("id"), date, date)
            let sc = applySchemes(qty, schemes)
            let pct = min(100, manualPct + sc.discPct)

            // FEFO: first-expiry-first-out, skipping expired batches
            let need = qty + sc.freeQty
            let batches = try db.prepare("SELECT * FROM batches WHERE item_id=? AND qty>0 AND exp_date>=? ORDER BY exp_date, id").all(item.v("id"), date)
            var remaining = need
            var paidLeft = qty
            let gst = item.n("gst_rate")
            for b in batches {
                if remaining <= 0 { break }
                let bid = b.i("id")
                let avail = b.n("qty") - (reserved[bid] ?? 0)
                if avail <= 0 { continue }
                let take = min(avail, remaining)
                reserved[bid] = (reserved[bid] ?? 0) + take
                remaining -= take

                let paid = min(take, paidLeft)
                let free = take - paid
                paidLeft -= paid

                let gross = r2(rate * paid)
                let discAmt = r2((gross * pct) / 100)
                let taxable = r2(gross - discAmt)
                let tax = splitTax(taxable, gst, intra)
                rows.append([
                    "line_index": idx, "item_id": item["id"]!, "item_name": item["name"]!, "hsn": item["hsn"] ?? NSNull(),
                    "batch_id": b["id"]!, "batch_no": b["batch_no"]!, "exp_date": b["exp_date"]!,
                    "qty": paid, "free_qty": free, "rate": rate, "disc_pct": pct, "manual_pct": manualPct, "disc_amt": discAmt, "gross": gross, "taxable": taxable,
                    "gst_rate": gst, "cgst": tax.cgst, "sgst": tax.sgst, "igst": tax.igst, "amount": r2(taxable + tax.cgst + tax.sgst + tax.igst),
                ])
            }
            if remaining > 0 { throw HttpError(409, "Not enough stock for \(item.str("name")): short by \(JS.numberString(remaining))", "NO_STOCK") }

            let mine = rows.filter { $0.i("line_index") == idx }
            func s(_ k: String) -> Double { r2(mine.reduce(0.0) { $0 + $1.n(k) }) }
            display.append([
                "line_index": idx, "item_id": item["id"]!, "item_name": item["name"]!, "unit": item["unit"] ?? NSNull(), "qty": qty,
                "pcs_per_box": ppb, "boxes": Foundation.floor(qty / ppb), "pcs": qty.truncatingRemainder(dividingBy: ppb),
                "free_qty": sc.freeQty, "rate": rate, "disc_pct": pct, "manual_pct": manualPct, "schemes": sc.applied, "gst_rate": gst,
                "disc_amt": s("disc_amt"), "taxable": s("taxable"),
                "tax": r2(s("cgst") + s("sgst") + s("igst")), "amount": s("amount"),
                "batches": mine.map { "\($0.str("batch_no")) ×\(JS.numberString($0.n("qty") + $0.n("free_qty")))" }.joined(separator: ", "),
            ])
        }

        func sum(_ k: String) -> Double { r2(rows.reduce(0.0) { $0 + $1.n(k) }) }
        let taxable = sum("taxable")
        let cgst = sum("cgst"), sgst = sum("sgst"), igst = sum("igst")
        let grand = r2(taxable + cgst + sgst + igst)
        // Settings › Billing & Dashboard › round the total to the rupee (on unless switched off)
        let total = co.str("bill_round") == "0" ? grand : JS.round(grand)
        return Built(date: date, party: party, tier: tier, intra: intra, rows: rows, display: display,
                     subtotal: sum("gross"), discount: sum("disc_amt"), taxable: taxable, cgst: cgst, sgst: sgst, igst: igst,
                     roundOff: r2(total - grand), total: total)
    }

    /// `POST /invoices/preview`
    static func preview(_ db: Database, _ input: Row) throws -> Row {
        let inv = try build(db, input)
        return ["lines": inv.display, "subtotal": inv.subtotal, "discount": inv.discount, "taxable": inv.taxable,
                "cgst": inv.cgst, "sgst": inv.sgst, "igst": inv.igst, "round_off": inv.roundOff, "total": inv.total,
                "supply": inv.intra ? "INTRA" : "INTER", "tier": inv.tier]
    }

    struct Existing { let id: Int; let invoiceNo: String; let receiptNo: String? }

    /// Shared by create and edit. `existing` when an edited bill is being rewritten in place.
    static func write(_ db: Database, _ input: Row, _ existing: Existing?) throws -> Int {
        let inv = try build(db, input)
        let party = inv.party
        let mode = (JS.truthy(input["pay_mode"]) ? JS.string(input.v("pay_mode")) : "CASH").uppercased()

        var paid = present(input["paid_amount"]) ? JS.number(input.v("paid_amount")) : (mode == "CREDIT" ? 0 : inv.total)
        if !paid.isFinite { throw HttpError(400, "Paid amount is not a number") }
        paid = r2(min(max(paid, 0), inv.total))

        if party == nil && paid < inv.total { throw HttpError(400, "Walk-in sales must be paid in full") }
        if let party, party.n("credit_limit") > 0 && !JS.truthy(input["override_credit"]) {
            let after = r2(try partyBalance(db, party.v("id")) + inv.total - paid)
            if after > party.n("credit_limit") {
                throw HttpError(409, "Credit limit exceeded: dues would be ₹\(JS.numberString(after)) against a limit of ₹\(JS.string(party["credit_limit"] ?? nil))", "CREDIT_LIMIT")
            }
        }

        let salesman: Any? = JS.truthy(input["salesman_id"]) ? input.v("salesman_id") : nil
        let saleType = (JS.truthy(input["sale_type"]) ? JS.string(input.v("sale_type")) : "COUNTER").uppercased()
        let vals: [Any?] = [inv.date, party?.v("id"), salesman, saleType, mode,
                            inv.subtotal, inv.discount, inv.taxable, inv.cgst, inv.sgst, inv.igst, inv.roundOff, inv.total, paid]
        var id: Int
        var invoiceNo: String
        if let existing {
            id = existing.id
            invoiceNo = existing.invoiceNo
            try db.prepare("UPDATE invoices SET date=?,party_id=?,salesman_id=?,sale_type=?,pay_mode=?,subtotal=?,discount=?,taxable=?,cgst=?,sgst=?,igst=?,round_off=?,total=?,paid=?,printed=0 WHERE id=?")
                .run(vals[0], vals[1], vals[2], vals[3], vals[4], vals[5], vals[6], vals[7], vals[8], vals[9], vals[10], vals[11], vals[12], vals[13], id)
        } else {
            invoiceNo = try nextNo(db, "INV", inv.date)
            id = try db.prepare("""
            INSERT INTO invoices(date,party_id,salesman_id,sale_type,pay_mode,subtotal,discount,taxable,cgst,sgst,igst,round_off,total,paid,invoice_no)
                   VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """).run(vals[0], vals[1], vals[2], vals[3], vals[4], vals[5], vals[6], vals[7], vals[8], vals[9], vals[10], vals[11], vals[12], vals[13], invoiceNo).lastInsertRowid
        }

        let insLine = db.prepare("""
        INSERT INTO invoice_lines(invoice_id,item_id,batch_id,qty,free_qty,rate,disc_pct,disc_amt,taxable,gst_rate,cgst,sgst,igst,amount,manual_disc)
             VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        """)
        let dec = db.prepare("UPDATE batches SET qty = qty - ? WHERE id = ? AND qty >= ?")
        for r in inv.rows {
            try insLine.run(id, r.v("item_id"), r.v("batch_id"), r.n("qty"), r.n("free_qty"), r.n("rate"), r.n("disc_pct"), r.n("disc_amt"), r.n("taxable"),
                            r.n("gst_rate"), r.n("cgst"), r.n("sgst"), r.n("igst"), r.n("amount"), r.n("manual_pct"))
            let units = r.n("qty") + r.n("free_qty")
            if try dec.run(units, r.v("batch_id"), units).changes != 1 { throw HttpError(409, "Stock changed for \(r.str("item_name")), please retry", "NO_STOCK") }
        }

        if let party {
            let lg = db.prepare("INSERT INTO ledger(party_id,date,type,ref_no,debit,credit,narration) VALUES(?,?,?,?,?,?,?)")
            try lg.run(party.v("id"), inv.date, "INVOICE", invoiceNo, inv.total, 0, "Sale \(invoiceNo)")
            if paid > 0 {
                let receiptNo = try existing?.receiptNo ?? nextNo(db, "RCT", inv.date)
                try db.prepare("INSERT INTO receipts(receipt_no,date,party_id,salesman_id,invoice_id,mode,amount,reference) VALUES(?,?,?,?,?,?,?,?)")
                    .run(receiptNo, inv.date, party.v("id"), salesman, id, mode, paid, "Paid at billing \(invoiceNo)")
                try lg.run(party.v("id"), inv.date, "RECEIPT", receiptNo, 0, paid, "Received at billing (\(mode))")
            }
        }
        return id
    }

    static func create(_ db: Database, _ input: Row) throws -> Int {
        try db.transaction { try write(db, input, nil) }
    }

    /// Edit a saved sale: put the old stock back, remove its lines and its ledger/receipt postings, then write the new version
    /// under the same id and invoice number. All in one transaction. Payments recorded later through vouchers are left alone.
    static func update(_ db: Database, _ id: Int, _ input: Row) throws -> Int {
        try db.transaction {
            guard let old = try db.prepare("SELECT * FROM invoices WHERE id=?").get(id) else { throw HttpError(404, "Invoice not found") }
            for l in try db.prepare("SELECT batch_id, qty, free_qty FROM invoice_lines WHERE invoice_id=?").all(id) {
                try db.prepare("UPDATE batches SET qty = qty + ? WHERE id = ?").run(l.n("qty") + l.n("free_qty"), l.v("batch_id"))
            }
            try db.prepare("DELETE FROM invoice_lines WHERE invoice_id=?").run(id)
            let rc = try db.prepare("SELECT receipt_no FROM receipts WHERE invoice_id=? ORDER BY id").all(id)
            for r in rc { try db.prepare("DELETE FROM ledger WHERE type='RECEIPT' AND ref_no=?").run(r.v("receipt_no")) }
            try db.prepare("DELETE FROM receipts WHERE invoice_id=?").run(id)
            try db.prepare("DELETE FROM ledger WHERE type='INVOICE' AND ref_no=?").run(old.v("invoice_no"))
            var inp = input
            if !JS.truthy(input["date"]) { inp["date"] = old["date"] }
            return try write(db, inp, Existing(id: id, invoiceNo: old.str("invoice_no"), receiptNo: rc.first?.s("receipt_no")))
        }
    }

    /// Delete a saved sale: the stock goes back on the shelf and its ledger entries, receipts and lines are removed. All or nothing.
    static func delete(_ db: Database, _ id: Int) throws -> Row {
        try db.transaction {
            guard let old = try db.prepare("SELECT * FROM invoices WHERE id=?").get(id) else { throw HttpError(404, "Invoice not found") }
            for l in try db.prepare("SELECT batch_id, qty, free_qty FROM invoice_lines WHERE invoice_id=?").all(id) {
                try db.prepare("UPDATE batches SET qty = qty + ? WHERE id = ?").run(l.n("qty") + l.n("free_qty"), l.v("batch_id"))
            }
            try db.prepare("DELETE FROM invoice_lines WHERE invoice_id=?").run(id)
            for r in try db.prepare("SELECT receipt_no FROM receipts WHERE invoice_id=?").all(id) {
                try db.prepare("DELETE FROM ledger WHERE type='RECEIPT' AND ref_no=?").run(r.v("receipt_no"))
            }
            try db.prepare("DELETE FROM receipts WHERE invoice_id=?").run(id)
            try db.prepare("DELETE FROM ledger WHERE type='INVOICE' AND ref_no=?").run(old.v("invoice_no"))
            try db.prepare("DELETE FROM invoices WHERE id=?").run(id)
            return ["id": id, "invoice_no": old["invoice_no"]!, "total": old["total"]!]
        }
    }

    static func get(_ db: Database, _ id: Any?) throws -> Row? {
        guard var inv = try db.prepare("""
        SELECT i.*, p.name party_name, p.gstin party_gstin, p.address party_address, p.state_code party_state, p.phone party_phone, p.mobiles party_mobiles, p.tel party_tel, p.email party_email, p.pan party_pan, p.fssai party_fssai, p.credit_days party_credit_days, s.name salesman_name
             FROM invoices i LEFT JOIN parties p ON p.id=i.party_id LEFT JOIN salesmen s ON s.id=i.salesman_id WHERE i.id=?
        """).get(id) else { return nil }
        let lines = try db.prepare("""
        SELECT l.*, it.name item_name, it.hsn, it.unit, it.pcs_per_box, b.batch_no, b.exp_date, b.mfg_date, it.mrp
             FROM invoice_lines l JOIN items it ON it.id=l.item_id JOIN batches b ON b.id=l.batch_id WHERE l.invoice_id=? ORDER BY l.id
        """).all(id)
        inv["lines"] = lines
        // One row per item (a bill line can be split over several batches): what the billing screen needs to reopen the bill
        var order: [Int] = []
        var grouped: [Int: Row] = [:]
        for l in lines {
            let k = l.i("item_id")
            var g = grouped[k] ?? ["item_id": l["item_id"]!, "item_name": l["item_name"]!, "pcs_per_box": l["pcs_per_box"]!, "qty": 0.0,
                                   "manual_disc": JS.truthy(l["manual_disc"]) ? l["manual_disc"]! : 0, "rate": l["rate"]!]
            if grouped[k] == nil { order.append(k) }
            g["qty"] = g.n("qty") + l.n("qty")
            grouped[k] = g
        }
        inv["edit_lines"] = order.map { grouped[$0]! }
        inv["supply"] = inv.n("igst") > 0 ? "INTER" : "INTRA"
        inv["amount_words"] = Words.rupees(inv.n("total"))
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
        inv["gst_summary"] = stableSorted(rates.map { g[$0]! }) { $0.n("rate") < $1.n("rate") }
        // for the printed bill (Settings › Printing › outstanding): the party's balance before this bill and after it
        if JS.truthy(inv["party_id"] ?? nil) {
            let prev = try db.prepare("""
            SELECT COALESCE(SUM(debit)-SUM(credit),0) b FROM ledger WHERE party_id=? AND (date < ? OR (date = ? AND id <
                  COALESCE((SELECT MIN(id) FROM ledger WHERE type='INVOICE' AND ref_no=?), 1000000000000)))
            """).get(inv["party_id"] ?? nil, inv["date"] ?? nil, inv["date"] ?? nil, inv["invoice_no"] ?? nil)!.n("b")
            inv["party_prev_balance"] = r2(prev)
            inv["party_balance_after"] = r2(prev + inv.n("total") - inv.n("paid"))
        }
        return inv
    }
}
