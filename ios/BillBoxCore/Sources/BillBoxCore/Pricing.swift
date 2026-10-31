import Foundation

// backend/src/services/pricing.js — set retail / wholesale prices from the MRP for many items at once.
// Selling prices are kept per piece WITHOUT GST; the MRP is per piece WITH GST. A price meant to include GST is divided by
// (1 + GST%) before it is stored, to 8 decimals, so a whole box always comes back to exactly the price that was set.
enum Pricing {
    static func r8(_ n: Double) -> Double { JS.round((n + JS.EPSILON) * 1e8) / 1e8 }
    static func boxOf(_ it: Row) -> Int { let v = JS.number(it["pcs_per_box"] ?? nil); return v.isFinite && v >= 1 ? Int(v) : 1 }
    static func gstOf(_ it: Row) -> Double { let v = JS.number(it["gst_rate"] ?? nil); return v.isFinite ? v : 0 }

    /// What one box comes to on a bill at this ex-GST piece rate: billing's own arithmetic (same state, no discount).
    static func billForBox(_ it: Row, _ rate: Double) -> Double {
        let gross = r2(rate * Double(boxOf(it)))
        let t = splitTax(gross, gstOf(it), true)
        return JS.round(r2(gross + t.cgst + t.sgst + t.igst))
    }

    static func roundTo(_ v: Double, _ round: String) -> Double {
        if round == "none" || (round == "auto" && v < 50) { return r2(v) }
        let step = round == "auto" ? 1 : (Double(round) ?? 1)
        return JS.round(v / step + 1e-9) * step
    }

    static func blankish(_ v: Any?) -> Bool { unwrap(v) == nil || JS.trim(JS.string(unwrap(v))).isEmpty }

    static func setPrices(_ db: Database, _ b: Row) throws -> Row {
        let mode = JS.string(unwrap(b["mode"] ?? nil) ?? "") == "table" ? "table" : "percent"
        let rv = unwrap(b["round"] ?? nil).map { JS.string($0) } ?? ""
        let round = ["auto", "none", "1", "5", "10"].contains(rv) ? rv : "auto"
        func pct(_ v: Any?, _ label: String) throws -> Double? {
            if blankish(v) { return nil }
            let n = JS.number(unwrap(v))
            if !n.isFinite || n < 0 || n >= 100 { throw HttpError(400, "\(label) must be a percentage from 0 to 99.99") }
            return n
        }
        func money(_ v: Any?, _ label: String) throws -> Double? {
            if blankish(v) { return nil }
            let n = JS.number(JS.string(unwrap(v)).replacingOccurrences(of: ",", with: ""))
            if !n.isFinite || n < 0 { throw HttpError(400, "\(label) must be a number (0 or more)") }
            return n
        }
        var retailOff: Double? = nil, wholesaleOff: Double? = nil
        var tiers: [(mrp: Double, retail: Double?, wholesale: Double?)] = []
        if mode == "percent" {
            retailOff = try pct(b["retail_off"] ?? nil, "Retail % below MRP")
            wholesaleOff = try pct(b["wholesale_off"] ?? nil, "Wholesale % below MRP")
            if retailOff == nil && wholesaleOff == nil { throw HttpError(400, "Enter the retail and/or wholesale % below MRP") }
        } else {
            for any in (b["tiers"] as? [Any]) ?? [] {
                let t = (any as? Row) ?? [:]
                let mrp = try money(t["mrp"] ?? nil, "MRP")
                guard let mrp, mrp > 0 else { throw HttpError(400, "Each row needs an MRP") }
                let ms = JS.numberString(mrp)
                let r = try money(t["retail"] ?? nil, "Retail price for MRP \(ms)"), w = try money(t["wholesale"] ?? nil, "Wholesale price for MRP \(ms)")
                if r != nil || w != nil { tiers.append((mrp, r, w)) }
            }
            if tiers.isEmpty { throw HttpError(400, "Enter a retail and/or wholesale price for at least one MRP") }
        }
        let perBox = JS.string(unwrap(b["per"] ?? nil) ?? "box").lowercased() != "piece"
        let iv = unwrap(b["include_gst"] ?? nil)
        let inclGst = !((iv as? Bool) == false || (iv as? String) == "0" || (iv as? String) == "false")
        let catId: Int? = JS.truthy(b["category_id"] ?? nil) ? Int(JS.number(unwrap(b["category_id"] ?? nil))) : nil
        let onlyIds = ((b["item_ids"] as? [Any]) ?? []).map { JS.number($0) }
        let only: [Double]? = onlyIds.isEmpty ? nil : onlyIds

        let rows = try db.prepare("""
            SELECT id,name,mrp,gst_rate,pcs_per_box,retail_price,wholesale_price FROM items
                WHERE active=1 AND (? IS NULL OR category_id=?) ORDER BY name, id
            """).all(catId, catId).filter { it in only == nil || only!.contains(Double(it.i("id"))) }

        func fromBoxIncl(_ it: Row, _ box: Double) -> Double { r8(box / Double(boxOf(it)) / (1 + gstOf(it) / 100)) }
        func fromPercent(_ it: Row, _ off: Double) -> Double {
            let unit = Double(boxOf(it) > 1 ? boxOf(it) : 1)
            return fromBoxIncl(it, roundTo(it.n("mrp") * unit * (1 - off / 100), round))
        }
        func fromTyped(_ it: Row, _ v: Double) -> Double {
            let perPiece = perBox ? v / Double(boxOf(it)) : v
            return r8(inclGst ? perPiece / (1 + gstOf(it) / 100) : perPiece)
        }

        var out: [Row] = []
        var skipped = 0
        for it in rows {
            if !(it.n("mrp") > 0) { skipped += 1; continue }
            var newRetail: Double? = nil, newWholesale: Double? = nil
            if mode == "percent" {
                if let o = retailOff { newRetail = fromPercent(it, o) }
                if let o = wholesaleOff { newWholesale = fromPercent(it, o) }
            } else {
                guard let t = tiers.first(where: { abs($0.mrp - it.n("mrp")) < 0.005 }) else { continue }
                if let v = t.retail { newRetail = fromTyped(it, v) }
                if let v = t.wholesale { newWholesale = fromTyped(it, v) }
            }
            let box = Double(boxOf(it)), g = gstOf(it), mrpBox = it.n("mrp") * box
            var c: Row = ["id": it.i("id"), "name": it.str("name"), "pcs_per_box": boxOf(it), "gst_rate": g, "mrp": it["mrp"]!, "mrp_box": r2(mrpBox)]
            for (k, nv) in [("retail", newRetail), ("wholesale", newWholesale)] {
                guard let nv else { continue }
                let old = it.n("\(k)_price")
                c["\(k)_old"] = it["\(k)_price"]!
                c["\(k)_old_bill"] = billForBox(it, old)
                c["\(k)_new"] = nv
                c["\(k)_box"] = r2(nv * box * (1 + g / 100))
                c["\(k)_bill"] = billForBox(it, nv)
                c["\(k)_below_pct"] = r2((1 - billForBox(it, nv) / mrpBox) * 100)
            }
            out.append(c)
        }
        let preview = JS.truthy(b["preview"] ?? nil)
        if !preview {
            let ur = db.prepare("UPDATE items SET retail_price=? WHERE id=?"), uw = db.prepare("UPDATE items SET wholesale_price=? WHERE id=?")
            try db.transaction {
                for c in out {
                    if c["retail_new"] != nil { try ur.run(c["retail_new"]!, c.i("id")) }
                    if c["wholesale_new"] != nil { try uw.run(c["wholesale_new"]!, c.i("id")) }
                }
            }
        }
        return ["mode": mode, "round": round, "updated": preview ? 0 : out.count, "would_update": out.count, "skipped_no_mrp": skipped,
                "items": Array(out.prefix(500))]
    }

