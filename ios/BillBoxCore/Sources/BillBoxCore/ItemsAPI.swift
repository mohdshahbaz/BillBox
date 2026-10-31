import Foundation

// backend/src/routes/items.js

extension Router {
    /// Distributor margin on selling price; retailer margin when buying at wholesale and selling at MRP (MRP includes GST).
    static func withMargins(_ it: Row) -> Row {
        var o = it
        let wholesaleInclGst = it.n("wholesale_price") * (1 + it.n("gst_rate") / 100)
        o["dist_margin_pct"] = it.n("wholesale_price") > 0 ? r2(((it.n("wholesale_price") - it.n("purchase_price")) / it.n("wholesale_price")) * 100) : 0
        o["retailer_margin_pct"] = it.n("mrp") > 0 ? r2(((it.n("mrp") - wholesaleInclGst) / it.n("mrp")) * 100) : 0
        return o
    }

    /// Validates and normalises the editable item fields. Items are identified by name (no SKU or barcode).
    static func cleanItem(_ b: Row, partial: Bool) throws -> Row {
        var o: Row = [:]
        func num(_ k: String, _ label: String, _ minV: Double = 0) throws {
            if !b.defined(k) && partial { return }
            let raw = b[k] ?? nil
            let v: Double
            if !b.defined(k) || raw is NSNull || (raw as? String) == "" { v = 0 } else { v = JS.number(raw) }
            if !v.isFinite || v < minV { throw HttpError(400, "\(label) must be a number\(minV == 0 ? " (0 or more)" : "")") }
            o[k] = v
        }
        if !partial || b.defined("name") {
            let raw = b["name"] ?? nil
            let base = (raw == nil || raw is NSNull) ? "" : JS.string(raw)
            let name = rx("\\s+", "g").replace(JS.trim(base), " ")
            if name.isEmpty { throw HttpError(400, "Item name is required") }
            if name.jsLength > 120 { throw HttpError(400, "Item name is too long (120 characters at most)") }
            o["name"] = name
        }
        try num("mrp", "MRP"); try num("retail_price", "Retail price"); try num("wholesale_price", "Wholesale price"); try num("purchase_price", "Purchase price")
        if b.defined("gst_rate") || !partial {
            let raw = b["gst_rate"] ?? nil
            let g = (!b.defined("gst_rate") || (raw as? String) == "") ? 18 : JS.number(raw)
            if !g.isFinite || g < 0 || g > 40 { throw HttpError(400, "GST rate must be between 0 and 40") }
            o["gst_rate"] = g
        }
        if b.defined("pcs_per_box") || !partial {
            let raw: Any? = JS.truthy(b["pcs_per_box"]) ? b.v("pcs_per_box") : 1
            let p = Foundation.floor(JS.number(raw))
            if !p.isFinite || p < 1 || p > 100000 { throw HttpError(400, "Pieces per box must be 1 or more") }
            o["pcs_per_box"] = p
        }
        o["unit"] = "PCS"   // everything is stored in pieces; boxes are worked out from pieces-per-box
        if b.defined("hsn") || !partial {
            let h2: String? = JS.blank(b["hsn"] ?? nil) == nil ? nil : JS.trim(JS.string(b.v("hsn")))
            if let h = h2, !h.isEmpty, !rx("^\\d{2,8}$").test(h) { throw HttpError(400, "HSN code must be 2 to 8 digits") }
            o["hsn"] = h2.map { $0 as Any } ?? NSNull()
        }
        if b.defined("category_id") || !partial { o["category_id"] = JS.blank(b["category_id"] ?? nil) ?? NSNull() }
        return o
    }

    static func assertNameFree(_ db: Database, _ name: String, _ exceptId: Int? = nil) throws {
        if try db.prepare("SELECT id FROM items WHERE active=1 AND lower(name)=lower(?) AND id <> ?").get(name, exceptId ?? 0) != nil {
            throw HttpError(409, "An item named \"\(name)\" already exists", "DUPLICATE")
        }
    }

    func categories(_ db: Database) throws -> Any { try db.prepare("SELECT * FROM categories ORDER BY name").all() }

