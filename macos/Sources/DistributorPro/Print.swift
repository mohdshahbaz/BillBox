import SwiftUI
import AppKit
import PDFKit

// MARK: - Layouts and geometry

enum PrintLayout: String, CaseIterable, Identifiable {
    case halfSheets, a4TwoUp, single, a4Full, a4FullOriginal
    var id: String { rawValue }
    var label: String {
        switch self {
        case .halfSheets: return "Half sheets (A4 cut in two, or A5): Original on one, Duplicate on the next"
        case .a4TwoUp: return "A4 sheet: Original on top, Duplicate below"
        case .single: return "Half sheet (A4 cut in two, or A5): Original copy only"
        case .a4Full: return "Full A4 page: Original + Duplicate, one copy per page"
        case .a4FullOriginal: return "Full A4 page: Original copy only"
        }
    }
    var isFullPage: Bool { self == .a4Full || self == .a4FullOriginal }
    /// Each page goes on its own half sheet (210 x 148.5 mm): the printer is asked for A5 paper, fed landscape.
    var isHalfSheet: Bool { self == .halfSheets || self == .single }
    static func parse(_ s: String) -> PrintLayout { PrintLayout(rawValue: s) ?? .halfSheets }
}

let copyLabels = ["ORIGINAL FOR RECIPIENT", "DUPLICATE FOR TRANSPORTER/SUPPLIER"]
let triplicateLabel = "TRIPLICATE FOR ASSESSEE"
/// The copy labels, as the company set them (Settings › Printing) or the standard ones; a third copy when switched on.
func copyLabelsFor(_ co: JSON) -> [String] {
    var l = [co.str("print_copy1").isEmpty ? copyLabels[0] : co.str("print_copy1").uppercased(),
             co.str("print_copy2").isEmpty ? copyLabels[1] : co.str("print_copy2").uppercased()]
    if co.str("print_triplicate") == "1" { l.append(co.str("print_copy3").isEmpty ? triplicateLabel : co.str("print_copy3").uppercased()) }
    return l
}

/// Settings › Printing › Text size: smaller, normal or larger print (rows grow with the text, so nothing is cut).
func printScale(_ co: JSON) -> CGFloat {
    switch co.str("print_font") { case "small": return 0.92; case "large": return 1.1; default: return 1 }
}

/// Paper sizes in points (1 mm = 2.8346 pt).
enum Paper {
    static let a4 = CGSize(width: 595.276, height: 841.89)
    /// A5 / half an A4 sheet, portrait; a half-sheet bill prints across it (landscape).
    static let a5 = CGSize(width: 420.945, height: 595.276)
}

/// A page is made of fixed-height blocks, so how many item rows fit is plain arithmetic and nothing is ever clipped.
/// If the items do not fit, the invoice continues on the next page. Half sheet = 210 x 148.5 mm, full page = A4.
/// `m` is the white margin all round (about 7 mm on a half sheet, 12 mm on A4) so nothing falls in the printer's unprintable edge.
struct Spec {
    let w: CGFloat, h: CGFloat, m: CGFloat
    let rowH: CGFloat, tableHead: CGFloat, foot: CGFloat, totals: CGFloat
    /// first-page header: seller and buyer side by side (sellerBand), then the info line (strip); buyerBand is spare (0)
    let strip: CGFloat, sellerBand: CGFloat, buyerBand: CGFloat
    let headNext: CGFloat
    let fs: CGFloat
    let cw: CGFloat

    var headFirst: CGFloat { strip + sellerBand + buyerBand + 0.6 }
    /// height inside the margins, less the ruled lines between the header, table and totals
    var inner: CGFloat { h - 2 * m - 2.4 }
    var size: CGSize { CGSize(width: w, height: h) }
    func cap(first: Bool, last: Bool) -> Int {
        Int(((inner - (first ? headFirst : headNext) - tableHead - foot - (last ? totals : 0)) / rowH).rounded(.down))
    }

    /// The same page with text (and the rows holding it) made larger or smaller.
    func scaled(_ k: CGFloat) -> Spec {
        k == 1 ? self : Spec(w: w, h: h, m: m, rowH: rowH * k, tableHead: tableHead * k, foot: foot * k, totals: totals * k,
                             strip: strip * k, sellerBand: sellerBand * k, buyerBand: buyerBand, headNext: headNext * k, fs: fs * k, cw: cw)
    }

    /// Room for the bank details under the GST table (Settings › Printing › Bank details), when the bill prints them.
    func withBank(_ co: JSON) -> Spec {
        let rows = bankRows(co)
        guard !rows.isEmpty else { return self }
        let extra = CGFloat(rows.count) * 8.4 * fs + (rows.contains { $0.0 == "ADDRESS" && $0.1.count > 70 } ? 8.4 * fs : 0) + 4
        return Spec(w: w, h: h, m: m, rowH: rowH, tableHead: tableHead, foot: foot, totals: totals + extra,
                    strip: strip, sellerBand: sellerBand, buyerBand: buyerBand, headNext: headNext, fs: fs, cw: cw)
    }

