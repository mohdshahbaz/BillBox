import Foundation

// backend/src/services/reports.js

enum Reports {
    static func one(_ db: Database, _ sql: String, _ args: Any?...) throws -> Row {
        let st = db.prepare(sql)
        switch args.count {
        case 0: return try st.get() ?? [:]
        case 1: return try st.get(args[0]) ?? [:]
        case 2: return try st.get(args[0], args[1]) ?? [:]
        case 3: return try st.get(args[0], args[1], args[2]) ?? [:]
        default: return try st.get(args[0], args[1], args[2], args[3]) ?? [:]
        }
    }
    static func monthOf(_ d: String) -> String { d.jsSlice(0, 7) }
    static func clamp(_ d: String, _ r: FYRange) -> String { d < r.from ? r.from : (d > r.to ? r.to : d) }

    /// Profit = selling value (ex-GST, after discounts) minus what the sold pieces cost (batch purchase price, else the item's).
    static func profit(_ db: Database, _ from: String, _ to: String) throws -> Row {
        let r = try one(db, """
        SELECT COALESCE(SUM(l.taxable),0) revenue,
                    COALESCE(SUM((l.qty+l.free_qty) * COALESCE(NULLIF(b.purchase_price,0), NULLIF(it.purchase_price,0), 0)),0) cost,
                    COALESCE(SUM(CASE WHEN COALESCE(NULLIF(b.purchase_price,0), NULLIF(it.purchase_price,0), 0)=0 THEN 1 ELSE 0 END),0) unknown_cost_lines
             FROM invoice_lines l JOIN invoices i ON i.id=l.invoice_id JOIN items it ON it.id=l.item_id LEFT JOIN batches b ON b.id=l.batch_id
             WHERE i.date BETWEEN ? AND ?
        """, from, to)
        let p = r2(r.n("revenue") - r.n("cost"))
        return ["revenue": r2(r.n("revenue")), "cost": r2(r.n("cost")), "profit": p,
                "margin_pct": r.n("revenue") > 0 ? r2((p / r.n("revenue")) * 100) : 0, "unknown_cost_lines": r["unknown_cost_lines"]!]
    }

    static func sumBetween(_ db: Database, _ table: String, _ col: String, _ from: String, _ to: String) throws -> Double {
        r2(try one(db, "SELECT COALESCE(SUM(\(col)),0) v FROM \(table) WHERE date BETWEEN ? AND ?", from, to).n("v"))
    }

    /// Settings › Stock: how many days ahead the dashboard warns about expiry (1 to 365, default 30).
    static func expiryDays(_ db: Database) throws -> Int {
        let r = try db.prepare("SELECT value FROM settings WHERE key='expiry_days'").get()
        let n = JS.parseInt(r.map { $0["value"] ?? nil } ?? nil)
        return n >= 1 && n <= 365 ? Int(n) : 30
    }

