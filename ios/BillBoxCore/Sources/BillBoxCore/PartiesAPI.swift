import Foundation

// backend/src/routes/parties.js and salesmen.js

extension Router {
    static let BAL_AT = "COALESCE((SELECT SUM(debit)-SUM(credit) FROM ledger l WHERE l.party_id=p.id AND l.date <= @to),0)"
    // utils/partyroutes.js: a party can be on several routes. parties.route_id is the first one, party_routes holds the others.
    /// SQL for "party p is on route r".
    static let ON_ROUTE = "(r.id=p.route_id OR r.id IN (SELECT x.route_id FROM party_routes x WHERE x.party_id=p.id))"
    /// Both in route-name order ("; " between names, as a route's own name has commas; ids as "3,7").
    static let ROUTE_NAMES = "(SELECT group_concat(name, '; ') FROM (SELECT r.name FROM routes r WHERE \(Router.ON_ROUTE) ORDER BY r.name, r.id))"
    static let ROUTE_IDS = "(SELECT group_concat(id) FROM (SELECT r.id FROM routes r WHERE \(Router.ON_ROUTE) ORDER BY r.name, r.id))"

    /// [3, 7] from [3, "7"], "3,7" or 3: whole numbers, no repeats, in the order given.
    static func idList(_ v: Any?) -> [Int] {
        guard let u = unwrap(v) else { return [] }
        let raw: [Any] = (u as? [Any]) ?? JS.string(u).split(separator: ",").map { String($0) as Any }
        var out: [Int] = []
        for x in raw {
            let n = (x as? String).map { JS.number(JS.trim($0)) } ?? JS.number(x)
            guard n.isFinite, n > 0, n < 9e15, n == n.rounded() else { continue }
            if !out.contains(Int(n)) { out.append(Int(n)) }
        }
        return out
    }

    /// A party's routes become `wanted` (those that exist): the first stays in parties.route_id (the one it has now, if kept), the rest in party_routes.
    @discardableResult
    static func setPartyRoutes(_ db: Database, _ pid: Any?, _ wanted: [Int]) throws -> [Int] {
        let have = Set(try db.prepare("SELECT id FROM routes").all().map { $0.i("id") })
        var ids: [Int] = []
        for id in wanted where have.contains(id) && !ids.contains(id) { ids.append(id) }
        guard let cur = try db.prepare("SELECT route_id FROM parties WHERE id=?").get(pid) else { return [] }
        let now: Int? = cur.has("route_id") ? cur.i("route_id") : nil
        let first: Int? = (now != nil && ids.contains(now!)) ? now : ids.first
        if now != first { try db.prepare("UPDATE parties SET route_id=? WHERE id=?").run(first, pid) }
        var kept = Set<Int>()
        for x in try db.prepare("SELECT id, route_id FROM party_routes WHERE party_id=? ORDER BY id").all(pid) {
            let rid = x.i("route_id")
            if rid != first && ids.contains(rid) && !kept.contains(rid) { kept.insert(rid) } else { try db.prepare("DELETE FROM party_routes WHERE id=?").run(x.v("id")) }
        }
        for rid in ids where rid != first && !kept.contains(rid) { try db.prepare("INSERT INTO party_routes(party_id,route_id) VALUES(?,?)").run(pid, rid) }
        return ids
    }

    /// One more route for a party (its first when it has none). false: it is on that route already.
    static func addPartyRoute(_ db: Database, _ pid: Any?, _ rid: Int) throws -> Bool {
        guard let p = try db.prepare("SELECT route_id FROM parties WHERE id=?").get(pid) else { return false }
        if !p.has("route_id") { try db.prepare("UPDATE parties SET route_id=? WHERE id=?").run(rid, pid); return true }
        if p.i("route_id") == rid { return false }
        let there = try db.prepare("SELECT 1 x FROM party_routes WHERE party_id=? AND route_id=?").get(pid, rid)
        if there != nil { return false }
        try db.prepare("INSERT INTO party_routes(party_id,route_id) VALUES(?,?)").run(pid, rid)
        return true
    }

