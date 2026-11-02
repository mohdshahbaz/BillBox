import Foundation

// backend/src/services/purchases.js and vouchers.js

enum Purchases {
    static let NO_EXPIRY = "2099-12-31"   // batches bought without an expiry date sort last in FEFO
    static let BOX_UNIT = rx("^(BOX|BOXES|BX|CASE|CS|CTN|CARTON)$", "i")

    static func blankNum(_ v: Any?) -> Bool {
        guard let u = unwrap(v) else { return true }
        return JS.trim(JS.string(u)).isEmpty
    }

    /// `num(v, label, { min })`
    static func num(_ v: Any?, _ label: String, min: Double = 0) throws -> Double {
        if blankNum(v) { return 0 }
        let n = JS.parseNumber(JS.string(unwrap(v)).replacingOccurrences(of: ",", with: ""))
        if !n.isFinite || n < min { throw HttpError(400, "\(label) must be a number\(min == 0 ? " (0 or more)" : "")") }
        return n
    }

    static func isStrDate(_ v: Any?) -> Bool { (unwrap(v) as? String).map { isDateRe.test($0) } ?? false }

    struct Built {
        var party: Row
        var date: String
        var intra: Bool
        var rows: [Row]
        var subtotal, discount, taxable, cgst, sgst, igst, roundOff, total: Double
        var suggested: Row
        var printedTotal: Double?
        var mismatch: Double
        var share: Double
    }

