import Foundation

// backend/src/utils: misc.js, fy.js, gst.js, schemes.js, words.js

// MARK: misc.js

func today() -> String { Clock.today() }

/// Short financial-year label for numbering: the bill's own date decides the year. "2026-10-28" -> "26-27".
func fyShort(_ date: String?) -> String {
    let d = (date?.isEmpty == false) ? date! : today()
    let y = Int(JS.number(d.jsSlice(0, 4)))
    let mo = Int(JS.number(d.jsSlice(5, 7))) - 1
    let start = mo >= 3 ? y : y - 1   // Indian FY: 1 Apr - 31 Mar
    return "\(String(start).jsSlice(2))-\(String(start + 1).jsSlice(2))"
}

/// Numbering of a series (INV, RCT, PUR, PAY, DN), as Settings › Billing & Dashboard › Numbering says (see misc.js).
/// A new number always follows the highest one already used with the same beginning (bills imported from Marg, or made
/// before the numbering was changed), so numbers carry on from the last bill and never clash.
let numberSeries: [(String, String, String)] = [("INV", "invoices", "invoice_no"), ("RCT", "receipts", "receipt_no"), ("PUR", "purchases", "purchase_no"),
                                                ("PAY", "payments", "voucher_no"), ("DN", "debit_notes", "note_no")]

struct Numbering { let prefix: String; let label: String; let withFy: Bool; let digits: Int; let head: String; let key: String }

func numbering(_ db: Database, _ prefix: String, _ date: String?) throws -> Numbering {
    func get(_ k: String) throws -> String {
        guard let r = try db.prepare("SELECT value FROM settings WHERE key=?").get(k), let v = unwrap(r["value"] ?? nil) else { return "" }
        return JS.string(v)
    }
    let typed = JS.trim(try get("num_\(prefix)_prefix"))
    let label = typed.isEmpty ? prefix : typed
    let withFy = try get("num_fy") != "0"
    let own = JS.parseInt(try get("num_\(prefix)_digits"))
    let d = JS.parseInt(try get("num_digits"))
    let digits = own >= 1 && own <= 9 ? Int(own) : (d >= 3 && d <= 6 ? Int(d) : 5)
    let year = fyShort(date)
    let last = label.unicodeScalars.last.map { CharacterSet.alphanumerics.contains($0) && $0.isASCII } ?? false
    let sep = last ? "/" : ""
    let head = withFy ? "\(label)\(sep)\(year)/" : label
    return Numbering(prefix: prefix, label: label, withFy: withFy, digits: digits, head: head, key: withFy ? "\(prefix)/\(year)" : prefix)
}

/// The highest number already used after this beginning, e.g. (422, "A000422") for "A".
func lastUsed(_ db: Database, _ prefix: String, _ head: String) throws -> (n: Int, no: String) {
    var best = (n: 0, no: "")
    guard let t = numberSeries.first(where: { $0.0 == prefix }) else { return best }
    for r in try db.prepare("SELECT \(t.2) AS no FROM \(t.1) WHERE substr(\(t.2), 1, ?) = ?").all(head.jsLength, head) {
        let no = JS.string(r["no"] ?? nil)
        let rest = no.jsSlice(head.jsLength)
        if rx("^[0-9]+$").test(rest) {
            let n = Int(JS.parseInt(rest))
            if n > best.n { best = (n, no) }
        }
    }
    return best
}

/// The number the next document of the series will get, without using it up.
func peekNo(_ db: Database, _ prefix: String, _ date: String?) throws -> Row {
    let s = try numbering(db, prefix, date)
    let c = try db.prepare("SELECT value FROM counters WHERE key = ?").get(s.key)
    let used = try lastUsed(db, prefix, s.head)
    let v = max(c.map { $0.i("value") } ?? 0, used.n) + 1
    return ["series": prefix, "label": s.label, "digits": s.digits, "with_fy": s.withFy, "last_no": used.no,
            "next_no": s.head + String(v).padStart(s.digits, "0"), "next": v]
}

/// Next number of a series, used up.
func nextNo(_ db: Database, _ prefix: String, _ date: String?) throws -> String {
    let s = try numbering(db, prefix, date)
    let used = try lastUsed(db, prefix, s.head).n
    try db.prepare("INSERT INTO counters(key,value) VALUES(?,0) ON CONFLICT(key) DO NOTHING").run(s.key)
    try db.prepare("UPDATE counters SET value = MAX(value, ?) + 1 WHERE key = ?").run(Double(used), s.key)
    let v = try db.prepare("SELECT value FROM counters WHERE key = ?").get(s.key)!.i("value")
    return s.head + String(v).padStart(s.digits, "0")
}

