import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Licence and subscription (backend/src/services/license.js, the same rules on every BillBox): a 15-day trial, then
/// read-only until a licence key is entered; the licence server turns the key into a signed activation for this device,
/// checked here without the internet and renewed online every few weeks.
public final class License {
    let backup: Backup
    let db: (@escaping () throws -> Any) async throws -> Any
    init(_ backup: Backup, db: @escaping (@escaping () throws -> Any) async throws -> Any) { self.backup = backup; self.db = db }

    /// "public" (the App Store / website app), "admin" (the owner's test build) or "" (tests: nothing is limited).
    public static var edition = ""

    static let SITE = "https://billbox-app.pages.dev"
    static let KEYS = ["live": "n5iJULtiUQmzWASMw96LVf9kQ6y5z77934tbchjqhpE", "test": "pL2sd4UksOSqnzAlNDcYtgcquKYTxZYu9fR0c0vbHVY"]
    static let TRIAL_DAYS = 15
    static let DAY = 86_400_000.0
    static let RENEW_BEFORE = 20 * DAY

    var env: String { License.edition == "public" ? "live" : "test" }
    var server: String { "\(License.SITE)/api/\(env)" }
    static func now() -> Double { (Date().timeIntervalSince1970 * 1000).rounded() }

    // settings, read and written in the router's turn
    func get(_ k: String) throws -> String { try backup.getSetting(k, "") }
    func set(_ k: String, _ v: String) throws { try backup.setSetting(k, v) }
    func del(_ ks: [String]) throws { for k in ks { try backup.reg.prepare("DELETE FROM app_settings WHERE key=?").run(k) } }

    // MARK: tokens

    static func bytes(_ b64url: String) -> Data? {
        var s = b64url.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        return Data(base64Encoded: s)
    }

    static func verify(_ sig: Data, _ message: Data, _ key: Data) -> Bool {
        #if canImport(CryptoKit)
        guard let pk = try? Curve25519.Signing.PublicKey(rawRepresentation: key) else { return false }
        return pk.isValidSignature(sig, for: message)
        #else
        return false
        #endif
    }

