import Foundation

/// A loosely typed JSON object. The backend returns plain JSON, so screens read it through these accessors
/// instead of a Codable model for every report and form: missing or null values never crash, they read as ""/0.
struct JSON: Identifiable, Hashable {
    var raw: [String: Any]
    /// Row number for lists whose rows carry no "id" (reports), so tables can still tell rows apart.
    var rid: Int

    init(_ raw: [String: Any] = [:], rid: Int = 0) {
        self.raw = raw
        self.rid = rid
    }

    var id: Int { (raw["id"] as? Int) ?? rid }

    /// Rows with an "id" are the same row when their ids match (lists keep their selection). Objects without one (a
    /// screen's status, totals, a report) are equal only when their contents are: SwiftUI skips a @State change that
    /// compares equal, so a new Google Drive or licence status was not shown until BillBox was opened again.
    static func == (a: JSON, b: JSON) -> Bool {
        guard a.id == b.id && a.rid == b.rid else { return false }
        if a.raw["id"] == nil && b.raw["id"] == nil { return NSDictionary(dictionary: a.raw).isEqual(to: b.raw) }
        return true
    }
    func hash(into h: inout Hasher) {
        h.combine(id)
        h.combine(rid)
    }

    func has(_ k: String) -> Bool {
        guard let v = raw[k] else { return false }
        return !(v is NSNull)
    }

    func str(_ k: String) -> String {
        guard let v = raw[k], !(v is NSNull) else { return "" }
        if let s = v as? String { return s }
        if let n = v as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
            let d = n.doubleValue
            if d == d.rounded() && abs(d) < 1e15 { return String(Int64(d)) }
            return String(d)
        }
        return "\(v)"
    }

    func num(_ k: String) -> Double {
        guard let v = raw[k], !(v is NSNull) else { return 0 }
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s.trimmingCharacters(in: .whitespaces)) ?? 0 }
        return 0
    }

    func int(_ k: String) -> Int { Int(num(k).rounded()) }
    func optInt(_ k: String) -> Int? { has(k) ? int(k) : nil }
    func bool(_ k: String) -> Bool {
        if let n = raw[k] as? NSNumber { return n.boolValue }
        let s = str(k).lowercased()
        return s == "true" || s == "1"
    }

    func obj(_ k: String) -> JSON { JSON(raw[k] as? [String: Any] ?? [:]) }
    func list(_ k: String) -> [JSON] { JSON.rows(raw[k]) }
    func strings(_ k: String) -> [String] { (raw[k] as? [Any])?.map { "\($0)" } ?? [] }

    static func rows(_ any: Any?) -> [JSON] {
        guard let a = any as? [Any] else { return [] }
        return a.enumerated().map { (i, e) in JSON((e as? [String: Any]) ?? [:], rid: i + 1) }
    }
}