    /// Pure calculation for a supplier bill, no writes:
    ///   items -> subtotal; minus bill discount -> taxable; plus CGST/SGST (or IGST); plus round off -> grand total.
    static func build(_ db: Database, _ input: Row) throws -> Built {
        if !JS.truthy(input["party_id"]) { throw HttpError(400, "Select the supplier") }
        guard let party = try db.prepare("SELECT * FROM parties WHERE id=?").get(input.v("party_id")) else { throw HttpError(404, "Supplier not found") }
        guard let lines = input["lines"] as? [Any], !lines.isEmpty else { throw HttpError(400, "Add at least one item") }
        let co = try Billing.settings(db)
        let intra = !JS.truthy(party["state_code"]) || party.s("state_code") == co.s("state_code")
        let date: String
        if JS.truthy(input["date"]) {
            guard let d = input.v("date") as? String, isDateRe.test(d) else { throw HttpError(400, "Bill date must be YYYY-MM-DD") }
            date = d
        } else { date = today() }

        var rows: [Row] = []
        for (i, lnAny) in lines.enumerated() {
            let ln = (lnAny as? Row) ?? [:]
            let n = i + 1
            var item: Row?
            if JS.truthy(ln["item_id"]) { item = try db.prepare("SELECT * FROM items WHERE id=? AND active=1").get(ln.v("item_id")) }
            guard let item else { throw HttpError(400, "Row \(n): choose the stock item") }
            let name = item.str("name")
            let q = try num(ln["qty"] ?? nil, "Row \(n) (\(name)) quantity")
            if !(q > 0) || !JS.isInteger(q) { throw HttpError(400, "Row \(n) (\(name)): quantity must be a whole number of at least 1") }
            let unitSrc: Any? = JS.truthy(ln["unit"]) ? ln.v("unit") : (JS.truthy(item["unit"]) ? item.v("unit") : "PCS")
            var unit = JS.trim(JS.string(unitSrc)).uppercased().jsSlice(0, 8)
            if unit.isEmpty { unit = "PCS" }
            let ppbRaw = item.n("pcs_per_box")
            let ppb = max(1, (ppbRaw.isNaN || ppbRaw == 0) ? 1 : ppbRaw)
            let pcs = BOX_UNIT.test(unit) ? q * ppb : q                 // stock is always kept in pieces
            let rate = try num(ln["rate"] ?? nil, "Row \(n) (\(name)) price")
            let amount = blankNum(ln["amount"] ?? nil) ? r2(q * rate) : r2(try num(ln["amount"] ?? nil, "Row \(n) (\(name)) amount"))
            let exp: Any? = JS.truthy(ln["exp_date"]) ? ln.v("exp_date") : NO_EXPIRY
            if !isStrDate(exp) { throw HttpError(400, "Row \(n) (\(name)): expiry must be YYYY-MM-DD") }
            if JS.truthy(ln["mfg_date"]) && !isStrDate(ln["mfg_date"] ?? nil) { throw HttpError(400, "Row \(n) (\(name)): mfg date must be YYYY-MM-DD") }
            let bn = JS.trim(JS.truthy(ln["batch_no"]) ? JS.string(ln.v("batch_no")) : "")
            rows.append([
                "line_index": i, "sno": n, "item_id": item["id"]!, "item_name": item["name"]!,
                "hsn": JS.truthy(ln["hsn"]) ? ln.v("hsn")! : (JS.truthy(item["hsn"]) ? item.v("hsn")! : NSNull()), "gst_rate": item["gst_rate"]!,
                "qty": q, "unit": unit, "pcs_qty": pcs, "rate": rate, "amount": amount,
                "batch_no": bn.isEmpty ? "AUTO-\(date.replacingOccurrences(of: "-", with: ""))" : bn,
                "mfg_date": JS.truthy(ln["mfg_date"]) ? ln.v("mfg_date")! : NSNull(), "exp_date": exp!,
                "mrp": JS.truthy(ln["mrp"]) ? JS.number(ln.v("mrp")) as Any : NSNull(),
            ])
        }

        let subtotal = r2(rows.reduce(0.0) { $0 + $1.n("amount") })
        let discount = r2(try num(input["discount"] ?? nil, "Discount"))
        if discount > subtotal + 0.005 { throw HttpError(400, "Discount cannot be more than the items total") }
        let taxable = r2(subtotal - discount)
        let share = subtotal > 0 ? taxable / subtotal : 0

        // Tax worked out from item GST rates (also offered to the user as "recalculate")
        var sugTax = 0.0
        for r in rows { sugTax += (r.n("amount") * share * r.n("gst_rate")) / 100 }
        sugTax = r2(sugTax)
        let suggested: Row = intra ? ["cgst": r2(sugTax / 2), "sgst": r2(sugTax - r2(sugTax / 2)), "igst": 0] : ["cgst": 0, "sgst": 0, "igst": sugTax]

        let taxGiven = !(blankNum(input["cgst"] ?? nil) && blankNum(input["sgst"] ?? nil) && blankNum(input["igst"] ?? nil))
        var cgst: Double, sgst: Double, igst: Double
        if JS.truthy(input["auto_tax"]) || !taxGiven {
            cgst = suggested.n("cgst"); sgst = suggested.n("sgst"); igst = suggested.n("igst")
        } else {
            cgst = r2(try num(input["cgst"] ?? nil, "CGST")); sgst = r2(try num(input["sgst"] ?? nil, "SGST")); igst = r2(try num(input["igst"] ?? nil, "IGST"))
        }

        let grand = r2(taxable + cgst + sgst + igst)
        var roundOff: Double
        if blankNum(input["round_off"] ?? nil) { roundOff = r2(JS.round(grand) - grand) } else {
            roundOff = r2(try num(input["round_off"] ?? nil, "Round off", min: -.infinity))
            if abs(roundOff) > 5 { throw HttpError(400, "Round off looks too large (more than 5 rupees). Check the figure.") }
        }
        let total = r2(grand + roundOff)
        let printed: Double? = blankNum(input["printed_total"] ?? nil) ? nil : JS.number(input.v("printed_total"))
        var mismatch = 0.0
        if let p = printed, p.isFinite, abs(p - total) > 1 { mismatch = r2(total - p) }

        return Built(party: party, date: date, intra: intra, rows: rows, subtotal: subtotal, discount: discount, taxable: taxable,
                     cgst: cgst, sgst: sgst, igst: igst, roundOff: roundOff, total: total, suggested: suggested, printedTotal: printed,
                     mismatch: mismatch, share: share)
    }

