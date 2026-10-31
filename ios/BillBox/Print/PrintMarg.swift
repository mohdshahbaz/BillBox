import SwiftUI

// The "Marg style" bill design (Settings › Printing › Bill design), the same file in the Mac and iPhone apps.
// It follows a Marg ERP bill: firm and party side by side, a band with GSTIN, the title box and the bill details, the
// item table with Box / Pcs / Free / Pack columns, the GST class table with the totals beside it, the amount in words,
// and Terms | Receiver | Authorised signatory at the bottom. Choices of its own (all under print_marg_*): colour,
// typeface, rate per box or piece, which columns, all GST classes or only those on the bill, due date, receiver box,
// e-mail and page number. The common print settings (copies, text size, capitals, terms, bank details…) apply too.

/// The design the company chose: "classic" (BillBox) or "marg".
func printStyle(_ co: JSON) -> String { co.str("print_style") == "marg" ? "marg" : "classic" }

/// Colour sets for the Marg design: (name and headings, filled bands).
let margColours: [(key: String, title: String)] = [("blue", "Marg blue"), ("mono", "Black only (any printer)"), ("green", "Green"), ("maroon", "Maroon")]
private func margInk(_ co: JSON) -> (Color, Color) {
    switch co.str("print_marg_colour") {
    case "mono": return (.black, Color.black.opacity(0.09))
    case "green": return (Color(red: 0.07, green: 0.37, blue: 0.13), Color(red: 0.86, green: 0.94, blue: 0.85))
    case "maroon": return (Color(red: 0.48, green: 0.12, blue: 0.17), Color(red: 0.97, green: 0.87, blue: 0.88))
    default: return (Color(red: 0.10, green: 0.10, blue: 0.50), Color(red: 0.75, green: 0.95, blue: 0.97))
    }
}

/// The Marg design's item columns: key, heading, width (nil = takes the rest), alignment.
struct MargColumn { let key: String; let head: String; let width: CGFloat?; let align: Alignment }
let margColumns: [MargColumn] = [
    MargColumn(key: "sn", head: "Sn.", width: 18, align: .center), MargColumn(key: "box", head: "Box", width: 24, align: .trailing),
    MargColumn(key: "pcs", head: "Pcs", width: 22, align: .trailing), MargColumn(key: "free", head: "Free", width: 22, align: .trailing),
    MargColumn(key: "pack", head: "Pack", width: 28, align: .center), MargColumn(key: "item", head: "Product", width: nil, align: .leading),
    MargColumn(key: "batch", head: "Batch", width: 40, align: .leading), MargColumn(key: "mrp", head: "MRP", width: 36, align: .trailing),
    MargColumn(key: "exp", head: "Exp.", width: 30, align: .center), MargColumn(key: "hsn", head: "HSN", width: 40, align: .center),
    MargColumn(key: "rate", head: "Rate", width: 40, align: .trailing), MargColumn(key: "dis", head: "Dis %", width: 24, align: .trailing),
    MargColumn(key: "gst", head: "GST %", width: 24, align: .trailing), MargColumn(key: "sgst", head: "SGST", width: 25, align: .trailing),
    MargColumn(key: "cgst", head: "CGST", width: 25, align: .trailing), MargColumn(key: "igst", head: "IGST", width: 26, align: .trailing),
    MargColumn(key: "amount", head: "Amount", width: 50, align: .trailing),
]
/// Columns that can be switched off (Settings › Printing › Marg style), with the default when never set.
let margOptionalColumns: [(key: String, title: String, on: Bool)] = [
    ("free", "Free", true), ("pack", "Pack", true), ("batch", "Batch", false), ("mrp", "MRP", true), ("exp", "Expiry", true),
    ("hsn", "HSN", true), ("dis", "Disc %", true), ("tax", "SGST / CGST (IGST) %", true), ("gst", "GST %", false),
]
func margShown(_ co: JSON) -> Set<String> {
    let raw = co.str("print_marg_cols")
    let set = Set(raw.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) })
    return Set(margOptionalColumns.filter { raw.isEmpty ? $0.on : set.contains($0.key) }.map(\.key))
}
/// The columns this bill prints (IGST instead of SGST and CGST on a bill to another state).
func margCols(_ co: JSON, inter: Bool) -> [MargColumn] {
    let on = margShown(co)
    let pcsOnly = co.str("print_qty") == "pcs"
    return margColumns.filter { c in
        switch c.key {
        case "free", "pack", "batch", "mrp", "exp", "hsn", "dis", "gst": return on.contains(c.key)
        case "sgst", "cgst": return on.contains("tax") && !inter
        case "igst": return on.contains("tax") && inter
        case "box": return !pcsOnly
        default: return true
        }
    }
}