    static let half = Spec(w: 595.276, h: 420.945, m: 20, rowH: 12, tableHead: 15, foot: 26, totals: 91,
                           strip: 15, sellerBand: 56, buyerBand: 0, headNext: 18, fs: 1, cw: 1)
    static let full = Spec(w: 595.276, h: 841.89, m: 34, rowH: 16, tableHead: 20, foot: 32, totals: 112,
                           strip: 19, sellerBand: 68, buyerBand: 0, headNext: 24, fs: 1.15, cw: 1.0)
}

/// The bank details printed above the amount in words, one per line, in this order; empty ones are left out.
let bankFields: [(key: String, label: String, title: String)] = [
    ("bank_name", "BANK NAME", "Bank name"), ("bank_ac_name", "ACCOUNT NAME", "Account name"), ("bank_ac_no", "ACCOUNT NUMBER", "Account number"),
    ("bank_ifsc", "IFSC CODE", "IFSC code"), ("bank_branch", "BRANCH NAME", "Branch name"), ("bank_branch_code", "BRANCH CODE", "Branch code"),
    ("bank_address", "ADDRESS", "Branch address"),
]
func bankRows(_ co: JSON) -> [(String, String)] {
    if co.str("print_bank_block") == "0" { return [] }
    return bankFields.compactMap { f in
        let v = co.str(f.key).trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : (f.label, v)
    }
}

/// Splits n item rows into pages (row index ranges, always at least one page).
func paginate(_ n: Int, _ g: Spec) -> [Range<Int>] {
    if n <= g.cap(first: true, last: true) { return [0..<n] }
    var pages: [Range<Int>] = []
    var i = 0
    var first = true
    while true {
        let remaining = n - i
        if remaining <= g.cap(first: first, last: true) { pages.append(i..<n); break }
        // leave at least one row for the last page so the totals never sit alone on an empty page
        let take = max(1, min(g.cap(first: first, last: false), remaining - 1))
        pages.append(i..<(i + take))
        i += take
        first = false
    }
    return pages
}

// MARK: - Invoice sheet

private let ink = Color.black
private let muted = Color.black.opacity(0.62)
private let frameLine: CGFloat = 1.1      // outer frame and band dividers
private let ruleLine: CGFloat = 0.6       // inner dividers
private let shade = Color.black.opacity(0.09)

/// Column widths (points, before the page multiplier). The Item column takes whatever is left.
private let widths: [CGFloat?] = [18, nil, 42, 82, 32, 40, 28, 48, 26, 54]
private let headings = ["#", "Description of goods", "HSN", "Qty (box / pcs)", "MRP", "Rate", "Disc %", "Taxable", "GST %", "Amount"]

private func cell(_ t: String, _ i: Int, _ g: Spec, bold: Bool = false) -> some View {
    let right = [3, 4, 5, 6, 7, 8, 9].contains(i)
    let center = i == 0
    let align: Alignment = center ? .center : (right ? .trailing : .leading)
    let w = widths[i].map { $0 * g.cw }
    return Text(t).font(.system(size: 7 * g.fs, weight: bold ? .semibold : .regular)).lineLimit(1).minimumScaleFactor(0.75)
        .padding(.horizontal, 3)
        .frame(width: w, alignment: align)
        .frame(maxWidth: w == nil ? .infinity : nil, alignment: align)
        .frame(maxHeight: .infinity)
}

/// Columns that can be left off the printed bill (Settings › Printing): key -> column index.
let optionalColumns: [(key: String, title: String, index: Int)] = [("hsn", "HSN", 2), ("mrp", "MRP", 4), ("disc", "Disc %", 6), ("taxable", "Taxable", 7), ("gst", "GST %", 8)]

/// The columns printed, from the company's `print_hide_cols` setting ("hsn,mrp").
func printedColumns(_ co: JSON) -> [Int] {
    let hide = Set(co.str("print_hide_cols").split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) })
    let gone = Set(optionalColumns.filter { hide.contains($0.key) }.map(\.index))
    return (0..<10).filter { !gone.contains($0) }
}

/// One table row. `height` nil = fill the remaining height (the empty part of the table, so the column lines run to the bottom).
private func rowView(_ v: [String], _ g: Spec, height: CGFloat?, bold: Bool = false, cols: [Int] = Array(0..<10)) -> some View {
    HStack(spacing: 0) {
        ForEach(cols, id: \.self) { i in cell(v[i], i, g, bold: bold) }
    }
    .frame(height: height)
    .frame(maxHeight: height == nil ? .infinity : nil)
}

/// "150 pcs" of a 24-per-box item -> "6 box 6 pcs", plus pieces given free.
private func qtyText(_ l: JSON, pieces: Bool = false) -> String {
    var s = pieces ? "\(l.int("qty")) pcs" : Fmt.boxPcs(l.int("qty"), l.int("pcs_per_box"))
    let f = l.int("free_qty")
    if f > 0 { s += " +\(f) free" }
    return s
}

private func hRule(_ w: CGFloat = ruleLine) -> some View { Rectangle().fill(ink).frame(height: w) }
private func vRule(_ w: CGFloat = ruleLine) -> some View { Rectangle().fill(ink).frame(width: w) }