    static func preview(_ db: Database, _ input: Row) throws -> Row {
        let p = try build(db, input)
        return ["date": p.date, "intra": p.intra, "subtotal": p.subtotal, "discount": p.discount, "taxable": p.taxable, "cgst": p.cgst,
                "sgst": p.sgst, "igst": p.igst, "round_off": p.roundOff, "total": p.total, "suggested_tax": p.suggested,
                "printed_total": p.printedTotal.map { $0 as Any } ?? NSNull(), "mismatch": p.mismatch,
                "supply": p.intra ? "INTRA" : "INTER", "lines": p.rows]
    }

    struct Written { let id: Int; let purchaseNo: String; let p: Built; let paid: Double; let mode: String; let supplierNo: String; let touched: [Int] }

    /// Shared by create and edit.
    static func write(_ db: Database, _ input: Row, _ existing: (id: Int, purchaseNo: String)?) throws -> Written {
        let p = try build(db, input)
        let supplierNo = JS.trim(JS.truthy(input["supplier_invoice_no"]) ? JS.string(input.v("supplier_invoice_no")) : "")
        if !supplierNo.isEmpty && !JS.truthy(input["allow_duplicate"]) {
            if let dup = try db.prepare("SELECT purchase_no FROM purchases WHERE party_id=? AND lower(supplier_invoice_no)=lower(?) AND id <> ?")
                .get(p.party.v("id"), supplierNo, existing?.id ?? 0) {
                throw HttpError(409, "Bill \(supplierNo) from \(p.party.str("name")) is already entered as \(dup.str("purchase_no"))", "DUPLICATE")
            }
        }
        let paid = r2(min(max(try num(input["paid_amount"] ?? nil, "Paid amount"), 0), max(p.total, 0)))
        let mode = (JS.truthy(input["pay_mode"]) ? JS.string(input.v("pay_mode")) : "CASH").uppercased()
        let vals: [Any?] = [supplierNo.isEmpty ? nil : supplierNo, p.date, p.party.v("id"), p.subtotal, p.discount, p.taxable, p.cgst, p.sgst, p.igst,
                            p.roundOff, p.total, paid, paid > 0 ? mode : nil, JS.truthy(input["notes"]) ? input.v("notes") : nil,
                            input.v("source") as? String == "PDF" ? "PDF" : "MANUAL"]
        var id: Int
        var purchaseNo: String
        if let existing {
            id = existing.id
            purchaseNo = existing.purchaseNo
            try db.prepare("UPDATE purchases SET supplier_invoice_no=?,date=?,party_id=?,subtotal=?,discount=?,taxable=?,cgst=?,sgst=?,igst=?,round_off=?,total=?,paid=?,pay_mode=?,notes=?,source=? WHERE id=?")
                .run(vals[0], vals[1], vals[2], vals[3], vals[4], vals[5], vals[6], vals[7], vals[8], vals[9], vals[10], vals[11], vals[12], vals[13], vals[14], id)
        } else {
            purchaseNo = try nextNo(db, "PUR", p.date)
            id = try db.prepare("""
            INSERT INTO purchases(supplier_invoice_no,date,party_id,subtotal,discount,taxable,cgst,sgst,igst,round_off,total,paid,pay_mode,notes,source,purchase_no)
                   VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """).run(vals[0], vals[1], vals[2], vals[3], vals[4], vals[5], vals[6], vals[7], vals[8], vals[9], vals[10], vals[11], vals[12], vals[13], vals[14], purchaseNo).lastInsertRowid
        }

        let upsert = db.prepare("""
        INSERT INTO batches(item_id,batch_no,mfg_date,exp_date,qty,purchase_price,mrp) VALUES(?,?,?,?,?,?,?)
             ON CONFLICT(item_id,batch_no) DO UPDATE SET qty = qty + excluded.qty, exp_date = excluded.exp_date,
               mfg_date = COALESCE(excluded.mfg_date, mfg_date), purchase_price = excluded.purchase_price, mrp = COALESCE(excluded.mrp, mrp)
        """)
        let insLine = db.prepare("""
        INSERT INTO purchase_lines(purchase_id,item_id,batch_id,batch_no,mfg_date,exp_date,qty,free_qty,rate,disc_pct,disc_amt,mrp,taxable,gst_rate,cgst,sgst,igst,amount,unit,pcs_qty)
             VALUES(?,?,?,?,?,?,?,0,?,0,0,?,?,?,0,0,0,?,?,?)
        """)
        var touched: [Int] = []
        let updateCost = !(input["update_cost"] is Bool && (input["update_cost"] as! Bool) == false)
        for r in p.rows {
            let lineTaxable = r2(r.n("amount") * p.share)
            let unitCost = r2(lineTaxable / r.n("pcs_qty"))                  // landed cost per piece after bill discount
            try upsert.run(r.v("item_id"), r.v("batch_no"), r.v("mfg_date"), r.v("exp_date"), r.n("pcs_qty"), unitCost, r.v("mrp"))
            let batch = try db.prepare("SELECT id FROM batches WHERE item_id=? AND batch_no=?").get(r.v("item_id"), r.v("batch_no"))!
            if !touched.contains(batch.i("id")) { touched.append(batch.i("id")) }
            try insLine.run(id, r.v("item_id"), batch.v("id"), r.v("batch_no"), r.v("mfg_date"), r.v("exp_date"), r.n("qty"), r.n("rate"), r.v("mrp"),
                            lineTaxable, r.n("gst_rate"), r.n("amount"), r.v("unit"), r.n("pcs_qty"))
            if updateCost && unitCost > 0 { try db.prepare("UPDATE items SET purchase_price=? WHERE id=?").run(unitCost, r.v("item_id")) }
        }
        return Written(id: id, purchaseNo: purchaseNo, p: p, paid: paid, mode: mode, supplierNo: supplierNo, touched: touched)
    }

