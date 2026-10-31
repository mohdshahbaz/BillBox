import Foundation

/// Parser for text read from a supplier's GST tax invoice, one string per PDF page (backend/src/services/pdfParser.js, line for line).
///   1. selectOriginalPages : only "Original" / "Original Copy" pages; Duplicate / Triplicate / Transporter / Office copies skipped
///   2. mergePages          : page 2+ lose repeated headers, "Page x of y", "Continued", b/f and c/f lines
///   3. parseItems          : column-aware rows (item name = description column), renumbered 1..n
///   4. parseTotals         : Discount, CGST, SGST, IGST, Round off and Grand total
///   5. parseSupplier       : name, address, GSTIN, state code, tel, phone, mobiles, FSSAI, PAN, email
/// Everything is a suggestion; nothing is saved by the parser.
public enum PDFParser {
    static let GSTIN_RE = "\\b\\d{2}[A-Z]{5}\\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]\\b"
    static let MONTHS = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6, "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12]
    static let GST_RATES: [Double] = [0, 3, 5, 12, 18, 28]

    static func pad(_ n: Any) -> String { JS.string(n).padStart(2, "0") }
    static func toNum(_ s: String) -> Double { JS.parseNumber(rx("[,\\s]", "g").replace(s, "")) }
    static func norm(_ s: String?) -> String {
        var x = (s ?? "").lowercased()
        x = rx("[^a-z0-9 ]+", "g").replace(x, " ")
        x = rx("\\s+", "g").replace(x, " ")
        return JS.trim(x)
    }
    static func tokensOf(_ s: String?) -> Set<String> { Set(norm(s).components(separatedBy: " ").filter { $0.jsLength > 1 }) }
    static func cleanLines(_ t: String?) -> [String] {
        rx("\\r?\\n").split(t ?? "").map { l -> String in
            var x = rx("[\\u00a0\\t]+", "g").replace(l, " ")
            x = rx("\\s+", "g").replace(x, " ")
            x = rx("(\\d)\\s+%", "g").replace(x) { m in m[1]! + "%" }
            return JS.trim(x)
        }.filter { !$0.isEmpty }
    }

    // MARK: 1. Original pages only

    static let KIND_RES: [(String, JSRegex)] = [
        ("original", rx("\\boriginal\\b(?!\\s+(?:invoice\\s+)?(?:no|number|date|ref))", "i")),
        ("duplicate", rx("\\bduplicate\\b", "i")),
        ("triplicate", rx("\\btriplicate\\b", "i")),
        ("other", rx("\\b(?:extra|office|transporter|customer|driver|accounts?)\\s+copy\\b", "i")),
    ]

    /// 'original' | 'duplicate' | 'triplicate' | 'other' | 'multi' | nil
    public static func copyKind(_ pageText: String) -> String? {
        let lines = cleanLines(pageText)
        // labels sit in the header or footer; scanning the middle would catch words inside item names
        let zone = (Array(lines.prefix(14)) + Array(lines.suffix(10))).joined(separator: "\n")
        let found = KIND_RES.filter { $0.1.test(zone) }.map { $0.0 }
        if found.isEmpty { return nil }
        if found.count > 1 { return "multi" }
        return found[0]
    }

