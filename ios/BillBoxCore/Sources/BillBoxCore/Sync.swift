import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Live sync between devices through Firebase Realtime Database (backend/src/services/sync.js, the same data on the server,
/// so the iPhone syncs with the Mac, Android and Windows/Linux):
///
///   users/<uid>/devices/<pushId>           one entry per device install; its place in the list is the device's slot
///   users/<uid>/books/<key>/info           { name, fy } of a synced company
///   users/<uid>/books/<key>/log/<pushId>   { s: slot, c: [{ t: table, k: key, r: row, z: "null,columns", q: stock delta }] }
///
/// The network parts run outside the router's queue; the books are only touched through `db`, which takes its turn.
public final class Sync {
    let engine: Engine
    let backup: Backup
    let db: (@escaping () throws -> Any) async throws -> Any

    public static var apiKey = "AIzaSyC0bS-ytJeaXl6PbE0cxzTa6FoOC2wTYo0"
    public static var databaseURL = "https://billbox-fd2c0-default-rtdb.asia-southeast1.firebasedatabase.app"
    public static var authURL = "https://identitytoolkit.googleapis.com/v1"
    public static var tokenURL = "https://securetoken.googleapis.com/v1/token"
    static let range = Database.idRange
    static let maxSlot = 210
    static let local: Set<String> = ["sync_out", "sync_state", "sync_seen", "sync_alias"]
    static let chunk = 400
    static let rules = #"{ "rules": { "users": { "$uid": { ".read": "auth != null && auth.uid === $uid", ".write": "auth != null && auth.uid === $uid" } } } }"#

    private let lock = NSLock()
    private var _version = 0, _errors = 0, _companies = 0
    private var _moved: [String: Int] = [:]
    private var _lastSync: String?, _lastError: String?
    private var _token: String?, _tokenExp = Date.distantPast
    private var running: Task<Void, Error>?
    private func locked<T>(_ f: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return f() }
    var version: Int { locked { _version } }

    init(_ engine: Engine, _ backup: Backup, db: @escaping (@escaping () throws -> Any) async throws -> Any) {
        self.engine = engine; self.backup = backup; self.db = db
    }

    /// Work on the books in the router's queue.
    func inDB<T>(_ f: @escaping () throws -> T) async throws -> T { (try await db { try f() }) as! T }

    // MARK: registry settings (call inside the queue)
    var reg: Database { engine.registry }
    func app(_ k: String) throws -> String? { try reg.prepare("SELECT value FROM app_settings WHERE key=?").get(k)?.s("value") }
    func setApp(_ k: String, _ v: String?) throws {
        if let v { try reg.prepare("INSERT INTO app_settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value").run(k, v) }
        else { try reg.prepare("DELETE FROM app_settings WHERE key=?").run(k) }
    }
    func map() throws -> [String: String] {
        guard let s = try app("sync_map"), let d = s.data(using: .utf8), let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return [:] }
        return o.compactMapValues { $0 as? String }
    }
    func setMap(_ m: [String: String]) throws {
        try setApp("sync_map", String(data: try JSONSerialization.data(withJSONObject: m, options: [.sortedKeys]), encoding: .utf8))
    }
    func slotNow() throws -> Int { Int(try app("sync_slot") ?? "") ?? 0 }

    static func now() -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f.string(from: Date())
    }
    static func offline() -> HttpError { HttpError(503, "No internet: BillBox could not reach the sync server. Your books are safe here and sync again when the internet is back.") }

    // MARK: network
    func call(_ url: String, method: String = "GET", headers: [String: String] = [:], body: Data? = nil) async throws -> (status: Int, json: Any?) {
        guard Category.internetAllowed, let u = URL(string: url) else { throw Sync.offline() }
        var req = URLRequest(url: u, timeoutInterval: 15)
        req.httpMethod = method
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = body
        let (data, resp): (Data, URLResponse?) = try await withCheckedThrowingContinuation { c in
            URLSession.shared.dataTask(with: req) { d, r, e in
                if e != nil { c.resume(throwing: Sync.offline()) } else { c.resume(returning: (d ?? Data(), r)) }
            }.resume()
        }
        let json = data.isEmpty ? nil : try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return ((resp as? HTTPURLResponse)?.statusCode ?? 0, json is NSNull ? nil : json)
    }
    static func json(_ o: Any) -> Data { (try? JSONSerialization.data(withJSONObject: o, options: [.fragmentsAllowed])) ?? Data("null".utf8) }

    static let authErrors = [
        "EMAIL_EXISTS": "That e-mail already has a BillBox sync account: sign in instead.",
        "EMAIL_NOT_FOUND": "No sync account with that e-mail: create one first.",
        "INVALID_PASSWORD": "Wrong password.", "INVALID_LOGIN_CREDENTIALS": "Wrong e-mail or password.",
        "INVALID_EMAIL": "That e-mail address is not valid.", "WEAK_PASSWORD": "Choose a password of at least 6 characters.",
        "OPERATION_NOT_ALLOWED": "E-mail sign-in is off in Firebase: turn on Authentication › Sign-in method › Email/Password.",
        "TOO_MANY_ATTEMPTS_TRY_LATER": "Too many tries: wait a few minutes.",
        "CONFIGURATION_NOT_FOUND": "Firebase Authentication is not set up yet: open Authentication in the Firebase console and press Get started.",
    ]

    func signIn(_ b: Row) async throws {
        let email = b.str("email").trimmingCharacters(in: .whitespaces).lowercased(), password = b.str("password")
        if email.isEmpty || password.isEmpty { throw HttpError(400, "Enter the e-mail and password of your sync account.") }
        let create = b["create"] as? Bool ?? (JS.number(b["create"]) == 1)
        let r = try await call("\(Sync.authURL)/accounts:\(create ? "signUp" : "signInWithPassword")?key=\(Sync.apiKey)", method: "POST",
                               headers: ["content-type": "application/json"], body: Sync.json(["email": email, "password": password, "returnSecureToken": true]))
        let j = r.json as? [String: Any] ?? [:]
        guard r.status == 200, let idToken = j["idToken"] as? String, let uid = j["localId"] as? String else {
            let m = ((j["error"] as? [String: Any])?["message"] as? String) ?? "Sign-in failed"
            let code = String(m.split(separator: " ").first ?? "").split(separator: ":").first.map(String.init) ?? m
            throw HttpError(400, Sync.authErrors[code] ?? m)
        }
        let refresh = j["refreshToken"] as? String ?? ""
        let exp = Double(j["expiresIn"] as? String ?? "3600") ?? 3600
        try await inDB {
            if let old = try self.app("sync_uid"), old != uid { try self.setApp("sync_slot", nil); try self.setMap([:]) }
            try self.setApp("sync_email", email); try self.setApp("sync_uid", uid); try self.setApp("sync_refresh", refresh)
        }
        locked { _token = idToken; _tokenExp = Date().addingTimeInterval(exp - 120) }
        _ = try await slot()
    }

    func signOut() throws {
        for cid in try map().keys { if let id = Int(cid), let d = try engine.openCompany(id) { try detach(d) } }
        for k in ["sync_email", "sync_uid", "sync_refresh", "sync_slot", "sync_map"] { try setApp(k, nil) }
        locked { _token = nil; _tokenExp = .distantPast; _lastError = nil }
    }

    func token(_ force: Bool) async throws -> String {
        if !force, let t = locked({ _token != nil && Date() < _tokenExp ? _token : nil }) { return t }
        guard let rt = try await inDB({ try self.app("sync_refresh") }) else { throw HttpError(401, "Sign in to sync first (Settings › Sync).") }
        var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-._~")
        let r = try await call("\(Sync.tokenURL)?key=\(Sync.apiKey)", method: "POST", headers: ["content-type": "application/x-www-form-urlencoded"],
                               body: Data("grant_type=refresh_token&refresh_token=\(rt.addingPercentEncoding(withAllowedCharacters: allowed) ?? rt)".utf8))
        let j = r.json as? [String: Any] ?? [:]
        guard r.status == 200, let t = j["id_token"] as? String else {
            if r.status == 400 { locked { _token = nil }; throw HttpError(401, "Your sync sign-in has expired: sign in again (Settings › Sync).") }
            throw HttpError(502, "The sync server answered \(r.status).")
        }
        if let n = j["refresh_token"] as? String { try await inDB { try self.setApp("sync_refresh", n) } }
        let exp = Double(j["expires_in"] as? String ?? "3600") ?? 3600
        locked { _token = t; _tokenExp = Date().addingTimeInterval(exp - 120) }
        return t
    }

    /// Realtime Database REST call under users/<uid>/.
    func rtdb(_ method: String, _ rel: String, _ body: Any? = nil, query: String = "") async throws -> Any? {
        guard let uid = try await inDB({ try self.app("sync_uid") }) else { throw HttpError(401, "Sign in to sync first (Settings › Sync).") }
        var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-._~")
        for attempt in 0..<2 {
            let t = try await token(attempt > 0)
            let r = try await call("\(Sync.databaseURL)/users/\(uid)/\(rel).json?auth=\(t.addingPercentEncoding(withAllowedCharacters: allowed) ?? t)\(query)", method: method,
                                   headers: ["content-type": "application/json"], body: body.map(Sync.json))
            if r.status == 401 && attempt == 0 { continue }
            if r.status == 401 || r.status == 403 { throw HttpError(403, "The sync database refused BillBox: set its rules (Firebase › Realtime Database › Rules) as shown in Settings › Sync.") }
            if r.status == 404 { throw HttpError(502, "The sync database was not found: create the Realtime Database in the Firebase console.") }
            if r.status >= 400 || r.status == 0 { throw HttpError(502, "The sync server answered \(r.status).") }
            return r.json
        }
        return nil
    }

    /// This device's slot: its place among the account's devices (each install adds itself once).
    func slot() async throws -> Int {
        let have = try await inDB { try self.slotNow() }
        if have > 0 { return have }
        var mine = try await inDB { try self.app("sync_device") }
        if mine == nil {
            let r = try await rtdb("POST", "devices", ["at": [".sv": "timestamp"], "name": "iPhone"] as [String: Any]) as? [String: Any]
            guard let name = r?["name"] as? String else { throw HttpError(502, "This device could not register for sync: try again.") }
            mine = name
            try await inDB { try self.setApp("sync_device", name) }
        }
        let all = ((try await rtdb("GET", "devices", query: "&shallow=true")) as? [String: Any] ?? [:]).keys.sorted()
        guard let i = all.firstIndex(of: mine!) else { try await inDB { try self.setApp("sync_device", nil) }; throw HttpError(502, "This device could not register for sync: try again.") }
        let n = i + 1
        if n > Sync.maxSlot { throw HttpError(400, "This sync account already has \(Sync.maxSlot) device installs: use a new sync account.") }
        try await inDB { try self.setApp("sync_slot", String(n)) }
        return n
    }

    // MARK: local tracking
    struct Table { let name: String, pk: String, intId: Bool, cols: [String], uniq: [[String]], fks: [(col: String, ref: String)] }
    func tables(_ d: Database) throws -> [Table] {
        var out: [Table] = []
        for t in try d.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name").all() {
            let name = t.str("name")
            if Sync.local.contains(name) || name.hasSuffix("_new") || name.hasSuffix("_old") { continue }
            let cols = try d.prepare("PRAGMA table_info(\(name))").all()
            let pk = cols.filter { $0.i("pk") > 0 }
            guard pk.count == 1 else { continue }
            let p = pk[0].str("name")
            // UNIQUE column sets (a category name, a batch number of an item) and the columns that point at other tables
            var uniq: [[String]] = []
            for x in try d.prepare("PRAGMA index_list(\(name))").all() where x.i("unique") == 1 && x.str("origin") == "u" {
                uniq.append(try d.prepare("PRAGMA index_info(\(x.str("name")))").all().map { $0.str("name") })
            }
            let fks = try d.prepare("PRAGMA foreign_key_list(\(name))").all().map { (col: $0.str("from"), ref: $0.str("table")) }
            out.append(Table(name: name, pk: p, intId: p == "id" && pk[0].str("type").uppercased().contains("INT"), cols: cols.map { $0.str("name") }, uniq: uniq, fks: fks))
        }
        return out
    }

    /// Called for every company opened (Engine.onOpen): turns tracking on for the synced ones.
    func attach(_ cid: Int, _ d: Database) {
        do {
            let sl = try slotNow()
            guard sl > 0, try map()[String(cid)] != nil else { d.idBase = 0; return }
            try d.exec("""
            CREATE TABLE IF NOT EXISTS sync_out (seq INTEGER PRIMARY KEY, tbl TEXT NOT NULL, rid, op TEXT NOT NULL, dq REAL);
            CREATE TABLE IF NOT EXISTS sync_state (k TEXT PRIMARY KEY, v TEXT);
            CREATE TABLE IF NOT EXISTS sync_seen (k TEXT PRIMARY KEY, at INTEGER);
            CREATE TABLE IF NOT EXISTS sync_alias (tbl TEXT NOT NULL, from_id INTEGER NOT NULL, to_id INTEGER NOT NULL, PRIMARY KEY (tbl, from_id));
            """)
            let ts = try tables(d)
            for t in try d.prepare("SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'bbsync_%'").all() { try d.exec("DROP TRIGGER IF EXISTS \(t.str("name"))") }
            for t in ts {
                let dq = t.name == "batches" && t.cols.contains("qty") ? "NEW.qty - OLD.qty" : "NULL"
                try d.exec("CREATE TRIGGER bbsync_\(t.name)_i AFTER INSERT ON \(t.name) BEGIN INSERT INTO sync_out(tbl,rid,op) VALUES('\(t.name)', NEW.\(t.pk), 'i'); END")
                try d.exec("CREATE TRIGGER bbsync_\(t.name)_u AFTER UPDATE ON \(t.name) BEGIN INSERT INTO sync_out(tbl,rid,op,dq) VALUES('\(t.name)', NEW.\(t.pk), 'u', \(dq)); "
                    + "INSERT INTO sync_out(tbl,rid,op) SELECT '\(t.name)', OLD.\(t.pk), 'd' WHERE OLD.\(t.pk) IS NOT NEW.\(t.pk); END")
                try d.exec("CREATE TRIGGER bbsync_\(t.name)_d AFTER DELETE ON \(t.name) BEGIN INSERT INTO sync_out(tbl,rid,op) VALUES('\(t.name)', OLD.\(t.pk), 'd'); END")
            }
            d.idTables = Set(ts.filter { $0.intId }.map { $0.name })
            d.idNext = [:]
            d.idBase = sl * Sync.range
        } catch {
            d.idBase = 0
        }
    }

    func detach(_ d: Database) throws {
        for t in try d.prepare("SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'bbsync_%'").all() { try d.exec("DROP TRIGGER IF EXISTS \(t.str("name"))") }
        try d.exec("DROP TABLE IF EXISTS sync_out; DROP TABLE IF EXISTS sync_seen; DROP TABLE IF EXISTS sync_state; DROP TABLE IF EXISTS sync_alias")
        d.idBase = 0
    }

    func getState(_ d: Database, _ k: String) throws -> String? { try d.prepare("SELECT v FROM sync_state WHERE k=?").get(k)?.s("v") }
    func putState(_ d: Database, _ k: String, _ v: String) throws {
        try d.prepare("INSERT INTO sync_state(k,v) VALUES(?,?) ON CONFLICT(k) DO UPDATE SET v=excluded.v").run(k, v)
    }

    /// A row as it travels: values without nulls (the database drops nulls), the null columns named in z.
    static func pack(_ row: Row) -> [String: Any] {
        var r: [String: Any] = [:], z: [String] = []
        for (c, v) in row {
            switch unwrap(v) {
            case nil: z.append(c)
            case is Data: continue
            case let x?: r[c] = x
            }
        }
        var out: [String: Any] = ["r": r]
        if !z.isEmpty { out["z"] = z.sorted().joined(separator: ",") }
        return out
    }

    /// Local changes not sent yet → log changes (at most 4000 sync_out rows).
    func outgoing(_ d: Database) throws -> (changes: [[String: Any]], upTo: Int) {
        let rows = try d.prepare("SELECT seq,tbl,rid,op,dq FROM sync_out ORDER BY seq LIMIT 4000").all()
        guard let lastRow = rows.last else { return ([], 0) }
        let info = Dictionary(uniqueKeysWithValues: try tables(d).map { ($0.name, $0) })
        struct G { var tbl: String; var rid: Any; var ins = false; var dq = 0.0; var last = 0 }
        var groups: [String: G] = [:]
        for x in rows {
            let key = x.str("tbl") + "\u{0}" + x.str("rid")
            var g = groups[key] ?? G(tbl: x.str("tbl"), rid: unwrap(x["rid"]) ?? NSNull())
            if x.str("op") == "i" { g.ins = true; g.dq = 0 } else if x.str("op") == "u", unwrap(x["dq"]) != nil { g.dq += x.n("dq") }
            g.last = x.i("seq")
            groups[key] = g
        }
        var changes: [[String: Any]] = []
        for g in groups.values.sorted(by: { $0.last < $1.last }) {
            guard let t = info[g.tbl] else { continue }
            if g.tbl == "settings" && JS.string(g.rid).hasPrefix("sync_") { continue }
            guard let row = try d.prepare("SELECT * FROM \(g.tbl) WHERE \(t.pk)=?").get(g.rid) else { changes.append(["t": g.tbl, "k": g.rid]); continue }
            var c: [String: Any] = ["t": g.tbl, "k": g.rid]
            for (k, v) in Sync.pack(row) { c[k] = v }
            if g.tbl == "batches" && !g.ins { c["q"] = (g.dq * 1000).rounded() / 1000 }
            changes.append(c)
        }
        return (changes, lastRow.i("seq"))
    }

    // numbered documents: two devices that make a bill at the same moment (or offline) can pick the same number
    static let numbered: [String: (String, String)] = ["invoices": ("invoice_no", "INV"), "receipts": ("receipt_no", "RCT"), "purchases": ("purchase_no", "PUR"),
                                                       "payments": ("voucher_no", "PAY"), "debit_notes": ("note_no", "DN")]

    /// Another device's changes → this company's books (one transaction; tracking of these writes is dropped).
    func apply(_ cid: Int, _ d: Database, _ entries: [[String: Any]]) throws -> Int {
        let info = Dictionary(uniqueKeysWithValues: try tables(d).map { ($0.name, $0) })
        let sl = try slotNow()
        var resend: [(String, Any)] = []
        var applied = 0, failed = 0
        try d.pragma("foreign_keys = OFF")
        defer { try? d.pragma("foreign_keys = ON") }
        try d.transaction {
            let before = try d.prepare("SELECT MAX(seq) AS m FROM sync_out").get()?.i("m") ?? 0
            for e in entries {
                if JS.number(e["x"]) == 1 { try self.resetBooks(d, info) }   // another device restored a backup over these books
                let list: [Any] = (e["c"] as? [Any]) ?? ((e["c"] as? [String: Any]).map { o in o.keys.sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }.compactMap { o[$0] } } ?? [])
                for case let c as [String: Any] in list {
                    guard let tn = c["t"] as? String, let t = info[tn] else { continue }
                    if tn == "settings" && JS.string(c["k"]).hasPrefix("sync_") { continue }
                    do {
                        try d.transaction { try self.applyOne(d, t, c, sl, &resend, info) }
                        applied += 1
                    } catch {
                        failed += 1
                    }
                }
            }
            try d.prepare("DELETE FROM sync_out WHERE seq > ?").run(before)
            // bills of this device that had to take a new number go out again
            for (tbl, rid) in resend { try d.prepare("INSERT INTO sync_out(tbl,rid,op) VALUES(?,?,'u')").run(tbl, rid) }
        }
        locked { _errors += failed }
        // the company was renamed on another device: the company list here shows the new name too
        if let nm = try d.prepare("SELECT value FROM settings WHERE key='company_name'").get()?.s("value")?.trimmingCharacters(in: .whitespaces), !nm.isEmpty {
            try reg.prepare("UPDATE companies SET name=? WHERE id=? AND name<>?").run(nm, cid, nm)
        }
        return applied
    }

    /// The same number on two bills: the older bill (lower id) keeps it; the other one, if made here, takes this device's
    /// next number (ledger lines follow) and goes out again; if another device made it, it is "no~id" until its copy arrives.
    func settleNumber(_ d: Database, _ t: Table, _ k: Any, _ vals: inout [String: Any?], _ sl: Int, _ resend: inout [(String, Any)]) throws {
        guard let nb = Sync.numbered[t.name] else { return }
        let (col, series) = nb
        guard let no = vals[col].flatMap({ unwrap($0) }).map({ JS.string($0) }) else { return }
        guard let other = try d.prepare("SELECT id, date FROM \(t.name) WHERE \(col)=? AND id<>?").get(no, k) else { return }
        let oid = other.i("id"), kid = Int(JS.number(k))
        if oid < kid { vals[col] = "\(no)~\(kid)"; return }
        if sl > 0 && oid / Sync.range == sl {
            let fresh = try nextNo(d, series, other.s("date"))
            try d.prepare("UPDATE \(t.name) SET \(col)=? WHERE id=?").run(fresh, oid)
            resend.append((t.name, oid))
            for c in try d.prepare("SELECT key FROM counters").all() { resend.append(("counters", c.str("key"))) }
            for l in try d.prepare("SELECT id FROM ledger WHERE ref_no=? AND id > ? AND id < ?").all(no, sl * Sync.range, (sl + 1) * Sync.range) {
                try d.prepare("UPDATE ledger SET ref_no=?, narration=REPLACE(narration, ?, ?) WHERE id=?").run(fresh, no, fresh, l.i("id"))
                resend.append(("ledger", l.i("id")))
            }
        } else {
            try d.prepare("UPDATE \(t.name) SET \(col)=? WHERE id=?").run("\(no)~\(oid)", oid)
        }
    }

    /// Empties every synced table (another device restored a backup: its full copy follows).
    func resetBooks(_ d: Database, _ info: [String: Table]) throws {
        for t in info.values { try d.exec("DELETE FROM \(t.name)") }
        try d.exec("DELETE FROM sync_out")
        d.idNext = [:]
    }

    /// A backup was restored over a synced company (Replace): its books go out whole after a reset that empties the other
    /// devices' copies, and this device reads on from that point (Engine.onReplace, inside the queue).
    func afterReplace(_ cid: Int) {
        do {
            guard try map()[String(cid)] != nil, let d = try engine.openCompany(cid) else { return }
            attach(cid, d)
            try d.exec("DELETE FROM sync_out; DELETE FROM sync_seen")
            for t in try tables(d) { try d.exec("INSERT INTO sync_out(tbl,rid,op) SELECT '\(t.name)', \(t.pk), 'i' FROM \(t.name)") }
            try d.prepare("DELETE FROM sync_state WHERE k=?").run("cursor")
            try putState(d, "reset", "1")
        } catch {}
    }

    // the same category or batch made on two devices at once
    func aliasOf(_ d: Database, _ tbl: String, _ id: Any?) throws -> Int? {
        guard let id = unwrap(id) else { return nil }
        return try d.prepare("SELECT to_id FROM sync_alias WHERE tbl=? AND from_id=?").get(tbl, id)?.i("to_id")
    }

    /// Row `loser` of t becomes `winner`: everything pointing at it follows, and later changes to it follow too.
    func fold(_ d: Database, _ t: Table, _ info: [String: Table], _ loser: Any, _ winner: Any) throws {
        for o in info.values { for f in o.fks where f.ref == t.name { try d.prepare("UPDATE \(o.name) SET \(f.col)=? WHERE \(f.col)=?").run(winner, loser) } }
        try d.prepare("UPDATE sync_alias SET to_id=? WHERE tbl=? AND to_id=?").run(winner, t.name, loser)
        try d.prepare("INSERT OR REPLACE INTO sync_alias(tbl,from_id,to_id) VALUES(?,?,?)").run(t.name, loser, winner)
    }

    /// The incoming row has the same name / batch number as another row here: the two are one record. The older one (lower
    /// id) stays on every device; the other is folded into it (bills follow; a batch's stock is added). true = done.
    func merged(_ d: Database, _ t: Table, _ c: [String: Any], _ vals: inout [String: Any?], _ info: [String: Table]) throws -> Bool {
        let k: Any = c["k"] ?? NSNull()
        let q = unwrap(c["q"]).map { JS.number($0) }
        for cols in t.uniq {
            let here = try d.prepare("SELECT * FROM \(t.name) WHERE \(t.pk)=?").get(k)
            let v: [Any?] = cols.map { col in vals.keys.contains(col) ? vals[col]!.flatMap { unwrap($0) } : here.flatMap { unwrap($0[col]) } }
            if v.contains(where: { $0 == nil }) { continue }
            guard let other = try d.prepare("SELECT * FROM \(t.name) WHERE \(cols.map { "\($0)=?" }.joined(separator: " AND ")) AND \(t.pk)<>?").allArgs(v + [k]).first else { continue }
            let stock = t.name == "batches"
            let oid = other.i(t.pk), kid = Int(JS.number(k))
            if oid < kid {
                // the incoming row is the newer copy: its stock goes to the older one
                let add = here.map { $0.n0("qty") + (q ?? 0) } ?? JS.number(vals["qty"].flatMap { unwrap($0) } ?? 0)
                if stock && add != 0 { try d.prepare("UPDATE batches SET qty = qty + ? WHERE id=?").run(add, oid) }
                try fold(d, t, info, kid, oid)   // (rows that arrived before it may already point at it)
                if here != nil { try d.prepare("DELETE FROM \(t.name) WHERE \(t.pk)=?").run(kid) }
                return true
            }
            // the copy here is the newer one: it gives way to the incoming row
            var c2 = c
            if stock {
                let mine = (here != nil && q != nil) ? here!.n0("qty") + q! : JS.number(vals["qty"].flatMap { unwrap($0) } ?? 0)
                vals["qty"] = mine + other.n0("qty")
                c2["q"] = NSNull()
            }
            try d.prepare("DELETE FROM \(t.name) WHERE \(t.pk)=?").run(oid)
            try fold(d, t, info, oid, kid)
            try write(d, t, c2, vals)
            return true
        }
        return false
    }

    func applyOne(_ d: Database, _ t: Table, _ c: [String: Any], _ sl: Int, _ resend: inout [(String, Any)], _ info: [String: Table]) throws {
        let k: Any = c["k"] ?? NSNull()
        // a row that was folded into another one: its stock changes go to the kept row, nothing else
        if t.intId, let al = try aliasOf(d, t.name, k) {
            if c["r"] != nil && t.name == "batches", let q = unwrap(c["q"]).map({ JS.number($0) }), q != 0 { try d.prepare("UPDATE batches SET qty = qty + ? WHERE id=?").run(q, al) }
            return
        }
        guard let r = c["r"] as? [String: Any] else { try d.prepare("DELETE FROM \(t.name) WHERE \(t.pk)=?").run(k); return }
        var vals: [String: Any?] = [:]
        for (col, v) in r where t.cols.contains(col) && col != t.pk {
            if v is [Any] || v is [String: Any] { vals[col] = String(data: Sync.json(v), encoding: .utf8) } else { vals[col] = v }
        }
        for col in (c["z"] as? String ?? "").split(separator: ",").map(String.init) where t.cols.contains(col) && col != t.pk { vals[col] = .some(nil) }
        for f in t.fks { if let x = vals[f.col], let a = try aliasOf(d, f.ref, x) { vals[f.col] = a } }
        if Sync.numbered[t.name] != nil { try settleNumber(d, t, k, &vals, sl, &resend) }
        else if !t.uniq.isEmpty, try merged(d, t, c, &vals, info) { return }
        try write(d, t, c, vals)
    }

    func write(_ d: Database, _ t: Table, _ c: [String: Any], _ vals: [String: Any?]) throws {
        let k: Any = c["k"] ?? NSNull()
        let q = unwrap(c["q"]).map { JS.number($0) }
        let keys = vals.keys.sorted()
        if try d.prepare("SELECT 1 AS x FROM \(t.name) WHERE \(t.pk)=?").get(k) != nil {
            var sets: [String] = [], args: [Any?] = []
            for col in keys {
                if t.name == "batches" && col == "qty" && q != nil { continue }
                if t.name == "counters" && col == "value" { sets.append("value = MAX(value, ?)"); args.append(vals[col]!); continue }
                sets.append("\(col)=?"); args.append(vals[col]!)
            }
            if t.name == "batches", let q, q != 0 { sets.append("qty = qty + ?"); args.append(q) }
            if !sets.isEmpty { try d.prepare("UPDATE \(t.name) SET \(sets.joined(separator: ",")) WHERE \(t.pk)=?").runArgs(args + [k]) }
        } else {
            let cols = [t.pk] + keys
            try d.prepare("INSERT INTO \(t.name)(\(cols.joined(separator: ","))) VALUES(\(cols.map { _ in "?" }.joined(separator: ",")))").runArgs([k] + keys.map { vals[$0]! })
        }
    }

    // MARK: push ids (Firebase keys start with the time they were made)
    static let pushChars = Array("-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz")
    static let pushIndex: [Character: Int] = Dictionary(uniqueKeysWithValues: pushChars.enumerated().map { ($1, $0) })
    static func pushTime(_ k: String) -> Int { k.prefix(8).reduce(0) { $0 * 64 + (pushIndex[$1] ?? 0) } }
    static func pushPrefix(_ ms: Int) -> String {
        var m = ms, s = ""
        for _ in 0..<8 { s = String(pushChars[m % 64]) + s; m /= 64 }
        return s
    }

    // MARK: sync steps
    func company(_ cid: Int) throws -> Database {
        guard let d = try engine.openCompany(cid) else { throw HttpError(404, "Company not found") }
        if d.idBase == 0 { attach(cid, d) }
        return d
    }

    @discardableResult
    func push(_ cid: Int, _ key: String, _ sl: Int) async throws -> String? {
        var last: String?
        if try await inDB({ try self.getState(try self.company(cid), "reset") }) == "1" {
            let name = (try await rtdb("POST", "books/\(key)/log", ["s": sl, "x": 1] as [String: Any]) as? [String: Any])?["name"] as? String
            try await inDB {
                let d = try self.company(cid)
                if let name {
                    try self.putState(d, "cursor", name); try self.putState(d, "floor", name)
                    try d.prepare("INSERT OR IGNORE INTO sync_seen(k,at) VALUES(?,?)").run(name, Sync.pushTime(name))
                }
                try d.prepare("DELETE FROM sync_state WHERE k=?").run("reset")
            }
        }
        for _ in 0..<20 {
            let out = try await inDB { try self.outgoing(try self.company(cid)) }
            if out.changes.isEmpty {
                if out.upTo > 0 { try await inDB { try self.company(cid).prepare("DELETE FROM sync_out WHERE seq <= ?").run(out.upTo) } }
                return last
            }
            var names: [String] = []
            var i = 0
            while i < out.changes.count {
                let part = Array(out.changes[i..<min(i + Sync.chunk, out.changes.count)])
                if let n = (try await rtdb("POST", "books/\(key)/log", ["s": sl, "c": part] as [String: Any]) as? [String: Any])?["name"] as? String { names.append(n); last = n }
                i += Sync.chunk
            }
            try await inDB {
                let d = try self.company(cid)
                for n in names { try d.prepare("INSERT OR IGNORE INTO sync_seen(k,at) VALUES(?,?)").run(n, Sync.pushTime(n)) }
                try d.prepare("DELETE FROM sync_out WHERE seq <= ?").run(out.upTo)
            }
        }
        return last
    }

    func pull(_ cid: Int, _ key: String, _ sl: Int) async throws -> Int {
        var got = 0
        var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-._~")
        for round in 0..<40 {
            let cursor = try await inDB { try self.getState(try self.company(cid), "cursor") }
            // first read goes back 15 s before the newest entry seen (an entry that reached the server a moment late is not
            // missed); later reads (catching up) go on from the newest entry
            let from: String? = cursor.map { round == 0 ? Sync.pushPrefix(max(0, Sync.pushTime($0) - 15000)) : $0 }
            let limit = cursor != nil && round == 0 ? 200 : 40
            let enc = { (s: String) in s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s }
            let q = "&orderBy=\(enc("\"$key\""))" + (from.map { "&startAt=\(enc("\"\($0)\""))" } ?? "") + "&limitToFirst=\(limit)"
            let page = (try await rtdb("GET", "books/\(key)/log", query: q)) as? [String: Any] ?? [:]
            let keys = page.keys.sorted()
            let (n, moved): (Int, Bool) = try await inDB {
                let d = try self.company(cid)
                var fresh: [String] = []
                let floor = try self.getState(d, "floor")
                for k in keys where try d.prepare("SELECT 1 AS x FROM sync_seen WHERE k=?").get(k) == nil && (floor == nil || k >= floor!) { fresh.append(k) }
                let theirs = fresh.compactMap { page[$0] as? [String: Any] }.filter { Int(JS.number($0["s"])) != sl }
                let n = theirs.isEmpty ? 0 : try self.apply(cid, d, theirs)
                for k in fresh { try d.prepare("INSERT OR IGNORE INTO sync_seen(k,at) VALUES(?,?)").run(k, Sync.pushTime(k)) }
                var moved = false
                if let last = keys.last {
                    if cursor == nil || last > cursor! { try self.putState(d, "cursor", last); moved = true }
                    let cur = try self.getState(d, "cursor") ?? last
                    try d.prepare("DELETE FROM sync_seen WHERE at < ?").run(Sync.pushTime(cur) - 120000)
                }
                return (n, moved)
            }
            got += n
            if keys.count < limit || (!moved && round > 0) { break }
        }
        return got
    }

    func syncCompany(_ cid: Int) async throws {
        guard let key = try await inDB({ try self.map()[String(cid)] }) else { return }
        // merged into another book on another device: move there
        if let into = (try await rtdb("GET", "books/\(key)/info/merged_into")) as? String, !into.isEmpty, into != key {
            try await follow(cid, key, into)
            return
        }
        let sl = try await inDB { try self.slotNow() }
        try await push(cid, key, sl)
        let got = try await pull(cid, key, sl)
        if got > 0 { locked { _version += 1 } }
        // the company's name in the account follows renames (Companies in your sync account)
        let (name, sent): (String, String?) = try await inDB {
            (try self.engine.companyRow(cid)?.str("name") ?? "", try self.getState(try self.company(cid), "info_name"))
        }
        if !name.isEmpty && sent != name {
            _ = try await rtdb("PUT", "books/\(key)/info/name", name)
            try await inDB { try self.putState(try self.company(cid), "info_name", name) }
        }
    }

    /// One round for every synced company: the app calls this every few seconds (GET /sync/tick).
    func tick() async -> Row {
        let on = (try? await inDB { try self.app("sync_uid") != nil && !(try self.map().isEmpty) }) ?? false
        if !on { return brief(false) }
        if let r = locked({ running }) { _ = try? await r.value; return brief(true) }
        let task = Task<Void, Error> {
            for cid in try await self.inDB({ try self.map().keys.compactMap { Int($0) }.sorted() }) { try await self.syncCompany(cid) }
        }
        locked { running = task }
        do { try await task.value; locked { _lastSync = Sync.now(); _lastError = nil } }
        catch { locked { _lastError = (error as? HttpError)?.message ?? error.localizedDescription } }
        locked { running = nil }
        return brief(true)
    }
    func brief(_ on: Bool) -> Row { locked { ["on": on, "version": _version, "companies": _companies, "moved": _moved, "last_sync": _lastSync as Any? ?? NSNull(), "last_error": _lastError as Any? ?? NSNull()] } }

    /// Sync this company: the first device sends all of its books, the other devices then join them.
    func turnOn(_ cid: Int) async throws -> Row {
        guard let row = try await inDB({ try self.engine.companyRow(cid) }) else { throw HttpError(404, "Company not found") }
        let sl = try await slot()
        if try await inDB({ try self.map()[String(cid)] }) != nil { return try await status(cid) }
        // the account already has this company (from another device): two books of one company would never meet
        if ((try await remote(cid))["books"] as? [Row] ?? []).contains(where: { $0["same_name"] as? Bool == true && $0["on_this_device"] as? Bool != true }) {
            throw HttpError(409, "\(row.str("name")) is already in your sync account from another device. Use \"Bring here\" under Companies in your sync account to use that copy on this device (back up first if this copy has bills the other one does not).")
        }
        let key = Sync.randomKey()
        _ = try await rtdb("PUT", "books/\(key)/info", ["name": row.str("name"), "fy": row.v("fy") ?? NSNull(), "at": [".sv": "timestamp"], "by": sl] as [String: Any])
        try await inDB {
            var m = try self.map(); m[String(cid)] = key; try self.setMap(m)
            guard let d = try self.engine.openCompany(cid) else { return }
            self.attach(cid, d)
            try d.exec("DELETE FROM sync_out")
            // everything already in the books goes up once, as the starting point for the other devices
            for t in try self.tables(d) { try d.exec("INSERT INTO sync_out(tbl,rid,op) SELECT '\(t.name)', \(t.pk), 'i' FROM \(t.name)") }
        }
        do {
            // where the starting copy ends in the log: a later merge replays only the changes after it
            if let last = try await push(cid, key, sl) { _ = try await rtdb("PUT", "books/\(key)/info/snap", last) }
        } catch { locked { _lastError = (error as? HttpError)?.message ?? error.localizedDescription } }
        return try await status(cid)
    }

    func turnOff(_ cid: Int) throws {
        var m = try map()
        guard m[String(cid)] != nil else { return }
        m[String(cid)] = nil; try setMap(m)
        if let d = try engine.openCompany(cid) { try detach(d) }
    }

    static func randomKey() -> String {
        let a = Array("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789")
        return "b" + String((0..<15).map { _ in a.randomElement()! })
    }

    /// Books of this account, marked when they are on this device already.
    func remote(_ cid: Int? = nil) async throws -> Row {
        let books = (try await rtdb("GET", "books", query: "&shallow=true")) as? [String: Any] ?? [:]
        let (m, row): ([String: String], Row?) = try await inDB { (try self.map(), try cid.flatMap { try self.engine.companyRow($0) }) }
        let here = Set(m.values)
        // "A.K Enterprises" = "AK ENTERPRISES"
        let norm = { (x: Any?) in String(JS.string(unwrap(x) ?? "").lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }) }
        var out: [Row] = []
        // which devices write to each book ("Mac, this device"), from its latest entries
        let dev = (try await rtdb("GET", "devices")) as? [String: Any] ?? [:]
        let slots = dev.keys.sorted()
        let mine = try await mySlots()
        func kind(_ n: String) -> String {
            n.hasPrefix("darwin") ? "Mac" : n.lowercased().hasPrefix("iphone") ? "iPhone" : n.hasPrefix("android") ? "Android" : n.hasPrefix("win32") ? "Windows" : n.hasPrefix("linux") ? "Linux" : "Device"
        }
        var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-._~")
        let order = "\"$key\"".addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        for key in books.keys.sorted() {
            let info = (try await rtdb("GET", "books/\(key)/info")) as? [String: Any] ?? [:]
            if info["merged_into"] != nil { continue }   // its changes were moved into another book (merge)
            let last = (try await rtdb("GET", "books/\(key)/log", query: "&orderBy=\(order)&limitToLast=300")) as? [String: Any] ?? [:]
            var used = Set<String>()
            for case let e as [String: Any] in last.values {
                let sl = Int(JS.number(e["s"]))
                guard sl > 0 else { continue }
                let n = sl <= slots.count ? ((dev[slots[sl - 1]] as? [String: Any])?["name"] as? String ?? "") : ""
                used.insert(mine.contains(sl) ? "this device" : kind(n))
            }
            let fyR = (info["fy"] as? String) ?? "", fyL = row.map { JS.string(unwrap($0["fy"]) ?? "") } ?? ""
            let same = row != nil && norm(info["name"]) == norm(row!["name"]) && fyR == fyL && m[String(cid ?? 0)] != key
            out.append(["key": key, "name": (info["name"] as? String) ?? "Company", "fy": info["fy"] ?? NSNull(), "on_this_device": here.contains(key), "same_name": same,
                        "open": cid.map { m[String($0)] == key } ?? false, "used_by": used.sorted()])
        }
        return ["books": out, "can_merge": cid.map { m[String($0)] != nil } ?? false]
    }

    /// Where the starting copy ends in a book's log: info.snap, or (older books) the first run of entries sent together.
    static func snapshotEnd(_ keys: [String], _ log: [String: Any], _ info: [String: Any]) -> String? {
        if let s = info["snap"] as? String, keys.contains(s) { return s }
        guard let first = keys.first else { return nil }
        let s0 = JS.number((log[first] as? [String: Any])?["s"])
        var end = first
        for i in 1..<max(keys.count, 1) where i < keys.count {
            let b = log[keys[i]] as? [String: Any] ?? [:]
            if b["x"] != nil || JS.number(b["s"]) != s0 || pushTime(keys[i]) - pushTime(keys[i - 1]) > 10000 { break }
            end = keys[i]
        }
        return end
    }

    /// The slots that are this device: its own, and earlier installs of the same kind (an iPhone that signed out and in
    /// again registered anew).
    func mySlots() async throws -> Set<Int> {
        let dev = (try await rtdb("GET", "devices")) as? [String: Any] ?? [:]
        let (me, sl) = try await inDB { (try self.app("sync_device"), try self.slotNow()) }
        let name = me.flatMap { (dev[$0] as? [String: Any])?["name"] as? String }
        var out: Set<Int> = [sl]
        for (i, k) in dev.keys.sorted().enumerated() where name != nil && (dev[k] as? [String: Any])?["name"] as? String == name { out.insert(i + 1) }
        return out
    }

    /// Two copies of one company (each device turned sync on for its own): the open company stays, and the other copy's
    /// changes since its starting copy are replayed on it and sent out; the devices on the other copy move here by
    /// themselves on their next sync (follow). backend/src/services/sync.js merge.
    func merge(_ cid: Int, _ key: String) async throws -> Row {
        let m = try await inDB { try self.map() }
        guard let tKey = m[String(cid)] else { throw HttpError(400, "Turn on sync for this company first, or use Bring here.") }
        if key.isEmpty || key == tKey { throw HttpError(400, "Choose the other copy of this company.") }
        guard let row = try await inDB({ try self.engine.companyRow(cid) }) else { throw HttpError(404, "Company not found") }
        guard let srcInfo = (try await rtdb("GET", "books/\(key)/info")) as? [String: Any] else { throw HttpError(404, "That company is no longer in the sync account.") }
        let srcCid = m.first(where: { $0.value == key }).flatMap { Int($0.key) }
        if let srcCid { try await syncCompany(srcCid) }            // that copy's last changes here are in its book first
        try await syncCompany(cid)
        let log = (try await rtdb("GET", "books/\(key)/log")) as? [String: Any] ?? [:]
        let keys = log.keys.sorted()
        let end = Sync.snapshotEnd(keys, log, srcInfo)
        let after = end.map { e in keys.filter { $0 > e } } ?? []
        if after.contains(where: { (log[$0] as? [String: Any])?["x"] != nil }) {
            throw HttpError(409, "A backup was restored on that copy after sync was turned on, so it cannot be merged.")
        }
        let entries = after.compactMap { log[$0] as? [String: Any] }.filter { $0["c"] != nil }
        let snap = keys.filter { end == nil || $0 <= end! }.compactMap { log[$0] as? [String: Any] }
        try await inDB {
            guard let d = try self.engine.openCompany(cid) else { throw HttpError(404, "Company not found") }
            // both copies must have started from the same books (same items and parties under the same ids)
            var probe = 0, same = 0
            for e in snap {
                for case let c as [String: Any] in (e["c"] as? [Any] ?? []) {
                    guard let t = c["t"] as? String, t == "items" || t == "parties", let r = c["r"] as? [String: Any] else { continue }
                    probe += 1
                    if let x = try d.prepare("SELECT name FROM \(t) WHERE id=?").get(c["k"] ?? NSNull()), x.str("name") == JS.string(r["name"]) { same += 1 }
                }
            }
            if probe > 0 && Double(same) / Double(probe) < 0.8 {
                throw HttpError(409, "The two copies of \(row.str("name")) did not start from the same books (different items and parties), so they cannot be merged. Keep one: stop syncing the other one on the device that uses it.")
            }
            _ = try self.backup.backupNow(reason: "before-merge")
            try self.replayInto(cid, d, entries)
        }
        // the devices still on that copy move to this one by themselves on their next sync (follow)
        _ = try await rtdb("PUT", "books/\(key)/info/merged_at", keys.last ?? "")
        _ = try await rtdb("PUT", "books/\(key)/info/merged_into", tKey)
        if let srcCid { try await inDB { try self.moved(srcCid, cid) } }
        do { try await syncCompany(cid) } catch { locked { _lastError = (error as? HttpError)?.message ?? error.localizedDescription } }
        locked { _version += 1 }
        var r = try await status(cid)
        r["company_id"] = cid
        r["merged"] = entries.count
        return r
    }

    /// Book changes replayed on company tid (inside the queue): applied, bill numbers used twice settled, sent out.
    func replayInto(_ tid: Int, _ d: Database, _ entries: [[String: Any]]) throws {
        _ = try apply(tid, d, entries)
        try d.transaction {
            // a bill whose number the other copy had already used takes the next number (its ledger lines follow)
            for (tbl, (col, series)) in Sync.numbered {
                for r in try d.prepare("SELECT id, date, \(col) AS no FROM \(tbl) WHERE \(col) LIKE '%~%'").all() {
                    let old = String(r.str("no").split(separator: "~").first ?? "")
                    let fresh = try nextNo(d, series, r.s("date"))
                    let lo = (r.i("id") / Sync.range) * Sync.range, hi = lo + Sync.range
                    try d.prepare("UPDATE \(tbl) SET \(col)=? WHERE id=?").run(fresh, r.i("id"))
                    try d.prepare("UPDATE ledger SET ref_no=?, narration=REPLACE(narration, ?, ?) WHERE ref_no=? AND id > ? AND id < ?").runArgs([fresh, old, fresh, old, lo, hi])
                    try d.prepare("INSERT INTO sync_out(tbl,rid,op) SELECT 'ledger', id, 'u' FROM ledger WHERE ref_no=? AND id > ? AND id < ?").run(fresh, lo, hi)
                    try d.prepare("INSERT INTO sync_out(tbl,rid,op) VALUES(?,?,'u')").run(tbl, r.i("id"))
                }
            }
            // the replayed changes go out to the other devices (a batch's stock as the change it made)
            for e in entries {
                for case let c as [String: Any] in (e["c"] as? [Any] ?? []) {
                    let t = JS.string(c["t"]), k: Any = c["k"] ?? NSNull()
                    if c["r"] == nil { try d.prepare("INSERT INTO sync_out(tbl,rid,op) VALUES(?,?,'d')").run(t, k) }
                    else if t == "batches", let q = unwrap(c["q"]) { try d.prepare("INSERT INTO sync_out(tbl,rid,op,dq) VALUES(?,?,'u',?)").run(t, k, JS.number(q)) }
                    else { try d.prepare("INSERT INTO sync_out(tbl,rid,op) VALUES(?,?,'i')").run(t, k) }
                }
            }
            for c in try d.prepare("SELECT key FROM counters").all() { try d.prepare("INSERT INTO sync_out(tbl,rid,op) VALUES('counters',?,'u')").run(c.str("key")) }
        }
    }

    /// Company `from` was merged into `to` (inside the queue): it is hidden (kept as a backup) and the app switches to `to`.
    func moved(_ from: Int, _ to: Int) throws {
        if let row = try engine.companyRow(from) { try reg.prepare("UPDATE companies SET name=? WHERE id=?").run(row.str("name"), to) }
        try reg.prepare("UPDATE companies SET active=0 WHERE id=?").run(from)
        var mm = try map(); mm[String(from)] = nil; try setMap(mm)
        locked { _moved[String(from)] = to; _companies += 1 }
    }

    /// This company's book was merged into another one (on another device): this device moves there too, and what it
    /// wrote into the old book after the merge is replayed on the other one.
    func follow(_ cid: Int, _ key: String, _ into: String) async throws {
        let sl = try await inDB { try self.slotNow() }
        try await push(cid, key, sl)
        let at = (try await rtdb("GET", "books/\(key)/info/merged_at")) as? String
        var tid = try await inDB { try self.map().first(where: { $0.value == into }).flatMap { Int($0.key) } }
        if tid == nil { tid = try await join(into).i("company_id") } else { try await syncCompany(tid!) }
        guard let t = tid else { return }
        if let at, !at.isEmpty {
            let mine = try await mySlots()
            var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-._~")
            let enc = { (x: String) in x.addingPercentEncoding(withAllowedCharacters: allowed) ?? x }
            let page = (try await rtdb("GET", "books/\(key)/log", query: "&orderBy=\(enc("\"$key\""))&startAt=\(enc("\"\(at)\""))")) as? [String: Any] ?? [:]
            let late = page.keys.sorted().filter { $0 > at }.compactMap { page[$0] as? [String: Any] }
                .filter { $0["c"] != nil && mine.contains(Int(JS.number($0["s"]))) }
            if !late.isEmpty { try await inDB { guard let d = try self.engine.openCompany(t) else { return }; try self.replayInto(t, d, late) } }
        }
        try await inDB { try self.moved(cid, t) }
        locked { _version += 1 }
    }

    /// Bring a synced company onto this device: a new, empty company that fills itself from the other devices' changes.
    func join(_ key: String) async throws -> Row {
        if key.isEmpty { throw HttpError(400, "Choose the company to bring here.") }
        if try await inDB({ try self.map().values.contains(key) }) { throw HttpError(400, "That company is already synced on this device.") }
        _ = try await slot()
        guard let info = (try await rtdb("GET", "books/\(key)/info")) as? [String: Any] else { throw HttpError(404, "That company is no longer in the sync account.") }
        let cid: Int = try await inDB {
            let cid = try self.engine.createCompany(name: (info["name"] as? String) ?? "Company", fy: info["fy"] as? String)
            guard let d = try self.engine.openCompany(cid) else { throw HttpError(404, "Company not found") }
            // start empty: every row (settings too) comes from the other devices
            for t in try self.tables(d) { try d.exec("DELETE FROM \(t.name)") }
            var m = try self.map(); m[String(cid)] = key; try self.setMap(m)
            self.attach(cid, d)
            try d.exec("DELETE FROM sync_out")
            return cid
        }
        do { try await syncCompany(cid); locked { _lastError = nil } } catch { locked { _lastError = (error as? HttpError)?.message ?? error.localizedDescription } }
        try await inDB {
            if let d = try self.engine.openCompany(cid), let nm = try d.prepare("SELECT value FROM settings WHERE key='company_name'").get()?.s("value"), !nm.isEmpty {
                try self.reg.prepare("UPDATE companies SET name=? WHERE id=?").run(nm, cid)
            }
        }
        locked { _version += 1 }
        var r = try await status(cid)
        r["company_id"] = cid
        return r
    }

    func status(_ cid: Int?) async throws -> Row {
        let base: Row = try await inDB {
            let m = try self.map()
            let companies: [Row] = try self.reg.prepare("SELECT id,name,fy FROM companies WHERE active=1 ORDER BY id").all().map {
                ["id": $0.i("id"), "name": $0.str("name"), "fy": $0.v("fy") ?? NSNull(), "synced": m[String($0.i("id"))] != nil]
            }
            var pending = 0
            let on = cid.map { m[String($0)] != nil } ?? false
            if on, let c = cid, let d = try self.engine.openCompany(c) { pending = (try? d.prepare("SELECT COUNT(*) AS n FROM sync_out").get()?.i("n")) ?? 0 }
            return ["signed_in": try self.app("sync_uid") != nil, "email": try self.app("sync_email") ?? "", "slot": try self.slotNow(),
                    "on": on, "companies": companies, "pending": pending] as Row
        }
        var r = base
        for (k, v) in brief(true) where k != "on" { r[k] = v }
        r["errors"] = locked { _errors }
        r["database"] = Sync.databaseURL
        r["rules"] = Sync.rules
        return r
    }

    /// GET /sync, /sync/tick, /sync/remote · POST /sync/signin, signout, on, off, now, join (routes/sync.js).
    func route(_ m: String, _ s: [String], _ b: Row, _ companyId: Int?) async throws -> Reply? {
        func ok(_ v: Any) -> Reply { .json(200, v) }
        let cid: Int? = try await inDB { (companyId ?? 0) != 0 ? companyId : try self.engine.firstCompanyId() }
        if s.count == 1 && m == "GET" { return ok(try await status(cid)) }
        guard s.count == 2 else { return nil }
        switch (m, s[1]) {
        case ("GET", "tick"): return ok(await tick())
        case ("GET", "remote"): return ok(try await remote(cid))
        case ("POST", "merge"): return ok(try await merge(cid ?? 0, b.str("key")))
        case ("POST", "signin"): try await signIn(b); return ok(try await status(cid))
        case ("POST", "signout"): try await inDB { try self.signOut() }; return ok(try await status(cid))
        case ("POST", "on"): return ok(try await turnOn(cid ?? 0))
        case ("POST", "off"): try await inDB { try self.turnOff(cid ?? 0) }; return ok(try await status(cid))
        case ("POST", "now"): _ = await tick(); return ok(try await status(cid))
        case ("POST", "join"): return ok(try await join(b.str("key")))
        default: return nil
        }
    }
}