    static func postLedger(_ db: Database, _ w: Written) throws {
        let lg = db.prepare("INSERT INTO ledger(party_id,date,type,ref_no,debit,credit,narration) VALUES(?,?,?,?,?,?,?)")
        try lg.run(w.p.party.v("id"), w.p.date, "PURCHASE", w.purchaseNo, 0, w.p.total, "Purchase \(w.purchaseNo)\(w.supplierNo.isEmpty ? "" : " / " + w.supplierNo)")
        if w.paid > 0 {
            let v = try nextNo(db, "PAY", w.p.date)
            try db.prepare("INSERT INTO payments(voucher_no,date,party_id,purchase_id,mode,amount,reference) VALUES(?,?,?,?,?,?,?)")
                .run(v, w.p.date, w.p.party.v("id"), w.id, w.mode, w.paid, "Paid at purchase \(w.purchaseNo)")
            try lg.run(w.p.party.v("id"), w.p.date, "PAYMENT", v, w.paid, 0, "Paid at purchase (\(w.mode))")
        }
    }

    /// Saves the bill AND adds the received pieces to batch stock, posts to the supplier ledger, all in one transaction.
    static func create(_ db: Database, _ input: Row) throws -> Int {
        try db.transaction {
            let w = try write(db, input, nil)
            try postLedger(db, w)
            return w.id
        }
    }