    /// Every route of a party, the first one first.
    static func partyRoutes(_ db: Database, _ pid: Any?) throws -> [Int] {
        var ids: [Int] = []
        if let p = try db.prepare("SELECT route_id FROM parties WHERE id=?").get(pid), p.has("route_id") { ids.append(p.i("route_id")) }
        for x in try db.prepare("SELECT route_id FROM party_routes WHERE party_id=? ORDER BY id").all(pid) {
            let rid = x.i("route_id")
            if !ids.contains(rid) { ids.append(rid) }
        }
        return ids
    }

    /// The routes a save asks for: route_ids (all of them), or the older route_id (changes the first, keeps the others; blank = none); a new_route is added.
    func wantedRoutes(_ db: Database, _ b: Row, _ pid: Any?) throws -> [Int] {
        var made: Int? = nil
        if let nr = b["new_route"] as? Row, JS.blank(nr["name"] ?? nil) != nil {
            let id = try resolveRoute(db, ["new_route": nr] as Row)
            let n = JS.number(id)
            if n.isFinite && n > 0 { made = Int(n) }
        }
        var ids: [Int]
        if b.defined("route_ids") {
            ids = Router.idList(b["route_ids"] ?? nil)
        } else {
            var now: [Int] = []
            if pid != nil { now = try Router.partyRoutes(db, pid) }
            if !b.defined("route_id") || made != nil {
                ids = now
            } else {
                let one = Router.idList(b["route_id"] ?? nil)
                ids = one.isEmpty ? [] : one + Array(now.dropFirst())   // "No route" from an older app clears them all
            }
        }
        if let made { ids.append(made) }
        return ids
    }

    static let PARTY_GSTIN = rx("^\\d{2}[A-Z]{5}\\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$")

    /// ?kind=CUSTOMER | SUPPLIER (default: all). balance > 0 = they owe us, balance < 0 = we owe them.
    func listParties(_ db: Database, _ q: [String: String]) throws -> Any {
        let like = "%\(JS.trim(q["q"] ?? ""))%"
        let kind = q["kind"] == "SUPPLIER" ? "AND p.type = 'SUPPLIER'" : (q["kind"] == "CUSTOMER" ? "AND p.type <> 'SUPPLIER'" : "")
        return try db.prepare("""
        SELECT p.*, \(Router.BAL_AT) balance, \(Router.ROUTE_NAMES) route_name, \(Router.ROUTE_IDS) route_ids FROM parties p
             WHERE p.active=1 \(kind) AND (p.name LIKE @q OR p.phone LIKE @q OR p.gstin LIKE @q OR COALESCE(p.mobiles,'') LIKE @q OR COALESCE(p.tel,'') LIKE @q) ORDER BY p.name
        """).all(["q": like, "to": try FY.range(q["fy"]).to] as Row)
    }

    /// Accepts route_id OR new_route {name, salesman_id, days}: the route is created and assigned in the same transaction.
    func resolveRoute(_ db: Database, _ b: Row) throws -> Any? {
        if let nr = b["new_route"] as? Row, JS.blank(nr["name"] ?? nil) != nil {
            let days = normDays(nr.defined("days") ? nr["days"] ?? nil : nr["day_of_week"] ?? nil)
            let id = try db.prepare("INSERT INTO routes(name,salesman_id,day_of_week,days) VALUES(?,?,?,?)")
                .run(JS.trim(JS.string(nr.v("name"))), JS.blank(nr["salesman_id"] ?? nil), days.map { JS.parseInt($0) }, days).lastInsertRowid
            return id
        }
        return JS.blank(b["route_id"] ?? nil)
    }