    static func fingerprint(_ pageText: String) -> Set<String> { Set(cleanLines(pageText).filter { rx("\\d").test($0) }.map { norm($0) }) }
    static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        if a.isEmpty || b.isEmpty { return 0 }
        let hit = a.filter { b.contains($0) }.count
        return Double(hit) / Double(a.count + b.count - hit)
    }

    struct Selected { var used: [Int]; var skipped: [Row]; var note: String; var pages: [String] }

    static func selectOriginalPages(_ pages: [String]) -> Selected {
        let kinds = pages.map(copyKind)
        let definite = kinds.compactMap { $0 }.filter { $0 != "multi" }
        var skipped: [Row] = []
        var keep: [Int]
        var note = ""
        if definite.isEmpty {
            keep = Array(pages.indices)
            if pages.count > 1 { note = "No copy labels (Original / Duplicate) found; all pages were read and repeated pages dropped." }
        } else {
            var cur: String?
            keep = []
            for (i, k) in kinds.enumerated() {
                if let k, k != "multi" { cur = k }
                let effective = cur ?? "original"           // pages before the first label belong to the first (original) copy
                if effective == "original" { keep.append(i) } else { skipped.append(["page": i + 1, "kind": cur.map { $0 as Any } ?? NSNull()]) }
            }
            if keep.isEmpty {
                keep = Array(pages.indices)
                skipped = []
                note = "No \"Original\" copy found on any page; all pages were read."
            }
        }
        // Same content twice (labels missing or ambiguous): keep the first
        var seen: [Set<String>] = []
        keep = keep.filter { i in
            let fp = fingerprint(pages[i])
            if fp.count >= 5 && seen.contains(where: { jaccard($0, fp) >= 0.85 }) { skipped.append(["page": i + 1, "kind": "repeat"]); return false }
            seen.append(fp)
            return true
        }
        return Selected(used: keep.map { $0 + 1 }, skipped: skipped, note: note, pages: keep.map { pages[$0] })
    }

    // MARK: 2. Merge pages

    static let TOTAL_MARK = rx("(^\\W*(?:less|add)\\s*:|sub\\s*-?\\s*total|total\\s*(amount|taxable|qty|quantity)|grand\\s*total|amount\\s*(chargeable\\s*)?in\\s*words|bank\\s*details|terms\\s*&?\\s*conditions|taxable\\s*value|total\\s*invoice)", "i")
    static let CONT_MARK_SRC = "(^|\\s)(continued|contd\\.?|c\\/f|b\\/f|c\\/o|b\\/d|carried\\s*forward|brought\\s*forward|page\\s*total|please\\s*turn\\s*over)(?=\\s|$|\\.)"
    static let CONT_MARK = rx(CONT_MARK_SRC, "i")
    /// Page furniture that carries a running total: "b/d 71.00 BOX 1,30,564.22". Never an item row.
    static let CARRY_LINE = rx("^\\W*(?:sub\\s*)?(?:totals?\\s*)?(?:b\\/d|b\\/f|c\\/o|c\\/f|brought\\s*forward|carried\\s*(?:forward|over)|page\\s*total)\\b", "i")
    static let PAGE_NO = rx("^\\W*(?:page\\s*)?\\d+\\s*(?:of|\\/)\\s*\\d+\\W*$", "i")
    static let COPY_LABEL = rx("^\\W*(?:original|duplicate|triplicate)(?:\\s+(?:copy|for\\s+[\\w\\/ ]+))?\\W*$", "i")

    struct Merged { var page: Int; var lines: [String]; var hdr: Int }

    static func mergePages(_ pageTexts: [String]) -> [Merged] {
        var out: [Merged] = []
        var headerSet: Set<String> = []
        for (p, t) in pageTexts.enumerated() {
            var lines = cleanLines(t)
            let hdr = lines.firstIndex { detectColumns($0) != nil } ?? -1
            if p == 0 {
                headerSet = Set(lines.prefix(hdr >= 0 ? hdr + 1 : 8).map { norm($0) })
            } else {
                lines = lines.filter { l in
                    let n = norm(l)
                    let contOnly = CONT_MARK.test(l) && !rx("\\d{3,}").test(rx(CONT_MARK_SRC, "i").replace(l, ""))
                    return !(headerSet.contains(n) || CARRY_LINE.test(l) || rx("^\\W*code\\W*$", "i").test(l) || PAGE_NO.test(l) || COPY_LABEL.test(l) || detectColumns(l) != nil || contOnly)
                }
            }
            out.append(Merged(page: p, lines: lines, hdr: p == 0 ? hdr : -1))
        }
        return out
    }

    // MARK: 3. Items

    static let COLS: [(String, JSRegex)] = [
        ("sno", rx("(?:^|\\s)(?:s\\.?\\s?no\\.?|sl\\.?\\s?no\\.?|sr\\.?\\s?no\\.?|sl|sr|s\\.n\\.?|no\\.?|#)(?=\\s|$)", "i")),
        ("desc", rx("(?:description(?:\\s+of\\s+(?:goods|items?))?|particulars|item(?:\\s+name)?|product(?:\\s+name)?|goods)", "i")),
        ("hsn", rx("\\b(?:hsn|sac)(?:\\s*\\/\\s*(?:hsn|sac))?(?:\\s*code)?\\b", "i")),
        ("qty", rx("\\b(?:qty|quantity|nos)\\b\\.?", "i")),
        ("unit", rx("\\b(?:unit|uom|per)\\b", "i")),
        ("mrp", rx("\\bmrp\\b", "i")),
        ("rate", rx("\\b(?:rate|price)\\b", "i")),
        ("disc", rx("\\bdisc(?:ount)?\\b", "i")),
        ("tax", rx("\\b(?:gst|cgst|sgst|igst|tax)\\b", "i")),
        ("amount", rx("\\b(?:amount|amt|value|total)\\b", "i")),
    ]

    /// Column order of an item-table header line, or nil when the line is not a header.
    public static func detectColumns(_ line: String) -> [String]? {
        var hits: [(Int, String)] = []
        for (k, re) in COLS { if let m = re.exec(line) { hits.append((m.index, k)) } }
        let keys = hits.map { $0.1 }
        if !keys.contains("desc") || !keys.contains("qty") || !(keys.contains("amount") || keys.contains("rate")) { return nil }
        return stableSorted(hits) { $0.0 < $1.0 }.map { $0.1 }
    }

    static let KIND_OK: [String: JSRegex] = [
        "hsn": rx("^\\d{4,8}$"), "qty": rx("^\\d[\\d,]*(\\.\\d+)?$"), "unit": rx("^[A-Za-z]{1,8}\\.?$"), "mrp": rx("^\\d[\\d,]*(\\.\\d+)?$"),
        "rate": rx("^\\d[\\d,]*(\\.\\d+)?$"), "amount": rx("^\\d[\\d,]*(\\.\\d+)?$"), "disc": rx("^-?\\d[\\d,]*(\\.\\d+)?%?$"), "tax": rx("^-?\\d+(\\.\\d+)?%?$"), "sno": rx("^\\d{1,3}\\.?$"),
    ]
    static let UNITS: Set<String> = ["PCS", "PC", "NOS", "NO", "BOX", "BOXES", "CASE", "CS", "CTN", "KG", "KGS", "GM", "GMS", "LTR", "LT", "L", "ML", "PKT", "PKTS", "PACK", "DOZ", "SET", "BAG", "BTL", "JAR", "BDL", "MTR"]

    static func plausible(_ q: Double, _ r: Double, _ a: Double, _ floor: Double = 0.4) -> Bool {
        if !(q > 0 && a > 0) { return false }
        if !(r > 0) { return true }
        let g = q * r
        return abs(g - a) <= max(0.6, g * 0.01) || (a < g * 0.995 && a >= g * floor)
            || GST_RATES.contains { x in x > 0 && abs(g * (1 + x / 100) - a) <= max(0.6, a * 0.01) }
    }

    static func rowFromColumns(_ line: String, _ cols: [String]) -> Row? {
        var toks = line.components(separatedBy: " ")
        let hasUnit = cols.contains("unit")
        if hasUnit {
            // "10PCS" glued: split it so that qty and unit are separate tokens
            let limit = toks.count - (cols.count - (cols.firstIndex(of: "desc") ?? -1) - 1)
            var out: [String] = []
            for (ti, t) in toks.enumerated() {
                if ti < limit { out.append(t); continue }
                if let m = rx("^(\\d+(?:\\.\\d+)?)([A-Za-z]{2,5})\\.?$").exec(t), UNITS.contains(m[2]!.uppercased()) { out.append(m[1]!); out.append(m[2]!) } else { out.append(t) }
            }
            toks = out
        } else {
            // "12 PCS": a bare unit word straight after a number, but the header has no Unit column: drop it
            let orig = toks
            toks = orig.enumerated().filter { (ti, t) in
                !(ti > 0 && UNITS.contains(rx("\\.$").replace(t, "").uppercased()) && rx("^\\d+(\\.\\d+)?$").test(orig[ti - 1]))
            }.map { $0.1 }
        }
        let k = cols.firstIndex(of: "desc") ?? -1
        let leftAll = k >= 0 ? Array(cols[0..<k]) : []
        let left = leftAll.filter { $0 != "sno" }
        let hasSno = leftAll.contains("sno")
        let right = Array(cols[(k + 1)...])
        if hasSno && KIND_OK["sno"]!.test(toks.first ?? "") { toks = Array(toks.dropFirst()) }
        // Try with all right-hand columns, then without the ones that are often blank
        let variants = [right, right.filter { $0 != "disc" }, right.filter { $0 != "disc" && $0 != "tax" }, right.filter { !["disc", "tax", "mrp"].contains($0) }]
        var seenV: [String] = []
        for v in variants { let s = v.joined(separator: "|"); if !seenV.contains(s) { seenV.append(s) } }
        for s in seenV {
            let rc = s.isEmpty ? [] : s.components(separatedBy: "|")
            let need = left.count + rc.count
            if toks.count < need + 1 { continue }
            let lt = Array(toks[0..<left.count]), rt = Array(toks[(toks.count - rc.count)...]), name = Array(toks[left.count..<(toks.count - rc.count)])
            func ok(_ arr: [String], _ kinds: [String]) -> Bool {
                kinds.enumerated().allSatisfy { (i, kk) in KIND_OK[kk] == nil || KIND_OK[kk]!.test(arr[i]) }
            }
            if !ok(lt, left) || !ok(rt, rc) { continue }
            func get(_ kind: String, _ arr: [String], _ kinds: [String]) -> String? {
                guard let i = kinds.firstIndex(of: kind) else { return nil }
                return arr[i]
            }
            let qty = toNum(get("qty", rt, rc) ?? get("qty", lt, left) ?? "undefined")
            let rate = toNum(get("rate", rt, rc) ?? "0"), amount = toNum(get("amount", rt, rc) ?? "0")
            let unitTok = get("unit", rt, rc) ?? get("unit", lt, left)
            if !(qty > 0) || !plausible(qty, rate, (amount != 0 && !amount.isNaN) ? amount : qty * rate, 0.1) { continue }
            let desc = JS.trim(rx("[|:;,]+$").replace(name.joined(separator: " "), ""))
            if !rx("[A-Za-z]{2}").test(desc) { continue }
            let hsn = get("hsn", rt, rc) ?? get("hsn", lt, left)
            let taxTok = get("tax", rt, rc)
            let mrpTok = get("mrp", rt, rc)
            return [
                "mrp_col": mrpTok.map { toNum($0) as Any } ?? NSNull(),
                "description": desc,
                "hsn": (hsn?.isEmpty == false) ? hsn! : NSNull(),
                "qty": qty,
                "unit": unitTok.map { rx("\\.$").replace($0, "").uppercased() as Any } ?? NSNull(),
                "rate": rate,
                "amount": (amount != 0 && !amount.isNaN) ? amount : r2(qty * rate),
                "tax_hint": taxTok.map { toNum($0.replacingOccurrences(of: "%", with: "")) as Any } ?? NSNull(),
            ]
        }
        return nil
    }

    /// Fallback when the header is missing or unreadable: find qty, rate and amount from the numbers on the line.
    static func rowByNumbers(_ line: String) -> Row? {
        let parts = line.components(separatedBy: " ")
        struct N { let idx: Int; let v: Double; let raw: String }
        var nums: [N] = []
        for (idx, p) in parts.enumerated() where rx("^-?\\d[\\d,]*(\\.\\d+)?%?$").test(p) {
            nums.append(N(idx: idx, v: toNum(p.replacingOccurrences(of: "%", with: "")), raw: p))
        }
        if nums.count < 3 { return nil }
        var first = 0
        if nums[0].idx == 0 && JS.isInteger(nums[0].v) && nums[0].v < 1000 { first = 1 }
        let hsnI = nums.indices.first { $0 >= first && rx("^\\d{4,8}$").test(nums[$0].raw) }
        let pool = nums.indices.filter { $0 >= first && $0 != hsnI }.map { nums[$0] }
        var best: (i: Int, j: Int, k: Int, kind: Int, q: Double, r: Double, a: Double)?
        for i in pool.indices {
            for j in (i + 1)..<max(i + 1, pool.count) where j < pool.count {
                for k in (j + 1)..<max(j + 1, pool.count) where k < pool.count {
                    let q = pool[i].v, r = pool[j].v, a = pool[k].v
                    if !(JS.isInteger(q) && q > 0 && q < 100000 && r > 0 && a > 0) { continue }
                    let g = q * r
                    let kind = abs(g - a) <= max(0.6, g * 0.005) ? 0 : (a < g * 0.995 && a >= g * 0.5 ? 2 : -1)
                    if kind < 0 { continue }
                    if best == nil || kind < best!.kind || (kind == best!.kind && k > best!.k) { best = (i, j, k, kind, q, r, a) }
                }
            }
        }
        guard let b = best else { return nil }
        let qt = pool[b.i], rt = pool[b.j]
        let nameEnd = min(qt.idx, hsnI.map { nums[$0].idx } ?? 1_000_000_000, rt.idx)
        let startIdx = first == 1 ? 1 : 0
        let desc = JS.trim(rx("[|:;,]+$").replace(nameEnd > startIdx ? parts[startIdx..<nameEnd].joined(separator: " ") : "", ""))
        if !rx("[A-Za-z]{2}").test(desc) { return nil }
        let after = qt.idx + 1 < parts.count ? parts[qt.idx + 1] : nil
        var unit: Any = NSNull()
        if let a = after, rx("^[A-Za-z]{2,6}\\.?$").test(a), UNITS.contains(rx("\\.$").replace(a, "").uppercased()) { unit = rx("\\.$").replace(a, "").uppercased() }
        return ["description": desc, "hsn": hsnI.map { nums[$0].raw as Any } ?? NSNull(), "qty": b.q, "unit": unit, "rate": b.r, "amount": b.a, "tax_hint": NSNull()]
    }

    public static func similarity(_ a: String?, _ b: String?) -> Double {
        let A = tokensOf(a), B = tokensOf(b)
        if A.isEmpty || B.isEmpty { return 0 }
        let hit = A.filter { B.contains($0) }.count
        return Double(hit) / Double(max(A.count, B.count))
    }

    static func bestMatch(_ text: String, _ list: [Row], _ hsn: Any?) -> (match: Row?, score: Double) {
        var best: Row?
        var score = 0.0
        let want = sizeTokens(text)
        for x in list {
            let have = sizeTokens(x.str("name"))
            if (want.pack != nil && have.pack != nil && want.pack != have.pack) || (want.mrp != nil && have.mrp != nil && want.mrp != have.mrp) { continue }
            var s = similarity(text, x.s("name"))
            if JS.truthy(hsn) && JS.truthy(x["hsn"]) && JS.string(x.v("hsn")) == JS.string(unwrap(hsn)) { s += 0.25 }
            if s > score { score = s; best = x }
        }
        return score >= 0.5 ? (best, min(1, score)) : (nil, score)
    }

    // MARK: facts read from the item name

    /// "(1X144)", "(1X300 PKT)", "(300 PKT)", "(1X432PKT)" -> 144 / 300 / 300 / 432 pieces in one box.
    public static func packFromName(_ name: String?) -> Int? {
        let s = name ?? ""
        guard let m = rx("\\(\\s*(?:(\\d+)\\s*[xX*]\\s*)?(\\d{1,5})\\s*(?:PKTS?|PCS?|NOS|PACKS?|UNITS?)?\\s*\\)", "i").exec(s) else {
            if let m2 = rx("\\b\\d+\\s*[xX]\\s*(\\d{2,5})\\b(?!\\s*(?:ml|g|gm|kg|ltr|l)\\b)", "i").exec(s) { return Int(m2[1]!) }
            return nil
        }
        let v = Int(m[2]!) ?? 0
        return v >= 1 ? v : nil
    }

    /// MRP printed inside an item name: "MRP-10/-", "M.R.P. Rs 10", "Rs.10/-", "₹10", "BIKANO CHIPS 10/-", "NAMKEEN @ 20".
    public static func mrpFromName(_ name: String?) -> Double? {
        let s = name ?? ""
        let forms = [
            rx("\\bM\\.?\\s*R\\.?\\s*P\\.?\\s*[-:.=]?\\s*(?:RS\\.?|INR|₹)?\\s*(\\d+(?:\\.\\d+)?)", "i"),
            rx("(?:\\bRS\\.?|\\bINR|₹)\\s*(\\d+(?:\\.\\d+)?)", "i"),
            rx("(?:^|[\\s(])(\\d+(?:\\.\\d+)?)\\s*\\/\\s*-"),
            rx("@\\s*(\\d+(?:\\.\\d+)?)\\b(?!\\s*(?:g|gm|kg|ml|l)\\b)", "i"),
        ]
        for re in forms {
            if let m = re.exec(s), let v = Double(m[1]!), v > 0, v < 100000 { return v }
        }
        return nil
    }

    /// HSN -> usual GST rate, used only when the bill does not print a single rate.
    static let HSN_RATE: [(String, Double)] = [
        ("2106", 12), ("2105", 18), ("1905", 18), ("1704", 18), ("1806", 18), ("1902", 12), ("1904", 18), ("2008", 12), ("2009", 12), ("2202", 28), ("2201", 18),
        ("0902", 5), ("1006", 5), ("1101", 0), ("1512", 5), ("1701", 5), ("0713", 0), ("3401", 18), ("3402", 18), ("3305", 18), ("3306", 18), ("3307", 18), ("2501", 0),
    ]
    public static func rateFromHsn(_ hsn: Any?) -> Double? {
        let h = JS.truthy(hsn) ? JS.string(unwrap(hsn)) : ""
        return HSN_RATE.first { h.hasPrefix($0.0) }?.1
    }

    static func enrichLine(_ r: inout Row, _ billRate: Double?) {
        r["pcs_per_box"] = packFromName(r.str("description")).map { $0 as Any } ?? NSNull()
        let col = r.v("mrp_col").map { JS.number($0) } ?? 0
        if col > 0 { r["mrp"] = col } else { r["mrp"] = mrpFromName(r.str("description")).map { $0 as Any } ?? NSNull() }   // the bill's MRP column wins
        r["mrp_col"] = nil
        // GST: the rate printed on the bill wins; else the usual rate for that HSN
        let g = billRate ?? rateFromHsn(r["hsn"] ?? nil)
        r["gst_rate"] = g.map { $0 as Any } ?? NSNull()
        r["gst_source"] = billRate != nil ? "bill" as Any : (g != nil ? "hsn" as Any : NSNull())
    }
    static func sizeTokens(_ s: String) -> (mrp: Double?, pack: Int?) { (mrpFromName(s), packFromName(s)) }

    // A name that wraps onto its own line sometimes carries a "(38%) (4.76% OFF)" footnote at the same height — strip those, keep the words.
    static let PCT_FRAG = rx("\\(\\s*-?\\d+(?:\\.\\d+)?\\s*%[^)]*\\)", "g")

    static func parseItems(_ merged: [Merged], _ items: [Row], _ warnings: inout [String]) -> (rows: [Row], lastIdx: Int, lastMi: Int) {
        var cols: [String]?
        for m in merged { if m.hdr >= 0, let c = detectColumns(m.lines[m.hdr]) { cols = c; break } }
        if cols == nil {
            outer: for m in merged { for l in m.lines { if let c = detectColumns(l) { cols = c; break outer } } }
        }
        if cols == nil { warnings.append("Item table header not recognised; rows were found by their numbers. Please check each row.") }
        var rows: [Row] = []
        var lastIdx = -1, lastMi = -1
        let foldBlock = rx("[₹$]|\\b(?:gst|cgst|sgst|igst|total|rs\\.?)\\b|(?:^|\\s)-(?:\\s+-){1,}", "i")
        for (mi, m) in merged.enumerated() {
            var start = 0
            if mi == 0 { start = m.hdr >= 0 ? m.hdr + 1 : 0 }
            var fold = 0
            var i = start
            while i < m.lines.count {
                let line = m.lines[i]
                defer { i += 1 }
                if CARRY_LINE.test(line) { continue }
                if TOTAL_MARK.test(line) || CONT_MARK.test(line) { break }   // totals block or page footer: the next page picks up the rows
                if let row = (cols.flatMap { rowFromColumns(line, $0) }) ?? rowByNumbers(line) {
                    rows.append(row); lastIdx = i; lastMi = mi; fold = 0; continue
                }
                // A short, number-free tail is most likely the rest of the item name above wrapping onto its own line.
                if !rows.isEmpty && fold < 4 && !foldBlock.test(line) {
                    let tail = JS.trim(PCT_FRAG.replace(line, ""))
                    if !tail.isEmpty && rx("[A-Za-z]").test(tail) && tail.jsLength <= 40 && !rx("\\d[\\d,]*\\.\\d\\d\\b").test(tail) && !rx("\\b\\d{5,}\\b").test(tail) {
                        let prev = rows[rows.count - 1].str("description")
                        rows[rows.count - 1]["description"] = JS.trim(rx("\\s+", "g").replace("\(prev) \(tail)", " "))
                        fold += 1
                    }
                }
            }
        }
        let out: [Row] = rows.enumerated().map { (i, r) in
            let m = bestMatch(r.str("description"), items, r["hsn"] ?? nil)
            let gross = r.n("qty") * r.n("rate")
            var o: Row = ["sno": i + 1]
            for (k, v) in r { o[k] = v }
            o["item_id"] = m.match?["id"] ?? NSNull()
            o["item_name"] = m.match?["name"] ?? NSNull()
            o["match_confidence"] = m.match != nil ? JS.round(m.score * 100) / 100 : 0
            o["amount_differs"] = r.n("rate") > 0 && abs(gross - r.n("amount")) > max(0.6, gross * 0.005)
            o["fractional_qty"] = !JS.isInteger(r.n("qty"))
            return o
        }
        if out.isEmpty { warnings.append("No item rows could be read. Add them manually or check the PDF.") }
        if out.contains(where: { !$0.has("item_id") }) { warnings.append("Some items were not matched to your stock list. Choose or create them.") }
        if out.contains(where: { ($0["fractional_qty"] as? Bool) == true }) { warnings.append("Some quantities are fractional; stock is kept in whole pieces. Please correct them.") }
        if out.contains(where: { ($0["amount_differs"] as? Bool) == true }) { warnings.append("For some rows Qty × Price does not equal the printed Amount (line discount?). The printed Amount was kept.") }
        return (out, lastIdx, lastMi)
    }

    // MARK: 4. Totals

    static let AMOUNT_RE = rx("-?\\d[\\d,]*\\.\\d{1,2}(?![\\d%])|-?\\d[\\d,]*(?![\\d.%,])", "g")
    /// Last money value on a line, ignoring "@ 2.50 %" rates: "Add : SGST @ 2.50 % 6,216.10" -> 6216.10
    static func lastAmount(_ line: String) -> Double? {
        let cleaned = rx("@?\\s*\\d+(?:\\.\\d+)?\\s*%", "g").replace(line, " ")
        let all = AMOUNT_RE.matches(cleaned)
        return all.isEmpty ? nil : toNum(all[all.count - 1])
    }
    static func rateOn(_ line: String) -> Double? {
        guard let m = rx("(\\d+(?:\\.\\d+)?)\\s*%").exec(line) else { return nil }
        return Double(m[1]!)
    }

    public static func parseTotals(_ lines: [String]) -> Row {
        var t: [String: Double?] = ["discount": nil, "cgst": nil, "sgst": nil, "igst": nil, "round_off": nil, "grand_total": nil]
        var rates: [String: [Double]] = ["cgst": [], "sgst": [], "igst": []]
        func add(_ k: String, _ v: Double) { t[k] = r2(((t[k] ?? nil) ?? 0) + v) }
        for line in lines {
            if rx("^\\W*(?:rupees|in\\s*words)", "i").test(line) { continue }
            guard let v = lastAmount(line) else { continue }
            if rx("grand\\s*total|invoice\\s*total|total\\s*invoice\\s*value|net\\s*(?:payable|amount)|bill\\s*amount|amount\\s*payable|total\\s*payable", "i").test(line) { t["grand_total"] = abs(v); continue }
            if rx("round(?:ed|ing)?[\\s\\-]*(?:off|of)\\b", "i").test(line) {
                let neg = rx("\\(\\s*-\\s*\\)|\\bless\\b|-\\s*[\\d.,]+\\s*$", "i").test(line)
                t["round_off"] = r2((neg ? -1 : 1) * abs(v))
                continue
            }
            if rx("\\bdiscount\\b|\\bdisc\\b", "i").test(line) && !rx("^\\s*\\d+\\.?\\s").test(line) { add("discount", abs(v)); continue }
            if rx("\\bC\\.?G\\.?S\\.?T\\b", "i").test(line) { add("cgst", abs(v)); if let r = rateOn(line) { rates["cgst"]!.append(r) }; continue }
            if rx("\\b(?:S\\.?G\\.?S\\.?T|UTGST)\\b", "i").test(line) { add("sgst", abs(v)); if let r = rateOn(line) { rates["sgst"]!.append(r) }; continue }
            if rx("\\bI\\.?G\\.?S\\.?T\\b", "i").test(line) { add("igst", abs(v)); if let r = rateOn(line) { rates["igst"]!.append(r) }; continue }
        }
        // Last resort: a table-footer summary row such as "TOTAL 157  27,257.71  40,223.4"
        if (t["grand_total"] ?? nil) == nil {
            for line in lines {
                if rx("^\\W*total\\s+\\d", "i").test(line) && !rx("^\\W*sub[\\s-]*total", "i").test(line), let v = lastAmount(line) { t["grand_total"] = abs(v); break }
            }
        }
        // GST rate of the bill: CGST% + SGST% (or IGST%) when one rate is printed; nil when several
        func uniq(_ a: [Double]) -> [Double] { var o: [Double] = []; for x in a where !o.contains(x) { o.append(x) }; return o }
        var gst: Double?
        if uniq(rates["cgst"]!).count == 1 && uniq(rates["sgst"]!).count <= 1 {
            let c = rates["cgst"]![0]
            let sg = rates["sgst"]!.first ?? 0
            gst = c + (sg != 0 ? sg : c)
        } else if uniq(rates["igst"]!).count == 1 { gst = rates["igst"]![0] }
        var out: Row = [:]
        for (k, v) in t { out[k] = v.map { $0 as Any } ?? NSNull() }
        out["gst_rate"] = gst.map { $0 as Any } ?? NSNull()
        return out
    }

    /// Tax-rate summary table: "5%  2,48,644.80  6,216.10  6,216.10  12,432.20" -> [5]
    static func summaryRates(_ lines: [String]) -> [Double] {
        var out: [Double] = []
        for l in lines { if let m = rx("^\\W*(\\d{1,2}(?:\\.\\d+)?)%\\s+[\\d,]+\\.\\d\\d\\b").exec(l), let v = Double(m[1]!), !out.contains(v) { out.append(v) } }
        return out
    }

    // MARK: 5. Supplier details

    static func toDigits(_ s: String) -> String { rx("\\D", "g").replace(s, "") }
    static func numbersIn(_ s: String) -> [String] {
        rx("[,;\\/&]|\\band\\b", "i").split(s).map { JS.trim($0) }.filter { toDigits($0).jsLength >= 6 && toDigits($0).jsLength <= 14 }
    }
    static func mobileOf(_ s: String) -> String? {
        let d = rx("^(91|0)(?=\\d{10}$)").replace(toDigits(s), "")
        return rx("^[6-9]\\d{9}$").test(d) ? d : nil
    }

    public static func parseSupplier(_ lines: [String], companyGstin: String, companyName: String) -> Row {
        // The supplier's block ends where the buyer's begins. Some templates print "Invoice No. / Date" between the supplier's
        // address and the supplier's GSTIN / mobile / e-mail, so the invoice row only ends it when no buyer heading is found.
        let buyerAt = lines.indices.first { $0 > 0 && BUYER_HEAD.test(lines[$0]) } ?? -1
        let invRe = rx("(?:invoice|bill|inv)\\s*(?:no|date)", "i")
        let stop = buyerAt > 0 ? buyerAt : (lines.indices.first { $0 > 0 && invRe.test(lines[$0]) } ?? -1)
        let head = Array(lines.prefix(stop > 0 ? min(stop, 16) : 14))
        let text = head.joined(separator: "\n")
        let own = companyGstin.uppercased()
        func uniqList(_ a: [String]) -> [String] { var o: [String] = []; for x in a where !o.contains(x) { o.append(x) }; return o }
        let gstins = uniqList(rx(GSTIN_RE, "g").matches(text)).filter { $0 != own }
        let gstin = gstins.first ?? uniqList(rx(GSTIN_RE, "g").matches(lines.joined(separator: "\n"))).filter { $0 != own }.first
        let sc = rx("state\\s*(?:code)?\\s*[:\\-]?\\s*(\\d{2})\\b", "i").exec(text)
        let pan = rx("\\bPAN\\s*(?:no\\.?|number|#)?\\s*[:\\-]?\\s*([A-Z]{5}\\d{4}[A-Z])\\b", "i").exec(text)
        let fssai = rx("FSSAI[^\\d\\n]{0,30}(\\d{14})", "i").exec(text)
            ?? rx("\\b(\\d{14})\\b").exec(text.components(separatedBy: "\n").filter { rx("fssai|lic", "i").test($0) }.joined(separator: " "))
        let email = rx("[\\w.+-]+@[\\w-]+(?:\\.[\\w-]+)+").exec(text)

        func label(_ re: JSRegex) -> String? { re.exec(text).flatMap { $0[1] }.map { JS.trim($0) } }
        let telRaw = label(rx("\\b(?:tel(?:ephone)?|landline)\\b\\.?\\s*(?:no\\.?)?\\s*[:\\-]?\\s*([\\d \\t\\-+(),\\/]{6,50})", "i"))
        let phoneRaw = label(rx("\\b(?:phone|ph)\\b\\.?\\s*(?:no\\.?)?\\s*[:\\-]?\\s*([\\d \\t\\-+(),\\/]{6,50})", "i"))
        let mobRaw = rx("\\b(?:mobile|mob|cell|whatsapp)\\b\\.?\\s*(?:no\\.?|nos\\.?)?\\s*[:\\-]?\\s*([\\d \\t\\-+(),\\/&and]{8,60})", "gi").matchAll(text).map { $0[1] ?? "" }
        var mobiles: [String] = []
        for raw in mobRaw { for n in numbersIn(raw) { if let m = mobileOf(n), !mobiles.contains(m) { mobiles.append(m) } } }
        // A number printed after "Tel." or "Phone" that is a 10-digit mobile belongs with the mobiles
        func split(_ raw: String?) -> String? {
            var land: [String] = []
            for n in (raw != nil && !raw!.isEmpty ? numbersIn(raw!) : []) {
                if let m = mobileOf(n) { if !mobiles.contains(m) { mobiles.append(m) } } else { land.append(n) }
            }
            let j = land.joined(separator: ", ")
            return j.isEmpty ? nil : j
        }
        let tel = split(telRaw)
        let phone = split(phoneRaw)
        // 10-digit mobile numbers printed without a label
        for m in rx("(?<![\\d-])(?:\\+?91[\\s-]?)?([6-9]\\d{9})(?!\\d)", "g").matchAll(text) {
            let n = m[1]!
            if !mobiles.contains(n) && !(phone != nil && toDigits(phone!).contains(n)) && !(tel != nil && toDigits(tel!).contains(n)) { mobiles.append(n) }
        }

        let (name, nameIdx) = supplierName(lines, companyName)
        var addr: [String] = []
        var i = nameIdx + 1
        let invoiceRe = rx("(tax\\s*invoice|invoice)", "i")
        let addressLabel = rx("^address\\s*[:\\-]?\\s*", "i")
        while i < head.count {
            let l = head[i]
            i += 1
            if BILL_ROW.test(l) { break }   // the invoice number row or the items table: the address is over
            if COPY_LABEL.test(l) || invoiceRe.test(l) { if !addr.isEmpty { break } else { continue } }
            // the address part of a line that also carries contact details ("NAGLA BYPASS, MORADABAD Tel: 01342-262626")
            let part = rx("[,.\\s]+$").replace(addressLabel.replace(withoutContact(l), ""), "")
            if rx("^\\d{6}$").test(part) && !addr.isEmpty { addr[addr.count - 1] += " - " + part; continue }   // the PIN code on a line of its own
            if !rx("[A-Za-z]{3}").test(part) { if !addr.isEmpty { break } else { continue } }
            addr.append(part)
            if addr.count >= 4 { break }
        }
        func opt(_ s: String?) -> Any { s.map { $0 as Any } ?? NSNull() }
        let a = addr.joined(separator: ", ")
        return [
            "name": opt(name), "address": a.isEmpty ? NSNull() : a, "gstin": opt(gstin),
            "state_code": sc != nil ? sc![1]! as Any : (gstin != nil ? gstin!.jsSlice(0, 2) as Any : NSNull()),
            "tel": opt(tel), "phone": opt(phone), "mobiles": mobiles, "fssai": opt(fssai?[1]),
            "pan": pan != nil ? pan![1]!.uppercased() as Any : (gstin != nil ? gstin!.jsSlice(2, 12) as Any : NSNull()), "email": opt(email?[0]),
        ]
    }

    static let SUFFIX = rx("\\b(pvt|private|ltd|limited|traders|enterprises?|distributors?|agenc(?:y|ies)|industries|foods|stores?|corporation|marketing|company|co\\.?|brothers|bros|beverages|trading|sales|suppliers?|sons|mart|udyog|impex|exports?|products|pharma|llp|emporium|depot|bhandar|kirana|wholesalers?|mills|provisions|associates|ventures)\\b", "i")
    static let GENERIC = rx("^(tax\\s*invoice|proforma(\\s*invoice)?|invoice|original|duplicate|triplicate|gstin|bill of supply|page|e-?invoice|irn|ack|cash|credit|\\(?see rule)", "i")
    static let INVOCATION = rx("^\\W*(?:shree|shri|sri|jai|om)\\s+(?:ganesh\\w*|mata\\s+di|ram|radhe|krishna|hanuman\\w*|balaji|sai\\s+ram|shyam|laxmi|lakshmi|durga)(?:\\s+(?:ji|namah?a?|ki\\s+jai|sahay\\w*))*\\W*$", "i")
    static let BILL_ROW = rx("\\b(?:invoice|bill|inv)\\s*(?:no|number|date)\\b|\\bdated\\b|\\bparticulars\\b|\\bdescription\\b|^s\\.?\\s*no\\b|\\bhsn\\b|\\bqty\\b", "i")
    static let BUYER_HEAD = rx("(party\\s*details|bill(?:ed)?\\s*to|buyer|consignee|ship(?:ped)?\\s*to|details\\s*of\\s*(?:receiver|buyer)|customer\\s*name|m\\/s)", "i")
    static let CONTACT_AT = rx("\\b(?:e-?mail(?:\\s*id)?|tel(?:ephone)?|phone|ph|mob(?:ile)?|cell|whatsapp|gstin|gst\\s*no|fssai|pan|cin|state\\s*code|website|fax|contact)\\b", "i")
    /// A header line with the contact details cut off: "SHREE TRADERS email : st@mail.com" -> "SHREE TRADERS".
    static func withoutContact(_ l: String) -> String {
        var s = rx("\\b(?:https?:\\/\\/|www\\.)\\S+", "gi").replace(rx("[\\w.+-]+@[\\w-]+(?:\\.[\\w-]+)+", "g").replace(l, " "), " ")
        if let m = CONTACT_AT.exec(s) { s = s.jsSlice(0, m.index) }
        s = rx("(?:\\+?91[\\s-]?)?[6-9]\\d{9}(?!\\d)", "g").replace(s, " ")
        s = rx("\\s+", "g").replace(s, " ")
        s = rx("^[\\s,;:|\\-\\/.]+").replace(s, "")
        s = rx("[\\s,;:|\\-\\/]+$").replace(s, "")
        return JS.trim(s)
    }
    /// The supplier's name among the first lines, without any e-mail / phone / GSTIN printed on the same line, and the line it is on.
    static func supplierName(_ lines: [String], _ companyName: String) -> (String?, Int) {
        let own = norm(companyName)
        var cand: [(String, Int)] = []
        for (idx, l) in lines.prefix(12).enumerated() {
            if GENERIC.test(l) || INVOCATION.test(l) || rx("^\\W*(bill to|ship to|buyer|consignee)", "i").test(l) { continue }
            let name = rx("^(?:m\\/s\\.?|from\\s*:)\\s*", "i").replace(withoutContact(l), "")
            if !rx("[A-Za-z]{3}").test(name) || GENERIC.test(name) { continue }
            if !own.isEmpty && norm(name).contains(own) { continue }
            cand.append((name, idx))
        }
        if let c = cand.first(where: { SUFFIX.test($0.0) && $0.0.jsLength < 70 }) ?? cand.first { return (c.0, c.1) }
        return (nil, -1)
    }
    static func guessSupplierName(_ lines: [String], _ companyName: String) -> String? { supplierName(lines, companyName).0 }

    // MARK: invoice no / date

    static func findInvoiceNo(_ text: String) -> String? {
        if let m = rx("(?:tax\\s+)?(?:proforma\\s+)?(?:invoice|inv|bill)\\s*(?:no|number|num|#)\\.?\\s*[:\\-#]?\\s*((?=[A-Z0-9\\/\\-]{0,24}\\d)[A-Z0-9][A-Z0-9\\/\\-]{2,24})", "i").exec(text) { return m[1] }
        // Some templates print the label on its own line with the values on a later line.
        let lines = text.components(separatedBy: "\n")
        if let li = lines.firstIndex(where: { rx("\\b(?:invoice|bill)\\s*(?:no|number|num|#)\\b", "i").test($0) }) {
            var i = li + 1
            while i < min(li + 3, lines.count) {
                var stripped = rx(GSTIN_RE, "g").replace(lines[i], " ")
                stripped = rx("(?:\\+?91[\\s-]?)?[6-9]\\d{9}\\b", "g").replace(stripped, " ")
                if let num = rx("\\b(\\d{2,8})\\b(?!\\s*[\\/\\-]\\d)").exec(stripped) { return num[1] }
                i += 1
            }
        }
        return nil
    }

    public static func normaliseDate(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        if let m = rx("(\\d{1,2})[\\/\\-.](\\d{1,2})[\\/\\-.](\\d{2,4})").exec(raw) {
            let d = m[1]!, mo = m[2]!
            var y = m[3]!
            y = y.jsLength == 2 ? "20" + y : y
            if let moN = Int(mo), let dN = Int(d), moN >= 1, moN <= 12, dN >= 1, dN <= 31 { return "\(y)-\(pad(mo))-\(pad(d))" }
        }
        if let m = rx("(\\d{1,2})[ \\-]([A-Za-z]{3})[A-Za-z]*[ \\-,.]*(\\d{2,4})").exec(raw), let mon = MONTHS[m[2]!.lowercased()] {
            let y = m[3]!.jsLength == 2 ? "20" + m[3]! : m[3]!
            return "\(y)-\(pad(mon))-\(pad(m[1]!))"
        }
        return nil
    }

    static let DATE_PAT = "(\\d{1,2}[\\/\\-.]\\d{1,2}[\\/\\-.]\\d{2,4}|\\d{1,2}[ \\-](?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*[ \\-,.]*\\d{2,4})"
    static func findDate(_ text: String) -> String? {
        if let near = rx("(?:(?:invoice|bill|inv|proforma)\\s*date|dated)\\s*[:\\-]?\\s*" + DATE_PAT, "i").exec(text), let d = normaliseDate(near[1]) { return d }
        return rx(DATE_PAT, "i").exec(text).flatMap { normaliseDate($0[1]) }
    }

    // MARK: entry points

    /// `pages`: text of each PDF page, in order. `items` / `parties` are the stock list and the suppliers to match against.
    public static func parseInvoicePages(_ pagesIn: [String], items: [Row] = [], parties: [Row] = [], companyGstin: String = "", companyName: String = "") -> Row {
        var warnings: [String] = []
        let sel = selectOriginalPages(pagesIn.isEmpty ? [""] : pagesIn)
        if !sel.note.isEmpty { warnings.append(sel.note) }
        let merged = mergePages(sel.pages)
        let first = merged[0].lines
        let firstText = first.joined(separator: "\n")

        let sup = parseSupplier(first, companyGstin: companyGstin, companyName: companyName)
        var matched: Row?
        if let g = sup.s("gstin") { matched = parties.first { JS.truthy($0["gstin"]) && $0.str("gstin").uppercased() == g } }
        if matched == nil, let n = sup.s("name") { matched = bestMatch(n, parties, nil).match }
        if !sup.has("name") { warnings.append("Supplier name not found") }

        let invoiceNo = findInvoiceNo(firstText)
        if invoiceNo == nil { warnings.append("Invoice number not found") }
        let date = findDate(firstText)
        if date == nil { warnings.append("Invoice date not found") }

        var (rows, lastIdx, lastMi) = parseItems(merged, items, &warnings)

        // Totals block: everything after the last item row (it may sit on a later Original page than the last row)
        let tail: [String] = lastMi >= 0
            ? Array(merged[lastMi].lines.dropFirst(lastIdx + 1)) + merged.dropFirst(lastMi + 1).flatMap { $0.lines }
            : Array(merged.flatMap { $0.lines }.suffix(40))
        var totals = parseTotals(tail)
        let billRates = summaryRates(tail)
        let fallbackRate: Double? = totals.has("gst_rate") ? totals.n("gst_rate") : (billRates.count == 1 ? billRates[0] : nil)
        for i in rows.indices { enrichLine(&rows[i], fallbackRate) }
        let subtotal = r2(rows.reduce(0.0) { $0 + $1.n("amount") })
        totals["subtotal"] = subtotal
        if !totals.has("grand_total") { warnings.append("Grand total not found on the bill") }
        let noTax = !totals.has("cgst") && !totals.has("sgst") && !totals.has("igst")
        if noTax { warnings.append("CGST / SGST / IGST amounts not found; they will be worked out from your item GST rates unless you type them.") }
        if totals.has("grand_total") && !rows.isEmpty {
            let calc = r2(subtotal - totals.n0("discount") + totals.n0("cgst") + totals.n0("sgst") + totals.n0("igst") + totals.n0("round_off"))
            if !noTax && abs(calc - totals.n("grand_total")) > 1 {
                warnings.append("Items − discount + taxes + round off = \(JS.numberString(calc)), but the bill's grand total is \(JS.numberString(totals.n("grand_total"))). Check the rows and the totals.")
            }
        }
        var supplier = sup
        supplier["matched_party_id"] = matched?["id"] ?? NSNull()
        supplier["matched_name"] = matched?["name"] ?? NSNull()
        return [
            "supplier": supplier,
            "invoice_no": invoiceNo.map { $0 as Any } ?? NSNull(), "date": date.map { $0 as Any } ?? NSNull(), "lines": rows, "totals": totals, "warnings": warnings,
            "pages": ["total": pagesIn.count, "used": sel.used, "skipped": sel.skipped] as Row,
            "stated_total": totals["grand_total"] ?? NSNull(),
        ]
    }

    /// Single string input (pages separated by form feed).
    public static func parseInvoiceText(_ text: String, items: [Row] = [], parties: [Row] = [], companyGstin: String = "", companyName: String = "") -> Row {
        parseInvoicePages(text.components(separatedBy: "\u{0C}"), items: items, parties: parties, companyGstin: companyGstin, companyName: companyName)
    }
}