    private static func reverse(_ db: Database, _ id: Int, _ old: Row) throws -> [Int] {
        var touched: [Int] = []
        for l in try db.prepare("SELECT batch_id, qty, free_qty, pcs_qty FROM purchase_lines WHERE purchase_id=?").all(id) {
            let q = l.has("pcs_qty") ? l.n("pcs_qty") : l.n("qty") + l.n("free_qty")
            try db.prepare("UPDATE batches SET qty = qty - ? WHERE id = ?").run(q, l.v("batch_id"))
            if !touched.contains(l.i("batch_id")) { touched.append(l.i("batch_id")) }
        }
        try db.prepare("DELETE FROM purchase_lines WHERE purchase_id=?").run(id)
        for pay in try db.prepare("SELECT voucher_no FROM payments WHERE purchase_id=?").all(id) {
            try db.prepare("DELETE FROM ledger WHERE type='PAYMENT' AND ref_no=?").run(pay.v("voucher_no"))
        }
        try db.prepare("DELETE FROM payments WHERE purchase_id=?").run(id)
        try db.prepare("DELETE FROM ledger WHERE type='PURCHASE' AND ref_no=?").run(old.v("purchase_no"))
        return touched
    }

    /// Edit a saved (manual or scanned) purchase; refused (changing nothing) if a batch would drop below what was already sold from it.
    static func update(_ db: Database, _ id: Int, _ input: Row) throws -> Int {
        try db.transaction {
            guard let old = try db.prepare("SELECT * FROM purchases WHERE id=?").get(id) else { throw HttpError(404, "Purchase bill not found") }
            let oldTouched = try reverse(db, id, old)
            let w = try write(db, input, (id, old.str("purchase_no")))
            try postLedger(db, w)
            var all = oldTouched
            for b in w.touched where !all.contains(b) { all.append(b) }
            for b in all {
                if let row = try db.prepare("SELECT b.qty, i.name FROM batches b JOIN items i ON i.id=b.item_id WHERE b.id=?").get(b), row.n("qty") < 0 {
                    throw HttpError(409, "\(row.str("name")): \(JS.numberString(-row.n("qty"))) piece(s) from this bill were already sold, so the quantity cannot be reduced that far.", "ALREADY_SOLD")
                }
            }
            return id
        }
    }

    /// Delete a purchase bill: its stock comes back out of the batches (refused if some of it was already sold) and its ledger entries go.
    static func delete(_ db: Database, _ id: Int) throws -> Row {
        try db.transaction {
            guard let old = try db.prepare("SELECT * FROM purchases WHERE id=?").get(id) else { throw HttpError(404, "Purchase bill not found") }
            let touched = try reverse(db, id, old)
            try db.prepare("DELETE FROM purchases WHERE id=?").run(id)
            for b in touched {
                if let row = try db.prepare("SELECT b.qty, i.name FROM batches b JOIN items i ON i.id=b.item_id WHERE b.id=?").get(b), row.n("qty") < 0 {
                    throw HttpError(409, "\(row.str("name")): \(JS.numberString(-row.n("qty"))) piece(s) from this bill were already sold, so it cannot be deleted.", "ALREADY_SOLD")
                }
            }
            return ["id": id, "purchase_no": old["purchase_no"]!, "total": old["total"]!]
        }
    }

    static func get(_ db: Database, _ id: Any?) throws -> Row? {
        guard var p = try db.prepare("""
        SELECT pu.*, pa.name party_name, pa.gstin party_gstin, pa.state_code party_state FROM purchases pu JOIN parties pa ON pa.id=pu.party_id WHERE pu.id=?
        """).get(id) else { return nil }
        var lines = try db.prepare("SELECT l.*, it.name item_name, COALESCE(it.hsn,'') hsn FROM purchase_lines l JOIN items it ON it.id=l.item_id WHERE l.purchase_id=? ORDER BY l.id").all(id)
        for i in lines.indices {
            lines[i]["sno"] = i + 1
            if lines[i].str("exp_date") >= "2099-01-01" { lines[i]["exp_date"] = NSNull() }
            if !JS.truthy(lines[i]["unit"]) { lines[i]["unit"] = "PCS" }
        }
        p["lines"] = lines
        return p
    }
}

