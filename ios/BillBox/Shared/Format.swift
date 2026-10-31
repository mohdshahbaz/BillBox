import Foundation

/// Indian formats used on every screen and printout: ₹1,23,456.00 and DD-MM-YYYY.
enum Fmt {
    private static let inr: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale(identifier: "en_IN")
        f.currencySymbol = "₹"
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()
    private static let plain: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_IN")
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()
    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func money(_ v: Double) -> String { inr.string(from: NSNumber(value: v)) ?? "₹\(v)" }
    static func money(_ j: JSON, _ k: String) -> String { money(j.num(k)) }
    /// A per-piece rate with up to 4 decimals (7.9365), never fewer than 2, so a price that is not a round paisa is not hidden.
    static func rate(_ v: Double) -> String {
        var s = String(format: "%.4f", v)
        while s.hasSuffix("0"), let dot = s.firstIndex(of: "."), s.distance(from: dot, to: s.endIndex) > 3 { s.removeLast() }
        return s
    }

    static func amount(_ v: Double) -> String { plain.string(from: NSNumber(value: v)) ?? "\(v)" }

    /// "2026-09-30" (or "2026-09-30 14:05") -> "30-09-2026" (time kept).
    static func dmy(_ s: String) -> String {
        guard s.count >= 10 else { return s }
        let parts = s.prefix(10).split(separator: "-")
        guard parts.count == 3, parts[0].count == 4 else { return s }
        return "\(parts[2])-\(parts[1])-\(parts[0])" + s.dropFirst(10)
    }

    /// Backup / system timestamps (UTC ISO text from the server) shown as Indian date and time: 27-10-2026, 04:43 PM.
    static func ist(_ s: String) -> String {
        let a = ISO8601DateFormatter(); a.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let b = ISO8601DateFormatter(); b.formatOptions = [.withInternetDateTime]
        guard let d = a.date(from: s) ?? b.date(from: s) else { return dmy(s) }
        let o = DateFormatter()
        o.locale = Locale(identifier: "en_IN"); o.timeZone = TimeZone(identifier: "Asia/Kolkata")
        o.dateFormat = "dd-MM-yyyy, hh:mm a"
        return o.string(from: d)
    }

    static func iso(_ d: Date) -> String { isoFormatter.string(from: d) }
    static func date(_ iso: String) -> Date { isoFormatter.date(from: String(iso.prefix(10))) ?? Date() }
    static var today: String { iso(Date()) }
    static var monthStart: String { String(today.prefix(7)) + "-01" }

    /// Whole numbers without ".0", everything else as typed.
    static func qty(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(v) }

    /// Stock is kept in pieces; people count in boxes and loose pieces: 150 pcs of a 24-per-box item -> "6 box 6 pcs".
    static func boxPcs(_ q: Int, _ perBox: Int) -> String {
        guard perBox > 1 else { return "\(q) pcs" }
        let b = q / perBox, p = q % perBox
        if b == 0 { return "\(p) pcs" }
        return p == 0 ? "\(b) box" : "\(b) box \(p) pcs"
    }

    /// "(1X144)", "(1X240 PKT)", "1X300" in an item name -> pieces in one box (144, 240, 300).
    static func packFromName(_ name: String) -> Int? {
        let pats = [#"\(\s*(?:\d+\s*[xX*]\s*)?(\d{1,5})\s*(?:PKTS?|PCS?|NOS|PACKS?|UNITS?)?\s*\)"#, #"\b\d+\s*[xX]\s*(\d{2,5})\b"#]
        for p in pats {
            guard let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]),
                  let m = re.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
                  let r = Range(m.range(at: 1), in: name), let n = Int(name[r]), n >= 1 else { continue }
            return n
        }
        return nil
    }

    static func cut(_ s: String, _ n: Int) -> String { s.count <= n ? s : String(s.prefix(n - 2)) + ".." }
}

extension Double {
    var r2: Double { (self * 100).rounded() / 100 }
}