    func addCategory(_ db: Database, _ b: Row) throws -> Reply {
        guard JS.blank(b["name"] ?? nil) != nil else { throw HttpError(400, "Category name is required") }
        let name = JS.trim(JS.string(b.v("name")))
        let id = try db.prepare("INSERT INTO categories(name) VALUES(?)").run(name).lastInsertRowid
        return .json(201, ["id": id, "name": name] as Row)
    }

    func listItems(_ db: Database, _ q: [String: String]) throws -> Any {
        let like = "%\(JS.trim(q["q"] ?? ""))%"
        let cat: Any? = (q["category_id"].map { !$0.isEmpty } ?? false) ? JS.number(q["category_id"]!) : nil
        let rows = try db.prepare("""
        SELECT i.*, c.name category,
               COALESCE(s.stock,0) stock, s.next_expiry
             FROM items i LEFT JOIN categories c ON c.id=i.category_id
             LEFT JOIN (SELECT item_id, SUM(qty) stock, MIN(CASE WHEN qty>0 AND exp_date < '2099-01-01' THEN exp_date END) next_expiry
                        FROM batches GROUP BY item_id) s ON s.item_id=i.id
             WHERE i.active=1 AND (i.name LIKE ? OR COALESCE(i.hsn,'') LIKE ?) AND (? IS NULL OR i.category_id = ?)
             ORDER BY i.name LIMIT ?
        """).all(like, like, cat, cat, q["all"] == "1" ? -1 : 1000)
        return rows.map(Router.withMargins)
    }

    func addItem(_ db: Database, _ b: Row) async throws -> Reply {
        var o = try Router.cleanItem(b, partial: false)
        try Router.assertNameFree(db, o.str("name"))
        if let pk = PDFParser.packFromName(o.str("name")) { o["pcs_per_box"] = pk }   // "(1X144)" in the name = 144 pieces per box
        // no category chosen: work it out from the name (rules, then the internet)
        if !JS.truthy(o["category_id"]) {
            let g = await Category.guess(o.str("name"))
            if let n = g.name { o["category_id"] = try Category.ensure(db, n) }
        }
        let id = try db.prepare("""
        INSERT INTO items(name,category_id,hsn,gst_rate,unit,mrp,retail_price,wholesale_price,purchase_price,pcs_per_box)
             VALUES(@name,@category_id,@hsn,@gst_rate,@unit,@mrp,@retail_price,@wholesale_price,@purchase_price,@pcs_per_box)
        """).run(o).lastInsertRowid
        return .json(201, ["id": id] as Row)
    }

    func updateItem(_ db: Database, _ id: String, _ b: Row) throws -> Any {
        guard let cur = try db.prepare("SELECT * FROM items WHERE id=?").get(id) else { throw HttpError(404, "Item not found") }
        var o = cur
        for (k, v) in try Router.cleanItem(b, partial: true) { o[k] = v }
        try Router.assertNameFree(db, o.str("name"), cur.i("id"))
        if let pk = PDFParser.packFromName(o.str("name")) { o["pcs_per_box"] = pk }
        o["id"] = cur["id"]
        try db.prepare("""
        UPDATE items SET name=@name,category_id=@category_id,hsn=@hsn,gst_rate=@gst_rate,unit=@unit,mrp=@mrp,retail_price=@retail_price,
               wholesale_price=@wholesale_price,purchase_price=@purchase_price,pcs_per_box=@pcs_per_box WHERE id=@id
        """).run(o)
        return ["ok": true] as Row
    }

    /// Fills the category of every uncategorised item from its name.
    func autoCategorize(_ db: Database) async throws -> Any {
        // pinned names (e.g. Bikano All Time Mix) are moved even when another category was chosen earlier
        var moved = 0
        for it in try db.prepare("SELECT id,name,category_id FROM items WHERE active=1").all() {
            guard let pin = Category.pinned(it.s("name")) else { continue }
            let cid = try Category.ensure(db, pin)
            if !it.has("category_id") || it.i("category_id") != cid {
                try db.prepare("UPDATE items SET category_id=? WHERE id=?").run(cid, it.v("id"))
                moved += 1
            }
        }
        let rows = try db.prepare("SELECT id,name FROM items WHERE active=1 AND category_id IS NULL").all()
        var done = 0, net = 0
        for it in rows {
            let g = await Category.guess(it.str("name"))
            if let n = g.name {
                try db.prepare("UPDATE items SET category_id=? WHERE id=?").run(try Category.ensure(db, n), it.v("id"))
                done += 1
                if g.source == "internet" { net += 1 }
            }
        }
        return ["checked": rows.count, "categorised": done + moved, "from_internet": net] as Row
    }