/// Settings › Numbering › Next number: the next document of the series gets `next` (it must come after the last one used).
func setNext(_ db: Database, _ prefix: String, _ next: Any?, _ date: String?) throws -> Row {
    guard numberSeries.contains(where: { $0.0 == prefix }) else { throw HttpError(400, "Unknown series") }
    let n = JS.parseInt(next)
    if !(n >= 1) || JS.string(Int(n)) != JS.trim(JS.string(next)) { throw HttpError(400, "Enter the next number as a whole number, 1 or more") }
    let s = try numbering(db, prefix, date)
    let used = try lastUsed(db, prefix, s.head)
    if Int(n) <= used.n { throw HttpError(409, "The next number must come after \(used.no), the last one used") }
    try db.prepare("INSERT INTO counters(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value").run(s.key, n - 1)
    return try peekNo(db, prefix, date)
}

/// Weekday list for a route: accepts [1,3], "1,3" or a single number; returns sorted unique 0-6 as "1,3" (or nil).
func normDays(_ v: Any?) -> String? {
    guard let u = unwrap(v) else { return nil }
    if let s = u as? String, s.isEmpty { return nil }
    let parts: [Any] = (u as? [Any]) ?? JS.string(u).components(separatedBy: ",")
    let a = parts.map { JS.parseInt($0) }.filter { $0 >= 0 && $0 <= 6 }.map { Int($0) }
    var seen = Set<Int>(), u2: [Int] = []
    for x in a where !seen.contains(x) { seen.insert(x); u2.append(x) }
    let sorted = u2.map(String.init).sorted()     // JavaScript's default sort compares text
    return sorted.isEmpty ? nil : sorted.joined(separator: ",")
}

// MARK: fy.js — Indian financial year: 1 April to 31 March. "2026-27" = 1 Apr 2026 .. 31 Mar 2027.

public struct FYRange {
    public let label: String
    public let startYear: Int
    public let from: String
    public let to: String
    public let current: Bool
    var json: Row { ["label": label, "start_year": startYear, "from": from, "to": to, "current": current] }
}

enum FY {
    static func startYearOf(_ date: String) -> Int {
        let y = Int(JS.number(date.jsSlice(0, 4))), m = Int(JS.number(date.jsSlice(5, 7)))
        return m >= 4 ? y : y - 1
    }
    static func labelOf(_ s: Int) -> String { "\(s)-\(String(s + 1).jsSlice(2))" }
    static func rangeOf(_ s: Int, current: Bool) -> FYRange {
        FYRange(label: labelOf(s), startYear: s, from: "\(s)-04-01", to: "\(s + 1)-03-31", current: current)
    }
    static func currentStart() -> Int { startYearOf(today()) }

    /// Accepts "2026-27", "2026-2027", "2026" or nothing (= the year that contains today).
    static func range(_ label: Any?) throws -> FYRange {
        guard let l = unwrap(label), !(l is String && (l as! String).isEmpty) else { return rangeOf(currentStart(), current: true) }
        let text = JS.trim(JS.string(l))
        guard let m = rx("^(\\d{4})(?:-(\\d{2}|\\d{4}))?$").exec(text) else { throw HttpError(400, "Financial year must look like 2026-27") }
        let s = Int(m[1]!)!
        if let g2 = m[2] {
            if Int(JS.number(g2.jsSlice(-2))) != (s + 1) % 100 { throw HttpError(400, "Financial year \(text) is not consecutive. Use \(labelOf(s)).") }
        }
        return rangeOf(s, current: s == currentStart())
    }

    /// Every financial year that has data, plus the current one, newest first.
    /// The year a company's books are for, when they are one year's books (Marg style); else nil (books for every year).
    static func booksFy(_ db: Database) throws -> String? {
        guard let v = try db.prepare("SELECT value FROM settings WHERE key='books_fy'").get()?.s("value"), !v.isEmpty else { return nil }
        return v
    }