/// GST classes in the table at the bottom: 5, 12, 18 and 28 always (like Marg) plus any other rate on the bill, or only the bill's.
func margClasses(_ inv: JSON, _ co: JSON) -> [Double] {
    let used = Set(inv.list("lines").map { $0.num("gst_rate") })
    let base: Set<Double> = co.str("print_marg_classes") == "used" ? [] : [5, 12, 18, 28]
    let all = base.union(used)
    return all.isEmpty ? [0] : all.sorted()
}

/// The page for the Marg design: heights follow the text size, the GST classes and the bank details.
func margSpec(_ base: Spec, _ inv: JSON, _ co: JSON) -> Spec {
    let f = base.fs
    let bank = bankRows(co)
    let bankH: CGFloat = bank.isEmpty ? 0 : CGFloat((bank.count + 1) / 2) * 8.2 * f + 5
    let classH = CGFloat(margClasses(inv, co).count + 2) * 8.6 * f + 4
    let totals = max(classH, 9 * 8.6 * f) + 13 * f + bankH + 1.2
    return Spec(w: base.w, h: base.h, m: base.m, rowH: base.rowH, tableHead: 15 * f, foot: 36 * f, totals: totals,
                strip: 24 * f, sellerBand: 52 * f, buyerBand: 0, headNext: 18 * f, fs: f, cw: base.cw)
}

@MainActor struct MargSheetView: View {
    let inv: JSON
    let co: JSON
    let rows: Range<Int>
    let page: Int
    let pages: Int
    let copy: String
    var g: Spec

    private var first: Bool { page == 0 }
    private var last: Bool { page == pages - 1 }
    private var inter: Bool { inv.num("igst") > 0 }
    private var cols: [MargColumn] { margCols(co, inter: inter) }
    private var accent: Color { margInk(co).0 }
    private var band: Color { margInk(co).1 }
    private var serif: Bool { co.str("print_marg_font") != "sans" }
    private var isNote: Bool { inv.str("doc_title") == "DEBIT NOTE" }
    private func on(_ key: String, _ dflt: Bool = true) -> Bool { co.str(key).isEmpty ? dflt : co.str(key) != "0" }
    private func hc(_ s: String) -> String { co.str("print_caps_head") == "1" ? s.uppercased() : s }
    private var companyName: String { co.str("company_name").isEmpty ? co.str("name") : co.str("company_name") }
    private var docTitle: String {
        if !inv.str("doc_title").isEmpty { return inv.str("doc_title") }
        return co.str("print_title").isEmpty ? "GST INVOICE" : co.str("print_title").uppercased()
    }
    private var noLabel: String { inv.str("doc_no_label").isEmpty ? "Invoice No." : inv.str("doc_no_label") }
    /// rate and MRP per box (like Marg) unless set to per piece
    private var perBox: Bool { co.str("print_marg_rate") != "pcs" && co.str("print_qty") != "pcs" }
    private var tableHeight: CGFloat { g.inner - (first ? g.headFirst : g.headNext) - g.foot - (last ? g.totals : 0) }
    /// width inside the frame; the header and totals are laid out in fixed shares of it
    private var W: CGFloat { g.w - 2 * g.m }

    private func t(_ s: String, _ size: CGFloat, bold: Bool = false, weight: Font.Weight? = nil) -> Text {
        Text(s).font(.system(size: size * g.fs, weight: weight ?? (bold ? .bold : .regular), design: serif ? .serif : .default))
    }
    private func hLine(_ w: CGFloat = 0.8) -> some View { Rectangle().fill(Color.black).frame(height: w) }
    private func vLine(_ w: CGFloat = 0.8) -> some View { Rectangle().fill(Color.black).frame(width: w) }