    static func dashboard(_ db: Database, _ fyLabel: Any?) throws -> Row {
        let fy = try FY.range(fyLabel)
        let t = clamp(today(), fy)                 // "today" = the last day of a finished year
        let m = monthOf(t), mFrom = m + "-01"
        func taxOut(_ f: String, _ to: String) throws -> Double { try one(db, "SELECT COALESCE(SUM(cgst+sgst+igst),0) v FROM invoices WHERE date BETWEEN ? AND ?", f, to).n("v") }
        // input tax credit: GST paid on purchases less the GST on goods sent back (debit notes)
        func taxIn(_ f: String, _ to: String) throws -> Double {
            try one(db, "SELECT COALESCE(SUM(cgst+sgst+igst),0) v FROM purchases WHERE date BETWEEN ? AND ?", f, to).n("v")
                - one(db, "SELECT COALESCE(SUM(cgst+sgst+igst),0) v FROM debit_notes WHERE date BETWEEN ? AND ?", f, to).n("v")
        }
        let bal = try one(db, """
        SELECT COALESCE(SUM(CASE WHEN b>0 THEN b ELSE 0 END),0) rec, COALESCE(-SUM(CASE WHEN b<0 THEN b ELSE 0 END),0) pay
                           FROM (SELECT SUM(debit)-SUM(credit) b FROM ledger WHERE date <= ? GROUP BY party_id)
        """, fy.to)
        var series: [Row] = []
        var i = 13
        while i >= 0 {
            let d = Clock.addDays(-i, Clock.localNoon(t))
            i -= 1
            if d < fy.from { continue }
            series.append(["date": d, "sales": try sumBetween(db, "invoices", "total", d, d), "purchases": try sumBetween(db, "purchases", "total", d, d)])
        }
        var monthly: [Row] = []
        for k in 0..<12 {
            let y = fy.startYear + (k + 3 >= 12 ? 1 : 0), mo = ((k + 3) % 12) + 1
            let mm = String(mo).padStart(2, "0")
            let from = "\(y)-\(mm)-01", to = "\(y)-\(mm)-31"
            monthly.append(["month": from.jsSlice(0, 7), "sales": try sumBetween(db, "invoices", "total", from, to),
                            "purchases": try sumBetween(db, "purchases", "total", from, to), "profit": try profit(db, from, to)["profit"]!])
        }
        let low = try lowStock(db, 8)
        let fyProfit = try profit(db, fy.from, fy.to), monthProfit = try profit(db, mFrom, t), dayProfit = try profit(db, t, t)
        let taxOutM = try taxOut(mFrom, t), taxInM = try taxIn(mFrom, t)
        return [
            "fy": fy.label, "fy_from": fy.from, "fy_to": fy.to, "is_current": fy.current, "as_of": t, "month": m,
            "today_sales": try sumBetween(db, "invoices", "total", t, t),
            "today_bills": try one(db, "SELECT COUNT(*) v FROM invoices WHERE date=?", t)["v"]!,
            "today_profit": dayProfit["profit"]!,
            "month_sales": try sumBetween(db, "invoices", "total", mFrom, t),
            "month_bills": try one(db, "SELECT COUNT(*) v FROM invoices WHERE date BETWEEN ? AND ?", mFrom, t)["v"]!,
            "month_profit": monthProfit["profit"]!,
            "month_purchases": try sumBetween(db, "purchases", "total", mFrom, t),
            "month_purchase_bills": try one(db, "SELECT COUNT(*) v FROM purchases WHERE date BETWEEN ? AND ?", mFrom, t)["v"]!,
            "fy_sales": try sumBetween(db, "invoices", "total", fy.from, fy.to),
            "fy_bills": try one(db, "SELECT COUNT(*) v FROM invoices WHERE date BETWEEN ? AND ?", fy.from, fy.to)["v"]!,
            "fy_purchases": try sumBetween(db, "purchases", "total", fy.from, fy.to),
            "fy_collections": try sumBetween(db, "receipts", "amount", fy.from, fy.to),
            "fy_profit": fyProfit["profit"]!, "fy_margin_pct": fyProfit["margin_pct"]!, "fy_cost": fyProfit["cost"]!, "fy_revenue": fyProfit["revenue"]!,
            "profit_unknown_cost_lines": fyProfit["unknown_cost_lines"]!,
            "today_collections": try sumBetween(db, "receipts", "amount", t, t),
            "receivable": r2(bal.n("rec")), "payable": r2(bal.n("pay")),
            "gst_output": r2(taxOutM), "gst_input": r2(taxInM), "gst_liability": r2(taxOutM - taxInM),
            "fy_gst_liability": r2(try taxOut(fy.from, fy.to) - taxIn(fy.from, fy.to)),
            "low_stock_count": low.total, "low_stock": low.rows, "low_stock_qty": low.threshold,
            // Settings › Stock › expiry warning (days); the key keeps its old name
            "expiring_30d": try one(db, "SELECT COUNT(*) v FROM batches WHERE qty>0 AND exp_date BETWEEN ? AND ?", today(), Clock.addDays(expiryDays(db)))["v"]!,
            "expiry_days": try expiryDays(db),
            "expired_stock": try one(db, "SELECT COUNT(*) v FROM batches WHERE qty>0 AND exp_date<?", today())["v"]!,
            "top_dues": try db.prepare("""
            SELECT p.id, p.name, SUM(l.debit)-SUM(l.credit) balance FROM parties p JOIN ledger l ON l.party_id=p.id AND l.date <= ?
                   GROUP BY p.id HAVING balance > 0.5 ORDER BY balance DESC LIMIT 5
            """).all(fy.to),
            "series": series, "monthly": monthly,
            "month_collections": try sumBetween(db, "receipts", "amount", mFrom, t),
            "unprinted_bills": try one(db, "SELECT COUNT(*) v FROM invoices WHERE printed=0 AND date BETWEEN ? AND ?", fy.from, fy.to)["v"]!,
            "top_items": try db.prepare("""
            SELECT i.id, i.name, i.pcs_per_box, SUM(l.qty + l.free_qty) qty, ROUND(SUM(l.amount),2) amount FROM invoice_lines l
                   JOIN invoices v ON v.id=l.invoice_id JOIN items i ON i.id=l.item_id WHERE v.date BETWEEN ? AND ?
                   GROUP BY i.id ORDER BY amount DESC, i.name LIMIT 6
            """).all(mFrom, t),
            "recent_bills": try db.prepare("""
            SELECT v.id, v.invoice_no, v.date, COALESCE(p.name, 'Cash sale') party, v.total, v.printed FROM invoices v LEFT JOIN parties p ON p.id=v.party_id
                   WHERE v.date BETWEEN ? AND ? ORDER BY v.date DESC, v.id DESC LIMIT 6
            """).all(fy.from, fy.to),
        ]
    }

