import Foundation

// JavaScript behaviour reproduced exactly, so every figure, message and decision matches the Mac app's server.

/// An error with an HTTP status and an optional code, like the server's HttpError (`CREDIT_LIMIT`, `DUPLICATE` …).
public struct HttpError: Error, LocalizedError, CustomStringConvertible {
    public let status: Int
    public let message: String
    public let code: String?
    public init(_ status: Int, _ message: String, _ code: String? = nil) {
        self.status = status
        self.message = message
        self.code = code
    }
    public var errorDescription: String? { message }
    public var description: String { message }
}

// MARK: - numbers

public enum JS {
    public static let EPSILON = 2.220446049250313e-16

    /// `Math.round`: halves go toward +infinity (2.5 -> 3, -2.5 -> -2).
    public static func round(_ x: Double) -> Double {
        if !x.isFinite { return x }
        let f = Foundation.floor(x)
        return x - f >= 0.5 ? f + 1 : f
    }

    /// `r2` of the server (utils/gst.js): Math.round((n + EPSILON) * 100) / 100
    public static func r2(_ n: Double) -> Double { round((n + EPSILON) * 100) / 100 }

    /// `Number(value)`: undefined (nil) -> NaN, null -> 0, true -> 1, "" -> 0, " 12 " -> 12, "abc" -> NaN.
    public static func number(_ v: Any?) -> Double {
        guard let v else { return .nan }
        if v is NSNull { return 0 }
        switch v {
        case let b as Bool: return b ? 1 : 0
        case let i as Int: return Double(i)
        case let i as Int64: return Double(i)
        case let d as Double: return d
        case let f as Float: return Double(f)
        case let s as String: return parseNumber(s)
        case let n as NSNumber: return n.doubleValue
        case let a as [Any]:
            if a.isEmpty { return 0 }
            if a.count == 1 { return number(a[0]) }
            return .nan
        default:
            if let u = unwrap(v) { return number(u) }
            return 0
        }
    }

    /// String to number the way `Number("…")` does it.
    public static func parseNumber(_ raw: String) -> Double {
        let s = raw.trimmingCharacters(in: jsSpace)
        if s.isEmpty { return 0 }
        if s == "Infinity" || s == "+Infinity" { return .infinity }
        if s == "-Infinity" { return -.infinity }
        let lower = s.lowercased()
        for (prefix, radix) in [("0x", 16), ("0o", 8), ("0b", 2)] where lower.hasPrefix(prefix) {
            let body = String(s.dropFirst(2))
            if let v = UInt64(body, radix: radix) { return Double(v) }
            return .nan
        }
        // JavaScript accepts "1.", ".5", "1e3", "+5"; it rejects "1,000", "0x", "1 2", "nan", "inf"
        let allowed = CharacterSet(charactersIn: "0123456789+-.eE")
        if s.unicodeScalars.contains(where: { !allowed.contains($0) }) { return .nan }
        if let d = Double(s) { return d }
        return .nan
    }

    /// `parseInt(value, 10)`.
    public static func parseInt(_ v: Any?) -> Double {
        let s = string(v).trimmingCharacters(in: jsSpace)
        var digits = ""
        var sign = 1.0
        var idx = s.startIndex
        if idx < s.endIndex, s[idx] == "-" || s[idx] == "+" {
            if s[idx] == "-" { sign = -1 }
            idx = s.index(after: idx)
        }
        while idx < s.endIndex, let a = s[idx].asciiValue, a >= 48, a <= 57 {
            digits.append(s[idx])
            idx = s.index(after: idx)
        }
        if digits.isEmpty { return .nan }
        return sign * (Double(digits) ?? .nan)
    }

    public static func isInteger(_ d: Double) -> Bool { d.isFinite && d == Foundation.floor(d) }