    /// Reads the MRP printed in the item name for every item that has none; items with no selling prices get MRP without GST.
    func autoMRP(_ db: Database) throws -> Any {
        let rows = try db.prepare("SELECT i.id,i.name,i.gst_rate,i.retail_price,i.wholesale_price,COALESCE(c.name,'Uncategorised') category FROM items i LEFT JOIN categories c ON c.id=i.category_id WHERE i.active=1 AND COALESCE(i.mrp,0)<=0").all()
        var byCat: [String: Row] = [:]
        var missing: [Row] = []
        try db.transaction {
            for it in rows {
                let cat = it.str("category")
                var g = byCat[cat] ?? ["found": 0, "missing": 0]
                guard let mrp = PDFParser.mrpFromName(it.s("name")) else {
                    g["missing"] = g.i("missing") + 1
                    byCat[cat] = g
                    missing.append(["id": it["id"]!, "name": it["name"]!, "category": it["category"]!])
                    continue
                }
                let gst = JS.truthy(it["gst_rate"]) ? it.n("gst_rate") : 0
                let ex = JS.round((mrp / (1 + gst / 100) + JS.EPSILON) * 1e6) / 1e6
                try db.prepare("UPDATE items SET mrp=?, retail_price=CASE WHEN COALESCE(retail_price,0)<=0 THEN ? ELSE retail_price END, wholesale_price=CASE WHEN COALESCE(wholesale_price,0)<=0 THEN ? ELSE wholesale_price END WHERE id=?")
                    .run(mrp, ex, ex, it.v("id"))
                g["found"] = g.i("found") + 1
                byCat[cat] = g
            }
        }
        let found = byCat.values.reduce(0) { $0 + $1.i("found") }
        return ["checked": rows.count, "found": found, "still_missing": missing.count, "by_category": byCat, "missing": Array(missing.prefix(50))] as Row
    }

    static func boxOf(_ it: Row) -> Double {
        let p = JS.parseInt(it["pcs_per_box"] ?? nil)
        return max(1, (p.isNaN || p == 0) ? 1 : p)
    }

    /// Selling prices for every item of a category from its MRP: price = MRP / (1 + GST%) x (1 - off%).
    func bulkPrices(_ db: Database, _ b: Row) throws -> Any {
        let catId: Any? = JS.truthy(b["category_id"]) ? JS.number(b.v("category_id")) : nil
        func parse(_ v: Any?, _ label: String) throws -> Double? {
            guard let u = unwrap(v), !JS.trim(JS.string(u)).isEmpty else { return nil }
            let n = JS.number(u)
            if !n.isFinite || n < 0 || n >= 100 { throw HttpError(400, "\(label) must be a percentage from 0 to 99.99") }
            return n
        }
        let retailOff = try parse(b["retail_off"] ?? nil, "Retail below MRP"), wholesaleOff = try parse(b["wholesale_off"] ?? nil, "Wholesale below MRP")
        if retailOff == nil && wholesaleOff == nil { throw HttpError(400, "Enter the retail and/or wholesale percentage below MRP") }
        let rows = try db.prepare("SELECT id,name,mrp,gst_rate,pcs_per_box,retail_price,wholesale_price FROM items WHERE active=1 AND (? IS NULL OR category_id=?) ORDER BY name").all(catId, catId)
        func gstOf(_ it: Row) -> Double { JS.truthy(it["gst_rate"]) ? it.n("gst_rate") : 0 }
        // The percentage is usually typed rounded (16.67 for 16.666...), so for items packed in boxes the whole box (GST included)
        // is rounded to the nearest rupee first, and the piece price is that box price divided out.
        func price(_ it: Row, _ off: Double) -> Double {
            let perPieceIncl = it.n("mrp") * (1 - off / 100)
            let ppb = Router.boxOf(it)
            let incl = ppb > 1 ? JS.round(perPieceIncl * ppb + JS.EPSILON) / ppb : perPieceIncl
            return JS.round((incl / (1 + gstOf(it) / 100) + JS.EPSILON) * 1e8) / 1e8
        }
        func boxIncl(_ it: Row, _ v: Double) -> Double { r2(v * Router.boxOf(it) * (1 + gstOf(it) / 100)) }
        var changes: [Row] = []
        var skipped = 0
        for it in rows {
            if !(it.n("mrp") > 0) { skipped += 1; continue }
            var c: Row = ["id": it["id"]!, "name": it["name"]!, "mrp": it["mrp"]!]
            if let r = retailOff { let nv = price(it, r); c["retail_old"] = it["retail_price"]!; c["retail_new"] = nv; c["retail_box"] = boxIncl(it, nv) }
            if let w = wholesaleOff { let nv = price(it, w); c["wholesale_old"] = it["wholesale_price"]!; c["wholesale_new"] = nv; c["wholesale_box"] = boxIncl(it, nv) }
            changes.append(c)
        }
        let preview = JS.truthy(b["preview"])
        if !preview {
            try db.transaction {
                for c in changes {
                    if c.defined("retail_new") { try db.prepare("UPDATE items SET retail_price=? WHERE id=?").run(c.n("retail_new"), c.v("id")) }
                    if c.defined("wholesale_new") { try db.prepare("UPDATE items SET wholesale_price=? WHERE id=?").run(c.n("wholesale_new"), c.v("id")) }
                }
            }
        }
        return ["updated": preview ? 0 : changes.count, "would_update": changes.count, "skipped_no_mrp": skipped, "sample": Array(changes.prefix(5))] as Row
    }

