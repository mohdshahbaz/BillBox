import Foundation

// backend/src/services/margImport.js — import from a Marg ERP CSV backup (folder or .zip): items, customers and suppliers
// with opening balances, sale bills, purchase bills, debit notes, receipts and payments, checked against Marg's own totals,
// closing balances and closing stock. Importing twice adds nothing twice.

public enum MargImport {
    /// How many pieces Marg's Rate A is for (margImport.js rateUnit): its own pack, the case or one piece, item by item; the
    /// pack that puts the per-piece sale rate just above the last purchase rate (per piece) wins, else Marg's own pack.
    /// Marg's last purchase rate is per piece for most items and per box for some (margImport.js purchaseRate).
    static func purchaseRate(_ lp: Double, _ sale: Double, _ packs: [Int]) -> Double {
        if !(lp > 0) || !(sale > 0) || lp <= sale * 3 { return r8(lp) }
        let off = { (d: Int) -> Double in abs(log(lp / Double(d) / (sale * 0.87))) }
        var best: Int? = nil
        for d in packs where d > 1 && (best == nil || off(d) < off(best!) - 1e-9) { best = d }
        if let b = best, off(b) <= log(2) { return r8(lp / Double(b)) }
        return r8(lp)
    }

    /// A name with the piece's MRP whose rate is above it: the rate is for a box (margImport.js byNameMrp).
    static func byNameMrp(_ it: Item, _ packs: [Int]) {
        guard let nm = PDFParser.mrpFromName(it.name), nm > 0 else { return }
        let incl = it.retail * (1 + it.gst / 100)
        if !(incl > nm * 1.02) { return }
        var seen: [Int] = []
        for d in packs where d > 1 && !seen.contains(d) {
            seen.append(d)
            let v = incl / Double(d)
            if v >= nm * 0.5 && v <= nm * 1.02 {
                it.retail = r8(it.retail / Double(d))
                if it.purchase > nm { it.purchase = r8(it.purchase / Double(d)) }
                return
            }
        }
    }

    static func rateUnit(_ rate: Double, _ packs: [Int], _ lp: Double, _ inner: [Int]) -> Int {
        let marg = max(1, packs.first ?? 1)
        if !(lp > 0) || !(rate > 0) { return marg }
        var cands: [Int] = [1]
        for p in packs where p > 0 && !cands.contains(p) { cands.append(p) }
        for q in inner where q > 1 && !cands.contains(marg * q) { cands.append(marg * q) }
        let off = { (d: Int) -> Double in abs(log(rate / Double(d) / (lp * 1.15))) }
        var best = marg
        for d in cands where off(d) < off(best) - 1e-9 { best = d }
        return off(best) <= log(3) ? best : marg
    }

    static let GSTIN_RE = rx("^\\d{2}[A-Z]{5}\\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$")
    static let PAN_RE = rx("^[A-Z]{5}\\d{4}[A-Z]$")
    static let NO_EXPIRY = "2099-12-31"

    static func r8(_ n: Double) -> Double { JS.round((n + JS.EPSILON) * 1e8) / 1e8 }
    static func num(_ s: String?) -> Double { let n = JS.number(JS.trim(s ?? "")); return n.isFinite ? n : 0 }
    static func int(_ s: String?) -> Int { Int(JS.round(num(s))) }
    /// JavaScript's `\\s` (and what `trim` removes).
    static func isJSSpace(_ v: UInt32) -> Bool {
        v == 0x20 || (v >= 0x09 && v <= 0x0d) || v == 0xa0 || v == 0x1680 || (v >= 0x2000 && v <= 0x200a) ||
            v == 0x2028 || v == 0x2029 || v == 0x202f || v == 0x205f || v == 0x3000 || v == 0xfeff
    }
    /// `s.replace(/[\\u0000-\\u001f\\u007f]/g, ' ').replace(/\\s+/g, ' ').trim()`, without regular expressions (it runs on every field).
    static func clean(_ s: String?) -> String {
        guard let s, !s.isEmpty else { return "" }
        var out = String.UnicodeScalarView()
        var pendingSpace = false
        for u in s.unicodeScalars {
            let v = u.value
            if v < 0x20 || v == 0x7f || isJSSpace(v) { pendingSpace = true; continue }
            if pendingSpace && !out.isEmpty { out.append(" ") }
            pendingSpace = false
            out.append(u)
        }
        return String(out)
    }
    static func key(_ s: String?) -> String { clean(s).lowercased() }
    static func day(_ s: String?) -> String? {
        guard let m = rx("^(\\d{1,2})-(\\d{1,2})-(\\d{4})").exec(JS.trim(s ?? "")) else { return nil }
        return "\(m[3]!)-\(m[2]!.padStart(2, "0"))-\(m[1]!.padStart(2, "0"))"
    }

    // MARK: reading the backup

