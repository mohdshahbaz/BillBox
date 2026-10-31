import Foundation

// backend/src/services/itemTools.js — tidy item names, find the same item entered twice, merge duplicates, and read
// item lists (company price lists found online) into new items. Strings are handled as UTF-16 units, exactly like
// JavaScript, so both engines give the same answers.
enum ItemTools {
    typealias U = [UInt16]

    static func u(_ s: String) -> U { Array(s.utf16) }
    static func str(_ a: U) -> String { String(decoding: a, as: UTF16.self) }
    static func str(_ a: ArraySlice<UInt16>) -> String { String(decoding: a, as: UTF16.self) }

    static func isDigit(_ c: UInt16) -> Bool { c >= 48 && c <= 57 }
    static func isUpperA(_ c: UInt16) -> Bool { c >= 65 && c <= 90 }
    static func isLowerA(_ c: UInt16) -> Bool { c >= 97 && c <= 122 }
    static func isLetterA(_ c: UInt16) -> Bool { isUpperA(c) || isLowerA(c) }
    static func lowerA(_ s: U) -> U { s.map { isUpperA($0) ? $0 + 32 : $0 } }
    static func upperA(_ s: U) -> U { s.map { isLowerA($0) ? $0 - 32 : $0 } }
    static func lowerA(_ s: String) -> String { str(lowerA(u(s))) }
    static func isWs(_ c: UInt16) -> Bool { c == 32 || c == 9 || c == 10 || c == 13 || c == 0xA0 }
    static let SP: UInt16 = 32, DOT: UInt16 = 46, COMMA: UInt16 = 44, LPAR: UInt16 = 40, RPAR: UInt16 = 41

    static let UNITS: [String: String] = [
        "g": "g", "gm": "g", "gms": "g", "gram": "g", "grams": "g", "gr": "g", "grm": "g", "grms": "g",
        "kg": "kg", "kgs": "kg", "kilo": "kg", "kilogram": "kg", "kilograms": "kg",
        "ml": "ml", "mls": "ml", "millilitre": "ml", "milliliter": "ml",
        "l": "L", "lt": "L", "ltr": "L", "ltrs": "L", "litre": "L", "liter": "L", "litres": "L", "liters": "L",
    ]
    static func unitOf(_ w: U, _ upper: Bool) -> U? {
        guard let x = UNITS[str(lowerA(w))] else { return nil }
        return upper ? upperA(u(x)) : u(x)
    }

    static func isNumber(_ w: U) -> Bool {
        if w.isEmpty { return false }
        var dots = 0
        for c in w { if c == DOT { dots += 1 } else if !isDigit(c) { return false } }
        return dots <= 1 && w[0] != DOT && w[w.count - 1] != DOT
    }

    static func trimEnd(_ s: U, _ set: String) -> U {
        let k = u(set)
        var b = s.count
        while b > 0 && k.contains(s[b - 1]) { b -= 1 }
        return Array(s[0..<b])
    }

    static func indexOf(_ h: U, _ n: U, _ from: Int = 0) -> Int {
        if n.isEmpty { return min(max(from, 0), h.count) }
        var i = max(from, 0)
        while i + n.count <= h.count {
            if h[i] == n[0] && Array(h[i..<(i + n.count)]) == n { return i }
            i += 1
        }
        return -1
    }
    static func includes(_ h: U, _ n: U) -> Bool { indexOf(h, n) >= 0 }
    static func startsWith(_ h: U, _ n: U, _ at: Int) -> Bool { at >= 0 && at + n.count <= h.count && Array(h[at..<(at + n.count)]) == n }
    /// `s.split(a).join(b)`
    static func replaceAll(_ s: U, _ a: U, _ b: U) -> U {
        var o: U = [], i = 0
        while i < s.count {
            if startsWith(s, a, i) { o += b; i += a.count } else { o.append(s[i]); i += 1 }
        }
        return o
    }
    static func split(_ s: U, _ sep: UInt16) -> [U] {
        var out: [U] = [], cur: U = []
        for c in s { if c == sep { out.append(cur); cur = [] } else { cur.append(c) } }
        out.append(cur)
        return out
    }
    /// Number(x) as a whole id; anything else becomes 0 (no item has id 0).
    static func toInt(_ v: Any?) -> Int { let d = JS.number(unwrap(v)); return d.isFinite && abs(d) < 1e15 ? Int(d) : 0 }
    static func jsNumber(_ w: U) -> Double { Double(str(w)) ?? .nan }