    /// Cleans and validates the party fields (shared by add and edit).
    static func cleanParty(_ b: Row, _ cur: Row?) throws -> Row {
        func get(_ k: String) -> Any? { b.defined(k) ? b[k] ?? nil : cur?[k] ?? nil }
        func txt(_ k: String, _ max: Int = 200) -> String? {
            let v = get(k)
            guard JS.blank(v) != nil else { return nil }
            return JS.trim(JS.string(unwrap(v))).jsSlice(0, max)
        }
        var o: Row = [:]
        let rawName = get("name")
        let name = JS.trim(rx("\\s+", "g").replace(JS.trim((rawName == nil || rawName is NSNull) ? "" : JS.string(rawName)), " "))
        if name.isEmpty { throw HttpError(400, "Party name is required") }
        o["name"] = name
        func put(_ k: String, _ v: String?) { o[k] = v.map { $0 as Any } ?? NSNull() }
        put("address", txt("address", 400))
        let gstin = txt("gstin", 15).map { rx("\\s+", "g").replace($0.uppercased(), "") }
        put("gstin", gstin)
        if let g = gstin, !g.isEmpty, !PARTY_GSTIN.test(g) { throw HttpError(400, "GSTIN \"\(g)\" is not valid (15 characters, e.g. 09ABCDE1234F1Z5)") }
        let state = txt("state_code", 2) ?? ((gstin?.isEmpty == false) ? gstin!.jsSlice(0, 2) : nil)
        put("state_code", state)
        if let s = state, !s.isEmpty, !rx("^\\d{2}$").test(s) { throw HttpError(400, "State code must be 2 digits, e.g. 09") }
        var pan = txt("pan", 10) ?? ((gstin?.isEmpty == false) ? gstin!.jsSlice(2, 12) : nil)
        if pan?.isEmpty == true { pan = nil }
        if let p = pan {
            pan = p.uppercased()
            if !rx("^[A-Z]{5}\\d{4}[A-Z]$").test(pan!) { throw HttpError(400, "PAN must look like ABCDE1234F") }
        }
        put("pan", pan)
        let fssai = txt("fssai", 14)
        put("fssai", fssai)
        if let f = fssai, !f.isEmpty, !rx("^\\d{14}$").test(f) { throw HttpError(400, "FSSAI number must be 14 digits") }
        let email = txt("email", 120)
        put("email", email)
        if let e = email, !e.isEmpty, !rx("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$").test(e) { throw HttpError(400, "Email address is not valid") }
        put("tel", txt("tel", 40))
        put("phone", txt("phone", 40))
        let mob = get("mobiles")
        let list: [String]
        if let arr = unwrap(mob) as? [Any] { list = arr.map { JS.trim(JS.string($0)) }.filter { !$0.isEmpty } } else {
            let src = (mob == nil || mob is NSNull) ? "" : JS.string(mob)
            list = rx("[,;\\n]+").split(src).map { JS.trim($0) }.filter { !$0.isEmpty }
        }
        var uniq: [String] = []
        for x in list where !uniq.contains(x) { uniq.append(x) }
        o["mobiles"] = uniq.isEmpty ? NSNull() : uniq.joined(separator: ", ")
        let type = unwrap(get("type")) as? String
        o["type"] = ["RETAILER", "WHOLESALER", "SUPPLIER"].contains(type ?? "") ? type! : "RETAILER"
        let tier = unwrap(get("price_tier")) as? String
        o["price_tier"] = ["RETAIL", "WHOLESALE", "MRP"].contains(tier ?? "") ? tier! : "RETAIL"
        let cl = JS.number(JS.truthy(get("credit_limit")) ? get("credit_limit") : 0)
        let cd = Foundation.floor(JS.number(JS.truthy(get("credit_days")) ? get("credit_days") : 0))
        if !(cl >= 0) || !(cd >= 0) { throw HttpError(400, "Credit limit and credit days cannot be negative") }
        o["credit_limit"] = cl
        o["credit_days"] = cd
        return o
    }