/// One copy of a bill (or debit note) on one page: everything inside a single ruled frame —
/// title strip, seller and bill details, Bill to, item table, tax summary and totals — with terms and signature below it.
@MainActor struct InvoiceSheetView: View {
    let inv: JSON
    let co: JSON
    let rows: Range<Int>
    let page: Int
    let pages: Int
    let copy: String
    var g: Spec = .half

    private var first: Bool { page == 0 }
    private var last: Bool { page == pages - 1 }
    /// "TAX INVOICE", or what the document says it is (a debit note prints on the same layouts as "DEBIT NOTE").
    private var docTitle: String {
        if !inv.str("doc_title").isEmpty { return inv.str("doc_title") }
        return co.str("print_title").isEmpty ? "TAX INVOICE" : co.str("print_title").uppercased()
    }
    private var noLabel: String { inv.str("doc_no_label").isEmpty ? "Invoice No." : inv.str("doc_no_label") }
    private var companyName: String { co.str("company_name").isEmpty ? co.str("name") : co.str("company_name") }
    private var cols: [Int] { printedColumns(co) }
    /// the item column says "Description of goods" unless the company changed it
    private var headingsFor: [String] { headings }
    private func on(_ key: String) -> Bool { co.str(key) != "0" }
    /// Settings › Printing › "Company and Bill to in CAPITALS"
    private func hc(_ s: String) -> String { co.str("print_caps_head") == "1" ? s.uppercased() : s }
    private var tableHeight: CGFloat { g.inner - (first ? g.headFirst : g.headNext) - g.foot - (last ? g.totals : 0) }

    private func t(_ s: String, _ size: CGFloat = 7, bold: Bool = false, weight: Font.Weight? = nil) -> Text {
        Text(s).font(.system(size: size * g.fs, weight: weight ?? (bold ? .bold : .regular)))
    }