    /// { "pro.csv": text, ... } from a folder (searched a few levels down) or a .zip. Marg writes Latin-1 text.
    static func readSource(_ p: Any?) throws -> [String: String] {
        guard let path = unwrap(p) as? String, path.hasPrefix("/"), FileManager.default.fileExists(atPath: path) else {
            throw HttpError(400, "Choose the Marg backup folder or .zip file.")
        }
        var files: [String: String] = [:]
        func take(_ name: String, _ data: Data) {
            let b = (name as NSString).lastPathComponent.lowercased()
            if b.hasSuffix(".csv") && files[b] == nil { files[b] = latin1(data) }
        }
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        if isDir.boolValue {
            func walk(_ d: String, _ depth: Int) {
                let names = ((try? FileManager.default.contentsOfDirectory(atPath: d)) ?? []).sorted { Array($0.utf16).lexicographicallyPrecedes(Array($1.utf16)) }
                for n in names {
                    let f = (d as NSString).appendingPathComponent(n)
                    var sub: ObjCBool = false
                    FileManager.default.fileExists(atPath: f, isDirectory: &sub)
                    if sub.boolValue { if depth < 3 && n != "__MACOSX" { walk(f, depth + 1) } }
                    else if let data = FileManager.default.contents(atPath: f) { take(n, data) }
                }
            }
            walk(path, 0)
        } else {
            guard let data = FileManager.default.contents(atPath: path) else { throw HttpError(400, "Choose the Marg backup folder or .zip file.") }
            let entries: [(name: String, data: Data)]
            do { entries = try Unzip.entries(data) } catch { throw HttpError(400, "\(error)") }
            for e in entries.sorted(by: { Array($0.name.utf16).lexicographicallyPrecedes(Array($1.name.utf16)) }) { take(e.name, e.data) }
        }
        for need in ["pro.csv", "order.csv", "mdis.csv", "dis.csv"] where files[need] == nil {
            throw HttpError(400, "This is not a Marg CSV backup: \(need) is missing.")
        }
        return files
    }

    /// Latin-1 bytes to text, one character per byte (as Node's 'latin1').
    static func latin1(_ data: Data) -> String {
        var v = String.UnicodeScalarView()
        v.append(contentsOf: data.map { Unicode.Scalar($0) })
        return String(v)
    }

    /// RFC 4180 CSV. First row = column names.
    static func parseCsv(_ text: String) -> [[String: String]] {
        var rows: [[String]] = []
        var row: [String] = [], f = "", q = false
        let chars = Array(text.unicodeScalars)
        var i = 0
        func endRow() { row.append(f); f = ""; if row.count > 1 || row[0] != "" { rows.append(row) }; row = [] }
        while i < chars.count {
            let c = chars[i]
            if q {
                if c == "\"" { if i + 1 < chars.count && chars[i + 1] == "\"" { f.unicodeScalars.append("\""); i += 1 } else { q = false } } else { f.unicodeScalars.append(c) }
            } else if c == "\"" && f.isEmpty { q = true }
            else if c == "," { row.append(f); f = "" }
            else if c == "\n" || c == "\r" {
                if c == "\r" && i + 1 < chars.count && chars[i + 1] == "\n" { i += 1 }
                endRow()
            } else { f.unicodeScalars.append(c) }
            i += 1
        }
        if !f.isEmpty || !row.isEmpty { endRow() }
        guard let head = rows.first?.map({ JS.trim($0).uppercased() }) else { return [] }
        return rows.dropFirst().map { r in
            var o: [String: String] = [:]
            for (k, h) in head.enumerated() where o[h] == nil { o[h] = k < r.count ? r[k] : "" }
            return o
        }
    }

    // MARK: the books built from the CSV tables

    final class Item { var code = "", name = "", pcsPerBox = 1, gst = 0.0, hsn: String?, mrp = 0.0, category: String?, purchase = 0.0, retail = 0.0
        var opening = 0, closing = 0, moved = 0, id = 0, batch = 0, isNew = false, rateFromList = false }
    final class Party { var code = "", kind = "", name = "", gstin: String?, state: String?, pan: String?, address: String?, phone: String?, mobiles: String?, tel: String?
        var opening = 0.0, closing = 0.0, moved = 0.0, id = 0 }
    struct Line { let item: Item; let qty: Int; let free: Int; let taxable: Double; let discAmt: Double; let discPct: Double; let gross: Double; let rate: Double
        let gst: Double; let cgst: Double; let sgst: Double; let igst: Double; let amount: Double; let stock: Bool; let challan: String }
    struct Doc { let kind: String; let no: String; let date: String; let party: Party; let rows: [Line]; let ref: String?
        let subtotal, discount, taxable, cgst, sgst, igst, roundOff, total: Double }
    struct Money { let kind: String; let no: String; let date: String; let party: Party; let amount: Double; let mode: String; let ref: String? }
    struct Model { var items: [Item]; var parties: [Party]; var docs: [Doc]; var money: [Money]; var summary: Row }

    /// `s.split(re)` (no capture groups): the pieces between matches, empty ones included.
    static func jsSplit(_ s: String, _ re: JSRegex) -> [String] {
        let ns = s as NSString
        var out: [String] = [], at = 0
        for m in re.matchAll(s) where m.length > 0 {
            out.append(ns.substring(with: NSRange(location: at, length: m.index - at)))
            at = m.index + m.length
        }
        out.append(ns.substring(from: at))
        return out
    }

    static func mobileOf(_ d: String) -> String? {
        let x = rx("^(91|0)(?=\\d{10}$)").replace(d, "")
        return rx("^[6-9]\\d{9}$").test(x) ? x : nil
    }

