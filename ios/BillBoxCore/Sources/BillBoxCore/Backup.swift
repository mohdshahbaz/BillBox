import Foundation

/// Local-disk backups (backend/src/services/backup.js). For each company it writes a consistent copy of the SQLite file with
/// VACUUM INTO, verifies it with PRAGMA integrity_check, records a SHA-256 in a manifest. Folder layout:
///   <backup_dir>/FMCG_Backup_YYYYMMDD_HHMMSS/<Company>_<id>.db, registry.db, manifest.json
public final class Backup {
    let engine: Engine
    static let PREFIX = "FMCG_Backup_"
    static let FOLDER_RE = rx("^FMCG_Backup_\\d{8}_\\d{6}(_\\d+)?$")
    /// The backup folder used when none was chosen (Mac: ~/DistributorProBackups). The iOS app points it into its Documents folder.
    public static var defaultDir: String = (NSHomeDirectory() as NSString).appendingPathComponent("DistributorProBackups")
    /// Lets the iOS app resolve a folder picked in Files (security-scoped) before it is used.
    public static var accessFolder: ((String) -> (() -> Void)?)?

    init(_ engine: Engine) { self.engine = engine }
    var reg: Database { engine.registry }

    func getSetting(_ k: String, _ d: String) throws -> String {
        try reg.prepare("SELECT value FROM app_settings WHERE key=?").get(k)?.s("value") ?? d
    }
    func setSetting(_ k: String, _ v: String) throws {
        try reg.prepare("INSERT INTO app_settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value").run(k, v)
    }

    public func config() throws -> Row {
        [
            "dir": try getSetting("backup_dir", Backup.defaultDir),
            "enabled": try getSetting("backup_enabled", "0") == "1",
            "time": try getSetting("backup_time", "21:00"),
            "on_exit": try getSetting("backup_on_exit", "0") == "1",
            "last_run": try getSetting("backup_last_run", ""),
            "last_status": try getSetting("backup_last_status", ""),
        ]
    }

    func saveConfig(_ b: Row) throws -> Row {
        if b.defined("dir") {
            let dir = JS.string(b["dir"] ?? nil)
            if !dir.hasPrefix("/") { throw HttpError(400, "Enter the full path of the backup folder, e.g. /Volumes/MyDrive/Backups") }
            try setSetting("backup_dir", dir)
        }
        if b.defined("enabled") { try setSetting("backup_enabled", JS.truthy(b["enabled"]) ? "1" : "0") }
        if b.defined("on_exit") { try setSetting("backup_on_exit", JS.truthy(b["on_exit"]) ? "1" : "0") }
        if b.defined("time") {
            let t = JS.string(b["time"] ?? nil)
            if !rx("^([01]\\d|2[0-3]):[0-5]\\d$").test(t) { throw HttpError(400, "Time must be HH:MM (24 hour)") }
            try setSetting("backup_time", t)
        }
        return try config()
    }

