import Foundation

/// After a supplier PDF is read: create the supplier and any stock items the bill mentions that are not in the books yet,
/// so the purchase screen opens with every row already linked (backend/src/services/autoCreate.js).
enum AutoCreate {
    static let BOX_UNIT = rx("^(BOX|BOXES|BX|CASE|CS|CTN|CARTON)$", "i")
    static func tidy(_ s: Any?) -> String { JS.trim(rx("\\s+", "g").replace(JS.truthy(s) ? JS.string(unwrap(s)) : "", " ")) }

    static func createMissing(_ db: Database, _ parsedIn: Row, online: Bool = true) async throws -> Row {
        var parsed = parsedIn
        var warnings = (parsed["warnings"] as? [String]) ?? []
        var lines = (parsed["lines"] as? [Row]) ?? []
        var missingOrder: [String] = []
        var missing: [String: Row] = [:]                       // lower-case name -> first line
        for l in lines where !JS.truthy(l["item_id"]) {
            let k = tidy(l["description"] ?? nil).lowercased()
            if !k.isEmpty && missing[k] == nil { missing[k] = l; missingOrder.append(k) }
        }

        // categories need the network, so settle them before the database transaction
        var cats: [String: (name: String?, source: String?)] = [:]
        var i = 0
        while i < missingOrder.count {
            let chunk = Array(missingOrder[i..<min(i + 5, missingOrder.count)])
            await withTaskGroup(of: (String, (String?, String?)).self) { group in
                for k in chunk {
                    let desc = missing[k]!.str("description")
                    group.addTask { (k, await Category.guess(desc, online: online)) }
                }
                for await (k, v) in group { cats[k] = v }
            }
            i += 5
        }

        var createdItems = 0, createdSupplier = false, noBox = 0, noRate = 0, internetCats = 0
        var sup = parsed["supplier"] as? Row
        try db.transaction {
            // supplier
            if var s = sup, JS.truthy(s["name"]), !JS.truthy(s["matched_party_id"]) {
                var p: Row?
                if JS.truthy(s["gstin"]) { p = try db.prepare("SELECT id,name FROM parties WHERE upper(gstin)=? AND active=1").get(s.str("gstin").uppercased()) }
                if p == nil { p = try db.prepare("SELECT id,name FROM parties WHERE lower(name)=lower(?) AND active=1").get(tidy(s["name"] ?? nil)) }
                if p == nil {
                    let mobiles = ((s["mobiles"] as? [Any]) ?? []).map { JS.string($0) }.joined(separator: ", ")
                    func v(_ k: String) -> Any? { JS.truthy(s[k]) ? s.v(k) : nil }
                    let id = try db.prepare("""
                    INSERT INTO parties(name,gstin,state_code,phone,tel,mobiles,address,fssai,pan,email,type,price_tier)
                               VALUES(?,?,?,?,?,?,?,?,?,?,'SUPPLIER','WHOLESALE')
                    """).run(tidy(s["name"] ?? nil), v("gstin"), JS.truthy(s["state_code"]) ? s.v("state_code") : "09", v("phone"), v("tel"),
                             mobiles.isEmpty ? nil : mobiles, v("address"), v("fssai"), v("pan"), v("email")).lastInsertRowid
                    p = ["id": id, "name": tidy(s["name"] ?? nil)]
                    createdSupplier = true
                }
                s["matched_party_id"] = p!["id"]
                s["matched_name"] = p!["name"]
                s["created"] = createdSupplier
                sup = s
            }

            // items
            var made: [String: Row] = [:]
            for idx in lines.indices {
                var l = lines[idx]
                if JS.truthy(l["item_id"]) { continue }
                let name = tidy(l["description"] ?? nil), k = name.lowercased()
                if name.isEmpty { continue }
                var it = made[k]
                if it == nil { it = try db.prepare("SELECT id,name FROM items WHERE active=1 AND lower(name)=lower(?)").get(name) }
                if it == nil {
                    let unit = JS.truthy(l["unit"]) ? l.str("unit") : ""
                    let ppbV = JS.truthy(l["pcs_per_box"]) ? l.n("pcs_per_box") : 1
                    if BOX_UNIT.test(unit) && !JS.truthy(l["pcs_per_box"]) { noBox += 1 }
                    let gst = l.has("gst_rate") ? l.n("gst_rate") : 18
                    if !l.has("gst_rate") { noRate += 1 }
                    let perPiece = BOX_UNIT.test(unit) ? r2(l.n("rate") / ppbV) : l.n("rate")          // cost of one piece
                    let mrp = JS.truthy(l["mrp"]) ? l.n("mrp") : 0
                    let sell = mrp != 0 ? r2(mrp / (1 + gst / 100)) : 0                                    // MRP without GST
                    let c = cats[k]
                    let catId = try Category.ensure(db, c?.name ?? nil)
                    if c?.source == "internet" { internetCats += 1 }
                    let id = try db.prepare("""
                    INSERT INTO items(name,category_id,hsn,gst_rate,unit,mrp,retail_price,wholesale_price,purchase_price,pcs_per_box)
                               VALUES(?,?,?,?,'PCS',?,?,?,?,?)
                    """).run(name, catId, JS.truthy(l["hsn"]) ? l.v("hsn") : nil, gst, mrp, sell, sell, perPiece, ppbV).lastInsertRowid
                    it = ["id": id, "name": name]
                    made[k] = it
                    createdItems += 1
                    l["category"] = (c?.name).map { $0 as Any } ?? NSNull()
                }
                l["item_id"] = it!["id"]
                l["item_name"] = it!["name"]
                l["match_confidence"] = 1
                l["created"] = true
                lines[idx] = l
            }
        }

        // the "not matched" warning no longer applies; say what was done instead
        if let wi = warnings.firstIndex(where: { rx("not matched to your stock list").test($0) }) { warnings.remove(at: wi) }
        let supName = (parsed["supplier"] as? Row)?.str("name") ?? ""
        if createdSupplier { warnings.insert("Supplier \"\(supName)\" was added to Parties.", at: 0) }
        if createdItems > 0 {
            warnings.insert("\(createdItems) new item\(createdItems > 1 ? "s" : "") added to Stock with HSN, GST rate, pieces per box and category taken from the bill\(internetCats > 0 ? " (\(internetCats) categories found on the internet)" : ""). Selling prices were set to MRP without GST; adjust them in Stock.", at: 0)
        }
        if noBox > 0 { warnings.append("\(noBox) item(s) are bought in boxes but the pieces per box were not in the name; set it in Stock.") }
        if noRate > 0 { warnings.append("\(noRate) item(s) had no GST rate on the bill; 18% was assumed. Check it in Stock.") }
        parsed["warnings"] = warnings
        parsed["lines"] = lines
        if let sup { parsed["supplier"] = sup }
        parsed["created"] = ["items": createdItems, "supplier": createdSupplier] as Row
        return parsed
    }
}