    /// Items that have been stocked before and are now at or below the company's low-stock level (pieces).
    static func lowStock(_ db: Database, _ limit: Int = 1000) throws -> (threshold: Double, total: Int, rows: [Row]) {
        let row = try db.prepare("SELECT value FROM settings WHERE key='low_stock_qty'").get()
        let p = JS.parseInt(row != nil ? row!["value"] ?? nil : "10")
        let threshold = max(0, (p.isNaN || p == 0) ? 0 : p)
        let all = try db.prepare("""
        SELECT i.id, i.name, i.pcs_per_box, COALESCE(SUM(b.qty),0) stock FROM items i JOIN batches b ON b.item_id=i.id
             WHERE i.active=1 GROUP BY i.id HAVING stock <= ? ORDER BY stock, i.name
        """).all(threshold)
        return (threshold, all.count, Array(all.prefix(limit)))
    }

    static let STD_RATES: [Double] = [0, 5, 12, 18, 28]

    /// Monthly outward supplies (GSTR-1 style summary): taxable value and CGST/SGST/IGST per rate slab.
    static func gstOutward(_ db: Database, _ month: Any?, _ fyLabel: Any?) throws -> Row {
        var m: String
        if JS.truthy(month) { m = JS.string(unwrap(month)) } else { m = monthOf(clamp(today(), try FY.range(fyLabel))) }
        if !rx("^\\d{4}-\\d{2}$").test(m) { throw HttpError(400, "Month must be YYYY-MM") }
        let rows = try db.prepare("""
        SELECT l.gst_rate rate, SUM(l.taxable) taxable, SUM(l.cgst) cgst, SUM(l.sgst) sgst, SUM(l.igst) igst, COUNT(DISTINCT l.invoice_id) invoices
             FROM invoice_lines l JOIN invoices i ON i.id=l.invoice_id WHERE substr(i.date,1,7)=? GROUP BY l.gst_rate
        """).all(m)
        var byRate: [Double: Row] = [:]
        for r in rows { byRate[r.n("rate")] = r }
        var rateSet: [Double] = []
        for x in STD_RATES + rows.map({ $0.n("rate") }) where !rateSet.contains(x) { rateSet.append(x) }
        let rates = rateSet.sorted()
        let out: [Row] = rates.map { rate in
            let r = byRate[rate] ?? ["taxable": 0, "cgst": 0, "sgst": 0, "igst": 0, "invoices": 0]
            let tax = r2(r.n("cgst") + r.n("sgst") + r.n("igst"))
            // the IGST column of this report carries the whole tax of the slab: CGST + SGST (+ any true IGST)
            return ["rate": rate, "taxable": r2(r.n("taxable")), "cgst": r2(r.n("cgst")), "sgst": r2(r.n("sgst")), "igst": tax, "tax": tax,
                    "value": r2(r.n("taxable") + tax), "invoices": r["invoices"]!]
        }
        func tot(_ k: String) -> Double { r2(out.reduce(0.0) { $0 + $1.n(k) }) }
        func split(_ cond: String) throws -> Row {
            try one(db, """
            SELECT COALESCE(SUM(l.taxable),0) taxable, COALESCE(SUM(l.cgst+l.sgst+l.igst),0) tax FROM invoice_lines l
                 JOIN invoices i ON i.id=l.invoice_id LEFT JOIN parties p ON p.id=i.party_id WHERE substr(i.date,1,7)=? AND \(cond)
            """, m)
        }
        let b2b = try split("COALESCE(p.gstin,'') <> ''"), b2c = try split("COALESCE(p.gstin,'') = ''")
        let inv = try one(db, "SELECT COUNT(*) n, COALESCE(SUM(round_off),0) ro FROM invoices WHERE substr(date,1,7)=?", m)
        let bought = try one(db, "SELECT COALESCE(SUM(cgst),0) c, COALESCE(SUM(sgst),0) s, COALESCE(SUM(igst),0) i FROM purchases WHERE substr(date,1,7)=?", m)
        let returned = try one(db, "SELECT COALESCE(SUM(cgst),0) c, COALESCE(SUM(sgst),0) s, COALESCE(SUM(igst),0) i FROM debit_notes WHERE substr(date,1,7)=?", m)
        let ic = bought.n("c") - returned.n("c"), isg = bought.n("s") - returned.n("s"), ii = bought.n("i") - returned.n("i")
        return [
            "month": m, "rows": out,
            "totals": ["taxable": tot("taxable"), "cgst": tot("cgst"), "sgst": tot("sgst"), "igst": tot("igst"), "tax": tot("tax"), "value": tot("value")] as Row,
            "invoices": inv["n"]!, "round_off": r2(inv.n("ro")),
            "b2b": ["taxable": r2(b2b.n("taxable")), "tax": r2(b2b.n("tax"))] as Row, "b2c": ["taxable": r2(b2c.n("taxable")), "tax": r2(b2c.n("tax"))] as Row,
            "input_credit": ["cgst": r2(ic), "sgst": r2(isg), "igst": r2(ii), "total": r2(ic + isg + ii),
                             "debit_notes": r2(returned.n("c") + returned.n("s") + returned.n("i"))] as Row,
            "net_payable": r2(tot("tax") - (ic + isg + ii)),
        ]
    }