    /// MRP groups for the price table: piece MRP, how many items, their box sizes and today's prices (GST included).
    static func mrpTable(_ db: Database, _ q: [String: String]) throws -> [Row] {
        let catId: Int? = (q["category_id"] ?? "").isEmpty ? nil : { let v = JS.number(q["category_id"]!); return v.isFinite ? Int(v) : -1 }()
        let rows = try db.prepare("""
            SELECT id,mrp,gst_rate,pcs_per_box,retail_price,wholesale_price FROM items
                WHERE active=1 AND mrp > 0 AND (? IS NULL OR category_id=?) ORDER BY mrp, id
            """).all(catId, catId)
        var groups: [Row] = []
        for it in rows {
            var gi = groups.firstIndex { abs($0.n("mrp") - it.n("mrp")) < 0.005 }
            if gi == nil {
                groups.append(["mrp": it["mrp"]!, "items": 0, "boxes": [Int](), "retail_box": NSNull(), "wholesale_box": NSNull(), "retail_piece": NSNull(), "wholesale_piece": NSNull()])
                gi = groups.count - 1
            }
            var g = groups[gi!]
            g["items"] = g.i("items") + 1
            var boxes = g["boxes"] as! [Int]
            if !boxes.contains(boxOf(it)) { boxes.append(boxOf(it)) }
            g["boxes"] = boxes
            let box = Double(boxOf(it)), k = 1 + gstOf(it) / 100
            let vals: [(String, Double)] = [("retail_box", r2(it.n("retail_price") * box * k)), ("wholesale_box", r2(it.n("wholesale_price") * box * k)),
                                            ("retail_piece", r2(it.n("retail_price") * k)), ("wholesale_piece", r2(it.n("wholesale_price") * k))]
            for (key, v) in vals where unwrap(g[key] ?? nil) == nil || v > g.n(key) { g[key] = v }
            groups[gi!] = g
        }
        return groups.map { g0 in
            var g = g0
            let boxes = (g["boxes"] as! [Int]).sorted()
            g["boxes"] = boxes
            g["mrp_box"] = boxes.count == 1 ? r2(g.n("mrp") * Double(boxes[0])) as Any : NSNull()
            return g
        }
    }
}