    static func list(_ db: Database) throws -> [FYRange] {
        if let own = try booksFy(db) {
            let s = Int(JS.number(own.jsSlice(0, 4)))
            return [rangeOf(s, current: s == currentStart())]
        }
        func q(_ sql: String) throws -> String? { try db.prepare(sql).get()?.s("d") }
        let dates = try [q("SELECT MIN(date) d FROM invoices"), q("SELECT MIN(date) d FROM purchases"), q("SELECT MIN(date) d FROM receipts"),
                         q("SELECT MIN(date) d FROM payments"), q("SELECT MIN(date) d FROM ledger")].compactMap { $0 }.filter { !$0.isEmpty }
        let maxes = try [q("SELECT MAX(date) d FROM invoices"), q("SELECT MAX(date) d FROM purchases")].compactMap { $0 }.filter { !$0.isEmpty }
        let cur = currentStart()
        let first = dates.isEmpty ? cur : min(dates.map(startYearOf).min()!, cur)
        let last = maxes.isEmpty ? cur : max(maxes.map(startYearOf).max()!, cur)
        var out: [FYRange] = []
        var s = last
        while s >= first { out.append(rangeOf(s, current: s == cur)); s -= 1 }
        return out
    }
}

// MARK: gst.js

/// Split GST on a taxable value. intra=true -> CGST+SGST (half each), else IGST.
func splitTax(_ taxable: Double, _ rate: Double, _ intra: Bool) -> (cgst: Double, sgst: Double, igst: Double) {
    let tax = r2((taxable * rate) / 100)
    if intra {
        let c = r2(tax / 2)
        return (c, r2(tax - c), 0)
    }
    return (0, 0, tax)
}

// MARK: schemes.js

/// For one item line, the best active scheme of each kind:
///  FREE_QTY: "Buy X get Y free" -> floor(qty / X) * Y free units;  PERCENT: % discount once qty >= minimum qty.
func applySchemes(_ qty: Double, _ schemes: [Row]) -> (freeQty: Double, discPct: Double, applied: [String]) {
    var freeQty = 0.0, discPct = 0.0
    var applied: [String] = []
    for s in schemes {
        let buy = s.n("buy_qty"), free = s.n("free_qty"), pct = s.n("percent")
        if s.str("type") == "FREE_QTY" && buy > 0 && qty >= buy {
            let f = Foundation.floor(qty / buy) * free
            if f > freeQty { freeQty = f; applied.append("Buy \(JS.string(s.v("buy_qty"))) get \(JS.string(s["free_qty"] ?? nil)) free") }
        } else if s.str("type") == "PERCENT" && qty >= buy && pct > discPct {
            discPct = pct
            applied.append("\(JS.string(s["percent"] ?? nil))% off on \(JS.string(s.v("buy_qty")))+")
        }
    }
    return (freeQty, discPct, applied)
}

// MARK: words.js — Indian numbering: Crore / Lakh / Thousand.

enum Words {
    static let ones = ["", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Eleven", "Twelve", "Thirteen",
                       "Fourteen", "Fifteen", "Sixteen", "Seventeen", "Eighteen", "Nineteen"]
    static let tens = ["", "", "Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy", "Eighty", "Ninety"]
    static func two(_ n: Int) -> String { n < 20 ? ones[n] : tens[n / 10] + (n % 10 != 0 ? " " + ones[n % 10] : "") }
    static func three(_ n: Int) -> String { (n >= 100 ? ones[n / 100] + " Hundred" + (n % 100 != 0 ? " " : "") : "") + (n % 100 != 0 ? two(n % 100) : "") }

    static func words(_ n: Int) -> String {
        if n == 0 { return "Zero" }
        var parts: [String] = []
        let cr = n / 10_000_000, lk = (n / 100_000) % 100, th = (n / 1000) % 100, rest = n % 1000
        if cr != 0 { parts.append(three(cr) + " Crore") }
        if lk != 0 { parts.append(two(lk) + " Lakh") }
        if th != 0 { parts.append(two(th) + " Thousand") }
        if rest != 0 { parts.append(three(rest)) }
        return parts.joined(separator: " ")
    }

    /// "Rupees Two Thousand Five Hundred Only"; a total that is not rounded to the rupee also says its paise.
    static func rupees(_ total: Double) -> String {
        let paise = Int(JS.round(abs(total) * 100)) % 100
        return paise != 0 ? "Rupees \(words(Int(Foundation.floor(total)))) and \(words(paise)) Paise Only" : "Rupees \(words(Int(JS.round(total)))) Only"
    }
}

/// A stable sort (JavaScript's Array.prototype.sort is stable).
func stableSorted<T>(_ a: [T], by less: (T, T) -> Bool) -> [T] {
    a.enumerated().sorted { x, y in
        if less(x.element, y.element) { return true }
        if less(y.element, x.element) { return false }
        return x.offset < y.offset
    }.map { $0.element }
}