    /// `String(number)`: 5 -> "5", 2.5 -> "2.5", 1e21 -> "1e+21".
    public static func numberString(_ d: Double) -> String {
        if d.isNaN { return "NaN" }
        if d.isInfinite { return d > 0 ? "Infinity" : "-Infinity" }
        if d == 0 { return "0" }
        if d == Foundation.floor(d) && abs(d) < 1e21 {
            if abs(d) < 9.007199254740992e15 { return String(Int64(d)) }
            return String(format: "%.0f", d)
        }
        // Swift's description is the shortest round-tripping form, as in JavaScript; only the exponent spelling differs
        var s = "\(d)"
        if let e = s.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            let mant = String(s[..<e])
            var exp = String(s[s.index(after: e)...])
            var expSign = "+"
            if exp.hasPrefix("-") { expSign = "-"; exp.removeFirst() } else if exp.hasPrefix("+") { exp.removeFirst() }
            let expVal = Int(exp) ?? 0
            if expSign == "-" && expVal <= 6 {
                // JavaScript writes 1e-6 .. 1e-7 boundary in plain form down to 1e-6
                return plainSmall(d)
            }
            let m = mant.hasSuffix(".0") ? String(mant.dropLast(2)) : mant
            s = "\(m)e\(expSign)\(expVal)"
        }
        return s
    }

    private static func plainSmall(_ d: Double) -> String {
        var s = String(format: "%.20f", d)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    /// `Number.prototype.toFixed(n)`.
    public static func toFixed(_ d: Double, _ n: Int) -> String {
        if !d.isFinite { return numberString(d) }
        // toFixed rounds the exact binary value half up (away from zero); %.Nf rounds half to even on the exact value,
        // which only differs on exact binary ties. Decimal arithmetic on the exact expansion settles those.
        let exact = Decimal(string: String(format: "%.40f", d)) ?? Decimal(d)
        var v = exact
        var out = Decimal()
        NSDecimalRound(&out, &v, n, d >= 0 ? .plain : .plain)
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.minimumFractionDigits = n
        f.maximumFractionDigits = n
        f.usesGroupingSeparator = false
        f.minimumIntegerDigits = 1
        return f.string(from: out as NSDecimalNumber) ?? String(format: "%.\(n)f", d)
    }

    /// `String(value)`.
    public static func string(_ v: Any?) -> String {
        guard let v else { return "undefined" }
        if v is NSNull { return "null" }
        switch v {
        case let s as String: return s
        case let b as Bool: return b ? "true" : "false"
        case let i as Int: return String(i)
        case let i as Int64: return String(i)
        case let d as Double: return numberString(d)
        case let a as [Any]: return a.map { e -> String in
            if e is NSNull { return "" }
            return string(e)
        }.joined(separator: ",")
        case is [String: Any]: return "[object Object]"
        case let n as NSNumber: return numberString(n.doubleValue)
        default:
            if let u = unwrap(v) { return string(u) }
            return "null"
        }
    }

    /// JavaScript truthiness.
    public static func truthy(_ v: Any?) -> Bool {
        guard let v = unwrap(v) else { return false }
        switch v {
        case let b as Bool: return b
        case let i as Int: return i != 0
        case let d as Double: return d != 0 && !d.isNaN
        case let s as String: return !s.isEmpty
        default: return true
        }
    }

    /// `blank(v)` of the server: undefined, null or only spaces -> nil, otherwise the value itself.
    public static func blank(_ v: Any?) -> Any? {
        guard let u = unwrap(v) else { return nil }
        if string(u).trimmingCharacters(in: jsSpace).isEmpty { return nil }
        return u
    }

    /// `String(x).trim()`.
    public static func trim(_ s: String) -> String { s.trimmingCharacters(in: jsSpace) }

    public static let jsSpace: CharacterSet = {
        var c = CharacterSet.whitespacesAndNewlines
        c.insert(charactersIn: "\u{FEFF}\u{00A0}\u{2028}\u{2029}")
        return c
    }()
}

/// Shorthand used throughout the port.
@inline(__always) public func r2(_ n: Double) -> Double { JS.r2(n) }

// MARK: - reading loosely typed rows and request bodies