    var body: some View {
        let lines = inv.list("lines")
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                if first { firstHeader } else { nextHeader }
                hRule(frameLine)
                // the item table: shaded heading row, light rule under every item, column lines down to the bottom
                VStack(spacing: 0) {
                    rowView(headingsFor, g, height: g.tableHead, bold: true, cols: cols).background(shade)
                    ForEach(Array(rows), id: \.self) { i in
                        let l = lines[i]
                        rowView(["\(i + 1)", Fmt.cut(co.str("print_caps") == "1" ? l.str("item_name").uppercased() : l.str("item_name"), g.fs > 1 ? 52 : 56), l.str("hsn"),
                                 qtyText(l, pieces: co.str("print_qty") == "pcs"),
                                 l.num("mrp") > 0 ? Fmt.qty(l.num("mrp")) : "", Fmt.amount(l.num("rate")),
                                 l.num("disc_pct") > 0 ? Fmt.qty(l.num("disc_pct")) : "", Fmt.amount(l.num("taxable")),
                                 Fmt.qty(l.num("gst_rate")), Fmt.amount(l.num("amount"))], g, height: g.rowH, cols: cols)
                    }
                    rowView(Array(repeating: "", count: 10), g, height: nil, cols: cols)
                }
                .frame(height: tableHeight, alignment: .top)
                .overlay(gridLines(rowCount: rows.count))
                if last { hRule(frameLine); totalsBlock }
            }
            .overlay(Rectangle().stroke(ink, lineWidth: frameLine))
            footer
        }
        .padding(g.m)
        .frame(width: g.w, height: g.h, alignment: .top)
        .background(Color.white)
        .foregroundStyle(ink)
        .environment(\.colorScheme, .light)
    }

    // MARK: header

    /// The top: seller on the left, buyer on the right, both in compact type (like a Marg bill), then one shaded line with the
    /// document title, number, date, salesman and payment. About 4 more item rows fit than with a three-band header.
    private var topBlock: some View {
        let contact = [co.str("company_phone").isEmpty ? "" : "Phone: \(co.str("company_phone"))",
                       co.str("state_code").isEmpty ? "" : "State code: \(co.str("state_code"))"].filter { !$0.isEmpty }.joined(separator: "   ")
        return HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                t(hc(companyName), 12, bold: true).lineLimit(1).minimumScaleFactor(0.6)
                if !co.str("print_tagline").isEmpty { t(hc(co.str("print_tagline")), 6.5).italic().lineLimit(1).minimumScaleFactor(0.7) }
                t(hc(co.str("company_address")), 6.5).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if !contact.isEmpty { t(hc(contact), 6.5).lineLimit(1).minimumScaleFactor(0.8) }
                if !co.str("company_gstin").isEmpty { t(hc("GSTIN: \(co.str("company_gstin"))"), 6.5, weight: .semibold).lineLimit(1) }
            }
            .padding(.horizontal, 5).padding(.vertical, 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            vRule()
            VStack(alignment: .leading, spacing: 1) {
                // the buyer stands out: "Bill to" and the party in bold, larger than the seller's details
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    t(hc(inv.str("doc_title") == "DEBIT NOTE" ? "Supplier:" : "Bill to:"), 7.5, bold: true)
                    t(hc(inv.str("party_name").isEmpty ? "Cash customer" : inv.str("party_name")), 11.5, bold: true).lineLimit(1).minimumScaleFactor(0.6)
                }
                ForEach(Array(buyerLines.enumerated()), id: \.offset) { _, l in
                    t(hc(l), 7.5, weight: l.hasPrefix("GSTIN") ? .bold : .semibold).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            .padding(.horizontal, 5).padding(.vertical, 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: g.sellerBand)
        .clipped()
    }

    /// Buyer details under the name, at most four short lines; empty details are left out.
    private var buyerLines: [String] {
        if !on("print_party") { return [] }   // Settings › Printing › party's address and numbers
        var mob: [String] = []
        for m in ([inv.str("party_phone")] + inv.str("party_mobiles").split(whereSeparator: { ",;/".contains($0) }).map(String.init)) {
            let x = m.trimmingCharacters(in: .whitespaces)
            if !x.isEmpty && !mob.contains(x) { mob.append(x) }
        }
        if !inv.str("party_tel").isEmpty { mob.append(inv.str("party_tel")) }
        func join(_ parts: [(String, String)]) -> String {
            parts.filter { !$0.1.trimmingCharacters(in: .whitespaces).isEmpty }.map { "\($0.0): \($0.1)" }.joined(separator: "   ")
        }
        return [
            inv.str("party_address"),
            join([("GSTIN", inv.str("party_gstin")), ("State", inv.str("party_state"))]),
            join([("Phone", mob.joined(separator: ", "))]),
            join([("PAN", inv.str("party_pan")), ("Email", inv.str("party_email")), ("FSSAI", inv.str("party_fssai"))]),
        ].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// One shaded line: title, number, date, salesman, payment (or a debit note's reference), and which copy it is.
    private var infoRow: some View {
        HStack(spacing: 10) {
            t(docTitle, 8.5, bold: true)
            ForEach(Array(details.enumerated()), id: \.offset) { _, kv in
                HStack(spacing: 3) {
                    t(kv.0 + ":", 6.5).foregroundStyle(muted)
                    t(kv.1, 7.5, bold: kv.2).lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            Spacer(minLength: 4)
            t(copy, 6, bold: true).lineLimit(1)
        }
        .padding(.horizontal, 5)
        .frame(height: g.strip)
        .background(shade)
    }

    /// (label, value, bold) items of the info line.
    private var details: [(String, String, Bool)] {
        var out: [(String, String, Bool)] = [(noLabel, inv.str("invoice_no"), true), ("Date", Fmt.dmy(inv.str("date")), true)]
        if inv.has("doc_line") {
            if !inv.str("doc_line").isEmpty { out.append(("Ref", inv.str("doc_line"), false)) }
        } else {
            if on("print_salesman") { out.append(("Salesman", inv.str("salesman_name").isEmpty ? "-" : inv.str("salesman_name"), false)) }
            let mode = inv.str("pay_mode").capitalized
            let type = inv.str("sale_type").capitalized
            if on("print_payment") { out.append(("Payment", [mode, type.isEmpty ? "" : "\(type) sale"].filter { !$0.isEmpty }.joined(separator: " · "), false)) }
            if !inv.str("ewb_no").isEmpty { out.append(("E-way bill", inv.str("ewb_no"), true)) }
        }
        return out
    }

    private var firstHeader: some View {
        VStack(spacing: 0) {
            topBlock
            hRule()
            infoRow
        }
        .frame(height: g.headFirst, alignment: .top)
    }

    private var nextHeader: some View {
        HStack {
            t("\(docTitle)  ·  \(noLabel) \(inv.str("invoice_no"))  ·  \(Fmt.dmy(inv.str("date")))  (continued)", 8.5, bold: true)
            Spacer()
            t(copy, 6.5, bold: true)
        }
        .padding(.horizontal, 6)
        .frame(height: g.headNext)
        .background(shade)
    }

    /// Column and row lines are drawn as exact vector strokes over the table, so they print crisp and always line up with the text.
    private func gridLines(rowCount: Int) -> some View {
        let g = self.g
        return Canvas { ctx, size in
            let ws = self.cols.map { widths[$0] }
            let fixed = ws.compactMap { $0 }.reduce(0, +) * g.cw
            var x: CGFloat = 0
            var cols = Path()
            for w in ws.dropLast() {
                x += w.map { $0 * g.cw } ?? (size.width - fixed)
                cols.move(to: CGPoint(x: x, y: 0))
                cols.addLine(to: CGPoint(x: x, y: size.height))
            }
            ctx.stroke(cols, with: .color(Color.black.opacity(0.55)), lineWidth: 0.5)
            var rowsPath = Path()
            if rowCount > 0 {
                for k in 1...rowCount {
                    let y = g.tableHead + CGFloat(k) * g.rowH
                    rowsPath.move(to: CGPoint(x: 0, y: y))
                    rowsPath.addLine(to: CGPoint(x: size.width, y: y))
                }
            }
            ctx.stroke(rowsPath, with: .color(Color.black.opacity(0.22)), lineWidth: 0.4)
            var head = Path()
            head.move(to: CGPoint(x: 0, y: g.tableHead))
            head.addLine(to: CGPoint(x: size.width, y: g.tableHead))
            ctx.stroke(head, with: .color(.black), lineWidth: ruleLine)
        }
        .allowsHitTesting(false)
    }

    // MARK: totals and footer

    private var totalsBlock: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 1.5) {
                if on("print_gst_table") { gstTable }
                Spacer(minLength: 2)
                bankBlock
                if co.str("print_balance") == "1" && inv.has("party_prev_balance") {
                    t("Previous balance \(balanceText(inv.num("party_prev_balance")))   ·   This bill \(Fmt.money(inv.num("total") - inv.num("paid")))   ·   Now due \(balanceText(inv.num("party_balance_after")))", 6.5, weight: .semibold)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                if on("print_words") {
                    t("Amount in words", 6, bold: true).foregroundStyle(muted)
                    t(inv.str("amount_words"), 7.5, weight: .semibold).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            sumColumn
                .frame(maxHeight: .infinity)
                // the line between "Amount in words" and the totals, down beside GRAND TOTAL to the frame
                .overlay(alignment: .leading) { vRule(frameLine) }
        }
        .frame(height: g.totals, alignment: .top)
    }

    /// Bank details, one per line with the labels lined up (BANK NAME:, ACCOUNT NUMBER: …).
    @ViewBuilder private var bankBlock: some View {
        let rows = bankRows(co)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        t(r.0 + ":", 6.5, bold: true).lineLimit(1).minimumScaleFactor(0.8).frame(width: 86 * g.cw, alignment: .leading)
                        t(r.1, 7, weight: .semibold).lineLimit(r.0 == "ADDRESS" ? 2 : 1).minimumScaleFactor(0.75).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.bottom, 2)
        }
    }

    /// Rate-wise GST: one row per GST rate on the bill.
    private var gstTable: some View {
            VStack(alignment: .leading, spacing: 1.5) {
                HStack(spacing: 0) {
                    ForEach(["GST %", "Items", "Taxable", "CGST", "SGST", "IGST"], id: \.self) { h in
                        t(h, 6.5, bold: true).frame(width: (h == "Items" ? 32 : 50) * g.cw, alignment: .trailing)
                    }
                }
                .padding(.bottom, 1)
                .overlay(alignment: .bottom) { Rectangle().fill(muted).frame(height: 0.4) }
                ForEach(inv.list("gst_summary")) { s in
                    HStack(spacing: 0) {
                        t(Fmt.qty(s.num("rate")), 6.5).frame(width: 50 * g.cw, alignment: .trailing)
                        t("\(Int(s.num("rows")))", 6.5).frame(width: 32 * g.cw, alignment: .trailing)
                        t(Fmt.amount(s.num("taxable")), 6.5).frame(width: 50 * g.cw, alignment: .trailing)
                        t(Fmt.amount(s.num("cgst")), 6.5).frame(width: 50 * g.cw, alignment: .trailing)
                        t(Fmt.amount(s.num("sgst")), 6.5).frame(width: 50 * g.cw, alignment: .trailing)
                        t(Fmt.amount(s.num("igst")), 6.5).frame(width: 50 * g.cw, alignment: .trailing)
                    }
                }
            }
    }

    /// The totals on the right, ending in the grand total.
    private var sumColumn: some View {
            VStack(spacing: 0) {
                VStack(spacing: 1) {
                    sumRow("Items total", inv.num("subtotal"))
                    if inv.num("discount") > 0 { sumRow("Less discount", -inv.num("discount")) }
                    sumRow("Taxable value", inv.num("taxable"))
                    if inv.num("cgst") > 0 { sumRow("CGST", inv.num("cgst")); sumRow("SGST", inv.num("sgst")) }
                    if inv.num("igst") > 0 { sumRow("IGST", inv.num("igst")) }
                    if abs(inv.num("round_off")) > 0 { sumRow("Round off", inv.num("round_off")) }
                    if inv.num("paid") > 0 && inv.num("paid") < inv.num("total") - 0.005 { sumRow("Paid", inv.num("paid")) }
                }
                .padding(.horizontal, 6).padding(.vertical, 4)
                Spacer(minLength: 0)
                hRule()
                HStack {
                    t(inv.str("doc_title") == "DEBIT NOTE" ? "NOTE TOTAL" : "GRAND TOTAL", 8.5, bold: true)
                    Spacer()
                    t("₹ " + Fmt.amount(inv.num("total")), 11, bold: true)
                }
                .padding(.horizontal, 6)
                .frame(height: 19 * g.fs)
                .background(shade)
            }
            .frame(width: 186 * g.cw)
    }

    private func sumRow(_ a: String, _ v: Double) -> some View {
        HStack { t(a, 7).foregroundStyle(muted); Spacer(); t(Fmt.amount(v), 7.5) }
    }

    /// Terms on the left, the company's signature block on the right, page number in the middle.
    private var footer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                if on("print_terms") && !co.str("invoice_terms").isEmpty {
                    t("Terms", 6, bold: true).foregroundStyle(muted)
                    t(co.str("invoice_terms"), 6.5).lineLimit(co.str("print_bank").isEmpty ? 2 : 1).fixedSize(horizontal: false, vertical: true)
                }
                if !co.str("print_bank").isEmpty { t(co.str("print_bank"), 6.5, weight: .semibold).lineLimit(1).minimumScaleFactor(0.7) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 1) {
                if !co.str("print_note").isEmpty { t(co.str("print_note"), 7, bold: true).lineLimit(1).minimumScaleFactor(0.7) }
                t(pages > 1 ? "Page \(page + 1) of \(pages)" : "", 6.5).foregroundStyle(muted)
            }
            VStack(alignment: .trailing, spacing: 0) {
                if on("print_signature") {
                    t(hc("For \(companyName)"), 7, bold: true).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    t("Authorised Signatory", 6.5).foregroundStyle(muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 2).padding(.top, 4)
        .frame(height: g.foot, alignment: .top)
    }
}

/// Two copies on one A4 sheet with a dashed cut line between them.
@MainActor struct TwoUpView: View {
    let inv: JSON, co: JSON
    var g: Spec = .half
    var body: some View {
        VStack(spacing: 0) {
            InvoiceSheetView(inv: inv, co: co, rows: 0..<inv.list("lines").count, page: 0, pages: 1, copy: copyLabelsFor(co)[0], g: g)
            InvoiceSheetView(inv: inv, co: co, rows: 0..<inv.list("lines").count, page: 0, pages: 1, copy: copyLabelsFor(co)[1], g: g)
        }
        .frame(width: g.w, height: g.h * 2)
        .overlay(alignment: .top) {
            Canvas { ctx, size in
                var p = Path()
                p.move(to: CGPoint(x: 0, y: 0.5)); p.addLine(to: CGPoint(x: size.width, y: 0.5))
                ctx.stroke(p, with: .color(Color.black.opacity(0.45)), style: StrokeStyle(lineWidth: 0.5, dash: [4, 3]))
            }
            .frame(height: 1).offset(y: g.h)
        }
    }
}

// MARK: - Rendering

/// Draws SwiftUI pages into a PDF. macOS 13+ draws vector text; macOS 12 (Monterey) draws each page as a sharp bitmap instead.
@MainActor
func renderPDF(pages: [AnyView], size: CGSize) -> PDFDocument? {
    if #available(macOS 13.0, *) { return renderVectorPDF(pages: pages, size: size) }
    return renderBitmapPDF(pages: pages, size: size)
}

@available(macOS 13.0, *)
@MainActor
private func renderVectorPDF(pages: [AnyView], size: CGSize) -> PDFDocument? {
    let data = NSMutableData()
    var box = CGRect(origin: .zero, size: size)
    guard let consumer = CGDataConsumer(data: data), let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
    for page in pages {
        let r = ImageRenderer(content: page.frame(width: size.width, height: size.height))
        r.proposedSize = ProposedViewSize(size)
        r.render { _, draw in
            ctx.beginPDFPage(nil)
            draw(ctx)
            ctx.endPDFPage()
        }
    }
    ctx.closePDF()
    return PDFDocument(data: data as Data)
}

@MainActor
private func renderBitmapPDF(pages: [AnyView], size: CGSize) -> PDFDocument? {
    let doc = PDFDocument()
    let scale: CGFloat = 4   // about 290 dpi
    for page in pages {
        let host = NSHostingView(rootView: page.frame(width: size.width, height: size.height))
        host.frame = NSRect(origin: .zero, size: size)
        let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        win.contentView = host
        host.layoutSubtreeIfNeeded()
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        let img = NSImage(size: size)
        img.addRepresentation(rep)
        if let p = PDFPage(image: img) { doc.insert(p, at: doc.pageCount) }
    }
    return doc.pageCount > 0 ? doc : nil
}

@MainActor
func invoicePDF(_ inv: JSON, company: JSON, layout: PrintLayout) -> PDFDocument? {
    let n = inv.list("lines").count
    let g: Spec = (layout.isFullPage ? Spec.full : Spec.half).scaled(printScale(company)).withBank(company)
    if layout == .a4TwoUp && paginate(n, g).count == 1 {
        return renderPDF(pages: [AnyView(TwoUpView(inv: inv, co: company, g: g))], size: CGSize(width: g.w, height: g.h * 2))
    }
    // a long invoice does not fit twice on one sheet: fall back to one copy per half sheet
    let labels = copyLabelsFor(company)
    let copies = (layout == .single || layout == .a4FullOriginal) ? [labels[0]] : labels
    let ranges = paginate(n, g)
    var pages: [AnyView] = []
    for c in copies {
        for (i, r) in ranges.enumerated() {
            pages.append(AnyView(InvoiceSheetView(inv: inv, co: company, rows: r, page: i, pages: ranges.count, copy: c, g: g)))
        }
    }
    return renderPDF(pages: pages, size: g.size)
}

// MARK: - Receipt voucher

@MainActor struct VoucherSheetView: View {
    let v: JSON
    let copy: String

    private func t(_ s: String, _ size: CGFloat = 9, bold: Bool = false) -> Text { Text(s).font(.system(size: size, weight: bold ? .bold : .regular)) }
    private func line(_ a: String, _ b: String) -> some View { HStack(alignment: .top) { t(a + ":", 9, bold: true).frame(width: 90, alignment: .leading); t(b, 9) } }

    var body: some View {
        let co = v.obj("company"), party = v.obj("party")
        let received = v.str("direction") == "RECEIVED"
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    t(co.str("name"), 13, bold: true)
                    t(co.str("address"), 7)
                    t((co.str("gstin").isEmpty ? "" : "GSTIN: \(co.str("gstin"))   ") + (co.str("phone").isEmpty ? "" : "Ph: \(co.str("phone"))"), 7)
                }
                Spacer()
                t(copy, 7, bold: true).padding(.horizontal, 4).padding(.vertical, 2).overlay(Rectangle().stroke(Color.black, lineWidth: 0.6))
            }
            .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 4)
            t(v.str("title").uppercased(), 11, bold: true).frame(maxWidth: .infinity).padding(.vertical, 4)
                .background(Color.gray.opacity(0.25))
            VStack(alignment: .leading, spacing: 5) {
                HStack { t("Voucher No: \(v.str("no"))", 9, bold: true); Spacer(); t("Date: \(Fmt.dmy(v.str("date")))", 9, bold: true) }
                line(received ? "Received from" : "Paid to", party.str("name"))
                if !party.str("address").isEmpty { line("Address", party.str("address")) }
                if !party.str("gstin").isEmpty { line("GSTIN", party.str("gstin")) }
                line("Payment mode", v.str("mode") + (v.str("reference").isEmpty ? "" : "   Ref: \(v.str("reference"))"))
                line("Amount", "₹ " + Fmt.amount(v.num("amount")))
                line("In words", v.str("amount_words"))
                line("Balance after", balanceText(v.num("balance")))
            }
            .padding(.horizontal, 10).padding(.top, 8)
            Spacer()
            HStack { t("Receiver's signature", 7); Spacer(); t("Authorised signatory", 7) }.padding(.horizontal, 10).padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(Rectangle().stroke(Color.black, lineWidth: 1.1))
        .padding(Spec.half.m)
        .frame(width: Spec.half.w, height: Spec.half.h, alignment: .top)
        .background(Color.white)
        .foregroundStyle(Color.black)
        .environment(\.colorScheme, .light)
    }
}

