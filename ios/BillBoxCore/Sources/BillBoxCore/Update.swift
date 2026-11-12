import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Settings › Updates (backend/src/services/update.js): the newest GitHub release of this edition and its file for the
/// platform asking. The iPhone build is unsigned, so the app only opens its download page.
enum Update {
    static var api = "https://api.github.com/repos/mohdshahbaz/BillBox/releases?per_page=30"
    static let files: [String: String] = [
        "android": #"^BillBox-android-.*\.apk$"#, "mac": #"^BillBox-mac-(?!.*-(arm64|intel)\.zip$).*\.zip$"#,
        "mac-arm64": #"^BillBox-mac-.*-arm64\.zip$"#, "mac-intel": #"^BillBox-mac-.*-intel\.zip$"#, "windows": #"^BillBox-windows-.*-setup\.exe$"#,
        "linux": #"^BillBox-linux-.*\.deb$"#, "linux-tar": #"^BillBox-linux-.*\.tar\.gz$"#, "iphone": #"^BillBox-iphone-.*\.ipa$"#,
    ]

    /// "16.2.12-admin" → [16, 2, 12]; newer(a, b) is true when a comes after b.
    static func parts(_ v: String) -> [Int] {
        var s = v
        if s.hasPrefix("v") { s.removeFirst() }
        return String(s.split(separator: "-").first ?? "").split(separator: ".").map { Int($0) ?? 0 }
    }
    static func newer(_ a: String, _ b: String) -> Bool {
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    static func check(version: String, edition: String, platform: String) async throws -> Row {
        guard Category.internetAllowed, let url = URL(string: api) else { throw HttpError(503, "No internet: could not look for a new version.") }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "accept")
        req.setValue("BillBox", forHTTPHeaderField: "user-agent")
        let (data, resp): (Data, URLResponse?) = try await withCheckedThrowingContinuation { c in
            URLSession.shared.dataTask(with: req) { d, r, e in
                if e != nil { c.resume(throwing: HttpError(503, "No internet: could not look for a new version.")) } else { c.resume(returning: (d ?? Data(), r)) }
            }.resume()
        }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if status != 200 { throw HttpError(502, "GitHub answered \(status) while looking for a new version.") }
        let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
        let admin = edition == "admin"
        let rel = list.filter { r in
            let tag = r["tag_name"] as? String ?? ""
            return r["draft"] as? Bool != true && tag.hasSuffix("-admin") == admin && (admin || r["prerelease"] as? Bool != true)
        }.sorted { newer($0["tag_name"] as? String ?? "", $1["tag_name"] as? String ?? "") }.first
        guard let rel else { return ["available": false, "current": version, "latest": NSNull()] }
        var latest = rel["tag_name"] as? String ?? ""
        if latest.hasPrefix("v") { latest.removeFirst() }
        var file: Any = NSNull()
        let assets = rel["assets"] as? [[String: Any]] ?? []
        func find(_ key: String) -> [String: Any]? {
            guard let pat = files[key], let re = try? NSRegularExpression(pattern: pat) else { return nil }
            return assets.first { a in let n = a["name"] as? String ?? ""; return re.firstMatch(in: n, range: NSRange(n.startIndex..., in: n)) != nil }
        }
        // a release from before the split has only the plain (universal) Mac zip: both kinds take that
        if let a = find(platform) ?? (platform.hasPrefix("mac-") ? find("mac") : nil) {
            file = ["name": a["name"] ?? "", "url": a["browser_download_url"] ?? "", "size": a["size"] ?? 0] as Row
        }
        let body = (rel["body"] as? String ?? "").components(separatedBy: "\n## Install").first ?? ""
        return ["available": !version.isEmpty && newer(latest, version), "current": version, "latest": latest, "page": rel["html_url"] ?? "",
                "published": rel["published_at"] ?? NSNull(), "notes": String(body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1500)), "file": file]
    }
}