    static func model(_ files: [String: String]) -> Model {
        func T(_ n: String) -> [[String: String]] { files[n].map(parseCsv) ?? [] }
        let pro = T("pro.csv"), order = T("order.csv"), mdis = T("mdis.csv"), dis = T("dis.csv"), gl = T("gledger.csv"), st = T("saletype.csv")
        var cleaning: [String] = [], warnings: [String] = []
        func note(_ s: String) { if !warnings.contains(s) { warnings.append(s) } }

        var commodity: [String: (hsn: String?, gst: Double)] = [:], company: [String: String?] = [:]
        for r in st {
            let code = clean(r["SCODE"])
            if code.isEmpty { continue }
            if clean(r["SGCODE"]) == "COMMCD" && commodity[code] == nil {
                let h = clean(r["PARNAM"])
                commodity[code] = (rx("^\\d{4,8}$").test(h) ? h : nil, num(r["IGST"]))
            } else if clean(r["SGCODE"]) == "ZZZZZZ" && company[code] == nil {
                let n = !clean(r["SNAME"]).isEmpty ? clean(r["SNAME"]) : clean(r["PARNAM"])
                company[code] = .some(n.isEmpty ? nil : n)
            }
        }

        // the packs each item's bill rows are written in (12 for a box of 12 packets)
        var linePacks: [String: Set<Int>] = [:]
        for l in dis { let p = int(l["PACK"]); if p > 1 { linePacks[clean(l["CODE"]), default: []].insert(p) } }
        // the pack each item is usually billed in (rows in another pack, like a later change of pack in Marg, are left out)
        var packCount: [String: [Int: Int]] = [:]
        for l in dis where clean(l["FLG"]) == "G" && num(l["SFRATE"]) > 0 {
            let p = max(1, int(l["PACK"]) != 0 ? int(l["PACK"]) : 1)
            packCount[clean(l["CODE"]), default: [:]][p, default: 0] += 1
        }
        func usualPack(_ c: String) -> Int {
            var best: (p: Int, n: Int)? = nil
            for (p, n) in packCount[c] ?? [:] where best == nil || n > best!.n || (n == best!.n && p < best!.p) { best = (p, n) }
            return best?.p ?? 1
        }
        var saleRate: [String: (date: String, rate: Double)] = [:]
        for l in dis where clean(l["FLG"]) == "G" && num(l["SFRATE"]) > 0 {
            let d = day(l["DATE"]) ?? ""
            let c = clean(l["CODE"])
            let p = max(1, int(l["PACK"]) != 0 ? int(l["PACK"]) : 1)
            if p != usualPack(c) { continue }
            if saleRate[c] == nil || d >= saleRate[c]!.date { saleRate[c] = (d, r8(num(l["SFRATE"]) / Double(p))) }
        }
        var batchMrp: [String: (date: String, mrp: Double)] = [:]
        for l in dis {
            let f = clean(l["FLG"]), b = num(l["BATCH"])
            if (f != "G" && f != "P") || !(b > 0) { continue }
            let d = day(l["DATE"]) ?? ""
            let c = clean(l["CODE"])
            if packCount[c] != nil && max(1, int(l["PACK"]) != 0 ? int(l["PACK"]) : 1) != usualPack(c) { continue }   // the usual pack only
            if batchMrp[c] == nil || d >= batchMrp[c]!.date { batchMrp[c] = (d, r2(b / Double(max(1, int(l["PACK"]) != 0 ? int(l["PACK"]) : 1)))) }
        }

        // items
        var items: [Item] = [], itemByCode: [String: Item] = [:], itemByKey: [String: Item] = [:]
        var skippedItems = 0, mergedItems = 0
        for r in pro {
            let code = clean(r["CODE"])
            var name = !clean(r["PRODUCT"]).isEmpty ? clean(r["PRODUCT"]) : clean(r["BILLNAME"])
            if code.isEmpty || name.isEmpty || clean(r["NAME"]).hasPrefix("#") || rx("^product name\\b", "i").test(name) { skippedItems += 1; continue }
            let pack = PDFParser.packFromName(name) ?? max(1, int(r["PACK"]) != 0 ? int(r["PACK"]) : 1)
            var k = key(name)
            if let ex = itemByKey[k], ex.pcsPerBox != pack, !clean(r["PACKING"]).isEmpty { name = "\(name) \(clean(r["PACKING"]))"; k = key(name) }
            if let ex = itemByKey[k] {
                // the same item under a second Marg code: its real sale rate beats the first code's list rate
                if ex.rateFromList, let sr = saleRate[code] { ex.retail = sr.rate; ex.rateFromList = false }
                itemByCode[code] = ex; mergedItems += 1; continue
            }
            let com = commodity[clean(r["GCODE6"])]
            let gst: Double = clean(r["TAXL"]) == "E" ? 0 : ((com?.gst ?? 0) != 0 ? com!.gst : (num(r["IGST"]) != 0 ? num(r["IGST"]) : 0))
            let rateEx = num(r["RATEA"]) / (1 + gst / 100)
            let rateA = num(r["RATEA"]) > 0 ? r8(rateEx / Double(Self.rateUnit(rateEx, [int(r["PACK"]), pack], num(r["LPRATE"]), (linePacks[code] ?? []).sorted()))) : 0
            let it = Item()
            it.code = code; it.name = name; it.pcsPerBox = pack; it.gst = gst; it.hsn = com?.hsn ?? nil
            let fromName = PDFParser.mrpFromName(name) ?? 0
            it.mrp = fromName != 0 ? fromName : (batchMrp[code]?.mrp ?? 0)
            it.category = Category.pinned(name) ?? Category.byRules(name) ?? Category.byRules(Category.cleanQuery(name)) ?? (company[clean(r["GCODE"])] ?? nil)
            it.purchase = Self.purchaseRate(num(r["LPRATE"]), saleRate[code]?.rate ?? rateA, [packCount[code] != nil ? usualPack(code) : 0, int(r["PACK"])])
            it.retail = saleRate[code]?.rate ?? rateA
            it.rateFromList = saleRate[code] == nil
            it.opening = int(r["OPENING"]); it.closing = int(r["BALANCE"])
            Self.byNameMrp(it, [pack, packCount[code] != nil ? usualPack(code) : 0, int(r["PACK"])])
            items.append(it); itemByCode[code] = it; itemByKey[k] = it
        }
        if skippedItems > 0 { cleaning.append("\(skippedItems) placeholder item rows skipped (###…, \"PRODUCT NAME\").") }
        if mergedItems > 0 { cleaning.append("\(mergedItems) duplicate item names merged into one item each.") }
        let noMrp = items.filter { $0.mrp == 0 }.count
        if noMrp > 0 { cleaning.append("\(noMrp) items have no MRP in their name or on their bill rows; set it later with Stock › Auto-fill missing MRPs or by editing the item.") }

        // parties
        var parties: [Party] = [], partyByCode: [String: Party] = [:], partyByKey: [String: Party] = [:]
        var badGstin = 0, mergedParties = 0, cityCut = 0
        for r in order {
            let group = clean(r["SCODE"])
            let kind = group.hasPrefix("C6") ? "CUSTOMER" : group.hasPrefix("D3") ? "SUPPLIER" : ""
            if kind.isEmpty { continue }
            let parts = jsSplit(r["PARNAM"] ?? "", rx("\\s{3,}", "g")).map(clean).filter { !$0.isEmpty }
            var name = parts.first ?? ""
            if name.isEmpty { continue }
            let town = clean(r["CITY"])
            if parts.count > 1 { cityCut += 1 }
            else if !town.isEmpty && name.jsLength > town.jsLength + 3 && name.lowercased().hasSuffix(" " + town.lowercased()) {
                name = clean(name.jsSlice(0, name.jsLength - town.jsLength)); cityCut += 1
            }
            let k = kind + "|" + key(name)
            let code = clean(r["ORDNO"])
            if let ex = partyByKey[k] { partyByCode[code] = ex; mergedParties += 1; continue }
            var gstin = rx("\\s", "g").replace(clean(r["GSTNO"]).uppercased(), "")
            if !gstin.isEmpty && !GSTIN_RE.test(gstin) { badGstin += 1; gstin = "" }
            let pan = clean(r["ITNO"]).uppercased()
            let city = clean(r["CITY"])
            var addr = [r["PARADD"], r["PARADD1"], r["PARADD2"]].map(clean).filter { !$0.isEmpty && !rx("aadhaa?r", "i").test($0) }
            if !city.isEmpty && !addr.contains(where: { $0.lowercased().contains(city.lowercased()) }) { addr.append(city) }
            let pin = clean(r["DSM"])
            if rx("^\\d{6}$").test(pin) && !addr.contains(where: { $0.contains(pin) }) { addr.append(pin) }
            var mobiles: [String] = [], land: [String] = []
            for f in ["PHONE1", "PHONE2", "PHONE3", "PHONE4"] {
                for piece in jsSplit(r[f] ?? "", rx("[,;\\/]", "g")) {
                    let d = rx("\\D", "g").replace(piece, "")
                    if d.count < 6 { continue }
                    if let m = mobileOf(d) { if !mobiles.contains(m) { mobiles.append(m) } } else if !land.contains(clean(piece)) { land.append(clean(piece)) }
                }
            }
            let p = Party()
            p.code = code; p.kind = kind; p.name = name
            p.gstin = gstin.isEmpty ? nil : gstin
            p.state = gstin.isEmpty ? nil : gstin.jsSlice(0, 2)
            p.pan = PAN_RE.test(pan) ? pan : (gstin.isEmpty ? nil : gstin.jsSlice(2, 12))
            p.address = addr.isEmpty ? nil : addr.joined(separator: ", ")
            p.phone = mobiles.first ?? land.first
            p.mobiles = mobiles.count > 1 ? mobiles.dropFirst().joined(separator: ", ") : nil
            p.tel = land.isEmpty ? nil : land.joined(separator: ", ")
            p.opening = r2(num(r["OPNING"])); p.closing = r2(num(r["BALANCE"]))
            parties.append(p); partyByCode[code] = p; partyByKey[k] = p
        }
        if cityCut > 0 { cleaning.append("\(cityCut) party names had the town padded onto the name; the town was moved to the address.") }
        if badGstin > 0 { cleaning.append("\(badGstin) invalid GSTINs dropped.") }
        if mergedParties > 0 { cleaning.append("\(mergedParties) duplicate party names merged.") }

        // bills
        var lines: [String: [[String: String]]] = [:]
        for l in dis { lines[clean(l["VOUCHER"]) + "|" + clean(l["CODEP"]), default: []].append(l) }
        var docs: [Doc] = [], bad: [String] = []
        var skipOther = 0
        for h in mdis {
            let type = clean(h["TYPE"])
            let kind = type == "S" ? "SALE" : type == "P" ? "PURCHASE" : type == "Q" ? "DEBIT_NOTE" : ""
            if kind.isEmpty { skipOther += 1; continue }
            let no = clean(h["VCN"])
            guard !no.isEmpty, let date = day(h["DATE"]) else { skipOther += 1; continue }
            guard let party = partyByCode[clean(h["CODEP"])], (kind == "SALE") == (party.kind == "CUSTOMER") else {
                note("\(no): its party (Marg code \(clean(h["CODEP"]))) is not a \(kind == "SALE" ? "customer" : "supplier"); bill skipped.")
                continue
            }
            let flag = type == "S" ? "G" : type
            var rows: [Line] = []
            for l in lines[clean(h["VOUCHER"]) + "|" + clean(h["CODEP"])] ?? [] {
                if clean(l["FLG"]) != flag { continue }
                guard let it = itemByCode[clean(l["CODE"])] else { note("\(no): item code \(clean(l["CODE"])) is not in the item list; that row is left out."); continue }
                let pcs = int(l["QTY"]), free = int(l["FREE"]), pack = max(1, int(l["PACK"]) != 0 ? int(l["PACK"]) : it.pcsPerBox)
                let taxable = r2(num(l["AMMMOUNT"])), disc = r2(num(l["SDISCOUNT"])), tax = r2(num(l["SSTAAMO"])), cg = r2(num(l["CGSTAMO"]))
                rows.append(Line(item: it, qty: pcs, free: free, taxable: taxable, discAmt: disc, discPct: num(l["DISC1"]), gross: r2(taxable + disc),
                                 rate: pcs > 0 ? r8(num(l["SFRATE"]) / Double(pack)) : 0, gst: num(l["CGST"]) > 0 ? num(l["CGST"]) * 2 : (tax > 0 ? it.gst : 0),
                                 cgst: cg > 0 ? cg : 0, sgst: cg > 0 ? r2(tax - cg) : 0, igst: cg > 0 ? 0 : tax, amount: r2(taxable + tax),
                                 stock: kind != "DEBIT_NOTE" && clean(l["GODWON"]) != "Y", challan: clean(l["CHALLAN"])))
            }
            let taxAmt = r2(num(h["TAXAMO"])), cg = r2(num(h["CGSTAMO"]))
            let ref: String? = kind == "PURCHASE" ? (clean(h["PM"]).isEmpty ? nil : clean(h["PM"]))
                : kind == "DEBIT_NOTE" ? rows.first(where: { !$0.challan.isEmpty })?.challan : nil
            let d = Doc(kind: kind, no: no, date: date, party: party, rows: rows, ref: ref,
                        subtotal: r2(rows.reduce(0.0) { $0 + $1.gross }), discount: r2(rows.reduce(0.0) { $0 + $1.discAmt }), taxable: r2(num(h["AMOUNTT"])),
                        cgst: cg > 0 ? cg : 0, sgst: cg > 0 ? r2(taxAmt - cg) : 0, igst: cg > 0 ? 0 : taxAmt, roundOff: r2(num(h["ROUND"])), total: r2(num(h["FINAL"])))
            let rowSum = r2(rows.reduce(0.0) { $0 + $1.taxable })
            if abs(r2(d.taxable + taxAmt + d.roundOff) - d.total) > 0.05 {
                bad.append("\(no): taxable + GST + round off = \(JS.numberString(r2(d.taxable + taxAmt + d.roundOff))), Marg total \(JS.numberString(d.total))")
            } else if abs(rowSum - d.taxable) > 0.5 {
                bad.append("\(no): rows add up to \(JS.numberString(rowSum)), Marg taxable \(JS.numberString(d.taxable))")
            }
            if rows.isEmpty { note("\(no): no item rows; skipped."); continue }
            docs.append(d)
        }
        if skipOther > 0 { cleaning.append("\(skipOther) other Marg vouchers (not sales, purchases or debit notes) left out.") }

        // money received / paid
        var money: [Money] = []
        for r in gl {
            let book = clean(r["BOOK"])
            if book != "R" && book != "P" { continue }
            guard let p = partyByCode[clean(r["CODE"])] else { continue }
            let amt = r2(book == "R" ? num(r["CREDIT"]) - num(r["DEBIT"]) : num(r["DEBIT"]) - num(r["CREDIT"]))
            guard amt > 0, let date = day(r["DATE"]) else { continue }
            let ref = clean(r["REMARK1"])
            let mode = rx("neft|rtgs|imps|bank|transfer", "i").test(ref) ? "BANK" : rx("upi|gpay|phonepe|paytm", "i").test(ref) ? "UPI" : rx("che?q", "i").test(ref) ? "CHEQUE" : "CASH"
            money.append(Money(kind: book == "R" ? "RECEIPT" : "PAYMENT", no: "\(book == "R" ? "MR" : "MP")/\(clean(r["VOUCHER"]))", date: date, party: p,
                               amount: amt, mode: mode, ref: ref.isEmpty ? nil : ref))
        }

        // Marg's own built-in accounts (codes STA…, e.g. GENERAL LEDGER) sit in the debtors group; unused and empty ones are left out
        let used = Set(docs.map { ObjectIdentifier($0.party) } + money.map { ObjectIdentifier($0.party) })
        let builtIn = parties.filter { $0.code.hasPrefix("STA") && $0.opening == 0 && $0.closing == 0 && !used.contains(ObjectIdentifier($0)) }
        if !builtIn.isEmpty {
            cleaning.append("\(builtIn.count) empty Marg system accounts left out (\(builtIn.prefix(3).map(\.name).joined(separator: ", "))\(builtIn.count > 3 ? ", …" : "")).")
            let gone = Set(builtIn.map { ObjectIdentifier($0) })
            parties.removeAll { gone.contains(ObjectIdentifier($0)) }
        }

        // checks against Marg's closing figures
        for d in docs {
            d.party.moved += d.kind == "PURCHASE" ? -d.total : d.total
            for x in d.rows where x.stock { x.item.moved += (d.kind == "SALE" ? -1 : 1) * (x.qty + x.free) }
        }
        for m in money { m.party.moved += m.kind == "RECEIPT" ? -m.amount : m.amount }
        let partyOff = parties.filter { abs(r2($0.opening + $0.moved) - $0.closing) > 0.05 }
            .map { "\($0.name): opening \(JS.numberString($0.opening)) + bills and payments = \(JS.numberString(r2($0.opening + $0.moved))), Marg closing \(JS.numberString($0.closing))" }
        let stockOff = items.filter { $0.opening + $0.moved != $0.closing }
            .map { "\($0.name): opening \($0.opening) + purchases − sales = \($0.opening + $0.moved), Marg closing \($0.closing)" }
        let negative = items.filter { $0.opening + $0.moved < 0 }.count
        if negative > 0 { note("\(negative) items have negative stock in Marg (sold more than was entered as bought); they come in negative so the totals still match.") }

        let dates = docs.map(\.date).sorted()
        func sum(_ k: String) -> Double { r2(docs.filter { $0.kind == k }.reduce(0.0) { $0 + $1.total }) }
        func msum(_ k: String) -> Double { r2(money.filter { $0.kind == k }.reduce(0.0) { $0 + $1.amount }) }
        func count(_ k: String) -> Int { docs.filter { $0.kind == k }.count }
        let summary: Row = [
            "period": dates.isEmpty ? NSNull() : ["from": dates.first!, "to": dates.last!] as Row,
            "found": ["items": items.count, "customers": parties.filter { $0.kind == "CUSTOMER" }.count, "suppliers": parties.filter { $0.kind == "SUPPLIER" }.count,
                      "sales": count("SALE"), "purchases": count("PURCHASE"), "debit_notes": count("DEBIT_NOTE"),
                      "receipts": money.filter { $0.kind == "RECEIPT" }.count, "payments": money.filter { $0.kind == "PAYMENT" }.count] as Row,
            "totals": ["sales": sum("SALE"), "purchases": sum("PURCHASE"), "debit_notes": sum("DEBIT_NOTE"), "receipts": msum("RECEIPT"), "payments": msum("PAYMENT"),
                       "opening_receivable": r2(parties.reduce(0.0) { $0 + ($1.opening > 0 ? $1.opening : 0) }),
                       "opening_payable": r2(parties.reduce(0.0) { $0 + ($1.opening < 0 ? -$1.opening : 0) })] as Row,
            "checks": [
                "bills": ["checked": docs.count, "ok": docs.count - bad.count, "problems": bad] as Row,
                "party_balances": ["checked": parties.count, "ok": parties.count - partyOff.count, "problems": partyOff] as Row,
                "stock": ["checked": items.count, "ok": items.count - stockOff.count, "problems": stockOff] as Row,
            ] as Row,
            "cleaning": cleaning, "warnings": warnings,
        ]
        return Model(items: items, parties: parties, docs: docs, money: money, summary: summary)
    }