    static func stamp(_ d: Date = Clock.now) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: d)
        func p(_ n: Int?) -> String { String(n ?? 0).padStart(2, "0") }
        return "\(c.year ?? 0)\(p(c.month))\(p(c.day))_\(p(c.hour))\(p(c.minute))\(p(c.second))"
    }
    static func slug(_ s: String) -> String {
        var x = rx("[^A-Za-z0-9]+", "g").replace(s, "_")
        x = rx("^_+|_+$", "g").replace(x, "")
        let out = x.jsSlice(0, 40)
        return out.isEmpty ? "Company" : out
    }
    static func sqlPath(_ p: String) -> String { p.replacingOccurrences(of: "'", with: "''") }

    static func sha256(_ file: String) throws -> String {
        let d = try Data(contentsOf: URL(fileURLWithPath: file))
        return SHA256.hex(d)
    }

    static func fileSize(_ p: String) -> Int { ((try? FileManager.default.attributesOfItem(atPath: p))?[.size] as? NSNumber)?.intValue ?? 0 }

    func copyAndVerify(_ raw: Database, _ dest: String) throws -> Row {
        try raw.exec("VACUUM INTO '\(Backup.sqlPath(dest))'")
        let chk = try Database(dest, readonly: true)
        defer { chk.close() }
        let r = try chk.prepare("PRAGMA integrity_check").get() ?? [:]
        let v = r.values.first.map { JS.string($0) } ?? ""
        if v != "ok" { throw HttpError(500, "Backup verification failed for \((dest as NSString).lastPathComponent): \(v)") }
        return ["file": (dest as NSString).lastPathComponent, "bytes": Backup.fileSize(dest), "sha256": try Backup.sha256(dest)]
    }

    func withFolderAccess<T>(_ dir: String, _ body: () throws -> T) rethrows -> T {
        let release = Backup.accessFolder?(dir)
        defer { release?() }
        return try body()
    }

    public func backupNow(reason: String = "manual") throws -> (folder: String, files: [Row]) {
        let dir = try config().str("dir")
        return try withFolderAccess(dir) {
            let fm = FileManager.default
            do {
                try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
                let probe = (dir as NSString).appendingPathComponent(".write-test-\(ProcessInfo.processInfo.processIdentifier)")
                try Data("ok".utf8).write(to: URL(fileURLWithPath: probe))
                try fm.removeItem(atPath: probe)
            } catch {
                let msg = "Cannot write to \"\(dir)\". Is the drive connected and the folder writable?"
                try setSetting("backup_last_status", "FAILED \(Clock.isoString()): \(msg)")
                throw HttpError(500, msg)
            }
            var folder = (dir as NSString).appendingPathComponent(Backup.PREFIX + Backup.stamp())
            var n = 2
            while fm.fileExists(atPath: folder) { folder = (dir as NSString).appendingPathComponent("\(Backup.PREFIX)\(Backup.stamp())_\(n)"); n += 1 }
            try fm.createDirectory(atPath: folder, withIntermediateDirectories: false)
            do {
                var files: [Row] = []
                for c in try reg.prepare("SELECT * FROM companies WHERE active=1 ORDER BY id").all() {
                    guard let raw = try engine.openCompany(c.i("id")) else { continue }
                    var f: Row = ["company_id": c["id"]!, "company": c["name"]!]
                    if JS.truthy(c["fy"]) { f["fy"] = c.str("fy") }
                    let yearPart = JS.truthy(c["fy"]) ? "_" + c.str("fy") : ""
                    for (k, v) in try copyAndVerify(raw, (folder as NSString).appendingPathComponent("\(Backup.slug(c.str("name")))\(yearPart)_\(c.i("id")).db")) { f[k] = v }
                    files.append(f)
                }
                var r: Row = ["company": "(company list)"]
                for (k, v) in try copyAndVerify(reg, (folder as NSString).appendingPathComponent("registry.db")) { r[k] = v }
                files.append(r)
                let manifest: Row = ["created": Clock.isoString(), "reason": reason, "files": files]
                try JSONText.pretty(manifest).write(toFile: (folder as NSString).appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
                try setSetting("backup_last_run", Clock.isoString())
                try setSetting("backup_last_status", "OK \((folder as NSString).lastPathComponent)")
                return (folder, files)
            } catch {
                try? fm.removeItem(atPath: folder)   // never leave a half-written backup looking valid
                try? setSetting("backup_last_status", "FAILED \(Clock.isoString()): \(Router.message(of: error))")
                throw error
            }
        }
    }

    /// What a picked item holds, after it was copied (and unzipped) into a private folder: a backup folder (one that has
    /// manifest.json), else a single company file (.db). Looks up to three folders deep, so a zipped backup or a folder that
    /// contains the backup folder both work.
    public static func locate(in root: String) -> (folder: String?, file: String?) {
        let fm = FileManager.default
        var level = [root]
        var dbs: [String] = []
        for _ in 0..<4 {
            var next: [String] = []
            for d in level {
                if fm.fileExists(atPath: (d as NSString).appendingPathComponent("manifest.json")) { return (d, nil) }
                for n in ((try? fm.contentsOfDirectory(atPath: d)) ?? []).sorted() where !n.hasPrefix(".") && n != "__MACOSX" {
                    let p = (d as NSString).appendingPathComponent(n)
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: p, isDirectory: &isDir) else { continue }
                    if isDir.boolValue { next.append(p) } else if n.lowercased().hasSuffix(".db") && n != "registry.db" { dbs.append(p) }
                }
            }
            level = next
        }
        return (nil, dbs.count == 1 ? dbs[0] : nil)
    }

    /// The iPhone keeps its folders under an app folder whose name can change when the app is installed again. A backup folder
    /// saved inside the old app folder is moved over to the same place in the current one.
    public func followAppFolder(documents: String) throws {
        let dir = try getSetting("backup_dir", "")
        guard !dir.isEmpty, !FileManager.default.fileExists(atPath: dir), let r = dir.range(of: "/Documents/") else { return }
        let fixed = (documents as NSString).appendingPathComponent(String(dir[r.upperBound...]))
        try setSetting("backup_dir", fixed)
    }

    /// Removes one backup folder, only when the user asks.
    func deleteBackup(_ name: String) throws -> Row {
        let dir = try config().str("dir")
        let n = (name as NSString).lastPathComponent
        if !Backup.FOLDER_RE.test(n) { throw HttpError(400, "That is not a backup folder made by BillBox.") }
        return try withFolderAccess(dir) {
            let f = (dir as NSString).appendingPathComponent(n)
            if !FileManager.default.fileExists(atPath: f) { throw HttpError(404, "That backup is already gone.") }
            try FileManager.default.removeItem(atPath: f)
            return ["deleted": n]
        }
    }

    public func listBackups() throws -> [Row] {
        let dir = try config().str("dir")
        return withFolderAccess(dir) {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
            return names.filter { Backup.FOLDER_RE.test($0) }.sorted().reversed().map { f -> Row in
                var files = 0, bytes = 0
                var created: Any = NSNull()
                var companies: [String] = []
                if let d = try? Data(contentsOf: URL(fileURLWithPath: (dir as NSString).appendingPathComponent(f + "/manifest.json"))),
                   let m = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let fl = m["files"] as? [[String: Any]] {
                    files = fl.count
                    bytes = fl.reduce(0) { $0 + Int(JS.number($1["bytes"] ?? nil)) }
                    created = m["created"] ?? NSNull()
                    companies = fl.filter { JS.truthy($0["company_id"]) }.map { JS.string($0["company"] ?? nil) }
                }
                return ["name": f, "files": files, "bytes": bytes, "created": created, "companies": companies]
            }
        }
    }

    /// Called every minute while the app is open (and on launch): runs the daily backup once the set time has passed and today's has not run.
    public func tick(_ now: Date = Clock.now) -> (folder: String, files: [Row])? {
        guard let c = try? config(), (c["enabled"] as? Bool) == true else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let comp = cal.dateComponents([.hour, .minute], from: now)
        let hhmm = "\(String(comp.hour ?? 0).padStart(2, "0")):\(String(comp.minute ?? 0).padStart(2, "0"))"
        let todayS = Clock.day(now)
        let lastDay = c.str("last_run").isEmpty ? "" : (Clock.parseISO(c.str("last_run")).map { Clock.day($0) } ?? "")
        if hhmm >= c.str("time") && lastDay != todayS {
            return try? backupNow(reason: "scheduled")
        }
        return nil
    }

    /// Is a scheduled backup due right now (used by the iOS background task)?
    public func isDue(_ now: Date = Clock.now) -> Bool {
        guard let c = try? config(), (c["enabled"] as? Bool) == true else { return false }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let comp = cal.dateComponents([.hour, .minute], from: now)
        let hhmm = "\(String(comp.hour ?? 0).padStart(2, "0")):\(String(comp.minute ?? 0).padStart(2, "0"))"
        let lastDay = c.str("last_run").isEmpty ? "" : (Clock.parseISO(c.str("last_run")).map { Clock.day($0) } ?? "")
        return hhmm >= c.str("time") && lastDay != Clock.day(now)
    }

    // MARK: restore

    func checkFile(_ file: String) throws {
        let base = (file as NSString).lastPathComponent
        var chk: Database?
        do {
            chk = try Database(file, readonly: true)
            let v = (try chk!.prepare("PRAGMA integrity_check").get() ?? [:]).values.first.map { JS.string($0) } ?? ""
            if v != "ok" { throw HttpError(400, "\(base) is damaged (\(v)). Nothing was restored.") }
            if try chk!.prepare("SELECT 1 FROM sqlite_master WHERE name='invoices'").get() == nil { throw HttpError(400, "\(base) is not a BillBox company file.") }
            chk!.close()
        } catch let e as HttpError {
            chk?.close()
            throw e
        } catch {
            chk?.close()
            throw HttpError(400, "\(base) cannot be opened as a database. Nothing was restored.")
        }
    }

    func swapIn(_ src: String, _ row: Row) throws {
        let dest = engine.path(row.str("file"))
        engine.closeCompany(row.i("id"))
        let tmp = dest + ".restoring"
        let fm = FileManager.default
        try? fm.removeItem(atPath: tmp)
        try fm.copyItem(atPath: src, toPath: tmp)
        for ext in ["-wal", "-shm"] { try? fm.removeItem(atPath: dest + ext) }
        if rename(tmp, dest) != 0 { throw HttpError(500, "Could not put the restored file in place.") }
    }

    static func norm(_ n: Any?) -> String { rx("\\s+", "g").replace(JS.trim(JS.truthy(n) ? JS.string(unwrap(n)) : ""), " ").lowercased() }

    /// The company a backup file belongs to is found by NAME, never by number, so a restore cannot overwrite a different company.
    func rowForCompany(_ name: Any?, create: Bool = true, fy: String? = nil) throws -> Row? {
        let wanted = Backup.norm(name)
        let year = (fy?.isEmpty ?? true) ? nil : fy
        // a company's year books share its name: the year tells them apart (nil = books for every year)
        if let hit = try reg.prepare("SELECT * FROM companies").all().first(where: {
            Backup.norm($0["name"] ?? nil) == wanted && (JS.truthy($0["fy"]) ? $0.str("fy") : nil) == year }) {
            if hit.i("active") == 0 { try reg.prepare("UPDATE companies SET active=1 WHERE id=?").run(hit.v("id")) }
            return hit
        }
        if !create { return nil }
        let nm = JS.trim(JS.truthy(name) ? JS.string(unwrap(name)) : "Restored company")
        let id = try engine.createCompany(name: nm, fy: year)
        return try reg.prepare("SELECT * FROM companies WHERE id=?").get(id)
    }

    func companyNameInFile(_ file: String) -> String? { companyInFile(file).name }

    /// (name, fy) as the file itself records them (fy only for one year's books).
    func companyInFile(_ file: String) -> (name: String?, fy: String?) {
        guard let d = try? Database(file, readonly: true) else { return (nil, nil) }
        defer { d.close() }
        func v(_ k: String) -> String? {
            guard let r = try? d.prepare("SELECT value FROM settings WHERE key=?").get(k), let x = r.s("value"), !x.isEmpty else { return nil }
            return x
        }
        return (v("company_name"), v("books_fy"))
    }

    /// MERGE: adds what the backup has and these books do not, and changes nothing that already exists (matched by natural keys).
    func mergeInto(_ row: Row, _ file: String) throws -> Row {
        guard let dst = try engine.openCompany(row.i("id")) else { throw HttpError(404, "Company not found") }
        let src = try Database(file, readonly: true)
        defer { src.close() }
        var added: [String: Int] = [:], skipped: [String: Int] = [:]
        var conflicts: [String] = []
        func add(_ k: String) { added[k] = (added[k] ?? 0) + 1 }
        func skip(_ k: String) { skipped[k] = (skipped[k] ?? 0) + 1 }
        func all(_ t: String) -> [Row] { (try? src.prepare("SELECT * FROM \(t)").all()) ?? [] }
        func cols(_ t: String) throws -> [String] { try dst.prepare("PRAGMA table_info(\(t))").all().map { $0.str("name") }.filter { $0 != "id" } }
        func insert(_ t: String, _ rec: Row) throws -> Int {
            let cs = try cols(t).filter { rec[$0] != nil }
            var args: [String: Any] = [:]
            for c in cs { args[c] = rec[c]! }
            return try dst.prepare("INSERT INTO \(t)(\(cs.joined(separator: ","))) VALUES(\(cs.map { "@" + $0 }.joined(separator: ",")))").run(args).lastInsertRowid
        }
        func key(_ v: Any?) -> String { Backup.norm(v) }
        func idx(_ t: String, _ f: String) throws -> [String: Int] {
            var m: [String: Int] = [:]
            for r in try dst.prepare("SELECT id,\(f) v FROM \(t)").all() { m[key(r["v"] ?? nil)] = r.i("id") }
            return m
        }
        var maps: [String: [Int: Int]] = ["categories": [:], "salesmen": [:], "routes": [:], "parties": [:], "items": [:], "batches": [:], "invoices": [:], "purchases": [:], "debit_notes": [:]]
        var newParties = Set<Int>()
        func m(_ name: String, _ id: Any?) -> Any {
            guard let i = intId(unwrap(id)), let v = maps[name]?[i] else { return NSNull() }
            return v
        }
        func byName(_ table: String, _ mapOut: ((Row) -> Row)? = nil) throws {
            var have = try idx(table, "name")
            for r in all(table) {
                var id = have[key(r["name"] ?? nil)]
                if id != nil { skip(table) } else {
                    var rec = r
                    if let mo = mapOut { for (k, v) in mo(r) { rec[k] = v } }
                    id = try insert(table, rec)
                    have[key(r["name"] ?? nil)] = id
                    add(table)
                }
                maps[table]![r.i("id")] = id!
            }
        }

        try dst.transaction {
            try byName("categories")
            try byName("salesmen")
            try byName("routes") { r in ["salesman_id": m("salesmen", r["salesman_id"] ?? nil)] }
            // parties: matched by name, a customer and a supplier with the same name are different parties
            var haveP: [String: Int] = [:]
            for r in try dst.prepare("SELECT id,name,type FROM parties").all() { haveP[key(r["name"] ?? nil) + "|" + (r.str("type") == "SUPPLIER" ? "S" : "C")] = r.i("id") }
            for r in all("parties") {
                let k = key(r["name"] ?? nil) + "|" + (r.str("type") == "SUPPLIER" ? "S" : "C")
                var id = haveP[k]
                if id != nil { skip("parties") } else {
                    var rec = r
                    rec["route_id"] = m("routes", r["route_id"] ?? nil)
                    id = try insert("parties", rec)
                    haveP[k] = id
                    newParties.insert(id!)
                    add("parties")
                }
                maps["parties"]![r.i("id")] = id!
            }
            var haveI = try idx("items", "name")
            for r in all("items") {
                var id = haveI[key(r["name"] ?? nil)]
                if id != nil { skip("items") } else {
                    var rec = r
                    rec["category_id"] = m("categories", r["category_id"] ?? nil)
                    id = try insert("items", rec)
                    haveI[key(r["name"] ?? nil)] = id
                    add("items")
                }
                maps["items"]![r.i("id")] = id!
            }
            var haveB: [String: Int] = [:]
            for r in try dst.prepare("SELECT id,item_id,batch_no FROM batches").all() { haveB["\(r.i("item_id"))|" + key(r["batch_no"] ?? nil)] = r.i("id") }
            for r in all("batches") {
                guard let itemId = maps["items"]![r.i("item_id")] else { continue }
                let k = "\(itemId)|" + key(r["batch_no"] ?? nil)
                var id = haveB[k]
                if id != nil { skip("batches") } else {
                    var rec = r
                    rec["item_id"] = itemId
                    id = try insert("batches", rec)
                    haveB[k] = id
                    add("batches")
                }
                maps["batches"]![r.i("id")] = id!
            }
            func schemeKey(_ a: Any?, _ r: Row) -> String {
                [JS.string(a), JS.string(r["type"] ?? nil), JS.string(r["buy_qty"] ?? nil), JS.string(r["free_qty"] ?? nil), JS.string(r["percent"] ?? nil)].joined(separator: "|")
            }
            var haveS = Set<String>()
            for r in try dst.prepare("SELECT item_id,type,buy_qty,free_qty,percent FROM schemes").all() { haveS.insert(schemeKey(r["item_id"] ?? nil, r)) }
            for r in all("schemes") {
                let itemId = maps["items"]![r.i("item_id")]
                let k = schemeKey(itemId.map { $0 as Any } ?? NSNull(), r)
                if itemId == nil || haveS.contains(k) { skip("schemes"); continue }
                var rec = r
                rec["item_id"] = itemId!
                _ = try insert("schemes", rec)
                haveS.insert(k)
                add("schemes")
            }

            // documents: by number
            func document(_ table: String, _ noCol: String, _ lineTable: String, _ fk: String, _ convert: (Row) -> Row, _ lineConvert: (Row, Int) -> Row, _ label: String) throws {
                var have: [String: Row] = [:]
                for r in try dst.prepare("SELECT id,\(noCol) no,date,total FROM \(table)").all() { have[r.str("no")] = r }
                let lines = all(lineTable)
                for r in all(table) {
                    if let cur = have[r.str(noCol)] {
                        if cur.str("date") == r.str("date") && abs(cur.n("total") - r.n("total")) < 0.005 { skip(table) } else {
                            conflicts.append("\(label) \(r.str(noCol)) exists here with different details; left as it is")
                            skip(table)
                        }
                        maps[table]![r.i("id")] = cur.i("id")
                        continue
                    }
                    var rec = r
                    for (k, v) in convert(r) { rec[k] = v }
                    let id = try insert(table, rec)
                    maps[table]![r.i("id")] = id
                    add(table)
                    for l in lines where l.i(fk) == r.i("id") {
                        guard let itemId = maps["items"]![l.i("item_id")] else { continue }
                        var lr = l
                        lr[fk] = id
                        for (k, v) in lineConvert(l, itemId) { lr[k] = v }
                        _ = try insert(lineTable, lr)
                    }
                }
            }
            try document("invoices", "invoice_no", "invoice_lines", "invoice_id",
                         { r in ["party_id": m("parties", r["party_id"] ?? nil), "salesman_id": m("salesmen", r["salesman_id"] ?? nil)] },
                         { l, itemId in ["item_id": itemId, "batch_id": m("batches", l["batch_id"] ?? nil)] }, "Bill")
            try document("purchases", "purchase_no", "purchase_lines", "purchase_id",
                         { r in ["party_id": m("parties", r["party_id"] ?? nil)] },
                         { l, itemId in ["item_id": itemId, "batch_id": m("batches", l["batch_id"] ?? nil)] }, "Purchase")
            // debit notes: by number, with their lines and the batches the pieces left (stock of existing batches is not changed)
            do {
                var have: [String: Row] = [:]
                for r in try dst.prepare("SELECT id,note_no no,date,total FROM debit_notes").all() { have[r.str("no")] = r }
                let lines = all("debit_note_lines"), stock = all("debit_note_stock")
                for r in all("debit_notes") {
                    if let cur = have[r.str("note_no")] {
                        if cur.str("date") == r.str("date") && abs(cur.n("total") - r.n("total")) < 0.005 { skip("debit_notes") } else {
                            conflicts.append("Debit note \(r.str("note_no")) exists here with different details; left as it is")
                            skip("debit_notes")
                        }
                        maps["debit_notes"]![r.i("id")] = cur.i("id")
                        continue
                    }
                    let pid = m("parties", r["party_id"] ?? nil)
                    if pid is NSNull { continue }
                    var rec = r
                    rec["party_id"] = pid
                    rec["purchase_id"] = m("purchases", r["purchase_id"] ?? nil)
                    let id = try insert("debit_notes", rec)
                    maps["debit_notes"]![r.i("id")] = id
                    add("debit_notes")
                    for l in lines where l.i("note_id") == r.i("id") {
                        guard let itemId = maps["items"]![l.i("item_id")] else { continue }
                        var lr = l
                        lr["note_id"] = id
                        lr["item_id"] = itemId
                        lr["batch_id"] = m("batches", l["batch_id"] ?? nil)
                        let lid = try insert("debit_note_lines", lr)
                        for st in stock where st.i("line_id") == l.i("id") {
                            let b = m("batches", st["batch_id"] ?? nil)
                            if b is NSNull { continue }
                            var sr = st
                            sr["line_id"] = lid
                            sr["batch_id"] = b
                            _ = try insert("debit_note_stock", sr)
                        }
                    }
                }
            }
            // a bill line must have a batch; drop any invoice line that lost it (it cannot happen with this app's own backups)
            try dst.exec("DELETE FROM invoice_lines WHERE batch_id IS NULL")

            func voucher(_ table: String, _ noCol: String, _ extra: (Row) -> Row) throws {
                var have = Set(try dst.prepare("SELECT \(noCol) no FROM \(table)").all().map { $0.str("no") })
                for r in all(table) {
                    if have.contains(r.str(noCol)) { skip(table); continue }
                    let pid = m("parties", r["party_id"] ?? nil)
                    if pid is NSNull { continue }
                    var rec = r
                    rec["party_id"] = pid
                    rec["salesman_id"] = m("salesmen", r["salesman_id"] ?? nil)
                    for (k, v) in extra(r) { rec[k] = v }
                    _ = try insert(table, rec)
                    have.insert(r.str(noCol))
                    add(table)
                }
            }
            try voucher("receipts", "receipt_no") { r in ["invoice_id": m("invoices", r["invoice_id"] ?? nil)] }
            try voucher("payments", "voucher_no") { r in ["purchase_id": m("purchases", r["purchase_id"] ?? nil)] }

            // ledger: new parties bring their whole ledger (with opening balance); existing parties only get lines they do not have yet
            func lkey(_ pid: Any?, _ r: Row) -> String {
                [JS.string(pid), JS.string(r["type"] ?? nil), r.str("ref_no"), JS.string(r["date"] ?? nil), JS.string(r["debit"] ?? nil), JS.string(r["credit"] ?? nil)].joined(separator: "|")
            }
            var haveL = Set<String>()
            for r in try dst.prepare("SELECT party_id,type,IFNULL(ref_no,'') ref_no,date,debit,credit FROM ledger").all() { haveL.insert(lkey(r["party_id"] ?? nil, r)) }
            for r in all("ledger") {
                let pidAny = m("parties", r["party_id"] ?? nil)
                guard let pid = intId(pidAny) else { continue }
                let k = lkey(pid, r)
                if haveL.contains(k) || (!newParties.contains(pid) && r.str("type") == "OPENING") { continue }
                var rec = r
                rec["party_id"] = pid
                _ = try insert("ledger", rec)
                haveL.insert(k)
                add("ledger")
            }
            // numbering never goes backwards
            for c in all("counters") {
                try dst.prepare("INSERT INTO counters(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=MAX(value,excluded.value)").run(c.v("key"), c.v("value"))
            }
        }
        return ["added": added, "skipped": skipped, "conflicts": conflicts]
    }

    func restore(_ b: Row) throws -> Row {
        let merge = (b.v("mode") as? String) == "merge"
        var merged: [Row] = []
        let dir = try config().str("dir")
        var restored: [String] = []
        if JS.truthy(b["file"]) {
            let file = JS.string(b.v("file"))
            var isDir: ObjCBool = false
            if !file.hasPrefix("/") || !FileManager.default.fileExists(atPath: file, isDirectory: &isDir) || isDir.boolValue { throw HttpError(400, "Choose a company backup file (.db).") }
            try checkFile(file)
            // the file knows which company it belongs to; only if it does not is the chosen company used
            let inFile = companyInFile(file)
            let own = inFile.name
            let row = own != nil ? try rowForCompany(own!, create: false, fy: inFile.fy) : nil
            let cid = JS.truthy(b["company_id"]) ? JS.number(b.v("company_id")) : Double(try engine.firstCompanyId() ?? 0)
            guard let target = try row ?? reg.prepare("SELECT * FROM companies WHERE id=?").get(cid) else { throw HttpError(404, "Company not found") }
            _ = try backupNow(reason: "before-restore")
            if merge {
                var mm: Row = ["company": target["name"]!]
                for (k, v) in try mergeInto(target, file) { mm[k] = v }
                merged.append(mm)
            } else { try swapIn(file, target) }
            restored.append(target.str("name"))
        } else {
            let f: String? = JS.truthy(b["folder"]) ? JS.string(b.v("folder")) : (JS.truthy(b["name"]) ? (dir as NSString).appendingPathComponent((JS.string(b.v("name")) as NSString).lastPathComponent) : nil)
            var isDir: ObjCBool = false
            guard let folder = f, folder.hasPrefix("/"), FileManager.default.fileExists(atPath: folder, isDirectory: &isDir), isDir.boolValue else {
                throw HttpError(400, "Choose a backup folder (one that contains manifest.json).")
            }
            let release = Backup.accessFolder?(folder)
            defer { release?() }
            guard let md = try? Data(contentsOf: URL(fileURLWithPath: (folder as NSString).appendingPathComponent("manifest.json"))),
                  let manifest = try? JSONSerialization.jsonObject(with: md) as? [String: Any] else {
                throw HttpError(400, "That folder has no readable manifest.json, so it is not a BillBox backup.")
            }
            let items = ((manifest["files"] as? [Any]) ?? []).compactMap { $0 as? Row }.filter { JS.truthy($0["company_id"]) }
            if items.isEmpty { throw HttpError(400, "That backup contains no company data.") }
            for x in items {
                let p = (folder as NSString).appendingPathComponent(x.str("file"))
                if !FileManager.default.fileExists(atPath: p) { throw HttpError(400, "\(x.str("file")) is missing from the backup folder. Nothing was restored.") }
                if JS.truthy(x["sha256"]), try Backup.sha256(p) != x.str("sha256") { throw HttpError(400, "\(x.str("file")) does not match its checksum (it was changed or damaged). Nothing was restored.") }
                try checkFile(p)
            }
            // companies that exist in the backup but not here are re-created from the backup's own company list
            var bReg: Database?
            let regFile = (folder as NSString).appendingPathComponent("registry.db")
            if FileManager.default.fileExists(atPath: regFile) { bReg = try Database(regFile, readonly: true) }
            defer { bReg?.close() }
            _ = try backupNow(reason: "before-restore")
            for x in items {
                var nm: Any? = x["company"] ?? nil
                if !JS.truthy(nm), let br = bReg { nm = try br.prepare("SELECT name FROM companies WHERE id=?").get(x.v("company_id"))?.v("name") }
                let p = (folder as NSString).appendingPathComponent(x.str("file"))
                guard let row = try rowForCompany(nm, fy: JS.truthy(x["fy"]) ? x.str("fy") : companyInFile(p).fy) else { continue }
                if merge {
                    var mm: Row = ["company": row["name"]!]
                    for (k, v) in try mergeInto(row, p) { mm[k] = v }
                    merged.append(mm)
                } else { try swapIn(p, row) }
                restored.append(row.str("name"))
            }
        }
        for id in try reg.prepare("SELECT id FROM companies").all().map({ $0.i("id") }) { _ = try engine.openCompany(id) }   // reopen + apply schema upgrades
        return ["restored": restored, "mode": merge ? "merge" : "replace", "merged": merged]
    }
}