    func addParty(_ db: Database, _ b: Row) throws -> Reply {
        let o = try Router.cleanParty(b, nil)
        let id: Int = try db.transaction {
            let routes = try wantedRoutes(db, b, nil)
            let pid = try db.prepare("""
            INSERT INTO parties(name,gstin,state_code,phone,tel,mobiles,address,fssai,pan,email,type,price_tier,credit_limit,credit_days)
                   VALUES(@name,@gstin,@state_code,@phone,@tel,@mobiles,@address,@fssai,@pan,@email,@type,@price_tier,@credit_limit,@credit_days)
            """).run(o).lastInsertRowid
            try Router.setPartyRoutes(db, pid, routes)
            let ob = JS.number(b["opening_balance"] ?? nil)
            let opening = (ob.isNaN || ob == 0) ? 0 : ob   // positive = they owe us, negative = we owe them
            if opening != 0 {
                try db.prepare("INSERT INTO ledger(party_id,date,type,ref_no,debit,credit,narration) VALUES(?,?,?,?,?,?,?)")
                    .run(pid, today(), "OPENING", "OPENING", opening > 0 ? opening : 0, opening < 0 ? -opening : 0, "Opening balance")
            }
            return pid
        }
        return .json(201, ["id": id] as Row)
    }

    func updateParty(_ db: Database, _ id: String, _ b: Row) throws -> Any {
        guard let cur = try db.prepare("SELECT * FROM parties WHERE id=?").get(id) else { throw HttpError(404, "Party not found") }
        var o = try Router.cleanParty(b, cur)
        try db.transaction {
            let routes = try wantedRoutes(db, b, cur.v("id"))
            o["id"] = cur["id"]
            try db.prepare("""
            UPDATE parties SET name=@name,gstin=@gstin,state_code=@state_code,phone=@phone,tel=@tel,mobiles=@mobiles,address=@address,
                     fssai=@fssai,pan=@pan,email=@email,type=@type,price_tier=@price_tier,credit_limit=@credit_limit,credit_days=@credit_days WHERE id=@id
            """).run(o)
            try Router.setPartyRoutes(db, cur.v("id"), routes)
        }
        return ["ok": true] as Row
    }

    /// A party with any history is archived (hidden, books stay correct); an unused one is removed.
    func deleteParty(_ db: Database, _ id: String) throws -> Any {
        guard let p = try db.prepare("SELECT * FROM parties WHERE id=?").get(id) else { throw HttpError(404, "Party not found") }
        let used = try db.prepare("SELECT (SELECT COUNT(*) FROM ledger WHERE party_id=@i) + (SELECT COUNT(*) FROM invoices WHERE party_id=@i) + (SELECT COUNT(*) FROM purchases WHERE party_id=@i) + (SELECT COUNT(*) FROM debit_notes WHERE party_id=@i) n")
            .get(["i": p["id"]!] as Row)!.n("n")
        if used != 0 { try db.prepare("UPDATE parties SET active=0 WHERE id=?").run(p.v("id")); return ["result": "archived"] as Row }
        try db.transaction {
            try db.prepare("DELETE FROM party_routes WHERE party_id=?").run(p.v("id"))
            try db.prepare("DELETE FROM parties WHERE id=?").run(p.v("id"))
        }
        return ["result": "deleted"] as Row
    }

    /// Selected financial year only; everything before it is carried in as one opening-balance line.
    func ledger(_ db: Database, _ id: String, _ q: [String: String]) throws -> Any {
        guard let party = try db.prepare("SELECT * FROM parties WHERE id=?").get(id) else { throw HttpError(404, "Party not found") }
        let fy = try FY.range(q["fy"])
        let open = r2(try db.prepare("SELECT COALESCE(SUM(debit)-SUM(credit),0) b FROM ledger WHERE party_id=? AND date < ?").get(party.v("id"), fy.from)!.n("b"))
        var run = open
        let rows: [Row] = try db.prepare("SELECT * FROM ledger WHERE party_id=? AND date BETWEEN ? AND ? ORDER BY date, id").all(party.v("id"), fy.from, fy.to).map { r in
            var x = r
            run = r2(run + r.n("debit") - r.n("credit"))
            x["balance"] = run
            return x
        }
        return ["party": party, "fy": fy.label, "opening_balance": open, "balance": run, "entries": rows] as Row
    }