    var body: some View {
        VStack(spacing: 0) {
            if first { header } else { nextHeader }
            hLine()
            table
            if last {
                hLine()
                totals
            }
            hLine()
            footer
        }
        .overlay(Rectangle().stroke(Color.black, lineWidth: 1.1))
        .padding(g.m)
        .frame(width: g.w, height: g.h, alignment: .top)
        .background(Color.white)
        .foregroundStyle(Color.black)
        .environment(\.colorScheme, .light)
    }

    // MARK: header

    private var header: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 1) {
                    t(hc(companyName), 15, bold: true).foregroundStyle(accent).lineLimit(1).minimumScaleFactor(0.55)
                    if !co.str("print_tagline").isEmpty { t(hc(co.str("print_tagline")), 6.5).italic().foregroundStyle(accent).lineLimit(1).minimumScaleFactor(0.7) }
                    t(hc(co.str("company_address")), 7.5).foregroundStyle(accent).lineLimit(2).minimumScaleFactor(0.8).fixedSize(horizontal: false, vertical: true)
                    if !co.str("company_phone").isEmpty { t("Phone : \(co.str("company_phone"))", 7.5).foregroundStyle(accent).lineLimit(1) }
                }
                .padding(.horizontal, 6).padding(.vertical, 3)
                .frame(width: W * 0.55, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .top)
                vLine()
                VStack(alignment: .leading, spacing: 0.5) {
                    HStack(alignment: .firstTextBaseline) {
                        t(hc(partyTitle), 10.5, bold: true).lineLimit(1).minimumScaleFactor(0.6)
                        Spacer(minLength: 2)
                        if on("print_marg_page") { t("Page \(page + 1)\(pages > 1 ? " of \(pages)" : "")", 6.5, bold: true) }
                    }
                    ForEach(Array(partyLines.enumerated()), id: \.offset) { _, l in
                        t(hc(l.0), 7.5, weight: l.1 ? .bold : .regular).lineLimit(1).minimumScaleFactor(0.65)
                    }
                }
                .padding(.horizontal, 6).padding(.vertical, 3)
                .frame(width: W * 0.45 - 0.8, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(height: g.sellerBand)
            .clipped()
            hLine()
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 1) {
                    if on("print_marg_email", false) && !co.str("company_email").isEmpty { t("E-Mail : \(co.str("company_email"))", 6.5).foregroundStyle(accent).lineLimit(1).minimumScaleFactor(0.6) }
                    if !co.str("company_gstin").isEmpty { t("GSTIN : \(co.str("company_gstin"))", 7.5, bold: true).foregroundStyle(accent).lineLimit(1).minimumScaleFactor(0.7) }
                    if !co.str("state_code").isEmpty { t("State code : \(co.str("state_code"))", 6.5).foregroundStyle(accent).lineLimit(1) }
                }
                .padding(.horizontal, 6)
                .frame(width: W * 0.34, alignment: .leading)
                .frame(maxHeight: .infinity)
                vLine()
                VStack(spacing: 0) {
                    t(docTitle, 12.5, bold: true).lineLimit(1).minimumScaleFactor(0.6)
                    t(copy, 5.5, bold: true).lineLimit(1).minimumScaleFactor(0.6)
                }
                .padding(.horizontal, 4)
                .frame(width: 150 * g.cw)
                .frame(maxHeight: .infinity)
                .background(band)
                vLine()
                // label : value, lined up in two groups (no Grid: the Mac app still runs on macOS 12)
                let rest = W - W * 0.34 - 150 * g.cw - 1.6 - 12
                HStack(alignment: .top, spacing: 0) {
                    detailGroup(detailPairs.map(\.0)).frame(width: rest * 0.56, alignment: .leading)
                    detailGroup(detailPairs.compactMap(\.1)).frame(width: rest * 0.44, alignment: .leading)
                }
                .padding(.horizontal, 6)
                .frame(width: W - W * 0.34 - 150 * g.cw - 1.6, alignment: .leading)
                .frame(maxHeight: .infinity)
            }
            .frame(height: g.strip)
        }
        .frame(height: g.headFirst, alignment: .top)
    }

    private var partyTitle: String {
        let name = inv.str("party_name").isEmpty ? "Cash customer" : inv.str("party_name")
        if isNote { return "Supplier: " + name }
        return (inv.str("party_name").isEmpty || co.str("print_marg_ms") == "0" ? "" : "M/s ") + name
    }

    /// The party's details under the name: (text, bold).
    private var partyLines: [(String, Bool)] {
        if !on("print_party") { return [] }
        var mob: [String] = []
        for m in ([inv.str("party_phone")] + inv.str("party_mobiles").split(whereSeparator: { ",;/".contains($0) }).map(String.init)) {
            let x = m.trimmingCharacters(in: .whitespaces)
            if !x.isEmpty && !mob.contains(x) { mob.append(x) }
        }
        if !inv.str("party_tel").isEmpty { mob.append(inv.str("party_tel")) }
        var out: [(String, Bool)] = []
        let addr = inv.str("party_address").trimmingCharacters(in: .whitespacesAndNewlines)
        if !addr.isEmpty { out.append((addr, false)) }
        if !inv.str("party_state").isEmpty { out.append(("State code : \(inv.str("party_state"))", false)) }
        if !mob.isEmpty { out.append(("Ph.No. : \(mob.joined(separator: ", "))", false)) }
        out.append(("GSTIN : \(inv.str("party_gstin").isEmpty ? "Unregistered" : inv.str("party_gstin"))", true))
        let more = [("PAN", inv.str("party_pan")), ("FSSAI", inv.str("party_fssai"))].filter { !$0.1.isEmpty }.map { "\($0.0) : \($0.1)" }
        if !more.isEmpty { out.append((more.joined(separator: "   "), false)) }
        return Array(out.prefix(5))
    }

    /// The bill details on the right of the title box, two to a row.
    private var detailPairs: [((String, String), (String, String)?)] {
        var left: [(String, String)] = [(noLabel, inv.str("invoice_no"))]
        var right: [(String, String)] = [("Date", Fmt.dmy(inv.str("date")))]
        if inv.has("doc_line") {
            if !inv.str("doc_line").isEmpty { left.append(("Ref", inv.str("doc_line"))) }
        } else {
            if on("print_salesman") { left.append(("Sales Man", inv.str("salesman_name").isEmpty ? "-" : inv.str("salesman_name").uppercased())) }
            let days = inv.int("party_credit_days")
            if on("print_marg_due") && inv.str("pay_mode") == "CREDIT" { right.append(("Due Date", Fmt.dmy(addDays(inv.str("date"), days)))) }
            else if on("print_payment") { right.append(("Payment", inv.str("pay_mode").capitalized)) }
            if !inv.str("ewb_no").isEmpty { left.append(("E-way bill", inv.str("ewb_no"))) }
        }
        var out: [((String, String), (String, String)?)] = []
        for i in 0..<max(left.count, right.count) {
            let l = i < left.count ? left[i] : ("", "")
            out.append((l, i < right.count ? right[i] : nil))
        }
        return out
    }

    private func detailGroup(_ kv: [(String, String)]) -> some View {
        HStack(alignment: .top, spacing: 3) {
            VStack(alignment: .leading, spacing: 1.5) { ForEach(Array(kv.enumerated()), id: \.offset) { _, p in t(p.0, 7.5).lineLimit(1) } }
                .fixedSize()
            VStack(spacing: 1.5) { ForEach(Array(kv.enumerated()), id: \.offset) { _, p in t(p.0.isEmpty ? "" : ":", 7.5) } }
                .fixedSize()
            VStack(alignment: .leading, spacing: 1.5) { ForEach(Array(kv.enumerated()), id: \.offset) { _, p in t(p.1, 7.5, bold: true).lineLimit(1).minimumScaleFactor(0.6) } }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var nextHeader: some View {
        HStack {
            t(hc(companyName), 9, bold: true).foregroundStyle(accent)
            t("·  \(docTitle)  ·  \(noLabel) \(inv.str("invoice_no"))  ·  \(Fmt.dmy(inv.str("date")))  (continued)", 8, bold: true)
            Spacer()
            t("Page \(page + 1) of \(pages)", 6.5, bold: true)
        }
        .padding(.horizontal, 6)
        .frame(height: g.headNext)
        .background(band)
    }

    // MARK: items

    private func cellText(_ c: MargColumn, _ i: Int, _ l: JSON) -> String {
        let ppb = max(1, l.int("pcs_per_box"))
        let qty = l.int("qty")
        let byBox = perBox && ppb > 1
        switch c.key {
        case "sn": return "\(i + 1)."
        case "box": return "\(qty / ppb)"
        case "pcs": return co.str("print_qty") == "pcs" ? "\(qty)" : "\(qty % ppb)"
        case "free": return l.int("free_qty") > 0 ? "\(l.int("free_qty"))" : "0"
        case "pack": return "\(ppb)*1"
        case "item": return Fmt.cut(co.str("print_caps") == "1" ? l.str("item_name").uppercased() : l.str("item_name"), 60)
        case "batch": return l.str("batch_no")
        case "mrp": return l.num("mrp") > 0 ? Fmt.amount(l.num("mrp") * Double(byBox ? ppb : 1)) : ""
        case "exp": return expText(l.str("exp_date"))
        case "hsn": return l.str("hsn")
        case "rate": return Fmt.amount(l.num("rate") * Double(byBox ? ppb : 1))
        case "dis": return Fmt.amount(l.num("disc_pct"))
        case "gst": return Fmt.amount(l.num("gst_rate"))
        case "sgst", "cgst": return Fmt.amount(l.num("gst_rate") / 2)
        case "igst": return Fmt.amount(l.num("gst_rate"))
        case "amount": return Fmt.amount(l.num("amount"))
        default: return ""
        }
    }

    private func cell(_ s: String, _ c: MargColumn, bold: Bool = false, size: CGFloat = 7.5) -> some View {
        let w = c.width.map { $0 * g.cw }
        return t(s, size, bold: bold).lineLimit(1).minimumScaleFactor(0.7)
            .padding(.horizontal, 2.5)
            .frame(width: w, alignment: c.align)
            .frame(maxWidth: w == nil ? .infinity : nil, alignment: c.align)
    }

    private var table: some View {
        let lines = inv.list("lines")
        return VStack(spacing: 0) {
            HStack(spacing: 0) { ForEach(cols, id: \.key) { c in cell(c.head, c, bold: true, size: 8) } }
                .frame(height: g.tableHead)
                .background(band)
            ForEach(Array(rows), id: \.self) { i in
                HStack(spacing: 0) { ForEach(cols, id: \.key) { c in cell(cellText(c, i, lines[i]), c) } }
                    .frame(height: g.rowH)
            }
            Spacer(minLength: 0)
        }
        .frame(height: tableHeight, alignment: .top)
        .overlay(columnLines)
    }

    private var columnLines: some View {
        let ws = cols.map(\.width), cw = g.cw, head = g.tableHead
        return Canvas { ctx, size in
            let fixed = ws.compactMap { $0 }.reduce(0, +) * cw
            var x: CGFloat = 0
            var p = Path()
            for w in ws.dropLast() {
                x += w.map { $0 * cw } ?? (size.width - fixed)
                p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height))
            }
            ctx.stroke(p, with: .color(.black), lineWidth: 0.6)
            var h = Path()
            h.move(to: CGPoint(x: 0, y: head)); h.addLine(to: CGPoint(x: size.width, y: head))
            ctx.stroke(h, with: .color(.black), lineWidth: 0.8)
        }
        .allowsHitTesting(false)
    }

    // MARK: totals

    private struct ClassRow { let label: String; let taxable, disc, sgst, cgst, igst: Double; var gst: Double { sgst + cgst + igst }; var total: Double { taxable + gst } }

    private var classRows: [ClassRow] {
        let lines = inv.list("lines")
        return margClasses(inv, co).map { r in
            let ls = lines.filter { abs($0.num("gst_rate") - r) < 0.001 }
            func sum(_ k: String) -> Double { ls.reduce(0) { $0 + $1.num(k) } }
            return ClassRow(label: "GST \(Fmt.amount(r))", taxable: sum("taxable"), disc: sum("disc_amt"), sgst: sum("sgst"), cgst: sum("cgst"), igst: sum("igst"))
        }
    }

    private var totals: some View {
        let rows = classRows
        let tot = ClassRow(label: "TOTAL", taxable: rows.reduce(0) { $0 + $1.taxable }, disc: rows.reduce(0) { $0 + $1.disc },
                           sgst: rows.reduce(0) { $0 + $1.sgst }, cgst: rows.reduce(0) { $0 + $1.cgst }, igst: rows.reduce(0) { $0 + $1.igst })
        let heads = inter ? ["CLASS", "TAXABLE", "DISC.", "IGST", "TOTAL GST", "AMOUNT"] : ["CLASS", "TAXABLE", "DISC.", "SGST", "CGST", "TOTAL GST", "AMOUNT"]
        func vals(_ r: ClassRow) -> [String] {
            inter ? [r.label, Fmt.amount(r.taxable), Fmt.amount(r.disc), Fmt.amount(r.igst), Fmt.amount(r.gst), Fmt.amount(r.total)]
                  : [r.label, Fmt.amount(r.taxable), Fmt.amount(r.disc), Fmt.amount(r.sgst), Fmt.amount(r.cgst), Fmt.amount(r.gst), Fmt.amount(r.total)]
        }
        let rh = 8.6 * g.fs
        let bank = bankRows(co)
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                // the GST class table
                VStack(spacing: 0) {
                    classLine(heads, bold: true, size: 7.5).frame(height: rh + 1).frame(maxWidth: .infinity).background(band)
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, r in classLine(vals(r)).frame(height: rh) }
                    hLine(0.6)
                    classLine(vals(tot), bold: true).frame(height: rh)
                    Spacer(minLength: 0)
                }
                .frame(width: W - 172 * g.cw - 0.8)
                .overlay(classGrid(count: heads.count))
                vLine()
                summary.frame(width: 172 * g.cw)
            }
            .frame(maxHeight: .infinity)
            hLine(0.6)
            HStack {
                t(co.str("print_words") == "0" ? "" : "Rs. " + inv.str("amount_words").replacingOccurrences(of: "Rupees ", with: ""), 7.5, weight: .semibold).lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 6)
                if co.str("print_balance") == "1" && inv.has("party_prev_balance") {
                    t("Old balance \(balanceText(inv.num("party_prev_balance")))  ·  Now due \(balanceText(inv.num("party_balance_after")))", 7, bold: true).lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 13 * g.fs)
            if !bank.isEmpty {
                hLine(0.6)
                bankBand(bank)
            }
        }
        .frame(height: g.totals, alignment: .top)
    }

    private func classLine(_ v: [String], bold: Bool = false, size: CGFloat = 7) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(v.enumerated()), id: \.offset) { i, s in
                t(s, size, bold: bold).lineLimit(1).minimumScaleFactor(0.6)
                    .padding(.horizontal, 3)
                    .frame(width: (W - 172 * g.cw - 0.8) / CGFloat(v.count), alignment: i == 0 ? .leading : .trailing)
            }
        }
    }

    private func classGrid(count: Int) -> some View {
        Canvas { ctx, size in
            var p = Path()
            let w = size.width / CGFloat(count)
            for k in 1..<count { p.move(to: CGPoint(x: w * CGFloat(k), y: 0)); p.addLine(to: CGPoint(x: w * CGFloat(k), y: size.height)) }
            ctx.stroke(p, with: .color(Color.black.opacity(0.7)), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }

    private var summary: some View {
        var rows: [(String, Double)] = [("SUB TOTAL", inv.num("subtotal"))]
        if inv.num("discount") > 0 { rows.append(("LESS DISCOUNT", -inv.num("discount"))) }
        if inv.num("discount") > 0 || abs(inv.num("taxable") - inv.num("subtotal")) > 0.005 { rows.append(("TAXABLE VALUE", inv.num("taxable"))) }
        if inter { rows.append(("IGST PAYABLE", inv.num("igst"))) } else { rows.append(("SGST PAYABLE", inv.num("sgst"))); rows.append(("CGST PAYABLE", inv.num("cgst"))) }
        rows.append(("ROUND OFF", inv.num("round_off")))
        if inv.num("paid") > 0 && inv.num("paid") < inv.num("total") - 0.005 { rows.append(("PAID", inv.num("paid"))) }
        return VStack(spacing: 0) {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                    HStack { t(r.0, 7.5).lineLimit(1); Spacer(); t(Fmt.amount(r.1), 7.5).lineLimit(1) }
                        .frame(height: min(9 * g.fs, (summaryRoom - 4) / CGFloat(rows.count)))
                        .minimumScaleFactor(0.7)
                }
            }
            .padding(.horizontal, 6).padding(.top, 2)
            Spacer(minLength: 0)
            hLine(0.6)
            HStack {
                t(isNote ? "NOTE TOTAL" : "GRAND TOTAL", 9.5, bold: true)
                Spacer()
                t(Fmt.amount(inv.num("total")), 11, bold: true)
            }
            .padding(.horizontal, 6)
            .frame(height: 17 * g.fs)
            .background(band)
        }
    }

    /// height of the totals area above the amount in words, less the GRAND TOTAL band
    private var summaryRoom: CGFloat {
        let bank = bankRows(co)
        let bankH: CGFloat = bank.isEmpty ? 0 : CGFloat((bank.count + 1) / 2) * 8.2 * g.fs + 5 + 0.6
        return g.totals - 13 * g.fs - 0.6 - bankH - 17 * g.fs - 0.6
    }

    private func bankBand(_ rows: [(String, String)]) -> some View {
        let half = (rows.count + 1) / 2
        return HStack(alignment: .top, spacing: 10) {
            ForEach(0..<2, id: \.self) { side in
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(rows[(side == 0 ? 0 : half)..<(side == 0 ? half : rows.count)].enumerated()), id: \.offset) { _, r in
                        HStack(spacing: 4) {
                            t(r.0 + " :", 6.5, bold: true).lineLimit(1).minimumScaleFactor(0.8).frame(width: 84 * g.cw, alignment: .leading)
                            t(r.1, 7, weight: .semibold).lineLimit(1).minimumScaleFactor(0.6)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .frame(height: CGFloat(half) * 8.2 * g.fs + 5, alignment: .top)
    }

    // MARK: footer

    private var footer: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                if on("print_terms") && !co.str("invoice_terms").isEmpty {
                    t("Terms & Conditions", 8, bold: true).underline()
                    t(co.str("invoice_terms"), 6.5).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
                if !co.str("print_bank").isEmpty { t(co.str("print_bank"), 6.5, weight: .semibold).lineLimit(1).minimumScaleFactor(0.7) }
                if !co.str("print_note").isEmpty { t(co.str("print_note"), 7, bold: true).lineLimit(1).minimumScaleFactor(0.7) }
            }
            .padding(.horizontal, 6).padding(.vertical, 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .layoutPriority(1)
            if on("print_marg_receiver") {
                vLine()
                VStack {
                    t("Receiver", 8, bold: true)
                    Spacer()
                    t("(signature and stamp)", 5.5).foregroundStyle(Color.black.opacity(0.55))
                }
                .padding(.vertical, 3)
                .frame(width: 140 * g.cw)
                .frame(maxHeight: .infinity)
            }
            if on("print_signature") {
                vLine()
                VStack(alignment: .leading) {
                    t(hc("For \(companyName)"), 7, bold: true).lineLimit(1).minimumScaleFactor(0.6)
                    Spacer()
                    t("Authorised signatory", 8, bold: true)
                }
                .padding(.horizontal, 6).padding(.vertical, 3)
                .frame(width: 150 * g.cw)
                .frame(maxHeight: .infinity, alignment: .leading)
            }
        }
        .frame(height: g.foot)
    }
}

/// "2027-05-31" -> "05/27" (how Marg prints an expiry).
func expText(_ d: String) -> String {
    let p = d.split(separator: "-")
    guard p.count >= 2, p[0].count == 4 else { return "" }
    return "\(p[1])/\(p[0].suffix(2))"
}

/// "2026-10-24" plus n days, as yyyy-MM-dd.
func addDays(_ d: String, _ n: Int) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = "yyyy-MM-dd"
    guard let x = f.date(from: d) else { return d }
    return f.string(from: x.addingTimeInterval(Double(n) * 86400))
}