/// JSON text helpers (JSON.stringify(x, null, 2) for manifests, compact for logs).
public enum JSONText {
    public static func pretty(_ v: Any) throws -> String { try stringify(v, indent: 2) }
    public static func compact(_ v: Any) throws -> String { try stringify(v, indent: 0) }

    static func stringify(_ v: Any?, indent: Int, level: Int = 0) throws -> String {
        let pad = indent > 0 ? "\n" + String(repeating: " ", count: indent * (level + 1)) : ""
        let padEnd = indent > 0 ? "\n" + String(repeating: " ", count: indent * level) : ""
        let colon = indent > 0 ? ": " : ":"
        guard let u = unwrap(v) else { return "null" }
        switch u {
        case let s as String: return quote(s)
        case let b as Bool: return b ? "true" : "false"
        case let i as Int: return String(i)
        case let d as Double: return d.isFinite ? JS.numberString(d) : "null"
        case let a as [Any]:
            if a.isEmpty { return "[]" }
            return "[" + (try a.map { pad + (try stringify($0, indent: indent, level: level + 1)) }.joined(separator: ",")) + padEnd + "]"
        case let o as [String: Any]:
            if o.isEmpty { return "{}" }
            let keys = orderedKeys(o)
            return "{" + (try keys.map { pad + quote($0) + colon + (try stringify(o[$0], indent: indent, level: level + 1)) }.joined(separator: ",")) + padEnd + "}"
        case let n as NSNumber: return JS.numberString(n.doubleValue)
        default: return quote("\(u)")
        }
    }