// MARK: - Jobs, preview, printing

struct PrintJob: Identifiable {
    let id = UUID()
    let title: String
    let fileName: String
    let document: PDFDocument
    /// sale bills in this job: marked printed once the job has gone to the printer
    var invoiceIds: [Int] = []
}

/// Remembers which bills have been printed (All Bills › Not printed lists the rest).
@MainActor
func markPrinted(_ ids: [Int], app: AppModel) {
    guard !ids.isEmpty else { return }
    Task { _ = try? await API.objRaw("POST", "/invoices/printed", body: ["ids": ids]) }
}

/// Several bills in one print job, in the order given, each with its copies, e.g. the bills kept to print later.
@MainActor
func printInvoices(_ ids: [Int], app: AppModel) async {
    guard !ids.isEmpty else { return }
    if ids.count == 1 { await printInvoice(ids[0], app: app, forcePreview: true); return }
    await app.guarded {
        let layout = PrintLayout.parse(app.settings.str("print_layout"))
        let all = PDFDocument()
        var nos: [String] = []
        for id in ids {
            let inv = try await API.obj("GET", "/invoices/\(id)")
            guard let pdf = invoicePDF(inv, company: app.settings, layout: layout) else { continue }
            for k in 0..<pdf.pageCount { if let pg = pdf.page(at: k) { all.insert(pg, at: all.pageCount) } }
            nos.append(inv.str("invoice_no"))
        }
        guard all.pageCount > 0 else { throw APIError(message: "Could not prepare the bills for printing", status: 0, code: nil) }
        let job = PrintJob(title: "\(nos.count) bills (\(nos.first ?? "") … \(nos.last ?? ""))", fileName: "Bills-\(nos.count).pdf", document: all, invoiceIds: ids)
        showPrintJob(job, app: app)
    }
}

