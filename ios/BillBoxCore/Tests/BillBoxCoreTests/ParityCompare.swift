import Foundation
#if SWIFT_PACKAGE
import BillBoxCore
#endif

/// Field-by-field comparison of a Mac (Node) reply with the iPhone (BillBoxCore) reply: the rules of tests/parity/compare.py.
enum ParityCompare {
    /// Keys whose value is a wall-clock time, a folder stamp or a file size: compared only when `loose` is off.
    static let looseKeys: Set<String> = ["created", "last_run", "last_status", "folder", "sha256", "bytes", "name_ts"]

    static func diff(_ a: Any?, _ b: Any?, _ path: String, loose: Bool, into diffs: inout [String]) {
        if a is Bool || b is Bool {
            if (a as? Bool) != (b as? Bool) { diffs.append("\(path): \(show(a)) != \(show(b))") }
            return
        }
        if let x = number(a), let y = number(b) {
            if x.isNaN && y.isNaN { return }
            if abs(x - y) > 1e-9 * max(1.0, abs(x), abs(y)) { diffs.append("\(path): \(show(a)) != \(show(b))") }
            return
        }
        if let x = a as? [String: Any], let y = b as? [String: Any] {
            for k in Set(x.keys).union(y.keys).sorted() {
                if (loose && looseKeys.contains(k)) || k == "created_at" { continue }   // created_at is the wall clock of each run
                guard let xv = x[k] else { diffs.append("\(path).\(k): missing on Mac (iPhone has \(show(y[k])))"); continue }
                guard let yv = y[k] else { diffs.append("\(path).\(k): missing on iPhone (Mac has \(show(xv)))"); continue }
                diff(xv, yv, "\(path).\(k)", loose: loose, into: &diffs)
            }
            return
        }
        if let x = a as? [Any], let y = b as? [Any] {
            if x.count != y.count { diffs.append("\(path): \(x.count) items on Mac, \(y.count) on iPhone") }
            for i in 0..<min(x.count, y.count) { diff(x[i], y[i], "\(path)[\(i)]", loose: loose, into: &diffs) }
            return
        }
        if a is NSNull && b is NSNull { return }
        if let x = a as? String, let y = b as? String, x == y { return }
        diffs.append("\(path): \(show(a)) != \(show(b))")
    }

    static func number(_ v: Any?) -> Double? {
        if let i = v as? Int { return Double(i) }
        if let d = v as? Double { return d }
        return nil
    }

    static func show(_ v: Any?) -> String {
        guard let v else { return "nothing" }
        let s = (try? JSONText.compact(v)) ?? "\(v)"
        return s.count > 120 ? String(s.prefix(120)) + "…" : s
    }

    /// Reads JSON the way both engines' outputs are compared: numbers as Int/Double, true/false as Bool.
    static func parse(_ text: String) throws -> Any {
        JSONNorm.normalize(try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])) as Any
    }
}