    /// Re-reads the pieces-per-box of every item from its name.
    func fixPacks(_ db: Database) throws -> Any {
        var changed = 0, checked = 0
        for it in try db.prepare("SELECT id,name,pcs_per_box FROM items WHERE active=1").all() {
            guard let pk = PDFParser.packFromName(it.s("name")) else { continue }
            checked += 1
            if it.n("pcs_per_box") != Double(pk) { try db.prepare("UPDATE items SET pcs_per_box=? WHERE id=?").run(pk, it.v("id")); changed += 1 }
        }
        return ["checked": checked, "changed": changed] as Row
    }

    func mrpGroups(_ db: Database, _ q: [String: String]) throws -> Any {
        let catId: Any? = (q["category_id"].map { !$0.isEmpty } ?? false) ? JS.number(q["category_id"]!) : nil
        return try db.prepare("""
        SELECT mrp, COUNT(*) items, MIN(retail_price) retail_min, MAX(retail_price) retail_max, MIN(wholesale_price) wholesale_min, MAX(wholesale_price) wholesale_max,
                    MIN(gst_rate) gst_min, MAX(gst_rate) gst_max,
                    MAX(retail_price * (1 + COALESCE(gst_rate,0) / 100.0)) retail_incl_max,
                    MAX(retail_price * MAX(1, COALESCE(pcs_per_box,1))) retail_box_max,
                    MAX(retail_price * MAX(1, COALESCE(pcs_per_box,1)) * (1 + COALESCE(gst_rate,0) / 100.0)) retail_box_incl_max,
                    MAX(wholesale_price * (1 + COALESCE(gst_rate,0) / 100.0)) wholesale_incl_max,
                    MAX(wholesale_price * MAX(1, COALESCE(pcs_per_box,1))) wholesale_box_max,
                    MAX(wholesale_price * MAX(1, COALESCE(pcs_per_box,1)) * (1 + COALESCE(gst_rate,0) / 100.0)) wholesale_box_incl_max
             FROM items WHERE active=1 AND mrp > 0 AND (? IS NULL OR category_id=?) GROUP BY mrp ORDER BY mrp
        """).all(catId, catId)
    }