    // MARK: writing into the open company

    static func write(_ db: Database, _ m: Model) throws -> (added: Row, existing: Row) {
        var added: [String: Int] = ["items": 0, "categories": 0, "customers": 0, "suppliers": 0, "sales": 0, "purchases": 0, "debit_notes": 0, "receipts": 0, "payments": 0]
        var existing: [String: Int] = ["items": 0, "parties": 0, "bills": 0, "vouchers": 0]
        func catId(_ name: String?) throws -> Int? {
            guard let name else { return nil }
            if let row = try db.prepare("SELECT id FROM categories WHERE lower(name)=lower(?)").get(name) { return row.i("id") }
            added["categories"]! += 1
            return try db.prepare("INSERT INTO categories(name) VALUES(?)").run(name).lastInsertRowid
        }
        let opening = (m.summary["period"] as? Row)?.str("from")
        for it in m.items {
            if let have = try db.prepare("SELECT id FROM items WHERE lower(name)=lower(?)").get(it.name) {
                it.id = have.i("id"); it.isNew = false; existing["items"]! += 1
            } else {
                it.id = try db.prepare("INSERT INTO items(name,category_id,hsn,gst_rate,unit,mrp,retail_price,wholesale_price,purchase_price,pcs_per_box) VALUES(?,?,?,?,?,?,?,?,?,?)")
                    .run(it.name, try catId(it.category), it.hsn, it.gst, "PCS", it.mrp, it.retail, it.retail, it.purchase, it.pcsPerBox).lastInsertRowid
                it.isNew = true; added["items"]! += 1
            }
            if let b = try db.prepare("SELECT id FROM batches WHERE item_id=? AND batch_no='MARG'").get(it.id) { it.batch = b.i("id") } else {
                it.batch = try db.prepare("INSERT INTO batches(item_id,batch_no,exp_date,qty,purchase_price,mrp) VALUES(?,'MARG',?,?,?,?)")
                    .run(it.id, NO_EXPIRY, it.isNew ? it.opening : 0, it.purchase, it.mrp != 0 ? it.mrp : nil).lastInsertRowid
            }
        }
        let lg = db.prepare("INSERT INTO ledger(party_id,date,type,ref_no,debit,credit,narration) VALUES(?,?,?,?,?,?,?)")
        for p in m.parties {
            if let have = try db.prepare("SELECT id FROM parties WHERE lower(name)=lower(?) AND \(p.kind == "SUPPLIER" ? "type='SUPPLIER'" : "type<>'SUPPLIER'")").get(p.name) {
                p.id = have.i("id"); existing["parties"]! += 1; continue
            }
            p.id = try db.prepare("INSERT INTO parties(name,gstin,state_code,phone,tel,mobiles,address,pan,type,price_tier) VALUES(?,?,?,?,?,?,?,?,?,?)")
                .run(p.name, p.gstin, p.state, p.phone, p.tel, p.mobiles, p.address, p.pan, p.kind == "SUPPLIER" ? "SUPPLIER" : "RETAILER", "RETAIL").lastInsertRowid
            added[p.kind == "SUPPLIER" ? "suppliers" : "customers"]! += 1
            if p.opening != 0, let opening { try lg.run(p.id, opening, "OPENING", "OPENING", p.opening > 0 ? p.opening : 0, p.opening < 0 ? -p.opening : 0, "Opening balance (Marg)") }
        }
        let move = db.prepare("UPDATE batches SET qty = qty + ? WHERE id = ?")
        for d in m.docs {
            if d.kind == "SALE" {
                if try db.prepare("SELECT 1 FROM invoices WHERE invoice_no=?").get(d.no) != nil { existing["bills"]! += 1; continue }
                let id = try db.prepare("INSERT INTO invoices(invoice_no,date,party_id,sale_type,pay_mode,subtotal,discount,taxable,cgst,sgst,igst,round_off,total,paid) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,0)")
                    .run(d.no, d.date, d.party.id, "COUNTER", "CREDIT", d.subtotal, d.discount, d.taxable, d.cgst, d.sgst, d.igst, d.roundOff, d.total).lastInsertRowid
                for x in d.rows {
                    try db.prepare("INSERT INTO invoice_lines(invoice_id,item_id,batch_id,qty,free_qty,rate,disc_pct,disc_amt,taxable,gst_rate,cgst,sgst,igst,amount,manual_disc) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)")
                        .run(id, x.item.id, x.item.batch, x.qty, x.free, x.rate, x.discPct, x.discAmt, x.taxable, x.gst, x.cgst, x.sgst, x.igst, x.amount, x.discPct)
                    if x.stock { try move.run(-(x.qty + x.free), x.item.batch) }
                }
                try lg.run(d.party.id, d.date, "INVOICE", d.no, d.total, 0, "Sale \(d.no)")
                added["sales"]! += 1
            } else if d.kind == "PURCHASE" {
                if try db.prepare("SELECT 1 FROM purchases WHERE purchase_no=?").get(d.no) != nil { existing["bills"]! += 1; continue }
                let id = try db.prepare("INSERT INTO purchases(purchase_no,supplier_invoice_no,date,party_id,subtotal,discount,taxable,cgst,sgst,igst,round_off,total,paid,source) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,0,'MARG')")
                    .run(d.no, d.ref, d.date, d.party.id, d.subtotal, d.discount, d.taxable, d.cgst, d.sgst, d.igst, d.roundOff, d.total).lastInsertRowid
                for x in d.rows {
                    try db.prepare("INSERT INTO purchase_lines(purchase_id,item_id,batch_id,batch_no,exp_date,qty,free_qty,rate,disc_pct,disc_amt,mrp,taxable,gst_rate,cgst,sgst,igst,amount,unit,pcs_qty) VALUES(?,?,?,'MARG',?,?,?,?,?,?,?,?,?,?,?,?,?,'PCS',?)")
                        .run(id, x.item.id, x.item.batch, NO_EXPIRY, x.qty, x.free, x.qty > 0 ? r8(x.gross / Double(x.qty)) : 0, x.discPct, x.discAmt,
                             x.item.mrp != 0 ? x.item.mrp : nil, x.taxable, x.gst, x.cgst, x.sgst, x.igst, x.gross, x.qty + x.free)
                    if x.stock { try move.run(x.qty + x.free, x.item.batch) }
                }
                try lg.run(d.party.id, d.date, "PURCHASE", d.no, 0, d.total, "Purchase \(d.no)\(d.ref.map { " / " + $0 } ?? "")")
                added["purchases"]! += 1
            } else {
                if try db.prepare("SELECT 1 FROM debit_notes WHERE note_no=?").get(d.no) != nil { existing["bills"]! += 1; continue }
                let id = try db.prepare("INSERT INTO debit_notes(note_no,date,party_id,against_bill,reason,subtotal,discount,taxable,cgst,sgst,igst,round_off,total,source) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,'MARG')")
                    .run(d.no, d.date, d.party.id, d.ref, "From Marg", d.subtotal, d.discount, d.taxable, d.cgst, d.sgst, d.igst, d.roundOff, d.total).lastInsertRowid
                for x in d.rows {
                    try db.prepare("INSERT INTO debit_note_lines(note_id,item_id,batch_id,qty,unit,pcs_qty,rate,amount,taxable,gst_rate,cgst,sgst,igst) VALUES(?,?,NULL,?,'PCS',?,?,?,?,?,?,?,?)")
                        .run(id, x.item.id, x.qty, x.qty, x.qty > 0 ? r8(x.gross / Double(x.qty)) : 0, x.gross, x.taxable, x.gst, x.cgst, x.sgst, x.igst)
                }
                try lg.run(d.party.id, d.date, "DEBIT_NOTE", d.no, d.total, 0, "Debit note \(d.no)\(d.ref.map { " against " + $0 } ?? "")")
                added["debit_notes"]! += 1
            }
        }
        for v in m.money {
            let ref = v.ref.map { " " + $0 } ?? ""
            if v.kind == "RECEIPT" {
                if try db.prepare("SELECT 1 FROM receipts WHERE receipt_no=?").get(v.no) != nil { existing["vouchers"]! += 1; continue }
                try db.prepare("INSERT INTO receipts(receipt_no,date,party_id,mode,amount,reference) VALUES(?,?,?,?,?,?)").run(v.no, v.date, v.party.id, v.mode, v.amount, v.ref)
                try lg.run(v.party.id, v.date, "RECEIPT", v.no, 0, v.amount, "Payment received (\(v.mode))\(ref)")
                added["receipts"]! += 1
            } else {
                if try db.prepare("SELECT 1 FROM payments WHERE voucher_no=?").get(v.no) != nil { existing["vouchers"]! += 1; continue }
                try db.prepare("INSERT INTO payments(voucher_no,date,party_id,mode,amount,reference) VALUES(?,?,?,?,?,?)").run(v.no, v.date, v.party.id, v.mode, v.amount, v.ref)
                try lg.run(v.party.id, v.date, "PAYMENT", v.no, v.amount, 0, "Payment made (\(v.mode))\(ref)")
                added["payments"]! += 1
            }
        }
        return (added, existing)
    }