/// A print preview cannot open on top of another sheet (the bill or voucher window), so this waits until that window has closed.
/// The preview opens in its own window, so it appears at once even while a bill, receipt or other popup is still closing.
@MainActor private var previewWindows: [NSWindow] = []

@MainActor
func showPrintJob(_ job: PrintJob, app: AppModel) {
    let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 640),
                       styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    win.title = job.title
    win.isReleasedWhenClosed = false
    win.contentView = NSHostingView(rootView: PrintPreviewSheet(job: job, onClose: { [weak win] in win?.close() }).environmentObject(app))
    win.center()
    previewWindows.append(win)
    let closing = ObjectIdentifier(win)
    NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: win, queue: .main) { _ in
        Task { @MainActor in previewWindows.removeAll { ObjectIdentifier($0) == closing } }
    }
    NSApp.activate(ignoringOtherApps: true)
    win.makeKeyAndOrderFront(nil)
}

@MainActor
func printInvoice(_ id: Int, app: AppModel, forcePreview: Bool = false) async {
    await app.guarded {
        let inv = try await API.obj("GET", "/invoices/\(id)")
        let layout = PrintLayout.parse(app.settings.str("print_layout"))
        guard let pdf = invoicePDF(inv, company: app.settings, layout: layout) else { throw APIError(message: "Could not prepare the invoice for printing", status: 0, code: nil) }
        let printer = app.settings.str("print_printer")
        if app.settings.str("print_auto") == "1" && !forcePreview && !printer.isEmpty {
            if runPrint(pdf, printer: printer, silent: true) { markPrinted([id], app: app); app.notify("Sent \(inv.str("invoice_no")) to \(printer).") }
            return
        }
        showPrintJob(PrintJob(title: "Invoice \(inv.str("invoice_no"))", fileName: "\(inv.str("invoice_no")).pdf", document: pdf, invoiceIds: [id]), app: app)
    }
}