    /// One space between words, none inside brackets' edges.
    static func squeeze(_ s: U) -> U {
        var o: U = [], sp = false
        for raw in s {
            let c: UInt16 = raw == 95 ? SP : raw
            if isWs(c) { sp = !o.isEmpty; continue }
            if sp && c != RPAR && c != COMMA && o.last != LPAR { o.append(SP) }
            sp = false
            o.append(c)
        }
        return o
    }

    static func titleWord(_ w: U, _ mixed: Bool) -> U {
        if let br = w.firstIndex(of: LPAR), br > 0 { return titleWord(Array(w[0..<br]), mixed) + Array(w[br...]) }
        var letters = 0, vowels = 0, digit = false, caps = 0
        let vow = u("aeiouyAEIOUY")
        for c in w {
            if isDigit(c) { digit = true }
            if isLetterA(c) { letters += 1; if isUpperA(c) { caps += 1 }; if vow.contains(c) { vowels += 1 } }
        }
        if digit || letters == 0 { return w }
        if mixed && caps == letters && letters <= 4 { return w }
        if letters <= 3 && vowels == 0 { return upperA(w) }
        var o: U = [], first = true
        for c in w {
            if isLetterA(c) { o.append(first ? (isLowerA(c) ? c - 32 : c) : (isUpperA(c) ? c + 32 : c)); first = false } else { o.append(c) }
        }
        return o
    }

    static func modeOf(_ v: Any?, _ dflt: String) -> String {
        let m = JS.string(unwrap(v) ?? "")
        return ["keep", "title", "upper"].contains(m) && unwrap(v) != nil ? m : dflt
    }

    /// Tidy an item name. mode keep: spacing and pack sizes; title: Title Case words too; upper: CAPITALS throughout.
    static func cleanName(_ name: String, _ mode: String = "keep") -> String { str(cleanName(u(name), mode)) }
    static func cleanName(_ name: U, _ mode: String) -> U {
        let s = squeeze(name)
        var up = 0, low = 0
        for c in s { if isUpperA(c) { up += 1 } else if isLowerA(c) { low += 1 } }
        let upperUnits = mode == "upper" || (mode == "keep" && up > 0 && low == 0)
        let words = s.isEmpty ? [] : split(s, SP)
        var out: [U] = []
        var i = 0
        while i < words.count {
            var w = words[i]
            if isNumber(w) && i + 1 < words.count {
                let nx = trimEnd(words[i + 1], ".,")
                if let un = unitOf(nx, upperUnits) {
                    let tail = Array(words[i + 1][nx.count...])
                    out.append(w + un + tail); i += 2; continue
                }
            }
            var k = 0, dots = 0
            while k < w.count && (isDigit(w[k]) || (w[k] == DOT && dots == 0 && k > 0)) { if w[k] == DOT { dots += 1 }; k += 1 }
            if k > 0 && k < w.count && w[k - 1] != DOT {
                let rest = Array(w[k...]), core = trimEnd(rest, ".,)")
                if !core.isEmpty, let un = unitOf(core, upperUnits) { w = Array(w[0..<k]) + un + Array(rest[core.count...]) }
            }
            if mode == "title" { w = titleWord(w, up > 0 && low > 0) } else if mode == "upper" { w = upperA(w) }
            out.append(w)
            i += 1
        }
        var joined: U = []
        for (n, w) in out.enumerated() { if n > 0 { joined.append(SP) }; joined += w }
        return trimEnd(joined, " ,")
    }

    /// What makes two names the same item: tidied, lower case, letters and digits only.
    static func itemKey(_ name: String) -> String { str(itemKey(u(name))) }
    static func itemKey(_ name: U) -> U { lowerA(cleanName(name, "keep")).filter { isLowerA($0) || isDigit($0) || $0 > 127 } }

    // MARK: tidy names and duplicates

    static let GENERIC = ["biscuit", "biscuits", "namkeen", "snacks", "snack", "chips", "noodles", "pouch", "sachet", "bottle", "jar", "box", "refill", "packet"]
    static let NOISE = ["mrp", "rs", "pkt", "pkts", "pcs", "pc", "pack", "packet", "x", "new", "the", "and", "of", "n", "no", "nos"]
    static let GENERIC_SK: [String] = GENERIC.map { str(skeleton(u($0))) }