    func receiptsOn(_ db: Database, _ q: [String: String]) throws -> Any {
        try db.prepare("""
        SELECT r.*, p.name party_name, s.name salesman_name FROM receipts r JOIN parties p ON p.id=r.party_id
             LEFT JOIN salesmen s ON s.id=r.salesman_id WHERE r.date=? ORDER BY r.id DESC
        """).all((q["date"]?.isEmpty == false) ? q["date"]! : today())
    }

    // MARK: salesmen and routes

    func listSalesmen(_ db: Database) throws -> Any { try db.prepare("SELECT * FROM salesmen WHERE active=1 ORDER BY name").all() }

    func addSalesman(_ db: Database, _ b: Row) throws -> Reply {
        guard JS.blank(b["name"] ?? nil) != nil else { throw HttpError(400, "Name is required") }
        let t = JS.number(b["monthly_target"] ?? nil)
        let id = try db.prepare("INSERT INTO salesmen(name,phone,monthly_target) VALUES(?,?,?)")
            .run(JS.trim(JS.string(b.v("name"))), JS.blank(b["phone"] ?? nil), (t.isNaN || t == 0) ? 0 : t).lastInsertRowid
        return .json(201, ["id": id] as Row)
    }

    func updateSalesman(_ db: Database, _ id: String, _ body: Row) throws -> Any {
        guard let cur = try db.prepare("SELECT * FROM salesmen WHERE id=?").get(id) else { throw HttpError(404, "Salesman not found") }
        var b = cur
        for (k, v) in body { b[k] = v }
        let t = JS.number(b["monthly_target"] ?? nil)
        try db.prepare("UPDATE salesmen SET name=?,phone=?,monthly_target=?,active=? WHERE id=?")
            .run(b.v("name"), JS.blank(b["phone"] ?? nil), (t.isNaN || t == 0) ? 0 : t, JS.truthy(b["active"]) ? 1 : 0, cur.v("id"))
        return ["ok": true] as Row
    }

    /// Delete: the salesman leaves the list and their routes are unassigned; bills and receipts keep the name (history).
    func deleteSalesman(_ db: Database, _ id: String) throws -> Any {
        guard let cur = try db.prepare("SELECT * FROM salesmen WHERE id=?").get(id) else { throw HttpError(404, "Salesman not found") }
        try db.transaction {
            try db.prepare("UPDATE routes SET salesman_id=NULL WHERE salesman_id=?").run(cur.v("id"))
            try db.prepare("UPDATE salesmen SET active=0 WHERE id=?").run(cur.v("id"))
        }
        return ["ok": true] as Row
    }

    /// Merge: this salesman's bills, receipts and routes move to `into`, then this salesman leaves the list.
    func mergeSalesman(_ db: Database, _ id: String, _ b: Row) throws -> Any {
        guard let from = try db.prepare("SELECT * FROM salesmen WHERE id=?").get(id),
              let into = try db.prepare("SELECT * FROM salesmen WHERE id=?").get(b["into"] ?? nil) else { throw HttpError(404, "Salesman not found") }
        if JS.number(from["id"] ?? nil) == JS.number(into["id"] ?? nil) { throw HttpError(400, "Choose another salesman to merge into") }
        var moved: Row = [:]
        try db.transaction {
            for t in ["invoices", "receipts", "routes"] {
                moved[t] = try db.prepare("UPDATE \(t) SET salesman_id=? WHERE salesman_id=?").run(into.v("id"), from.v("id")).changes
            }
            if JS.number(into["monthly_target"] ?? nil) == 0, JS.number(from["monthly_target"] ?? nil) > 0 {
                try db.prepare("UPDATE salesmen SET monthly_target=? WHERE id=?").run(from.v("monthly_target"), into.v("id"))
            }
            try db.prepare("UPDATE salesmen SET active=0 WHERE id=?").run(from.v("id"))
        }
        return ["ok": true, "into": into.v("id"), "moved": moved] as Row
    }