/// A debit note printed on the bill layouts, headed DEBIT NOTE, its rows in pieces like a sale bill.
@MainActor
func debitNotePDF(_ d: JSON, company: JSON, layout: PrintLayout) -> PDFDocument? {
    var raw = d.raw
    raw["lines"] = d.raw["print_lines"] ?? [Any]()
    return invoicePDF(JSON(raw), company: company, layout: layout)
}

@MainActor
func printDebitNote(_ id: Int, app: AppModel) async {
    await app.guarded {
        let d = try await API.obj("GET", "/debit-notes/\(id)")
        guard let pdf = debitNotePDF(d, company: app.settings, layout: PrintLayout.parse(app.settings.str("print_layout"))) else {
            throw APIError(message: "Could not prepare the debit note for printing", status: 0, code: nil)
        }
        showPrintJob(PrintJob(title: "Debit note \(d.str("note_no"))", fileName: "\(d.str("note_no").replacingOccurrences(of: "/", with: "-")).pdf", document: pdf), app: app)
    }
}

@MainActor
func printVoucher(_ no: String, app: AppModel) async {
    await app.guarded {
        // the number holds slashes (RCT/26-27/00001): encode them too, or the server sees extra path segments and answers 404
        var segment = CharacterSet.alphanumerics
        segment.insert(charactersIn: "-._~")
        let v = try await API.obj("GET", "/vouchers/\(no.addingPercentEncoding(withAllowedCharacters: segment) ?? no)")
        let pages = copyLabels.map { AnyView(VoucherSheetView(v: v, copy: $0)) }
        guard let pdf = renderPDF(pages: pages, size: CGSize(width: Spec.half.w, height: Spec.half.h)) else { return }
        showPrintJob(PrintJob(title: "Receipt \(no)", fileName: "\(no).pdf", document: pdf), app: app)
    }
}