    /// A word reduced to its consonants (h and y count as vowels, doubles collapse): Bhujia, Bhujiya and Bujia all give "bj".
    static func skeleton(_ w: U) -> U {
        var o: U = [w[0]]
        let skip = u("aeiouyh")
        for c in w.dropFirst() where !skip.contains(c) { if o.last != c { o.append(c) } }
        return o
    }

    struct Sig { var sizes: String; var words: [String]; var mrp: Double; var box: Int }

    static func signature(_ it: Row) -> Sig {
        let tidy = lowerA(cleanName(u(it.str("name")), "keep"))
        var sizes: [String] = [], words: [String] = []
        var w: U = []
        func flush() {
            if w.isEmpty { return }
            var k = 0
            while k < w.count && (isDigit(w[k]) || w[k] == DOT) { k += 1 }
            if k > 0 && k < w.count && UNITS[str(Array(w[k...]))] != nil {
                let t = str(w); if !sizes.contains(t) { sizes.append(t) }
            } else if k < w.count && !isDigit(w[w.count - 1]) && w.count >= 2 && !NOISE.contains(str(w)) {
                let sk = str(skeleton(w)); if !words.contains(sk) { words.append(sk) }
            }
            w = []
        }
        for c in tidy {
            if isLowerA(c) || isDigit(c) || (c == DOT && !w.isEmpty && isDigit(w[w.count - 1])) { w.append(c) } else { flush() }
        }
        flush()
        sizes.sort { $0.utf16.lexicographicallyPrecedes($1.utf16) }
        let m = JS.number(it["mrp"] ?? nil), bx = JS.number(it["pcs_per_box"] ?? nil)
        return Sig(sizes: sizes.joined(separator: ","), words: words, mrp: m.isFinite ? m : 0, box: bx.isFinite && bx >= 1 ? Int(bx) : 1)
    }

    /// 0..1 when the two may be the same item, -1 when they cannot be (different pack size, MRP or box).
    static func likeness(_ a: Sig, _ b: Sig, _ match: String) -> Double {
        if a.sizes != b.sizes { return -1 }
        if a.mrp > 0 && b.mrp > 0 && abs(a.mrp - b.mrp) >= 0.005 { return -1 }
        if a.box != b.box && a.box > 1 && b.box > 1 { return -1 }
        if a.words.isEmpty || b.words.isEmpty { return -1 }
        let common = a.words.filter { b.words.contains($0) }.count
        if common == 0 { return -1 }
        let jac = Double(common) / Double(a.words.count + b.words.count - common)
        let ca = a.words.filter { !GENERIC_SK.contains($0) }, cb = b.words.filter { !GENERIC_SK.contains($0) }
        let sameWords = !ca.isEmpty && ca.count == cb.count && ca.allSatisfy { cb.contains($0) }
        let ok = sameWords || (match == "loose" && a.words[0] == b.words[0] && jac >= 0.5)
        return ok ? JS.round(jac * 100) / 100 : -1
    }