    // utils/routematch.js: a customer goes on every route that lists a place (comma separated) found in its name or address.
    static let ROUTE_FILLER: Set<String> = ["ROUTE", "ROUTES", "BEAT", "MON", "TUE", "TUES", "WED", "THU", "THUR", "THURS", "FRI", "SAT", "SUN",
        "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY", "SUNDAY"]
    static let ROUTE_GENERIC: Set<String> = ["ROAD", "NAGAR", "MARG", "CHOWK", "CHAURAHA", "BAZAR", "BAZAAR", "MARKET", "COLONY", "STREET",
        "NEAR", "MAIN", "GALI", "LANE", "SECTOR", "AREA", "SIDE", "THE", "AND", "OPP", "OPPOSITE", "BEHIND", "SHOP", "STORE", "STORES"]
    static func routeWords(_ s: String) -> [String] {
        let up = s.uppercased().unicodeScalars.map { ($0 >= "A" && $0 <= "Z") || ($0 >= "0" && $0 <= "9") ? Character($0) : " " }
        return String(up).split(separator: " ").map(String.init)
    }
    /// A place as " A B " (ROUTE / BEAT / weekdays dropped); nil if under 3 letters or only one common word.
    static func routeKey(_ name: String) -> String? {
        let all = routeWords(name)
        let kept = all.filter { !ROUTE_FILLER.contains($0) }
        let list = kept.isEmpty ? all : kept
        let k = list.joined(separator: " ")
        if k.count < 3 || (list.count == 1 && ROUTE_GENERIC.contains(list[0])) { return nil }
        return " \(k) "
    }
    /// Every place a route lists: "Khajrana, New Palasia / Rajwada" → [" KHAJRANA ", " NEW PALASIA ", " RAJWADA "].
    static func routeKeys(_ name: String) -> [String] {
        var out: [String] = []
        for part in name.split(whereSeparator: { ",;/&+|".contains($0) }) {
            if let k = routeKey(String(part)), !out.contains(k) { out.append(k) }
        }
        return out
    }

    /// {matches: [{party_id, party_name, address, route_id, route_name}], unmatched, assigned}: one match per customer and route it is
    /// not on yet (a customer can be in several). apply → adds the routes: only `assignments` [{party_id, route_id}] when given,
    /// else only `party_ids` when given, else all. (choices and unclear stay in the reply, empty, for apps that still read them.)
    func autoAssignRoutes(_ db: Database, _ b: Row) throws -> Any {
        let apply = JS.truthy(b["apply"] ?? nil)
        let only: Set<Double>? = (unwrap(b["party_ids"] ?? nil) as? [Any]).map { ids in Set(ids.map { JS.number($0) }) }
        let routes: [(id: Int, name: String, keys: [String])] = try db.prepare("SELECT id, name FROM routes ORDER BY name, id").all().compactMap { r in
            let name = JS.string(r.v("name"))
            let keys = Router.routeKeys(name)
            return keys.isEmpty ? nil : (id: r.i("id"), name: name, keys: keys)
        }
        let parties = try db.prepare("SELECT id, name, address, route_id FROM parties WHERE active=1 AND type <> 'SUPPLIER' ORDER BY name, id").all()
        var on: [Int: Set<Int>] = [:]   // party → routes it is on
        for x in try db.prepare("SELECT party_id, route_id FROM party_routes").all() { on[x.i("party_id"), default: []].insert(x.i("route_id")) }
        var matches: [Row] = []
        var unmatched = 0
        for p in parties {
            if let only, !only.contains(JS.number(p.v("id"))) { continue }
            var has = on[p.i("id")] ?? []
            if p.has("route_id") { has.insert(p.i("route_id")) }
            let addr = p.v("address") == nil ? "" : JS.string(p.v("address"))
            let text = " " + Router.routeWords(JS.string(p.v("name"))).joined(separator: " ") + " | " + Router.routeWords(addr).joined(separator: " ") + " "
            var n = 0
            for r in routes {
                if has.contains(r.id) || !r.keys.contains(where: { text.contains($0) }) { continue }
                matches.append(["party_id": p.v("id") as Any, "party_name": p.v("name") as Any, "address": addr, "route_id": r.id, "route_name": r.name] as Row)
                n += 1
            }
            if n == 0 && has.isEmpty { unmatched += 1 }
        }
        var assigned = 0
        if apply {
            let ok = Set(try db.prepare("SELECT id FROM routes").all().map { $0.i("id") })
            var pairs: [(pid: Any?, rid: Int)] = []
            if let list = unwrap(b["assignments"] ?? nil) as? [Any] {
                for a in list {
                    guard let o = a as? Row else { continue }
                    let pid = JS.number(o["party_id"] ?? nil), rid = JS.number(o["route_id"] ?? nil)
                    if pid > 0 && rid > 0 && rid < 9e15 && rid == rid.rounded() && ok.contains(Int(rid)) { pairs.append((pid: pid, rid: Int(rid))) }
                }
            } else {
                pairs = matches.map { (pid: $0.v("party_id"), rid: $0.i("route_id")) }
            }
            try db.transaction {
                let live = db.prepare("SELECT 1 x FROM parties WHERE id=? AND active=1 AND type <> 'SUPPLIER'")
                for m in pairs {
                    let there = try live.get(m.pid)
                    if there != nil, try Router.addPartyRoute(db, m.pid, m.rid) { assigned += 1 }
                }
            }
        }
        return ["matches": matches, "choices": [Row](), "unclear": 0, "unmatched": unmatched, "assigned": assigned] as Row
    }

