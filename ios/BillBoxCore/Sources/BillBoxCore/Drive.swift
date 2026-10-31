import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Backups to Google Drive (backend/src/services/drive.js): Google's "TV and limited input" sign-in (a short code entered at
/// google.com/device), the drive.file permission, a "BillBox Backups" folder and one folder per backup inside it.
/// The network parts run outside the router's queue, so an upload never holds up billing; the books are only touched
/// through `db`, which takes its turn in that queue.
public final class Drive {
    let backup: Backup
    let db: (@escaping () throws -> Any) async throws -> Any
    init(_ backup: Backup, db: @escaping (@escaping () throws -> Any) async throws -> Any) { self.backup = backup; self.db = db }

    static let SCOPE = "https://www.googleapis.com/auth/drive.file"
    static let FOLDER = "BillBox Backups"
    static let FOLDER_TYPE = "application/vnd.google-apps.folder"
    static func offline() -> HttpError { HttpError(503, "Could not reach Google. Check the internet connection and try again.", "OFFLINE") }

    // settings (registry app_settings), each read or write in its turn
    func get(_ k: String) async throws -> String { (try await db { try self.backup.getSetting(k, "") }) as? String ?? "" }
    func set(_ k: String, _ v: String) async throws { _ = try await db { try self.backup.setSetting(k, v); return 0 } }
    func del(_ ks: [String]) async throws {
        _ = try await db { for k in ks { try self.backup.reg.prepare("DELETE FROM app_settings WHERE key=?").run(k) }; return 0 }
    }

    static func form(_ o: [(String, String)]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return Data(o.map { "\($0.0.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")=\($0.1.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }.joined(separator: "&").utf8)
    }