    /// Bill-wise detail for the monthly GST workbook: B2B (party has GSTIN), B2C (no GSTIN) and the rate-wise summary.
    static func gstOutwardDetail(_ db: Database, _ month: Any?, _ fyLabel: Any?) throws -> Row {
        var base = try gstOutward(db, month, fyLabel)
        let m = base.str("month")
        let bills = try db.prepare("""
        SELECT i.id, i.invoice_no, i.date, COALESCE(p.name,'Cash customer') party, COALESCE(p.gstin,'') gstin, COALESCE(p.state_code,'') state_code,
                    i.taxable, i.cgst, i.sgst, i.igst, i.round_off, i.total
             FROM invoices i LEFT JOIN parties p ON p.id=i.party_id WHERE substr(i.date,1,7)=? ORDER BY i.date, i.id
        """).all(m)
        let rates = try db.prepare("""
        SELECT l.invoice_id, GROUP_CONCAT(DISTINCT l.gst_rate) rates FROM invoice_lines l JOIN invoices i ON i.id=l.invoice_id
             WHERE substr(i.date,1,7)=? GROUP BY l.invoice_id
        """).all(m)
        var rm: [Int: String] = [:]
        for r in rates { rm[r.i("invoice_id")] = r.str("rates") }
        let rows: [Row] = bills.map { b in
            var x = b
            x["rates"] = (rm[b.i("id")] ?? "").components(separatedBy: ",").filter { !$0.isEmpty }.map { $0 + "%" }.joined(separator: ", ")
            let tax = r2(b.n("cgst") + b.n("sgst") + b.n("igst"))
            x["tax"] = tax
            x["igst"] = tax    // IGST column = CGST + SGST (+ IGST)
            return x
        }
        base["b2b_bills"] = rows.filter { !$0.str("gstin").isEmpty }
        base["b2c_bills"] = rows.filter { $0.str("gstin").isEmpty }
        return base
    }