    /// Price list by MRP: for each MRP value the retail and wholesale price per piece that every item with that MRP gets.
    func bulkPricesByMRP(_ db: Database, _ b: Row) throws -> Any {
        let catId: Any? = JS.truthy(b["category_id"]) ? JS.number(b.v("category_id")) : nil
        var tiers: [(mrp: Double, retail: Double?, wholesale: Double?)] = []
        for tAny in (b["tiers"] as? [Any]) ?? [] {
            let t = (tAny as? Row) ?? [:]
            func num(_ v: Any?, _ label: String) throws -> Double? {
                guard let u = unwrap(v), !JS.trim(JS.string(u)).isEmpty else { return nil }
                let n = JS.number(u)
                if !n.isFinite || n < 0 { throw HttpError(400, "\(label) must be a number (0 or more)") }
                return n
            }
            let mrp = try num(t["mrp"] ?? nil, "MRP")
            guard let m = mrp, m > 0 else { throw HttpError(400, "Each row needs an MRP") }
            let tier = (m, try num(t["retail"] ?? nil, "Retail price for MRP \(JS.numberString(m))"), try num(t["wholesale"] ?? nil, "Wholesale price for MRP \(JS.numberString(m))"))
            if tier.1 != nil || tier.2 != nil { tiers.append(tier) }
        }
        if tiers.isEmpty { throw HttpError(400, "Enter a retail and/or wholesale price for at least one MRP") }
        let items = try db.prepare("SELECT id,name,mrp,gst_rate,pcs_per_box,retail_price,wholesale_price FROM items WHERE active=1 AND mrp>0 AND (? IS NULL OR category_id=?)").all(catId, catId)
        // prices are kept to 8 decimals: 2500 per box of 300 is 8.33333333 a piece, so a whole box comes back to exactly 2500
        func r6(_ n: Double) -> Double { JS.round((n + JS.EPSILON) * 1e8) / 1e8 }
        let perBox = (JS.truthy(b["per"]) ? JS.string(b.v("per")) : "piece").lowercased() == "box"
        let inclGst = JS.truthy(b["include_gst"])
        func ppbOf(_ it: Row) -> Double { max(1, JS.truthy(it["pcs_per_box"]) ? it.n("pcs_per_box") : 1) }
        func gstOf(_ it: Row) -> Double { JS.truthy(it["gst_rate"]) ? it.n("gst_rate") : 0 }
        func exGst(_ it: Row, _ v: Double) -> Double { r6((inclGst ? v / (1 + gstOf(it) / 100) : v) / (perBox ? ppbOf(it) : 1)) }
        var changes: [Row] = []
        var perTier: [Row] = tiers.map { ["mrp": $0.mrp, "items": 0] }
        for it in items {
            guard let ti = tiers.firstIndex(where: { abs($0.mrp - it.n("mrp")) < 0.005 }) else { continue }
            let t = tiers[ti]
            perTier[ti]["items"] = perTier[ti].i("items") + 1
            var c: Row = ["id": it["id"]!, "name": it["name"]!, "mrp": it["mrp"]!]
            if let r = t.retail { let nv = exGst(it, r); c["retail_old"] = it["retail_price"]!; c["retail_new"] = nv; c["retail_box"] = r2(nv * ppbOf(it) * (1 + gstOf(it) / 100)) }
            if let w = t.wholesale { let nv = exGst(it, w); c["wholesale_old"] = it["wholesale_price"]!; c["wholesale_new"] = nv; c["wholesale_box"] = r2(nv * ppbOf(it) * (1 + gstOf(it) / 100)) }
            changes.append(c)
        }
        let preview = JS.truthy(b["preview"])
        if !preview {
            try db.transaction {
                for c in changes {
                    if c.defined("retail_new") { try db.prepare("UPDATE items SET retail_price=? WHERE id=?").run(c.n("retail_new"), c.v("id")) }
                    if c.defined("wholesale_new") { try db.prepare("UPDATE items SET wholesale_price=? WHERE id=?").run(c.n("wholesale_new"), c.v("id")) }
                }
            }
        }
        return ["updated": preview ? 0 : changes.count, "would_update": changes.count, "per_mrp": perTier, "sample": Array(changes.prefix(5))] as Row
    }