    func call(_ url: String, method: String = "GET", headers: [String: String] = [:], body: Data? = nil) async throws -> (status: Int, json: [String: Any]) {
        guard Category.internetAllowed, let u = URL(string: url) else { throw Drive.offline() }
        var req = URLRequest(url: u, timeoutInterval: 120)
        req.httpMethod = method
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = body
        let (data, resp): (Data, URLResponse?) = try await withCheckedThrowingContinuation { c in
            URLSession.shared.dataTask(with: req) { d, r, e in
                if e != nil { c.resume(throwing: Drive.offline()) } else { c.resume(returning: (d ?? Data(), r)) }
            }.resume()
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return ((resp as? HTTPURLResponse)?.statusCode ?? 0, json)
    }
    static let FORM = ["content-type": "application/x-www-form-urlencoded"]
    static func why(_ j: [String: Any], _ status: Int) -> String {
        if let d = j["error_description"] as? String, !d.isEmpty { return d }
        if let e = j["error"] as? String, !e.isEmpty { return e }
        if let e = j["error"] as? [String: Any], let m = e["message"] as? String { return m }
        return String(status)
    }

    func status() async throws -> Row {
        [
            "client_id": try await get("drive_client_id"), "has_secret": try await get("drive_client_secret") != "",
            "connected": try await get("drive_refresh") != "", "waiting": try await get("drive_device") != "",
            "folder": try await get("drive_folder_id").isEmpty ? "" : Drive.FOLDER,
            "last_upload": try await get("drive_last_upload"), "last_status": try await get("drive_last_status"),
        ]
    }

    func saveClient(_ b: Row) async throws -> Row {
        let text = { (k: String) in JS.truthy(b[k] ?? nil) ? JS.trim(JS.string(b.v(k))) : "" }
        let id = text("client_id"), secret = text("client_secret")
        if !id.hasSuffix(".apps.googleusercontent.com") || id == ".apps.googleusercontent.com" {
            throw HttpError(400, "Paste the Client ID from Google Cloud (it ends in .apps.googleusercontent.com).")
        }
        if secret.isEmpty { throw HttpError(400, "Paste the client secret too.") }
        if id != (try await get("drive_client_id")) { try await del(["drive_refresh", "drive_folder_id", "drive_device"]) }
        try await set("drive_client_id", id)
        try await set("drive_client_secret", secret)
        return try await status()
    }

    func connect() async throws -> Row {
        let id = try await get("drive_client_id")
        if id.isEmpty { throw HttpError(400, "Add the Google Client ID and secret first.") }
        let r = try await call("https://oauth2.googleapis.com/device/code", method: "POST", headers: Drive.FORM, body: Drive.form([("client_id", id), ("scope", Drive.SCOPE)]))
        if r.status != 200 { throw HttpError(502, "Google did not give a code (\(Drive.why(r.json, r.status))).") }
        try await set("drive_device", JS.string(r.json["device_code"]))
        return ["user_code": JS.string(r.json["user_code"]),
                "verification_url": (r.json["verification_url"] as? String) ?? (r.json["verification_uri"] as? String) ?? "https://www.google.com/device",
                "interval": r.json["interval"] ?? 5, "expires_in": r.json["expires_in"] ?? 1800]
    }

    func poll() async throws -> Row {
        let dev = try await get("drive_device")
        if dev.isEmpty { throw HttpError(400, "Press Connect first.") }
        let r = try await call("https://oauth2.googleapis.com/token", method: "POST", headers: Drive.FORM, body: Drive.form([
            ("client_id", try await get("drive_client_id")), ("client_secret", try await get("drive_client_secret")), ("device_code", dev),
            ("grant_type", "urn:ietf:params:oauth:grant-type:device_code")]))
        let err = r.json["error"] as? String ?? ""
        if err == "authorization_pending" || err == "slow_down" { return ["connected": false, "waiting": true] }
        try await del(["drive_device"])
        guard r.status == 200, let refresh = r.json["refresh_token"] as? String, !refresh.isEmpty else {
            throw HttpError(400, err == "access_denied" ? "Google sign-in was declined." : err == "expired_token" ? "The code ran out. Press Connect again."
                : "Google did not connect (\(Drive.why(r.json, r.status))).")
        }
        try await set("drive_refresh", refresh)
        _ = try await folder(JS.string(r.json["access_token"]))
        return ["connected": true, "waiting": false, "folder": Drive.FOLDER]
    }

    func disconnect() async throws -> Row {
        try await del(["drive_refresh", "drive_folder_id", "drive_device", "drive_last_upload", "drive_last_status"])
        return try await status()
    }

    func token() async throws -> String {
        let refresh = try await get("drive_refresh")
        if refresh.isEmpty { throw HttpError(400, "Google Drive is not connected.") }
        let r = try await call("https://oauth2.googleapis.com/token", method: "POST", headers: Drive.FORM, body: Drive.form([
            ("client_id", try await get("drive_client_id")), ("client_secret", try await get("drive_client_secret")), ("refresh_token", refresh), ("grant_type", "refresh_token")]))
        guard r.status == 200, let tok = r.json["access_token"] as? String, !tok.isEmpty else {
            if (r.json["error"] as? String) == "invalid_grant" {
                try await del(["drive_refresh", "drive_folder_id"])
                throw HttpError(401, "Google Drive was disconnected (the permission was removed or ran out). Connect again.")
            }
            throw HttpError(502, "Google did not answer (\(Drive.why(r.json, r.status))).")
        }
        return tok
    }

    func makeFolder(_ tok: String, _ name: String, _ parent: String?) async throws -> String {
        var meta: [String: Any] = ["name": name, "mimeType": Drive.FOLDER_TYPE]
        if let parent { meta["parents"] = [parent] }
        let r = try await call("https://www.googleapis.com/drive/v3/files?fields=id", method: "POST",
                               headers: ["authorization": "Bearer \(tok)", "content-type": "application/json"], body: try JSONSerialization.data(withJSONObject: meta))
        guard r.status == 200, let id = r.json["id"] as? String else { throw HttpError(502, "Google Drive did not make the folder \"\(name)\" (\(Drive.why(r.json, r.status))).") }
        return id
    }

    func folder(_ tok: String) async throws -> String {
        let id = try await get("drive_folder_id")
        if !id.isEmpty {
            let r = try await call("https://www.googleapis.com/drive/v3/files/\(id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id)?fields=id,trashed",
                                   headers: ["authorization": "Bearer \(tok)"])
            if r.status == 200 && !JS.truthy(r.json["trashed"]) { return id }
        }
        let made = try await makeFolder(tok, Drive.FOLDER, nil)
        try await set("drive_folder_id", made)
        return made
    }

    /// Uploads one backup folder (the newest when none is named) into BillBox Backups.
    func upload(_ b: Row) async throws -> Row {
        let list = (try await db { try self.backup.listBackups() }) as? [Row] ?? []
        let name = JS.truthy(b["folder"] ?? nil) ? JS.string(b.v("folder")) : (list.first?.str("name") ?? "")
        if name.isEmpty { throw HttpError(400, "There is no backup to upload yet. Press Back up now first.") }
        let base = (name as NSString).lastPathComponent
        let root = ((try await db { try self.backup.config() }) as? Row)?.str("dir") ?? ""
        let dir = (root as NSString).appendingPathComponent(base)
        // the files are read while the folder is open (a folder picked in Files needs its permission)
        let files: [(String, Data)]? = backup.withFolderAccess(root) {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else { return nil }
            let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).sorted()
            return names.compactMap { f -> (String, Data)? in
                var d: ObjCBool = false
                let p = (dir as NSString).appendingPathComponent(f)
                guard FileManager.default.fileExists(atPath: p, isDirectory: &d), !d.boolValue, let data = FileManager.default.contents(atPath: p) else { return nil }
                return (f, data)
            }
        }
        guard let files else { throw HttpError(404, "Backup \(name) not found.") }
        let tok = try await token()
        let parent = try await folder(tok)
        let sub = try await makeFolder(tok, base, parent)
        var bytes = 0
        for (f, data) in files {
            let boundary = "billbox" + String(Int(Date().timeIntervalSince1970 * 1000), radix: 36)
            let meta = String(decoding: try JSONSerialization.data(withJSONObject: ["name": f, "parents": [sub]] as [String: Any]), as: UTF8.self)
            var body = Data("--\(boundary)\r\ncontent-type: application/json; charset=UTF-8\r\n\r\n\(meta)\r\n--\(boundary)\r\ncontent-type: application/octet-stream\r\n\r\n".utf8)
            body.append(data)
            body.append(Data("\r\n--\(boundary)--\r\n".utf8))
            let r = try await call("https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id", method: "POST",
                                   headers: ["authorization": "Bearer \(tok)", "content-type": "multipart/related; boundary=\(boundary)"], body: body)
            if r.status != 200 {
                try await set("drive_last_status", "failed: \(f)")
                throw HttpError(502, "Google Drive did not take \(f) (\(Drive.why(r.json, r.status))).")
            }
            bytes += data.count
        }
        try await set("drive_last_upload", name)
        try await set("drive_last_status", "ok")
        return ["folder": name, "files": files.count, "bytes": bytes, "drive_folder": Drive.FOLDER]
    }

    /// After a backup: upload it too when Drive is connected; a failure is only recorded.
    public func afterBackup(_ folder: String) async {
        guard (try? await get("drive_refresh"))?.isEmpty == false else { return }
        do { _ = try await upload(["folder": folder]) } catch { try? await set("drive_last_status", "failed: \(Router.message(of: error))") }
    }

    /// /backup/drive/... (answered outside the queue, see the class note).
    func route(_ m: String, _ s: [String], _ b: Row) async throws -> Reply? {
        let n = s.count
        func ok(_ v: Any) -> Reply { .json(200, v) }
        if n == 2 && m == "GET" { return ok(try await status()) }
        guard n == 3 else { return nil }
        switch (m, s[2]) {
        case ("PUT", "client"): return ok(try await saveClient(b))
        case ("POST", "connect"): return ok(try await connect())
        case ("POST", "poll"): return ok(try await poll())
        case ("POST", "disconnect"): return ok(try await disconnect())
        case ("POST", "upload"): return ok(try await upload(b))
        default: return nil
        }
    }
}