    struct PreviewDone: Error { let out: (added: Row, existing: Row) }

    /// What the backup holds, the checks, and what importing would add, without changing anything.
    /// One year's books take only that year's Marg data.
    static func checkYear(_ db: Database, _ m: Model) throws {
        guard let own = try FY.booksFy(db), let per = m.summary["period"] as? Row else { return }
        let fy = try FY.range(own)
        let from = per.str("from"), to = per.str("to")
        if from < fy.from || to > fy.to {
            let y = Int(JS.number(from.jsSlice(0, 4))) - (Int(JS.number(from.jsSlice(5, 7))) < 4 ? 1 : 0)
            let theirs = try FY.range(String(y)).label
            throw HttpError(400, "This Marg data is for \(theirs) (\(from) to \(to)), but these are the \(own) books. Open or add the \(theirs) books first (Settings › Companies).", "WRONG_YEAR")
        }
    }

    static func preview(_ db: Database, _ p: Any?) throws -> Row {
        let m = model(try readSource(p))
        try checkYear(db, m)
        var out: (added: Row, existing: Row) = ([:], [:])
        do { _ = try db.transaction { () throws -> Int in throw PreviewDone(out: try write(db, m)) } } catch let e as PreviewDone { out = e.out }
        var r = m.summary
        r["would_add"] = out.added
        r["already_here"] = out.existing
        return r
    }