    func listRoutes(_ db: Database) throws -> Any {
        try db.prepare("""
        SELECT r.*, s.name salesman_name, (SELECT COUNT(*) FROM parties p WHERE p.active=1 AND \(Router.ON_ROUTE)) outlets
             FROM routes r LEFT JOIN salesmen s ON s.id=r.salesman_id ORDER BY r.days, r.name
        """).all()
    }

    func addRoute(_ db: Database, _ b: Row) throws -> Reply {
        guard JS.blank(b["name"] ?? nil) != nil else { throw HttpError(400, "Route name is required") }
        let days = normDays(b.defined("days") ? b["days"] ?? nil : b["day_of_week"] ?? nil)
        let id = try db.prepare("INSERT INTO routes(name,salesman_id,day_of_week,days) VALUES(?,?,?,?)")
            .run(JS.trim(JS.string(b.v("name"))), JS.blank(b["salesman_id"] ?? nil), days.map { JS.parseInt($0) }, days).lastInsertRowid
        return .json(201, ["id": id] as Row)
    }

    func updateRoute(_ db: Database, _ id: String, _ body: Row) throws -> Any {
        guard let cur = try db.prepare("SELECT * FROM routes WHERE id=?").get(id) else { throw HttpError(404, "Route not found") }
        var b = cur
        for (k, v) in body { b[k] = v }
        guard JS.blank(b["name"] ?? nil) != nil else { throw HttpError(400, "Route name is required") }
        let name = JS.trim(JS.string(b.v("name")))
        let src: Any? = body.defined("days") ? body["days"] ?? nil : (body.defined("day_of_week") ? body["day_of_week"] ?? nil : cur["days"] ?? nil)
        let days = normDays(src)
        try db.prepare("UPDATE routes SET name=?,salesman_id=?,day_of_week=?,days=? WHERE id=?")
            .run(name, JS.blank(b["salesman_id"] ?? nil), days.map { JS.parseInt($0) }, days, cur.v("id"))
        return ["ok": true] as Row
    }

    func deleteRoute(_ db: Database, _ id: String) throws -> Any {
        try db.transaction {
            // outlets stay: one that is on other routes too keeps those (the next becomes its first), the rest are just unassigned
            try db.prepare("DELETE FROM party_routes WHERE route_id=?").run(id)
            try db.prepare("UPDATE parties SET route_id=(SELECT x.route_id FROM party_routes x WHERE x.party_id=parties.id ORDER BY x.id LIMIT 1) WHERE route_id=?").run(id)
            try db.prepare("DELETE FROM party_routes WHERE route_id=(SELECT p.route_id FROM parties p WHERE p.id=party_routes.party_id)").run()
            try db.prepare("DELETE FROM routes WHERE id=?").run(id)
        }
        return ["ok": true] as Row
    }