    /// Sales or purchase book: chronological register with period totals.
    static func book(_ db: Database, _ type: String, _ from: Any?, _ to: Any?, _ fyLabel: Any?) throws -> Row {
        let fy = try FY.range(fyLabel)
        let f = clamp(JS.truthy(from) ? JS.string(unwrap(from)) : (fy.current ? monthOf(today()) + "-01" : fy.from), fy)
        let t = clamp(JS.truthy(to) ? JS.string(unwrap(to)) : (fy.current ? today() : fy.to), fy)
        let isSales = type == "sales"
        let rows = type == "debit"
            ? try db.prepare("""
            SELECT d.id, d.date, d.note_no no, COALESCE(d.against_bill,'') ref, p.name party, COALESCE(p.gstin,'') gstin,
                              d.taxable, d.cgst, d.sgst, d.igst, d.round_off, d.total FROM debit_notes d JOIN parties p ON p.id=d.party_id
                              WHERE d.date BETWEEN ? AND ? ORDER BY d.date, d.id
            """).all(f, t)
            : isSales
            ? try db.prepare("""
            SELECT i.id, i.date, i.invoice_no no, '' ref, COALESCE(p.name,'Cash customer') party, COALESCE(p.gstin,'') gstin,
                              i.taxable, i.cgst, i.sgst, i.igst, i.round_off, i.total FROM invoices i LEFT JOIN parties p ON p.id=i.party_id
                              WHERE i.date BETWEEN ? AND ? ORDER BY i.date, i.id
            """).all(f, t)
            : try db.prepare("""
            SELECT u.id, u.date, u.purchase_no no, COALESCE(u.supplier_invoice_no,'') ref, p.name party, COALESCE(p.gstin,'') gstin,
                              u.taxable, u.cgst, u.sgst, u.igst, u.round_off, u.total FROM purchases u JOIN parties p ON p.id=u.party_id
                              WHERE u.date BETWEEN ? AND ? ORDER BY u.date, u.id
            """).all(f, t)
        func sum(_ k: String) -> Double { r2(rows.reduce(0.0) { $0 + $1.n(k) }) }
        return ["type": type == "debit" ? "debit" : isSales ? "sales" : "purchase", "from": f, "to": t, "rows": rows,
                "totals": ["count": rows.count, "taxable": sum("taxable"), "cgst": sum("cgst"), "sgst": sum("sgst"), "igst": sum("igst"),
                           "round_off": sum("round_off"), "total": sum("total")] as Row]
    }

    /// All bills: sales and purchases together, filterable.
    static func bills(_ db: Database, type: String, from: Any?, to: Any?, q: Any?, unpaid: Bool, unprinted: Bool = false, fy fyLabel: Any?) throws -> Row {
        let fy = try FY.range(fyLabel)
        let f = clamp(JS.truthy(from) ? JS.string(unwrap(from)) : fy.from, fy), t = clamp(JS.truthy(to) ? JS.string(unwrap(to)) : fy.to, fy)
        let like = "%\(JS.trim(JS.truthy(q) ? JS.string(unwrap(q)) : ""))%"
        var parts: [String] = []
        if type != "PURCHASE" && type != "DEBIT_NOTE" {
            parts.append("""
            SELECT 'SALE' type, i.id, i.date, i.invoice_no no, '' ref, COALESCE(p.name,'Cash customer') party, i.total, i.paid, i.printed
                            FROM invoices i LEFT JOIN parties p ON p.id=i.party_id WHERE i.date BETWEEN @f AND @t
                            AND (i.invoice_no LIKE @q OR COALESCE(p.name,'Cash customer') LIKE @q)
            """)
        }
        if type != "SALE" && type != "DEBIT_NOTE" {
            parts.append("""
            SELECT 'PURCHASE' type, u.id, u.date, u.purchase_no no, COALESCE(u.supplier_invoice_no,'') ref, p.name party, u.total, u.paid, 1 printed
                            FROM purchases u JOIN parties p ON p.id=u.party_id WHERE u.date BETWEEN @f AND @t
                            AND (u.purchase_no LIKE @q OR COALESCE(u.supplier_invoice_no,'') LIKE @q OR p.name LIKE @q)
            """)
        }
        // goods returned to suppliers: nothing is due on a debit note, so paid = total
        if type == "ALL" || type == "DEBIT_NOTE" {
            parts.append("""
            SELECT 'DEBIT_NOTE' type, d.id, d.date, d.note_no no, COALESCE(d.against_bill,'') ref, p.name party, d.total, d.total paid, 1 printed
                            FROM debit_notes d JOIN parties p ON p.id=d.party_id WHERE d.date BETWEEN @f AND @t
                            AND (d.note_no LIKE @q OR COALESCE(d.against_bill,'') LIKE @q OR p.name LIKE @q)
            """)
        }
        var sql = "SELECT * FROM (\(parts.joined(separator: " UNION ALL ")))"
        var cond: [String] = []
        if unpaid { cond.append("total - paid > 0.5") }
        if unprinted { cond.append("printed = 0") }
        if !cond.isEmpty { sql += " WHERE " + cond.joined(separator: " AND ") }
        sql += " ORDER BY date DESC, id DESC LIMIT 1000"
        let rows = try db.prepare(sql).all(["f": f, "t": t, "q": like] as [String: Any])
        func total(_ ty: String) -> Double { r2(rows.filter { $0.str("type") == ty }.reduce(0.0) { $0 + $1.n("total") }) }
        return ["rows": rows, "totals": ["sales": total("SALE"), "purchases": total("PURCHASE"), "debit_notes": total("DEBIT_NOTE"),
                                         "due": r2(rows.reduce(0.0) { $0 + ($1.n("total") - $1.n("paid")) })] as Row]
    }
}