    static func cleanPreview(_ db: Database, _ q: [String: String]) throws -> Row {
        let mode = ["keep", "title", "upper"].contains(q["case"] ?? "") ? q["case"]! : "keep"
        let match = ["exact", "similar", "loose"].contains(q["match"] ?? "") ? q["match"]! : "similar"
        let items = try db.prepare("""
            SELECT i.id, i.name, i.gst_rate, i.mrp, i.pcs_per_box,
              (SELECT COUNT(*) FROM invoice_lines WHERE item_id=i.id) + (SELECT COUNT(*) FROM purchase_lines WHERE item_id=i.id) + (SELECT COUNT(*) FROM debit_note_lines WHERE item_id=i.id) used,
              (SELECT COALESCE(SUM(qty),0) FROM batches WHERE item_id=i.id) stock
            FROM items i WHERE i.active=1 ORDER BY i.name, i.id
            """).all()
        var renames: [Row] = []
        var parent = Array(0..<items.count)
        func find(_ x: Int) -> Int { var i = x; while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }; return i }
        let keys = items.map { itemKey($0.str("name")) }
        let sigs = items.map(signature)
        var group = items.indices.map { [$0] }
        // two items can only end up together when their MRPs and boxes agree (checked against every member, so no chains)
        func fits(_ x: Int, _ y: Int) -> Bool {
            !(sigs[x].mrp > 0 && sigs[y].mrp > 0 && abs(sigs[x].mrp - sigs[y].mrp) >= 0.005) && !(sigs[x].box != sigs[y].box && sigs[x].box > 1 && sigs[y].box > 1)
        }
        @discardableResult func join(_ i: Int, _ j: Int) -> Bool {
            let a = find(i), b = find(j)
            if a == b { return false }
            if !group[a].allSatisfy({ x in group[b].allSatisfy { y in fits(x, y) } }) { return false }
            let lo = min(a, b), hi = max(a, b)
            parent[hi] = lo
            group[lo] = group[lo] + group[hi]
            return true
        }
        var best = items.map { _ in 1.0 }
        var firstByKey: [String: Int] = [:]
        for (i, it) in items.enumerated() {
            let c = cleanName(it.str("name"), mode)
            if !c.isEmpty && c != it.str("name") { renames.append(["id": it.i("id"), "name": it.str("name"), "clean": c]) }
            if keys[i].isEmpty { continue }
            if let f = firstByKey[keys[i]] { join(f, i) } else { firstByKey[keys[i]] = i }
        }
        if match != "exact" {
            var bySize: [String: [Int]] = [:], sizeOrder: [String] = []
            for i in items.indices {
                if bySize[sigs[i].sizes] == nil { sizeOrder.append(sigs[i].sizes); bySize[sigs[i].sizes] = [] }
                bySize[sigs[i].sizes]!.append(i)
            }
            for list in sizeOrder.map({ bySize[$0]! }) {
                for x in 0..<list.count {
                    for y in (x + 1)..<max(x + 1, list.count) {
                        let i = list[x], j = list[y]
                        if !keys[i].isEmpty && keys[i] == keys[j] { continue }
                        let l = likeness(sigs[i], sigs[j], match)
                        if l < 0 { continue }
                        if find(i) != find(j) && !join(i, j) { continue }
                        if l < best[i] { best[i] = l }
                        if l < best[j] { best[j] = l }
                    }
                }
            }
        }
        var order: [Int] = [], members: [Int: [Int]] = [:]
        for i in items.indices { let r = find(i); if members[r] == nil { order.append(r); members[r] = [] }; members[r]!.append(i) }
        var groups: [Row] = []
        for r in order {
            let list0 = members[r]!
            if list0.count < 2 { continue }
            let list = list0.map { items[$0] }
            let ranked = list.sorted { a, b in
                if a.n("used") != b.n("used") { return a.n("used") > b.n("used") }
                if a.n("stock") != b.n("stock") { return a.n("stock") > b.n("stock") }
                return a.i("id") < b.i("id")
            }
            let keep = ranked[0]
            let same = list0.allSatisfy { keys[$0] == keys[list0[0]] }
            let brief = { (x: Row) -> Row in ["id": x.i("id"), "name": x.str("name"), "used": x["used"]!, "stock": x["stock"]!, "mrp": x["mrp"]!, "pcs_per_box": x["pcs_per_box"]!] }
            var warnings: [String] = []
            if list.contains(where: { $0.n("gst_rate") != keep.n("gst_rate") }) { warnings.append("Different GST rates") }
            let boxN = { (x: Row) -> Double in let v = x.n("pcs_per_box"); return max(1, v.isFinite && v != 0 ? v : 1) }
            if list.contains(where: { boxN($0) != boxN(keep) }) { warnings.append("Different pieces per box") }
            groups.append(["key": keys[list0[0]].isEmpty ? String(keep.i("id")) : keys[list0[0]], "match": same ? "same" : "similar",
                           "score": same ? 1.0 : list0.map { best[$0] }.min()!,
                           "keep": brief(keep), "merge": ranked.dropFirst().map(brief), "warnings": warnings])
        }
        groups.sort { a, b in
            let x = (a["keep"] as! Row).str("name"), y = (b["keep"] as! Row).str("name")
            if x != y { return x.utf16.lexicographicallyPrecedes(y.utf16) }
            return (a["keep"] as! Row).i("id") < (b["keep"] as! Row).i("id")
        }
        return ["mode": mode, "match": match, "items": items.count, "renames": renames, "groups": groups]
    }

    static func applyClean(_ db: Database, _ b: Row) throws -> Row {
        try db.transaction {
            let mode = modeOf(b["case"] ?? nil, "keep")
            let only: [Int]? = (b["ids"] as? [Any]).map { $0.map(toInt) }
            let items = try db.prepare("SELECT id,name FROM items WHERE active=1 ORDER BY id").all()
            let taken = db.prepare("SELECT id FROM items WHERE active=1 AND lower(name)=lower(?) AND id <> ?")
            let upd = db.prepare("UPDATE items SET name=?, pcs_per_box=? WHERE id=?")
            let cur = db.prepare("SELECT pcs_per_box FROM items WHERE id=?")
            var renamed = 0
            var skipped: [Row] = []
            for it in items {
                if let only, !only.contains(it.i("id")) { continue }
                let c = cleanName(it.str("name"), mode)
                if c.isEmpty || c == it.str("name") { continue }
                if try taken.get(c, it.i("id")) != nil {
                    skipped.append(["id": it.i("id"), "name": it.str("name"), "clean": c, "reason": "Another item already has this name: merge them instead"]); continue
                }
                let had: Any? = try cur.get(it.i("id"))?["pcs_per_box"] ?? nil
                let pk: Any = PDFParser.packFromName(c).map { $0 as Any } ?? had ?? NSNull()
                try upd.run(c, pk, it.i("id"))
                renamed += 1
            }
            return ["renamed": renamed, "skipped": skipped]
        }
    }

    static func mergeItems(_ db: Database, _ b: Row) throws -> Row {
        try db.transaction {
            let keepId = toInt(b["keep_id"] ?? nil)
            let ids = ((b["merge_ids"] as? [Any]) ?? []).map(toInt).filter { $0 != keepId }
            guard keepId != 0, var keep = try db.prepare("SELECT * FROM items WHERE id=? AND active=1").get(keepId) else { throw HttpError(404, "Choose the item to keep") }
            if ids.isEmpty { throw HttpError(400, "Choose the items to merge into it") }
            var moved: [String: Int] = ["invoice_lines": 0, "purchase_lines": 0, "debit_note_lines": 0, "batches": 0, "schemes": 0]
            var names: [String] = []
            for id in ids {
                guard let m = try db.prepare("SELECT * FROM items WHERE id=? AND active=1").get(id) else { throw HttpError(404, "Item \(id) not found") }
                for bt in try db.prepare("SELECT * FROM batches WHERE item_id=? ORDER BY id").all(id) {
                    if let same = try db.prepare("SELECT id FROM batches WHERE item_id=? AND batch_no=?").get(keepId, bt.v("batch_no")) {
                        try db.prepare("UPDATE batches SET qty=qty+? WHERE id=?").run(bt.v("qty"), same.i("id"))
                        for t in ["invoice_lines", "purchase_lines", "debit_note_lines", "debit_note_stock"] {
                            try db.prepare("UPDATE \(t) SET batch_id=? WHERE batch_id=?").run(same.i("id"), bt.i("id"))
                        }
                        try db.prepare("DELETE FROM batches WHERE id=?").run(bt.i("id"))
                    } else {
                        try db.prepare("UPDATE batches SET item_id=? WHERE id=?").run(keepId, bt.i("id"))
                    }
                    moved["batches"]! += 1
                }
                for t in ["invoice_lines", "purchase_lines", "debit_note_lines", "schemes"] {
                    moved[t]! += try db.prepare("UPDATE \(t) SET item_id=? WHERE item_id=?").run(keepId, id).changes
                }
                for k in ["mrp", "retail_price", "wholesale_price", "purchase_price"] {
                    if !(keep.n(k) > 0) && m.n(k) > 0 { keep[k] = m[k]; try db.prepare("UPDATE items SET \(k)=? WHERE id=?").run(m.v(k), keepId) }
                }
                for k in ["hsn", "category_id"] {
                    if JS.blank(keep[k] ?? nil) == nil && JS.blank(m[k] ?? nil) != nil { keep[k] = m[k]; try db.prepare("UPDATE items SET \(k)=? WHERE id=?").run(m.v(k), keepId) }
                }
                try db.prepare("UPDATE items SET active=0 WHERE id=?").run(id)
                names.append(m.str("name"))
            }
            let mv: Row = ["invoice_lines": moved["invoice_lines"]!, "purchase_lines": moved["purchase_lines"]!, "debit_note_lines": moved["debit_note_lines"]!,
                           "batches": moved["batches"]!, "schemes": moved["schemes"]!]
            return ["kept": keepId, "name": keep.str("name"), "merged": names, "moved": mv]
        }
    }

    // MARK: item lists from the internet

    static let BLOCK = ["br", "p", "div", "tr", "li", "h1", "h2", "h3", "h4", "h5", "h6", "table", "tbody", "thead", "ul", "ol", "section", "article", "header", "footer", "dd", "dt", "option", "hr"]
    static let ENT: [String: String] = ["amp": "&", "nbsp": " ", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "rsquo": "'", "lsquo": "'", "ndash": "-", "mdash": "-", "times": "x", "rupee": "₹", "copy": "©"]

    /// A web page as lines of text: table cells joined by " | ", scripts and styles dropped.
    static func htmlLines(_ html: String) -> [U] {
        let s = u(html)
        let low = lowerA(s)
        var o: U = []
        var i = 0
        let GT: UInt16 = 62, LT: UInt16 = 60, SLASH: UInt16 = 47, AMP: UInt16 = 38, SEMI: UInt16 = 59
        while i < s.count {
            let c = s[i]
            if c == LT {
                if startsWith(low, u("<!--"), i) { let e = indexOf(low, u("-->"), i + 4); i = e < 0 ? s.count : e + 3; continue }
                var j = i + 1
                if j < s.count && s[j] == SLASH { j += 1 }
                var name: U = []
                while j < s.count && (isLetterA(s[j]) || isDigit(s[j])) { name.append(low[j]); j += 1 }
                let end = indexOf(s, [GT], j)
                if name.isEmpty || end < 0 { o.append(c); i += 1; continue }
                let nm = str(name)
                if ["script", "style", "noscript", "svg"].contains(nm) && !(i + 1 < s.count && s[i + 1] == SLASH) {
                    let close = indexOf(low, u("</" + nm), end)
                    if close < 0 { i = s.count } else { let g = indexOf(low, [GT], close); i = g < 0 ? s.count : g + 1 }
                    continue
                }
                if nm == "td" || nm == "th" { o += u(" | ") } else if BLOCK.contains(nm) { o.append(10) } else { o.append(SP) }
                i = end + 1
                continue
            }
            if c == AMP {
                let semi = indexOf(s, [SEMI], i)
                if semi > i && semi - i <= 8 {
                    let ent = Array(s[(i + 1)..<semi])
                    var rep: U? = nil
                    if ent.first == 35 {   // #
                        let hex = ent.count > 1 && (ent[1] == 120 || ent[1] == 88)
                        let digits = Array(ent[(hex ? 2 : 1)...])
                        var n = digits.isEmpty ? -1 : 0
                        var q = 0
                        while q < digits.count && n >= 0 {
                            let d = isUpperA(digits[q]) ? digits[q] + 32 : digits[q]
                            let v = isDigit(d) ? Int(d) - 48 : (hex && d >= 97 && d <= 102 ? Int(d) - 87 : -1)
                            n = v < 0 ? -1 : n * (hex ? 16 : 10) + v
                            q += 1
                        }
                        if n > 0 && n < 0xD800 { rep = n == 160 ? [SP] : [UInt16(n)] }
                    } else if let e = ENT[str(lowerA(ent))] { rep = u(e) }
                    if let rep { o += rep; i = semi + 1; continue }
                }
            }
            o.append(c)
            i += 1
        }
        var lines: [U] = []
        for raw in split(o, 10) {
            let cells = split(raw, 124).map(squeeze).filter { !$0.isEmpty }
            var line: U = []
            for (n, x) in cells.enumerated() { if n > 0 { line += u(" | ") }; line += x }
            if !line.isEmpty { lines.append(line) }
        }
        return lines
    }

    static let SKIP = ["http", "www.", "copyright", "©", "all rights", "privacy", "cookie", "login", "sign in", "cart", "subscribe", "whatsapp", "call us", "email"]
    static let PRICE_WORDS = ["mrp", "rs", "rs.", "inr", "price", "₹", "@"]

    static func priceCell(_ cell: U) -> Double? {
        var t = lowerA(cell)
        for w in ["mrp", "rs.", "rs", "inr", "₹", "/-", ":", " "] { t = replaceAll(t, u(w), []) }
        t = replaceAll(t, [COMMA], [])
        return isNumber(t) ? jsNumber(t) : nil
    }

    static func nameAndMrp(_ text: U) -> (name: U, mrp: Double?) {
        let low = lowerA(text)
        var best = -1
        for wS in PRICE_WORDS {
            let w = u(wS)
            var from = 0
            while true {
                let at = indexOf(low, w, from)
                if at < 0 { break }
                from = at + 1
                let before = at == 0 ? SP : low[at - 1]
                if isLetterA(before) || isDigit(before) { continue }
                var k = at + w.count
                if wS != "₹" && wS != "@" && k < low.count && isLetterA(low[k]) { continue }
                while k < low.count && (low[k] == SP || low[k] == DOT || low[k] == 58 || low[k] == 45 || low[k] == 61 || low[k] == 0x20B9) { k += 1 }
                if k < low.count && isDigit(low[k]) && (best < 0 || at < best) { best = at }
            }
        }
        if best < 0 { return (text, nil) }
        var k = best
        while k < text.count && !isDigit(text[k]) { k += 1 }
        var num: U = []
        while k < text.count && (isDigit(text[k]) || text[k] == COMMA || (text[k] == DOT && k + 1 < text.count && isDigit(text[k + 1]))) {
            if text[k] != COMMA { num.append(text[k]) }
            k += 1
        }
        return (trimEnd(Array(text[0..<best]), " -,:|(/"), isNumber(num) ? jsNumber(num) : nil)
    }

    static func hasUnit(_ name: U) -> Bool {
        for x in split(cleanName(name, "keep"), SP) {
            var k = 0
            while k < x.count && (isDigit(x[k]) || x[k] == DOT) { k += 1 }
            if k > 0 && k < x.count && UNITS[str(lowerA(trimEnd(Array(x[k...]), ".,)")))] != nil { return true }
        }
        return false
    }

    static func extractList(_ db: Database, _ b: Row) throws -> Row {
        let mode = modeOf(b["case"] ?? nil, "title")
        let company = squeeze(u(JS.truthy(b["company"]) ? JS.string(b.v("company")) : ""))
        var lines: [U]
        if JS.truthy(b["html"]) { lines = htmlLines(JS.string(b.v("html"))) } else {
            var t = u(JS.truthy(b["text"]) ? JS.string(b.v("text")) : "")
            t = replaceAll(replaceAll(t, [13, 10], [10]), [13], [10])
            lines = split(t, 10).map(squeeze).filter { !$0.isEmpty }
        }
        var existing: [String: Row] = [:]
        for it in try db.prepare("SELECT id,name FROM items WHERE active=1 ORDER BY id").all() {
            let k = itemKey(it.str("name"))
            if !k.isEmpty && existing[k] == nil { existing[k] = it }
        }
        var out: [Row] = []
        var seenIndex: [String: Int] = [:]
        var merged = 0
        var mrpCol = -1, headerCells = 0   // a table heading with an "MRP" column says which cell is the MRP
        for line in lines {
            let ll = lowerA(line)
            if SKIP.contains(where: { includes(ll, u($0)) }) { continue }
            let cells = split(line, 124).map(squeeze).filter { !$0.isEmpty }
            if cells.count < 2 { mrpCol = -1; headerCells = 0 } else {
                var h = -1
                for (i, c) in cells.enumerated() where !c.contains(where: isDigit) && includes(lowerA(c), u("mrp")) { h = i; break }
                if h >= 0 { mrpCol = h; headerCells = cells.count; continue }
            }
            var nameCell = -1
            for (i, c) in cells.enumerated() {
                if c.filter(isLetterA).count >= 3 && priceCell(c) == nil { nameCell = i; break }
            }
            if nameCell < 0 { continue }
            var (name, mrp) = nameAndMrp(cells[nameCell])
            if mrp == nil && mrpCol >= 0 && mrpCol != nameCell && cells.count == headerCells {
                if let p = priceCell(cells[mrpCol]), p > 0 { mrp = p }
            }
            // the pack size in a cell of its own: "Bhujia | 200 gm"
            if !hasUnit(name) {
                for i in (nameCell + 1)..<max(nameCell + 1, cells.count) {
                    if i == mrpCol && cells.count == headerCells { continue }
                    if cells[i].count <= 12 && priceCell(cells[i]) == nil && hasUnit(cells[i]) { name = name + [SP] + cells[i]; break }
                }
            }
            if mrp == nil {
                for (i, c) in cells.enumerated() where i != nameCell {
                    if let p = priceCell(c), p > 0, mrp == nil || p > mrp! { mrp = p }
                }
            }
            var k = 0
            while k < name.count && isDigit(name[k]) { k += 1 }
            if k > 0 && k < name.count && (name[k] == DOT || name[k] == RPAR || name[k] == SP) && !hasUnit(Array(name[0..<min(k + 3, name.count)])) {
                name = squeeze(Array(name[(k + 1)...]))
            }
            if name.count < 3 || name.count > 90 { continue }
            if !((mrp ?? 0) > 0) && !hasUnit(name) { continue }
            if !company.isEmpty && !includes(lowerA(name), lowerA(company)) { name = company + [SP] + name }
            let clean = cleanName(name, mode)
            let key = str(itemKey(clean))
            if key.isEmpty { continue }
            if let at = seenIndex[key] {
                if !(JS.number(out[at]["mrp"] ?? nil) > 0) && (mrp ?? 0) > 0 { out[at]["mrp"] = mrp! }
                merged += 1
                continue
            }
            let ex = existing[key]
            let cleanS = str(clean)
            let pk = PDFParser.packFromName(cleanS)
            let row: Row = ["name": cleanS, "mrp": (mrp ?? 0) > 0 ? mrp! as Any : NSNull(), "pack": pk.map { $0 as Any } ?? NSNull(),
                            "exists_id": ex.map { $0.i("id") as Any } ?? NSNull(), "exists_name": ex.map { $0.str("name") as Any } ?? NSNull()]
            seenIndex[key] = out.count
            out.append(row)
            if out.count >= 400 { break }
        }
        return ["lines": lines.count, "items": out, "found": out.count, "duplicates_merged": merged,
                "new": out.filter { !JS.truthy($0["exists_id"] ?? nil) }.count]
    }

    static func bulkAdd(_ db: Database, _ b: Row) throws -> Row {
        try db.transaction {
            let list = (b["items"] as? [Any]) ?? []
            if list.isEmpty { throw HttpError(400, "Choose the items to add") }
            let catId: Int? = JS.blank(b["category"] ?? nil) == nil ? nil : try Category.ensure(db, str(squeeze(u(JS.string(b.v("category"))))))
            let gv = unwrap(b["gst_rate"] ?? nil)
            let gst = gv == nil || (gv as? String) == "" ? 18 : JS.number(gv)
            if !gst.isFinite || gst < 0 || gst > 40 { throw HttpError(400, "GST rate must be between 0 and 40") }
            var added: [Row] = [], skipped: [Row] = []
            let dup = db.prepare("SELECT id FROM items WHERE active=1 AND lower(name)=lower(?)")
            let ins = db.prepare("INSERT INTO items(name,category_id,hsn,gst_rate,unit,mrp,pcs_per_box) VALUES(?,?,?,?,?,?,?)")
            for any in list {
                let it = (any as? Row) ?? [:]
                let name = str(squeeze(u(JS.truthy(it["name"]) ? JS.string(it.v("name")) : "")))
                if name.isEmpty { skipped.append(["name": name, "reason": "No name"]); continue }
                if name.utf16.count > 120 { skipped.append(["name": name, "reason": "Name is too long"]); continue }
                if try dup.get(name) != nil { skipped.append(["name": name, "reason": "Already in your items"]); continue }
                let mrp = JS.truthy(it["mrp"]) ? JS.number(it.v("mrp")) : 0
                let r = try ins.run(name, catId, nil, gst, "PCS", mrp.isFinite && mrp > 0 ? mrp : 0, PDFParser.packFromName(name) ?? 1)
                added.append(["id": r.lastInsertRowid, "name": name])
            }
            return ["added": added, "skipped": skipped, "category_id": catId.map { $0 as Any } ?? NSNull()]
        }
    }
}