    /// After a Marg import, new bills carry on Marg's own numbering (A000423 after A000422), unless the numbering was already
    /// chosen in Settings (see margImport.js followMarg).
    static func followMarg(_ db: Database, _ m: Model) throws -> Row {
        func get(_ k: String) throws -> String {
            guard let r = try db.prepare("SELECT value FROM settings WHERE key=?").get(k), let v = unwrap(r["value"] ?? nil) else { return "" }
            return JS.string(v)
        }
        let set = db.prepare("INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value")
        var out: [(String, String)] = []
        if try get("num_fy") != "" { return [:] }
        for (kind, s) in [("SALE", "INV"), ("PURCHASE", "PUR"), ("DEBIT_NOTE", "DN")] {
            if try get("num_\(s)_prefix") != "" { continue }
            var best: JSRegex.Match?
            for d in m.docs where d.kind == kind {
                if let x = rx("^(.*?[^0-9])([0-9]+)$").exec(d.no), best == nil || JS.parseInt(x[2]) > JS.parseInt(best![2]) { best = x }
            }
            guard let b = best, let pre = b[1], !JS.trim(pre).isEmpty, let num = b[2] else { continue }
            try set.run("num_\(s)_prefix", pre)
            try set.run("num_\(s)_digits", String(min(9, num.jsLength)))
            out.append((s, pre))
        }
        if !out.isEmpty { try set.run("num_fy", "0") }
        var r: Row = [:]
        for (s, _) in out { r[s] = try peekNo(db, s, nil)["next_no"] ?? "" }
        return r
    }