    /// The payload of a token signed with the edition's key (or `keyEnv`), or nil.
    func read(_ token: String, keyEnv: String? = nil) -> [String: Any]? {
        let e = keyEnv ?? env
        let t = token.components(separatedBy: .whitespacesAndNewlines).joined()
        let parts = t.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts[0] == "BB1", let body = License.bytes(parts[1]), let sig = License.bytes(parts[2]),
              let key = License.KEYS[e].flatMap(License.bytes),
              let p = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any], p["env"] as? String == e,
              License.verify(sig, Data("\(parts[0]).\(parts[1])".utf8), key) else { return nil }
        return p
    }

    static func num(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue ?? (v as? Double) }
    static func day(_ ms: Double) -> String { String(ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: ms / 1000)).prefix(10)) }

    // MARK: this device

    func device() throws -> String {
        var d = try get("license_device")
        if d.isEmpty {
            d = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(20)).uppercased()
            try set("license_device", d)
        }
        return d
    }

    func trialStart() throws -> Double {
        var t = Double(try get("license_trial_start")) ?? 0
        if t == 0 { t = License.now(); try set("license_trial_start", String(Int64(t))) }
        return t
    }

    func activation() throws -> [String: Any]? {
        guard let a = read(try get("license_activation")), a["t"] as? String == "act", a["dev"] as? String == (try device()) else { return nil }
        return a
    }

    func status() throws -> Row {
        let ed = License.edition
        if ed.isEmpty { return ["edition": "", "state": "unlimited", "writable": true] }
        let now = License.now(), dev = try device()
        var base: Row = ["edition": ed, "env": env, "device": dev, "site": License.SITE,
                         "buy_url": "\(License.SITE)/buy.html?device=\(dev)" + (ed == "admin" ? "&test=1" : "")]
        let a = try activation()
        let lexp = License.num(a?["lexp"]), exp = License.num(a?["exp"]) ?? 0
        if let a, (lexp == nil || lexp! > now), exp > now {
            base["state"] = "licensed"; base["writable"] = true
            base["plan"] = a["plan"] as? String ?? ""; base["email"] = a["email"] as? String ?? ""; base["name"] = a["name"] as? String ?? ""
            base["licence_id"] = a["lic"] as? String ?? ""
            if let l = lexp { base["expires"] = License.day(l) } else { base["expires"] = NSNull() }
            base["renew_by"] = License.day(exp)
            base["needs_renewal"] = exp - now < License.RENEW_BEFORE
            base["last_check"] = try get("license_checked")
            return base
        }
        let left = min(License.TRIAL_DAYS, max(0, Int(((try trialStart()) + Double(License.TRIAL_DAYS) * License.DAY - now) / License.DAY + 0.999999)))
        base["state"] = left > 0 ? "trial" : "expired"
        base["writable"] = left > 0
        base["trial_days"] = License.TRIAL_DAYS
        base["trial_days_left"] = left
        base["reason"] = a == nil ? "" : (lexp != nil && lexp! <= now ? "The licence ran out" : "The licence needs to be checked online")
        base["has_key"] = !(try get("license_key")).isEmpty
        return base
    }

    func writable() -> Bool { ((try? status())?["writable"] as? Bool) ?? true }

    // MARK: online

    func call(_ path: String, _ body: [String: Any]) async throws -> [String: Any] {
        guard let u = URL(string: server + path) else { throw HttpError(503, "Could not reach the BillBox licence server.", "OFFLINE") }
        var req = URLRequest(url: u, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp): (Data, URLResponse?) = try await withCheckedThrowingContinuation { c in
            URLSession.shared.dataTask(with: req) { d, r, e in
                if e != nil { c.resume(throwing: HttpError(503, "Could not reach the BillBox licence server. Check the internet connection and try again.", "OFFLINE")) }
                else { c.resume(returning: (d ?? Data(), r)) }
            }.resume()
        }
        let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let st = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if st != 200 { throw HttpError(st == 404 ? 400 : st >= 500 ? 502 : st, j["error"] as? String ?? "The licence server said no (\(st)).", j["code"] as? String) }
        return j
    }

    func activate(_ b: Row) async throws -> Row {
        if License.edition.isEmpty { return try await db { try self.status() } as? Row ?? [:] }
        let stored = (try await db { try self.get("license_key") }) as? String ?? ""
        let given = (b["key"] as? String) ?? ""
        let key = (given.isEmpty ? stored : given).components(separatedBy: .whitespacesAndNewlines).joined()
        guard let lic = read(key), lic["t"] as? String == "lic" else {
            let other = read(key, keyEnv: env == "live" ? "test" : "live") != nil
            throw HttpError(400, other ? (env == "live" ? "That is a test licence key: it works only in the admin (test) BillBox." : "That is a live licence key: it works only in the BillBox from the website.")
                : "That is not a BillBox licence key. Copy the whole key from the e-mail or the website (it starts with BB1.).")
        }
        if let e = License.num(lic["exp"]), e <= License.now() { throw HttpError(400, "This licence ran out on \(License.day(e)). Renew it on \(License.SITE).") }
        let dev = (try await db { try self.device() }) as? String ?? ""
        let r = try await call("/activate", ["key": key, "device": dev, "name": String(((b["device_name"] as? String) ?? "iPhone").prefix(60))])
        guard let tok = r["activation"] as? String, let a = read(tok), a["t"] as? String == "act", a["dev"] as? String == dev else {
            throw HttpError(502, "The licence server gave an activation that does not check out. Try again.")
        }
        return (try await db {
            try self.set("license_key", key); try self.set("license_activation", tok)
            try self.set("license_checked", ISO8601DateFormatter().string(from: Date()))
            return try self.status()
        }) as? Row ?? [:]
    }

    func renew() async throws -> Row {
        let s = (try await db { try self.status() }) as? Row ?? [:]
        let key = (try await db { try self.get("license_key") }) as? String ?? ""
        if License.edition.isEmpty || key.isEmpty || (s["state"] as? String == "licensed" && s["needs_renewal"] as? Bool != true) { return s }
        do { return try await activate([:]) } catch {
            var r = (try await db { try self.status() }) as? Row ?? [:]
            r["renew_error"] = Router.message(of: error)
            return r
        }
    }

    func deactivate() async throws -> Row {
        let key = (try await db { try self.get("license_key") }) as? String ?? ""
        let dev = (try await db { try self.device() }) as? String ?? ""
        if !key.isEmpty { _ = try? await call("/deactivate", ["key": key, "device": dev]) }
        return (try await db { try self.del(["license_key", "license_activation", "license_checked"]); return try self.status() }) as? Row ?? [:]
    }

    func resetTrial() throws -> Row {
        if License.edition != "admin" { throw HttpError(403, "Only the admin (test) BillBox can reset the trial.") }
        try del(["license_key", "license_activation", "license_checked", "license_trial_start"])
        return try status()
    }

    /// Reading, printing, exports, backups and the licence itself always work; the rest needs the trial or a licence.
    func allows(_ method: String, _ segs: [String]) -> Bool {
        if License.edition.isEmpty || method == "GET" || method == "HEAD" { return true }
        if let f = segs.first, ["license", "backup", "sync", "update"].contains(f) { return true }
        if segs.count == 3 && segs[0] == "companies" && segs[2] == "activate" { return true }
        if segs.count == 3 && segs[0] == "invoices" && segs[2] == "printed" { return true }
        if segs.last == "preview" { return true }
        return writable()
    }

    static func blocked() -> HttpError {
        HttpError(402, "Your \(TRIAL_DAYS)-day BillBox trial has ended. Your books are safe and can still be seen, printed and backed up; to add or change anything, buy a licence (Settings › Licence) or enter your licence key.", "LICENSE")
    }

    /// /license/... (outside the queue: the online steps take their own turns for the settings).
    func route(_ m: String, _ s: [String], _ b: Row) async throws -> Reply? {
        func ok(_ v: Any) -> Reply { .json(200, v) }
        if s.count == 1 && m == "GET" { return ok((try await db { try self.status() }) as? Row ?? [:]) }
        guard s.count == 2, m == "POST" else { return nil }
        switch s[1] {
        case "activate": return ok(try await activate(b))
        case "renew": return ok(try await renew())
        case "deactivate": return ok(try await deactivate())
        case "reset-trial": return ok((try await db { try self.resetTrial() }) as? Row ?? [:])
        default: return nil
        }
    }
}