    /// Manifest keys in the order the Mac writes them, everything else alphabetical.
    static let preferred = ["created", "reason", "files", "company_id", "company", "fy", "file", "bytes", "sha256"]
    static func orderedKeys(_ o: [String: Any]) -> [String] {
        let pref = preferred.filter { o[$0] != nil }
        return pref + o.keys.filter { !preferred.contains($0) }.sorted()
    }

    static func quote(_ s: String) -> String {
        var out = "\""
        for ch in s.unicodeScalars {
            switch ch {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if ch.value < 0x20 { out += String(format: "\\u%04x", ch.value) } else { out.unicodeScalars.append(ch) }
            }
        }
        return out + "\""
    }
}

/// SHA-256 (FIPS 180-4), so backups carry the same checksums as on the Mac without extra packages.
public enum SHA256 {
    static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
        0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
        0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
        0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    public static func hex(_ data: Data) -> String {
        var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
        var msg = [UInt8](data)
        let bitLen = UInt64(msg.count) * 8
        msg.append(0x80)
        while msg.count % 64 != 56 { msg.append(0) }
        for i in (0..<8).reversed() { msg.append(UInt8((bitLen >> (UInt64(i) * 8)) & 0xff)) }
        var w = [UInt32](repeating: 0, count: 64)
        func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }
        var chunk = 0
        while chunk < msg.count {
            for i in 0..<16 {
                let b = chunk + i * 4
                w[i] = UInt32(msg[b]) << 24 | UInt32(msg[b + 1]) << 16 | UInt32(msg[b + 2]) << 8 | UInt32(msg[b + 3])
            }
            for i in 16..<64 {
                let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7]
            for i in 0..<64 {
                let S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch = (e & f) ^ (~e & g)
                let t1 = hh &+ S1 &+ ch &+ k[i] &+ w[i]
                let S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let t2 = S0 &+ maj
                hh = g; g = f; f = e; e = d &+ t1; d = c; c = b; b = a; a = t1 &+ t2
            }
            h[0] = h[0] &+ a; h[1] = h[1] &+ b; h[2] = h[2] &+ c; h[3] = h[3] &+ d
            h[4] = h[4] &+ e; h[5] = h[5] &+ f; h[6] = h[6] &+ g; h[7] = h[7] &+ hh
            chunk += 64
        }
        return h.map { String(format: "%08x", $0) }.joined()
    }
}