    /// Items that were ever sold or bought are archived (history stays intact); unused items are removed.
    func deleteItem(_ db: Database, _ id: String, _ q: [String: String]) throws -> Any {
        guard let it = try db.prepare("SELECT * FROM items WHERE id=?").get(id) else { throw HttpError(404, "Item not found") }
        let used = try db.prepare("SELECT (SELECT COUNT(*) FROM invoice_lines WHERE item_id=@i) + (SELECT COUNT(*) FROM purchase_lines WHERE item_id=@i) + (SELECT COUNT(*) FROM debit_note_lines WHERE item_id=@i) n").get(["i": it["id"]!] as Row)!.n("n")
        let stock = try db.prepare("SELECT COALESCE(SUM(qty),0) n FROM batches WHERE item_id=?").get(it.v("id"))!.n("n")
        if stock > 0 && !JS.truthy(q["force"]) { throw HttpError(409, "\(it.str("name")) still has \(JS.numberString(stock)) units in stock. Sell or adjust the stock first.", "HAS_STOCK") }
        if used != 0 { try db.prepare("UPDATE items SET active=0 WHERE id=?").run(it.v("id")); return ["result": "archived"] as Row }
        try db.transaction {
            try db.prepare("DELETE FROM schemes WHERE item_id=?").run(it.v("id"))
            try db.prepare("DELETE FROM batches WHERE item_id=?").run(it.v("id"))
            try db.prepare("DELETE FROM items WHERE id=?").run(it.v("id"))
        }
        return ["result": "deleted"] as Row
    }

    /// Stock in (opening stock / add stock).
    func addBatch(_ db: Database, _ bIn: Row) throws -> Reply {
        var b = bIn
        if !JS.truthy(b["item_id"]) { throw HttpError(400, "Choose the item") }
        b["batch_no"] = JS.blank(b["batch_no"] ?? nil) ?? "OPENING"
        b["exp_date"] = JS.blank(b["exp_date"] ?? nil) ?? "2099-12-31"
        let qty = JS.parseInt(b["qty"] ?? nil)
        if !(qty > 0) { throw HttpError(400, "Quantity must be greater than zero") }
        func isD(_ v: Any?) -> Bool { isDateRe.test(JS.string(v)) }
        if !isD(b["exp_date"] ?? nil) || (JS.blank(b["mfg_date"] ?? nil) != nil && !isD(b["mfg_date"] ?? nil)) { throw HttpError(400, "Dates must be in YYYY-MM-DD format") }
        try db.prepare("""
        INSERT INTO batches(item_id,batch_no,mfg_date,exp_date,qty,purchase_price,mrp) VALUES(?,?,?,?,?,?,?)
             ON CONFLICT(item_id,batch_no) DO UPDATE SET qty = qty + excluded.qty,
               exp_date = excluded.exp_date, mfg_date = COALESCE(excluded.mfg_date, mfg_date)
        """).run(b.v("item_id"), JS.trim(JS.string(b.v("batch_no"))), JS.blank(b["mfg_date"] ?? nil), b.v("exp_date"), qty,
                 JS.blank(b["purchase_price"] ?? nil), JS.blank(b["mrp"] ?? nil))
        return .json(201, ["ok": true] as Row)
    }

    func listSchemes(_ db: Database) throws -> Any {
        try db.prepare("SELECT s.*, i.name item_name FROM schemes s JOIN items i ON i.id=s.item_id WHERE s.active=1").all()
    }

    func addScheme(_ db: Database, _ b: Row) throws -> Reply {
        let type = b.v("type") as? String
        if type != "FREE_QTY" && type != "PERCENT" { throw HttpError(400, "Scheme type must be FREE_QTY or PERCENT") }
        let buy = JS.parseInt(b["buy_qty"] ?? nil), free = JS.parseInt(b["free_qty"] ?? nil), pct = JS.number(b["percent"] ?? nil)
        try db.prepare("INSERT INTO schemes(item_id,type,buy_qty,free_qty,percent,valid_from,valid_to) VALUES(?,?,?,?,?,?,?)")
            .run(b.v("item_id"), type, (buy.isNaN || buy == 0) ? 1 : buy, (free.isNaN || free == 0) ? 0 : free, (pct.isNaN || pct == 0) ? 0 : pct,
                 JS.blank(b["valid_from"] ?? nil), JS.blank(b["valid_to"] ?? nil))
        return .json(201, ["ok": true] as Row)
    }

    func deleteScheme(_ db: Database, _ id: String) throws -> Any {
        try db.prepare("UPDATE schemes SET active=0 WHERE id=?").run(id)
        return ["ok": true] as Row
    }
}