public extension Dictionary where Key == String, Value == Any {
    /// Number(row[k]) with SQL NULL -> 0 and a missing key -> NaN, as in JavaScript.
    func n(_ k: String) -> Double { JS.number(self[k]) }
    /// Number, with NULL / missing read as 0 (for columns where the server relies on `|| 0` or arithmetic on non-null values).
    func n0(_ k: String) -> Double { let v = JS.number(self[k]); return v.isNaN ? 0 : v }
    func i(_ k: String) -> Int { let v = JS.number(self[k]); return v.isFinite ? Int(v) : 0 }
    /// The raw value, nil for missing and NULL.
    func v(_ k: String) -> Any? { unwrap(self[k]) }
    /// Text or nil (NULL / missing).
    func s(_ k: String) -> String? {
        guard let x = unwrap(self[k]) else { return nil }
        return JS.string(x)
    }
    /// Text, "" for NULL / missing.
    func str(_ k: String) -> String { s(k) ?? "" }
    func has(_ k: String) -> Bool { unwrap(self[k]) != nil }
    /// `k in obj` / `obj[k] !== undefined`: present, even when null.
    func defined(_ k: String) -> Bool { self[k] != nil }
}

/// A Swift Int for an id that came from JSON, a row or a path.
func intId(_ v: Any?) -> Int? {
    let d = JS.number(v)
    return d.isFinite ? Int(d) : nil
}

// MARK: - regular expressions with JavaScript's API

/// A JavaScript-style regular expression. `i` = case-insensitive, `g` = global (for replace / matchAll), `m` = multi-line.
public final class JSRegex {
    let re: NSRegularExpression
    let global: Bool
    private static var cache: [String: NSRegularExpression] = [:]
    private static let lock = NSLock()

    public init(_ pattern: String, _ flags: String = "") {
        global = flags.contains("g")
        var opts: NSRegularExpression.Options = []
        if flags.contains("i") { opts.insert(.caseInsensitive) }
        if flags.contains("m") { opts.insert(.anchorsMatchLines) }
        if flags.contains("s") { opts.insert(.dotMatchesLineSeparators) }
        let key = pattern + "/" + flags.replacingOccurrences(of: "g", with: "")
        JSRegex.lock.lock()
        defer { JSRegex.lock.unlock() }
        if let r = JSRegex.cache[key] { re = r } else {
            // JavaScript's `$` (no m flag) only matches at the very end; ICU's also matches before a final newline.
            let p = pattern
            do { re = try NSRegularExpression(pattern: p, options: opts) } catch { fatalError("Bad regex \(pattern): \(error)") }
            JSRegex.cache[key] = re
        }
    }

    public struct Match {
        /// groups[0] = whole match; nil for a group that did not take part.
        public let groups: [String?]
        /// UTF-16 offset of the match (JavaScript's `m.index`).
        public let index: Int
        public let length: Int
        public subscript(_ i: Int) -> String? { i < groups.count ? groups[i] : nil }
    }

    private func make(_ m: NSTextCheckingResult, _ ns: NSString) -> Match {
        var g: [String?] = []
        for i in 0..<m.numberOfRanges {
            let r = m.range(at: i)
            g.append(r.location == NSNotFound ? nil : ns.substring(with: r))
        }
        return Match(groups: g, index: m.range.location, length: m.range.length)
    }

    /// `re.test(s)`
    public func test(_ s: String) -> Bool {
        re.firstMatch(in: s, options: [], range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }

    /// `re.exec(s)` / `s.match(re)` without g.
    public func exec(_ s: String) -> Match? {
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, options: [], range: NSRange(location: 0, length: ns.length)) else { return nil }
        return make(m, ns)
    }

    /// `s.matchAll(re)` / repeated exec with g.
    public func matchAll(_ s: String) -> [Match] {
        let ns = s as NSString
        return re.matches(in: s, options: [], range: NSRange(location: 0, length: ns.length)).map { make($0, ns) }
    }

    /// `s.match(re)` with g: every whole match.
    public func matches(_ s: String) -> [String] { matchAll(s).compactMap { $0.groups[0] } }