enum Vouchers {
    /// Cash/bank voucher against a party. RECEIVED -> receipts + ledger credit; PAID -> payments + ledger debit.
    static func record(_ db: Database, _ b: Row) throws -> Row {
        try db.transaction {
            let amount = r2(JS.number(b["amount"] ?? nil))
            if !JS.truthy(b["party_id"]) || !(amount > 0) { throw HttpError(400, "Party and a positive amount are required") }
            if try db.prepare("SELECT 1 FROM parties WHERE id=?").get(b.v("party_id")) == nil { throw HttpError(404, "Party not found") }
            let direction = (JS.truthy(b["direction"]) ? JS.string(b.v("direction")) : "RECEIVED").uppercased()
            if !["RECEIVED", "PAID"].contains(direction) { throw HttpError(400, "Direction must be RECEIVED or PAID") }
            let date = JS.truthy(b["date"]) ? JS.string(b.v("date")) : today()
            let mode = (JS.truthy(b["mode"]) ? JS.string(b.v("mode")) : "CASH").uppercased()
            let ref = JS.truthy(b["reference"]) ? " " + JS.string(b.v("reference")) : ""
            let lg = db.prepare("INSERT INTO ledger(party_id,date,type,ref_no,debit,credit,narration) VALUES(?,?,?,?,?,?,?)")
            var no: String
            if direction == "RECEIVED" {
                no = try nextNo(db, "RCT", date)
                try db.prepare("INSERT INTO receipts(receipt_no,date,party_id,salesman_id,mode,amount,reference) VALUES(?,?,?,?,?,?,?)")
                    .run(no, date, b.v("party_id"), JS.blank(b["salesman_id"] ?? nil), mode, amount, JS.blank(b["reference"] ?? nil))
                try lg.run(b.v("party_id"), date, "RECEIPT", no, 0, amount, "Payment received (\(mode))\(ref)")
            } else {
                no = try nextNo(db, "PAY", date)
                try db.prepare("INSERT INTO payments(voucher_no,date,party_id,mode,amount,reference) VALUES(?,?,?,?,?,?)")
                    .run(no, date, b.v("party_id"), mode, amount, JS.blank(b["reference"] ?? nil))
                try lg.run(b.v("party_id"), date, "PAYMENT", no, amount, 0, "Payment made (\(mode))\(ref)")
            }
            return ["voucher_no": no, "direction": direction, "amount": amount, "balance": r2(try Billing.partyBalance(db, b.v("party_id")))]
        }
    }

    /// Everything the print engine needs for a receipt / payment voucher.
    static func get(_ db: Database, _ voucherNo: String) throws -> Row {
        let rec = try db.prepare("SELECT receipt_no no, date, party_id, mode, amount, reference FROM receipts WHERE receipt_no=?").get(voucherNo)
        let pay = rec != nil ? nil : try db.prepare("SELECT voucher_no no, date, party_id, mode, amount, reference FROM payments WHERE voucher_no=?").get(voucherNo)
        guard var v = rec ?? pay else { throw HttpError(404, "Voucher not found") }
        let party = try db.prepare("SELECT id,name,address,gstin,phone,mobiles FROM parties WHERE id=?").get(v.v("party_id"))
        let co = try Billing.settings(db)
        v["direction"] = rec != nil ? "RECEIVED" : "PAID"
        v["title"] = rec != nil ? "Receipt Voucher" : "Payment Voucher"
        v["party"] = party ?? NSNull()
        v["amount_words"] = Words.rupees(v.n("amount"))
        v["balance"] = r2(try Billing.partyBalance(db, v.v("party_id")))
        v["company"] = ["name": co["company_name"] ?? NSNull(), "address": co["company_address"] ?? NSNull(),
                        "gstin": co["company_gstin"] ?? NSNull(), "phone": co["company_phone"] ?? NSNull()] as Row
        return v
    }
}
