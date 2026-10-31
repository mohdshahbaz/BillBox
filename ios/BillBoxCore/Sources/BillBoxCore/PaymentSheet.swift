import Foundation

// backend/src/services/paymentSheet.js — payments from a photo of a handwritten sheet (text read on the device by OCR).
// One row per line:   party name, bill amount, bill amount, ...  [separator] payment
// The payment is the last number when it is not joined to the bills by a comma, or follows "paid", "rcvd", "cash" and
// similar words. Plain character work (no regex) so both engines give the same answer.
enum PaymentSheet {
    static let PAY_WORDS = ["paid", "pay", "payment", "rcvd", "recd", "received", "recieved", "rec", "cash", "amt", "jama", "diya"]
    static let STOP_WORDS = ["m", "s", "ms", "mss", "shri", "sri", "shree", "the", "and", "store", "stores", "traders", "trader", "trading",
                             "general", "genral", "gen", "kirana", "enterprises", "enterprise", "ent", "agency", "agencies", "mart", "shop", "co", "bros", "brothers"]

    static func isDigit(_ c: Character) -> Bool { c >= "0" && c <= "9" }
    static func isAsciiLetter(_ c: Character) -> Bool { (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") }
    static func isSpace(_ c: Character) -> Bool { c == " " || c == "\t" || c == "\r" || c == "\n" }

    /// OCR often reads 0 as O and 1 as l / I / | when they sit inside a number.
    static func fixDigits(_ s: String) -> [Character] {
        var ch = Array(s)
        for i in 0..<ch.count {
            let c = ch[i]
            let near = (i > 0 && isDigit(ch[i - 1])) || (i + 1 < ch.count && isDigit(ch[i + 1]))
            if !near { continue }
            if c == "O" || c == "o" { ch[i] = "0" } else if c == "l" || c == "I" || c == "|" { ch[i] = "1" }
        }
        return ch
    }

    static func trimChars(_ s: String, _ set: String) -> String {
        let a = Array(s), keep = Set(set)
        var i = 0, j = a.count
        while i < j && keep.contains(a[i]) { i += 1 }
        while j > i && keep.contains(a[j - 1]) { j -= 1 }
        return String(a[i..<j])
    }

    /// Lower-case words of a name (ASCII letters and digits; anything else splits words).
    static func words(_ s: String) -> [String] {
        var out: [String] = [], w = ""
        for c in s.lowercased() {
            if isAsciiLetter(c) || isDigit(c) { w.append(c) } else { if !w.isEmpty { out.append(w) }; w = "" }
        }
        if !w.isEmpty { out.append(w) }
        return out
    }

    static func bigrams(_ s: String) -> [String] {
        let a = Array(s)
        var out: [String] = []
        if a.count >= 2 { for i in 0..<(a.count - 1) { out.append(String(a[i...i + 1])) } }
        return out
    }

    /// How alike two party names are, 0 to 1.
    static func nameScore(_ a: String, _ b: String) -> Double {
        let wa = words(a), wb = words(b)
        let na = wa.joined(), nb = wb.joined()
        if na.isEmpty || nb.isEmpty { return 0 }
        if na == nb { return 1 }
        let A = bigrams(na), B = bigrams(nb)
        var common = 0
        var left = B
        for g in A { if let k = left.firstIndex(of: g) { common += 1; left.remove(at: k) } }
        var score = A.count + B.count > 0 ? Double(2 * common) / Double(A.count + B.count) : 0
        let ca = wa.filter { !STOP_WORDS.contains($0) }.joined(), cb = wb.filter { !STOP_WORDS.contains($0) }.joined()
        if ca.isEmpty { score = min(score, 0.5) }   // only words like "Traders" or "Store": not enough to tell parties apart
        if ca.count >= 3 && cb.count >= 3 && (ca == cb || cb.hasPrefix(ca) || ca.hasPrefix(cb)) { score = max(score, ca == cb ? 0.95 : 0.85) }
        return JS.round(score * 100) / 100
    }

    struct Match {
        let id: Int, name: String, score: Double
        static func before(_ x: Match, _ y: Match) -> Bool {
            if x.score != y.score { return x.score > y.score }
            if x.name != y.name { return x.name < y.name }
            return x.id < y.id
        }
    }

    struct Line { var name: String; var bills: [Double]; var payment: Double?; var amount: Double }

    /// Splits one written line into the party name, the bill amounts and the payment.
    static func parseLine(_ raw: String) -> Line {
        var s = fixDigits(raw.components(separatedBy: "₹").joined(separator: " "))
        s = Array(String(s).components(separatedBy: "/-").joined(separator: " "))
        // a serial number in front: "1. Ram Store ..." or "1) Ram Store ..."
        var i = 0
        while i < s.count && isSpace(s[i]) { i += 1 }
        var j = i
        while j < s.count && isDigit(s[j]) { j += 1 }
        if j > i && j < s.count && (s[j] == "." || s[j] == ")") { s = Array(s[(j + 1)...]) }
        let first = s.firstIndex(where: isDigit) ?? -1
        let namePart = first < 0 ? String(s) : String(s[0..<first])
        let nameTrim = " \t,.-:=;|/"
        var name = trimChars(namePart, nameTrim)
        // "Rs", "paid", "cash" written before the first amount belong to the amount, not the name
        var payWord = false
        while true {
            let a = Array(name)
            let sp = a.lastIndex(of: " ") ?? -1
            let tail = trimChars(String(a[(sp + 1)...]).lowercased(), ".:-=")
            if tail != "rs" && !PAY_WORDS.contains(tail) { break }
            if tail != "rs" { payWord = true }
            name = sp < 0 ? "" : trimChars(String(a[0..<sp]), nameTrim)
        }
        var nums: [(value: Double, sep: String)] = []
        if first >= 0 {
            var sep = ""
            var k = first
            while k < s.count {
                if isDigit(s[k]) {
                    var t = ""
                    while k < s.count && isDigit(s[k]) { t.append(s[k]); k += 1 }
                    // Indian grouping inside one amount: 1,200 or 1,20,000 (commas between bills follow 3 or more digits)
                    var group = t.count, firstGroup = true
                    while k < s.count && s[k] == "," && ((firstGroup && group == 1) || (!firstGroup && group == 2)) {
                        var e = k + 1
                        while e < s.count && isDigit(s[e]) { e += 1 }
                        let run = e - (k + 1)
                        if !(run == 3 || (run == 2 && e < s.count && s[e] == ",")) { break }
                        t += String(s[(k + 1)..<e])
                        k = e; group = run; firstGroup = false
                    }
                    if k + 1 < s.count && s[k] == "." && isDigit(s[k + 1]) {
                        t.append(s[k]); k += 1
                        while k < s.count && isDigit(s[k]) { t.append(s[k]); k += 1 }
                    }
                    nums.append((Double(t) ?? 0, sep))
                    sep = ""
                } else { sep.append(s[k]); k += 1 }
            }
        }
        let hasPayWord = { (sep: String) in words(sep).contains { PAY_WORDS.contains($0) } }
        let isPayment = { (n: (value: Double, sep: String)) in !n.sep.isEmpty && (!n.sep.contains(",") || hasPayWord(n.sep)) }
        var bills = nums.map { $0.value }
        var payment: Double? = nil
        if nums.count >= 2, isPayment(nums[nums.count - 1]) { payment = nums[nums.count - 1].value; bills.removeLast() }
        else if nums.count == 1, payWord || hasPayWord(nums[0].sep) { payment = nums[0].value; bills = [] }
        let amount = payment != nil ? r2(payment!) : r2(bills.reduce(0, +))
        return Line(name: name, bills: bills.map(r2), payment: payment.map(r2), amount: amount)
    }

    /// Reads every line and finds the party and bills each one means.
    static func parse(_ db: Database, _ b: Row) throws -> Row {
        let text = (JS.truthy(b["text"]) ? JS.string(b.v("text")) : "").replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let parties = try db.prepare("SELECT id,name FROM parties WHERE active=1 AND type <> 'SUPPLIER' ORDER BY name, id").all()
        let billsOf = db.prepare("SELECT id,invoice_no,date,total,paid FROM invoices WHERE party_id=? ORDER BY date DESC, id DESC")
        var rows: [Row] = []
        var lineNo = 0
        var readyTotal = 0.0, ready = 0
        for line in text.components(separatedBy: "\n") {
            lineNo += 1
            if trimChars(line, " \t\r").isEmpty { continue }
            let p = parseLine(line)
            if p.name.isEmpty && p.bills.isEmpty && p.payment == nil { continue }
            var scored: [Match] = []
            for x in parties {
                let sc = nameScore(p.name, x.str("name"))
                if sc >= 0.3 { scored.append(Match(id: x.i("id"), name: x.str("name"), score: sc)) }
            }
            scored.sort(by: Match.before)
            let best: Match? = !scored.isEmpty && scored[0].score >= 0.6 ? scored[0] : nil
            var problems: [String] = []
            if p.name.isEmpty { problems.append("No party name") }
            else if best == nil { problems.append("Party not found") }
            else if scored.count > 1 && scored[1].score == best!.score { problems.append("More than one party matches") }
            if !(p.amount > 0) { problems.append("No amount") }
            var used = Set<Int>()
            var billRefs: [Row] = []
            for amt in p.bills {
                guard let best else { billRefs.append(["amount": amt, "invoice_no": NSNull()]); continue }
                if let hit = try billsOf.all(best.id).first(where: { !used.contains($0.i("id")) && abs($0.n("total") - amt) < 0.5 }) {
                    used.insert(hit.i("id"))
                    billRefs.append(["amount": amt, "invoice_no": hit.str("invoice_no"), "invoice_id": hit.i("id"), "date": hit.str("date")])
                } else { billRefs.append(["amount": amt, "invoice_no": NSNull()]) }
            }
            var r: Row = ["line": lineNo, "text": trimChars(line, " \t\r"), "name": p.name]
            r["party_id"] = best.map { $0.id as Any } ?? NSNull()
            r["party_name"] = best.map { $0.name as Any } ?? NSNull()
            r["balance"] = best != nil ? r2(try Billing.partyBalance(db, best!.id)) as Any : NSNull()
            r["score"] = best?.score ?? 0
            r["candidates"] = scored.prefix(3).map { ["id": $0.id, "name": $0.name, "score": $0.score] as Row }
            r["bills"] = billRefs
            r["payment"] = p.payment.map { $0 as Any } ?? NSNull()
            r["amount"] = p.amount
            r["reference"] = reference(billRefs).map { $0 as Any } ?? NSNull()
            r["problems"] = problems
            if problems.isEmpty { ready += 1; readyTotal += p.amount }
            rows.append(r)
        }
        return ["rows": rows, "lines": rows.count, "ready": ready, "total": r2(readyTotal)]
    }

    /// "Bills A000412, A000418, 950" for the receipt's reference.
    static func reference(_ bills: [Row]) -> String? {
        if bills.isEmpty { return nil }
        return "Bills " + bills.map { JS.truthy($0["invoice_no"]) ? $0.str("invoice_no") : JS.string($0["amount"] ?? nil) }.joined(separator: ", ")
    }

    /// Saves the checked rows as receipts, all or nothing.
    static func save(_ db: Database, _ b: Row) throws -> Row {
        try db.transaction {
            let rows = (b["rows"] as? [Any])?.compactMap { $0 as? Row } ?? []
            if rows.isEmpty { throw HttpError(400, "No payments to save") }
            let date = JS.truthy(b["date"]) ? JS.string(b.v("date")) : today()
            let mode = JS.truthy(b["mode"]) ? JS.string(b.v("mode")) : "CASH"
            var saved: [Row] = []
            var total = 0.0
            for (i, r) in rows.enumerated() {
                do {
                    let v = try Vouchers.record(db, ["party_id": r["party_id"] ?? nil, "amount": r["amount"] ?? nil, "date": date, "mode": mode,
                                                     "reference": JS.truthy(r["reference"]) ? r["reference"]! : NSNull(), "direction": "RECEIVED"])
                    let p = try db.prepare("SELECT name FROM parties WHERE id=?").get(r.v("party_id"))
                    saved.append(["voucher_no": v["voucher_no"]!, "party_id": r.v("party_id") as Any, "party": p?.str("name") ?? "", "amount": v["amount"]!, "balance": v["balance"]!])
                    total += JS.number(v["amount"] ?? nil)
                } catch let e as HttpError {
                    throw HttpError(e.status, "Row \(i + 1): \(e.message)")
                }
            }
            return ["saved": saved, "count": saved.count, "total": r2(total)]
        }
    }
}