    /// Settings › Import from Marg › Correct item prices (margImport.js correctPrices): items already here whose price is
    /// far off what Marg says are put right; without `apply` it only lists them.
    static func correctPrices(_ db: Database, _ p: Any?, apply: Bool) throws -> Row {
        let m = model(try readSource(p))
        func far(_ have: Double, _ want: Double) -> Bool { want > 0 ? (!(have > 0) || have / want >= 1.9 || want / have >= 1.9) : false }
        var items: [Any] = []
        var checked = 0
        let keys = ["retail_price", "wholesale_price", "purchase_price", "mrp"]
        func work() throws {
            for it in m.items {
                guard let h = try db.prepare("SELECT id,name,retail_price,wholesale_price,purchase_price,mrp FROM items WHERE lower(name)=lower(?)").get(it.name) else { continue }
                checked += 1
                let want: [String: Double] = ["retail_price": r8(it.retail), "wholesale_price": r8(it.retail), "purchase_price": r8(it.purchase), "mrp": r2(it.mrp)]
                var have: [String: Double] = [:], next: [String: Double] = [:]
                for k in keys { have[k] = JS.number(h[k] ?? nil).isNaN ? 0 : JS.number(h[k] ?? nil); next[k] = far(have[k]!, want[k]!) ? want[k]! : have[k]! }
                if keys.allSatisfy({ next[$0] == have[$0] }) { continue }
                let o: Row = ["name": h["name"] ?? NSNull(), "retail_old": have["retail_price"]!, "retail_new": next["retail_price"]!,
                              "wholesale_old": have["wholesale_price"]!, "wholesale_new": next["wholesale_price"]!,
                              "purchase_old": have["purchase_price"]!, "purchase_new": next["purchase_price"]!, "mrp_old": have["mrp"]!, "mrp_new": next["mrp"]!]
                items.append(o)
                if apply {
                    try db.prepare("UPDATE items SET retail_price=?,wholesale_price=?,purchase_price=?,mrp=? WHERE id=?")
                        .run(next["retail_price"]!, next["wholesale_price"]!, next["purchase_price"]!, next["mrp"]!, h.i("id"))
                }
            }
        }
        if apply { _ = try db.transaction { () throws -> Int in try work(); return 0 } } else { try work() }
        return ["checked": checked, "changed": items.count, "applied": apply, "items": items] as Row
    }

    static func run(_ db: Database, _ p: Any?) throws -> Row {
        let m = model(try readSource(p))
        try checkYear(db, m)
        var numbering: Row = [:]
        let out = try db.transaction { () throws -> (added: Row, existing: Row) in let w = try write(db, m); numbering = try followLast(db); return w }
        var r = m.summary
        r["added"] = out.added
        r["already_here"] = out.existing
        r["numbering"] = numbering
        return r
    }
}