    /// Beat plan: outlets to visit for a salesman on a weekday (default today), with dues to collect.
    func beat(_ db: Database, _ id: String, _ q: [String: String]) throws -> Any {
        var day: Double
        if let d = q["day"] { day = JS.parseInt(d) } else {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone.current
            day = Double(cal.component(.weekday, from: Clock.now) - 1)
        }
        // the salesman's routes of that day; an outlet on two of them shows once, with both names
        let due = "r.salesman_id=@sm AND (',' || COALESCE(r.days, CAST(r.day_of_week AS TEXT), '') || ',') LIKE '%,' || @day || ',%' AND \(Router.ON_ROUTE)"
        let rows = try db.prepare("""
        SELECT p.id, p.name, p.phone, p.address, p.credit_limit,
               (SELECT group_concat(name, '; ') FROM (SELECT r.name FROM routes r WHERE \(due) ORDER BY r.name, r.id)) route_name,
               COALESCE((SELECT SUM(debit)-SUM(credit) FROM ledger l WHERE l.party_id=p.id AND l.date <= @to),0) outstanding,
               (SELECT MAX(date) FROM invoices i WHERE i.party_id=p.id AND i.date <= @to) last_order
             FROM parties p
             WHERE p.active=1 AND EXISTS (SELECT 1 FROM routes r WHERE \(due)) ORDER BY route_name, p.name
        """).all(["sm": id, "day": day.isNaN ? NSNull() as Any : JS.numberString(day) as Any, "to": try FY.range(q["fy"]).to] as Row)
        return ["day": day.isNaN ? NSNull() as Any : day, "outlets": rows, "total_outstanding": r2(rows.reduce(0.0) { $0 + $1.n("outstanding") })] as Row
    }

    /// Month target vs achievement + today's van-sales cash-up.
    func performance(_ db: Database, _ id: String, _ q: [String: String]) throws -> Any {
        guard let sm = try db.prepare("SELECT * FROM salesmen WHERE id=?").get(id) else { throw HttpError(404, "Salesman not found") }
        let fyr = try FY.range(q["fy"])
        func cl(_ d: String) -> String { d < fyr.from ? fyr.from : (d > fyr.to ? fyr.to : d) }
        let month = (q["month"]?.isEmpty == false) ? q["month"]! : cl(today()).jsSlice(0, 7)
        let date = (q["date"]?.isEmpty == false) ? q["date"]! : cl(today())
        let sales = try db.prepare("SELECT COALESCE(SUM(total),0) v, COUNT(*) n FROM invoices WHERE salesman_id=? AND substr(date,1,7)=?").get(sm.v("id"), month)!
        let coll = try db.prepare("SELECT COALESCE(SUM(amount),0) v FROM receipts WHERE salesman_id=? AND substr(date,1,7)=?").get(sm.v("id"), month)!
        let dayInv = try db.prepare("SELECT COUNT(*) n, COALESCE(SUM(total),0) total, COALESCE(SUM(paid),0) paid FROM invoices WHERE salesman_id=? AND date=?").get(sm.v("id"), date)!
        let byMode = try db.prepare("SELECT mode, COALESCE(SUM(amount),0) amount FROM receipts WHERE salesman_id=? AND date=? GROUP BY mode").all(sm.v("id"), date)
        let target = sm.n("monthly_target")
        return [
            "salesman": sm, "month": month, "target": sm["monthly_target"] ?? NSNull(),
            "sales": r2(sales.n("v")), "invoices": sales["n"]!, "collections": r2(coll.n("v")),
            "achievement_pct": target > 0 ? r2((sales.n("v") / target) * 100) as Any : NSNull(),
            "day": ["date": date, "bills": dayInv["n"]!, "sales": r2(dayInv.n("total")), "credit_given": r2(dayInv.n("total") - dayInv.n("paid")), "collected_by_mode": byMode] as Row,
        ] as Row
    }
}