/// Prints through the macOS print system. `silent` skips the print panel (used for the saved printer).
/// The paper follows the layout: A5 / half-A4 sheets for the half-sheet layouts, A4 for the rest.
@MainActor
@discardableResult
func runPrint(_ pdf: PDFDocument, printer: String, silent: Bool) -> Bool {
    let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
    if !printer.isEmpty, let p = NSPrinter(name: printer) { info.printer = p }
    info.topMargin = 0; info.bottomMargin = 0; info.leftMargin = 0; info.rightMargin = 0
    // Half-sheet bills go out on A5 / half-A4 paper (one copy per cut sheet), landscape; the A4 layouts on A4, portrait.
    // The page already carries its own white margin, so it is printed at its real size.
    let size = pdf.page(at: 0)?.bounds(for: .mediaBox).size ?? Paper.a4
    if size.width > size.height {
        info.paperSize = Paper.a5
        info.orientation = .landscape
    } else {
        info.paperSize = Paper.a4
        info.orientation = .portrait
    }
    guard let op = pdf.printOperation(for: info, scalingMode: .pageScaleDownToFit, autoRotate: true) else { return false }
    op.showsPrintPanel = !silent
    op.showsProgressPanel = !silent
    return op.run()
}

@MainActor struct PrintPreviewSheet: View {
    @EnvironmentObject private var app: AppModel
    let job: PrintJob
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(job.title).font(.title3.weight(.semibold))
                Spacer()
                Text("\(job.document.pageCount) page\(job.document.pageCount == 1 ? "" : "s")").foregroundStyle(.secondary)
            }
            .padding(16)
            PDFPreview(document: job.document)
            HStack {
                Button("Save PDF…") {
                    if let d = job.document.dataRepresentation(), let url = Files.save(job.fileName, data: d) { app.notify("Saved \(url.lastPathComponent)") }
                }
                Spacer()
                Button("Close") { onClose() }.keyboardShortcut(.cancelAction)
                Button("Print…") {
                    if runPrint(job.document, printer: app.settings.str("print_printer"), silent: false) { markPrinted(job.invoiceIds, app: app) }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 820, height: 640)
    }
}