    /// `s.replace(re, fn)`: first match only unless g.
    public func replace(_ s: String, _ fn: (Match) -> String) -> String {
        let ns = s as NSString
        var all = re.matches(in: s, options: [], range: NSRange(location: 0, length: ns.length))
        if !global, let f = all.first { all = [f] }
        if all.isEmpty { return s }
        var out = ""
        var last = 0
        for m in all {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            out += fn(make(m, ns))
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }

    /// `s.replace(re, "text")` (the replacement is literal; the server never uses $1 in replacements).
    public func replace(_ s: String, _ with: String) -> String { replace(s) { _ in with } }

    /// `s.split(re)`.
    public func split(_ s: String) -> [String] {
        let ns = s as NSString
        let all = re.matches(in: s, options: [], range: NSRange(location: 0, length: ns.length))
        if ns.length == 0 { return all.isEmpty ? [""] : [] }
        var out: [String] = []
        var last = 0
        for m in all {
            if m.range.length == 0 && (m.range.location == 0 || m.range.location >= ns.length) { continue }
            out.append(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
            for g in 1..<max(1, m.numberOfRanges) {
                let r = m.range(at: g)
                out.append(r.location == NSNotFound ? "" : ns.substring(with: r))
            }
            last = m.range.location + m.range.length
        }
        out.append(ns.substring(from: last))
        return out
    }
}

/// `new RegExp(p, f)` shorthand.
@inline(__always) func rx(_ p: String, _ f: String = "") -> JSRegex { JSRegex(p, f) }

public extension String {
    /// UTF-16 length, as JavaScript's `.length`.
    var jsLength: Int { (self as NSString).length }
    /// `slice(a, b)` on UTF-16 offsets, negative counts from the end.
    func jsSlice(_ a: Int, _ b: Int? = nil) -> String {
        let ns = self as NSString
        let len = ns.length
        var s = a < 0 ? max(0, len + a) : min(a, len)
        var e = b.map { $0 < 0 ? max(0, len + $0) : min($0, len) } ?? len
        if e < s { e = s }
        s = min(s, len)
        return ns.substring(with: NSRange(location: s, length: e - s))
    }
    /// `padStart(n, c)`.
    func padStart(_ n: Int, _ c: Character = " ") -> String {
        count >= n ? self : String(repeating: c, count: n - count) + self
    }
    func jsTrim() -> String { JS.trim(self) }
}

// MARK: - dates (local time, like toLocaleDateString('en-CA'))

public enum Clock {
    /// Tests can fix "now"; the app always uses the real time.
    public static var override: Date?
    public static var now: Date { override ?? Date() }

    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// YYYY-MM-DD in local time.
    public static func day(_ d: Date) -> String {
        isoDay.timeZone = TimeZone.current
        return isoDay.string(from: d)
    }

    public static func today() -> String { day(now) }

    /// `new Date().toISOString()`: 2026-10-28T12:25:16.123Z
    public static func isoString(_ d: Date = now) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return f.string(from: d)
    }

    /// Parses toISOString() text back.
    public static func parseISO(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC")
        for fmt in ["yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", "yyyy-MM-dd'T'HH:mm:ss'Z'"] {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    /// Adds days in local time and returns YYYY-MM-DD (the server's addDays).
    public static func addDays(_ n: Int, _ base: Date = now) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        return day(cal.date(byAdding: .day, value: n, to: base) ?? base)
    }

    /// `new Date('YYYY-MM-DDT12:00:00')` (local noon).
    public static func localNoon(_ iso: String) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return now }
        return cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12)) ?? now
    }
}

let isDateRe = rx("^\\d{4}-\\d{2}-\\d{2}$")
func isDate(_ v: Any?) -> Bool {
    guard let s = unwrap(v) as? String else { return false }
    return isDateRe.test(s)
}

/// Turns Foundation JSON values into plain Swift values: a JSON number becomes Int or Double and only true / false become Bool
/// (Foundation's NSNumber 1 would otherwise also read as `true`, and 0 as `false`).
public enum JSONNorm {
    public static func normalize(_ v: Any?) -> Any? {
        guard let v else { return nil }
        if v is NSNull { return NSNull() }
        if let s = v as? String { return s }
        if let n = v as? NSNumber, !(v is String) {
            let t = String(cString: n.objCType)
            if t == "c" || t == "B" { return n.boolValue }
            if ["q", "l", "i", "s", "Q", "L", "I", "S", "C"].contains(t) { return n.intValue }
            let d = n.doubleValue
            if d == d.rounded() && abs(d) < 9.007199254740992e15 && t != "d" && t != "f" { return Int(d) }
            return d
        }
        if let a = v as? [Any] { return a.map { normalize($0) ?? NSNull() } }
        if let o = v as? [String: Any] {
            var out: [String: Any] = [:]
            for (k, x) in o { out[k] = normalize(x) ?? NSNull() }
            return out
        }
        return v
    }
    public static func row(_ v: Any?) -> Row { (normalize(v) as? Row) ?? [:] }
}
