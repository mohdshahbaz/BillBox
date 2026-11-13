import SwiftUI
import UIKit
import PDFKit

// MARK: - Layouts and geometry (identical to the Mac)

enum PrintLayout: String, CaseIterable, Identifiable {
    case halfSheets, a4TwoUp, single, a4Full, a4FullOriginal
    var id: String { rawValue }
    var label: String {
        switch self {
        case .halfSheets: return "Half sheets (A5): Original on one A5 sheet, Duplicate on the next"
        case .a4TwoUp: return "A4 sheet: Original on top, Duplicate below"
        case .single: return "Half sheet (A5): Original copy only"
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
/// `m` is the white margin all round (about 4 mm on a half sheet, 5 mm on A4) so nothing falls in the printer's unprintable edge.
struct Spec {
    let w: CGFloat, h: CGFloat, m: CGFloat
    let rowH: CGFloat, tableHead: CGFloat, foot: CGFloat, totals: CGFloat
    /// first-page header: seller and buyer side by side (sellerBand), then the info line (strip); buyerBand is spare (0)
    let strip: CGFloat, sellerBand: CGFloat, buyerBand: CGFloat
    let headNext: CGFloat
    let fs: CGFloat
    let cw: CGFloat

    var headFirst: CGFloat { strip + sellerBand + buyerBand + 0.6 }
    /// height inside the margins, less the ruled lines between the header, table, totals and footer
    var inner: CGFloat { h - 2 * m - 3.6 }
    /// width inside the margins: the one width every block of the bill (header, table, totals, footer) is held to
    var contentW: CGFloat { w - 2 * m }
    var size: CGSize { CGSize(width: w, height: h) }
    func cap(first: Bool, last: Bool) -> Int {
        Int(((inner - (first ? headFirst : headNext) - tableHead - foot - (last ? totals : 0)) / rowH).rounded(.down))
    }

    /// The same page with text (and the rows holding it) made larger or smaller.
    func scaled(_ k: CGFloat) -> Spec {
        k == 1 ? self : Spec(w: w, h: h, m: m, rowH: rowH * k, tableHead: tableHead * k, foot: foot * k, totals: totals * k,
                             strip: strip * k, sellerBand: sellerBand * k, buyerBand: buyerBand, headNext: headNext * k, fs: fs * k, cw: cw)
    }

    /// The bank details sit in the footer, in the room it already has. With compact totals (Settings › Printing, on unless
    /// switched off) the totals take only the height their lines need, and the rest goes to item rows.
    func withBank(_ co: JSON, _ inv: JSON = JSON()) -> Spec {
        guard compactPrint(co) else { return self }
        func on(_ k: String) -> Bool { co.str(k).isEmpty || co.str(k) != "0" }
        let f = fs
        var n = 1                                                               // items total
        if inv.num("discount") > 0 { n += 2 }                                   // less discount, taxable value
        if gstByRate(co) { n += gstRateLines(inv).count }
        else {
            if inv.num("cgst") > 0 { n += 2 }
            if inv.num("igst") > 0 { n += 1 }
        }
        if inv.num("paid") > 0 && inv.num("paid") < inv.num("total") - 0.005 { n += 1 }
        let right = CGFloat(n) * 9 * f + 6 + 17 * f
        let left = leftOther(co, inv, f)
        let sig: CGFloat = signatureInBand(co) || receiverInBand(co) ? 26 * f : 0
        let need = (max(right, left, sig) + 2).rounded(.up)
        let banded = Spec(w: w, h: h, m: m, rowH: rowH, tableHead: tableHead, foot: foot, totals: min(totals, need),
                          strip: strip, sellerBand: sellerBand, buyerBand: buyerBand, headNext: headNext, fs: fs, cw: cw)
        // the footer then holds one line of terms; kept full height when the bank lines still have to print there
        guard signatureInBand(co), bankLines(co).isEmpty || bankTabFits(co, inv, banded) else { return banded }
        return Spec(w: w, h: h, m: m, rowH: rowH, tableHead: tableHead, foot: footerEmpty(co) ? 0 : (foot * 0.6).rounded(), totals: banded.totals,
                    strip: strip, sellerBand: sellerBand, buyerBand: buyerBand, headNext: headNext, fs: fs, cw: cw)
    }

    /// The same page with another white margin all round (the BillBox design keeps it small, so more of the sheet is bill).
    func withMargin(_ nm: CGFloat) -> Spec {
        Spec(w: w, h: h, m: nm, rowH: rowH, tableHead: tableHead, foot: foot, totals: totals,
             strip: strip, sellerBand: sellerBand, buyerBand: buyerBand, headNext: headNext, fs: fs, cw: cw)
    }

    func withBankBlock(_ co: JSON) -> Spec {
        let rows = bankRows(co)
        guard !rows.isEmpty else { return self }
        let extra = CGFloat(rows.count) * 8.4 * fs + (rows.contains { $0.0 == "ADDRESS" && $0.1.count > 70 } ? 8.4 * fs : 0) + 4
        return Spec(w: w, h: h, m: m, rowH: rowH, tableHead: tableHead, foot: foot, totals: totals + extra,
                    strip: strip, sellerBand: sellerBand, buyerBand: buyerBand, headNext: headNext, fs: fs, cw: cw)
    }

    static let half = Spec(w: 595.276, h: 420.945, m: 12, rowH: 12, tableHead: 15, foot: 26, totals: 91,
                           strip: 15, sellerBand: 56, buyerBand: 0, headNext: 18, fs: 1, cw: 1)
    static let full = Spec(w: 595.276, h: 841.89, m: 14, rowH: 16, tableHead: 20, foot: 32, totals: 112,
                           strip: 19, sellerBand: 68, buyerBand: 0, headNext: 24, fs: 1.15, cw: 1.0)
}

/// Settings › Printing › Compact totals (on unless switched off): the GST and bank details take less room, for more item rows.
func compactPrint(_ co: JSON) -> Bool { co.str("print_compact") != "0" }
/// With compact totals the signature ("For <company>" / Authorised Signatory) sits in the totals band, right of the bank details
/// behind a ruled line, and the footer keeps one line of terms: the room saved goes to item rows.
func signatureInBand(_ co: JSON) -> Bool { compactPrint(co) && co.str("print_signature") != "0" }
/// Width of that signature block in the totals band.
func signatureBandWidth(_ g: Spec) -> CGFloat { 100 * g.cw }
/// Settings › Printing › Receiver's signature box: an empty box for the buyer's signature, between the bank details and yours.
func receiverInBand(_ co: JSON) -> Bool { compactPrint(co) && co.str("print_receiver") != "0" }
func receiverBandWidth(_ g: Spec) -> CGFloat { 86 * g.cw }
/// Nothing left for the footer row (terms off or empty, no payment line, no note): the row is left out and its room goes to items.
func footerEmpty(_ co: JSON) -> Bool {
    (co.str("print_terms") == "0" || co.str("invoice_terms").trimmingCharacters(in: .whitespaces).isEmpty)
        && co.str("print_bank").isEmpty && co.str("print_note").isEmpty
}

/// The bank details printed above the amount in words, one per line, in this order; empty ones are left out.
let bankFields: [(key: String, label: String, title: String)] = [
    ("bank_name", "BANK NAME", "Bank name"), ("bank_ac_name", "ACCOUNT NAME", "Account name"), ("bank_ac_no", "ACCOUNT NUMBER", "Account number"),
    ("bank_ifsc", "IFSC CODE", "IFSC code"), ("bank_branch", "BRANCH NAME", "Branch name"), ("bank_branch_code", "BRANCH CODE", "Branch code"),
    ("bank_address", "ADDRESS", "Branch address"),
]
/// The bank details in at most three short lines of (label, value) pairs, for the footer:
///   Bank: … · A/c name: …  /  A/c no.: … · IFSC: …  /  Branch: … (code) · …address
func bankLines(_ co: JSON) -> [[(String, String)]] {
    if co.str("print_bank_block") == "0" { return [] }
    func v(_ k: String) -> String { co.str(k).trimmingCharacters(in: .whitespacesAndNewlines) }
    let branch = v("bank_branch") + (v("bank_branch_code").isEmpty ? "" : (v("bank_branch").isEmpty ? "Code " : " (") + v("bank_branch_code") + (v("bank_branch").isEmpty ? "" : ")"))
    let lines: [[(String, String)]] = [
        [("Bank", v("bank_name")), ("A/c name", v("bank_ac_name"))],
        [("A/c no.", v("bank_ac_no")), ("IFSC", v("bank_ifsc"))],
        [("Branch", branch), ("", v("bank_address"))],
    ]
    return lines.map { $0.filter { !$0.1.isEmpty } }.filter { !$0.isEmpty }
}

/// One line of bank details: bold labels, values after them, " · " between.
func bankLineText(_ pairs: [(String, String)], size: CGFloat, serif: Bool = false) -> Text {
    let design: Font.Design = serif ? .serif : .default
    var t = Text("")
    for (i, p) in pairs.enumerated() {
        if i > 0 { t = t + Text("  ·  ").font(.system(size: size, design: design)) }
        if !p.0.isEmpty { t = t + Text(p.0 + ": ").font(.system(size: size, weight: .bold, design: design)) }
        t = t + Text(p.1).font(.system(size: size, weight: .medium, design: design))
    }
    return t
}

/// Settings › Printing › Bank details size: how big the bank block prints beside "Amount in words" - the text size and the share of the
/// band's left side the block gets (the words take the rest, so a bigger block means a narrower "Amount in words").
func bankSize(_ co: JSON) -> (scale: CGFloat, width: CGFloat) {
    switch co.str("print_bank_size") {
    case "s": return (0.9, 0.56)
    case "l": return (1.15, 0.66)
    case "xl": return (1.3, 0.70)
    default: return (1.0, 0.62)
    }
}
/// The bank details as (label, value) rows for the aligned block above "Amount in words": Bank, A/c name, A/c no., IFSC, Branch, Address.
func bankTabRows(_ co: JSON) -> [(String, String)] { bankLines(co).flatMap { $0 }.map { ($0.0.isEmpty ? "Address" : $0.0, $0.1) } }
/// Height of that block: a small heading and one line per row.
func bankTabHeight(_ co: JSON, _ fs: CGFloat) -> CGFloat { let n = bankTabRows(co).count; return n == 0 ? 0 : CGFloat((n + 1) / 2) * bankRowH * fs * bankSize(co).scale }
/// Height of one bank row in the totals band.
let bankRowH: CGFloat = 7.0
/// Height of the left side of the totals band above "Amount in words": GST table and balance line.
func leftTop(_ co: JSON, _ inv: JSON, _ f: CGFloat) -> CGFloat {
    func on(_ k: String) -> Bool { co.str(k).isEmpty || co.str(k) != "0" }
    var left: CGFloat = 8
    if on("print_gst_table") { let n = hsnGst(inv).count; left += CGFloat(max(1, n) + 1 + (n > 1 ? 1 : 0)) * 8.6 * f + 3 }
    if co.str("print_balance") == "1" && inv.has("party_prev_balance") { left += 9 * f }
    return left
}
/// Height the left side of the band needs in all: the bank block shares the height of "Amount in words".
func leftOther(_ co: JSON, _ inv: JSON, _ f: CGFloat) -> CGFloat {
    let words: CGFloat = co.str("print_words") != "0" ? 6.5 * f + 2 * 8.5 * f : 0
    return leftTop(co, inv, f) + max(words, bankTabHeight(co, f))
}
/// Rows per column of the bank block: one column when every row fits the free height of the band (above and beside "Amount in words"), else two.
func bankTabPer(_ co: JSON, _ inv: JSON, _ g: Spec) -> Int {
    let n = bankTabRows(co).count
    if n == 0 { return 0 }
    let fit = Int((g.totals - leftTop(co, inv, g.fs) - 2) / (bankRowH * g.fs * bankSize(co).scale))
    return n <= fit ? n : (n + 1) / 2
}
/// True when the bank block fits in the totals band of this page design (otherwise the bank lines stay in the footer).
func bankTabFits(_ co: JSON, _ inv: JSON, _ g: Spec) -> Bool {
    bankTabHeight(co, g.fs) > 0 && leftOther(co, inv, g.fs) + 2 <= g.totals + 0.5 && bankTabWide(co, inv, g)
}
/// Smallest scale a bank value may shrink to in the totals band; below that the bank lines go to the footer instead.
let bankValueMinScale: CGFloat = 0.6
/// True when every bank value fits its column of the totals band at `bankValueMinScale` or more, so no account number or
/// IFSC is ever cut off with "…". The widths are the ones `InvoicePage` uses (totals column, signature and receiver boxes,
/// the bank block's share). Text width is estimated at 0.6 em per character (semibold, digits and capitals).
func bankTabWide(_ co: JSON, _ inv: JSON, _ g: Spec) -> Bool {
    let rows = bankTabRows(co)
    guard !rows.isEmpty else { return false }
    let sig = signatureInBand(co), recv = receiverInBand(co)
    let sumW = (sig || recv ? 176 : 186) * g.cw
    let leftW = g.contentW - sumW - 12 - (sig ? signatureBandWidth(g) : 0) - (recv ? receiverBandWidth(g) : 0)
    let share: CGFloat = recv ? 0.66 : sig ? min(0.8, bankSize(co).width + 0.12) : bankSize(co).width
    let sc = bankSize(co).scale
    let per = max(1, bankTabPer(co, inv, g))
    let cols = CGFloat((rows.count + per - 1) / per)
    let colW = (leftW * share - 6 - 8 * (cols - 1)) / cols
    let valueW = colW - 32 * g.cw * sc - 4
    let longest = rows.map { CGFloat($0.1.count) }.max() ?? 0
    return longest * 7 * sc * 0.6 * bankValueMinScale <= valueW
}

func bankRows(_ co: JSON) -> [(String, String)] {
    if co.str("print_bank_block") == "0" { return [] }
    return bankFields.compactMap { f in
        let v = co.str(f.key).trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : (f.label, v)
    }
}

/// One row of the HSN-wise GST summary: an HSN code at one GST rate, its taxable value and tax.
/// Settings › Printing › GST in the totals: "rate" prints one line per GST rate ("GST @5%", "IGST @5%") instead of CGST and SGST.
func gstByRate(_ co: JSON) -> Bool { co.str("print_gst_lines") == "rate" }

/// The bill's tax as one line per GST rate, lowest rate first: ("GST @5%", 1917.75), or IGST on a bill to another state.
func gstRateLines(_ inv: JSON) -> [(String, Double)] {
    var rates: [Double] = [], amt: [Double: Double] = [:], inter: [Double: Bool] = [:]
    for l in inv.list("lines") {
        let r = l.num("gst_rate"), tax = l.num("cgst") + l.num("sgst") + l.num("igst")
        if abs(tax) < 0.005 { continue }
        if amt[r] == nil { rates.append(r) }
        amt[r, default: 0] += tax
        if l.num("igst") > 0 { inter[r] = true }
    }
    return rates.sorted().map { r in ((inter[r] == true ? "IGST" : "GST") + " @\(Fmt.qty(r))%", amt[r] ?? 0) }
}

struct HsnGst { let hsn: String; let rate, taxable, cgst, sgst, igst: Double; var gst: Double { cgst + sgst + igst } }

/// The bill's items grouped by HSN and GST rate, in the order they first appear.
func hsnGst(_ inv: JSON) -> [HsnGst] {
    var keys: [String] = []
    var acc: [String: (String, Double, Double, Double, Double, Double)] = [:]
    for l in inv.list("lines") {
        let h = l.str("hsn").trimmingCharacters(in: .whitespaces)
        let k = "\(h)|\(Fmt.amount(l.num("gst_rate")))"
        if acc[k] == nil { keys.append(k); acc[k] = (h, l.num("gst_rate"), 0, 0, 0, 0) }
        acc[k]!.2 += l.num("taxable"); acc[k]!.3 += l.num("cgst"); acc[k]!.4 += l.num("sgst"); acc[k]!.5 += l.num("igst")
    }
    return keys.map { k in let a = acc[k]!; return HsnGst(hsn: a.0.isEmpty ? "-" : a.0, rate: a.1, taxable: a.2, cgst: a.3, sgst: a.4, igst: a.5) }
}

/// Settings › Printing › Typeface: the classic serif (like Marg) or modern letters. The BillBox and Marg designs print in the
/// serif until another is chosen; Busy and Bizom in modern letters.
func printSerif(_ co: JSON) -> Bool {
    co.str("print_marg_font").isEmpty ? ["classic", "marg"].contains(printStyle(co)) : co.str("print_marg_font") != "sans"
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

private func cell(_ t: String, _ i: Int, _ g: Spec, bold: Bool = false, serif: Bool = false) -> some View {
    let right = [3, 4, 5, 6, 7, 8, 9].contains(i)
    let center = i == 0
    let align: Alignment = center ? .center : (right ? .trailing : .leading)
    let w = widths[i].map { $0 * g.cw }
    return Text(t).font(.system(size: 7 * g.fs, weight: bold ? .semibold : .regular, design: serif ? .serif : .default)).lineLimit(1).minimumScaleFactor(0.75)
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
private func rowView(_ v: [String], _ g: Spec, height: CGFloat?, bold: Bool = false, cols: [Int] = Array(0..<10), serif: Bool = false) -> some View {
    HStack(spacing: 0) {
        ForEach(cols, id: \.self) { i in cell(v[i], i, g, bold: bold, serif: serif) }
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
/// A vertical divider the full height of its row. Given its height explicitly: on macOS 12 (bitmap printing) a bare Rectangle
/// in a row came out as a short tick or not at all.
private func vRule(_ w: CGFloat = ruleLine, color: Color = ink) -> some View {
    GeometryReader { p in Rectangle().fill(color).frame(width: w, height: p.size.height) }.frame(width: w)
}

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

    /// Settings › Printing › Typeface (classic serif like Marg unless Modern is chosen)
    private var serif: Bool { printSerif(co) }
    private func t(_ s: String, _ size: CGFloat = 7, bold: Bool = false, weight: Font.Weight? = nil) -> Text {
        Text(s).font(.system(size: size * g.fs, weight: weight ?? (bold ? .bold : .regular), design: serif ? .serif : .default))
    }

    var body: some View {
        let lines = inv.list("lines")
        let W = g.contentW
        // One ruled box, exactly as wide as the page inside its margins: header, item table, totals and the footer
        // (terms, bank, signature) all sit inside the same border, so the margins are equal on all four sides.
        VStack(spacing: 0) {
            if first { firstHeader } else { nextHeader }
            hRule(frameLine)
            // the item table: shaded heading row, light rule under every item, column lines down to the bottom
            VStack(spacing: 0) {
                rowView(headingsFor, g, height: g.tableHead, bold: true, cols: cols, serif: serif).background(shade)
                ForEach(Array(rows), id: \.self) { i in
                    let l = lines[i]
                    rowView(["\(i + 1)", Fmt.cut(co.str("print_caps") == "1" ? l.str("item_name").uppercased() : l.str("item_name"), g.fs > 1 ? 52 : 56), l.str("hsn"),
                             qtyText(l, pieces: co.str("print_qty") == "pcs"),
                             l.num("mrp") > 0 ? Fmt.qty(l.num("mrp")) : "", Fmt.amount(l.num("rate")),
                             l.num("disc_pct") > 0 ? Fmt.qty(l.num("disc_pct")) : "", Fmt.amount(l.num("taxable")),
                             Fmt.qty(l.num("gst_rate")), Fmt.amount(l.num("amount"))], g, height: g.rowH, cols: cols, serif: serif)
                }
                rowView(Array(repeating: "", count: 10), g, height: nil, cols: cols, serif: serif)
            }
            .frame(width: W, height: tableHeight, alignment: .top)
            .overlay(gridLines(rowCount: rows.count))
            if last { hRule(frameLine); totalsBlock.frame(width: W).clipped() }
            if g.foot > 0 {
                hRule(frameLine)
                footer
            }
        }
        .frame(width: W, height: g.inner + 3.6, alignment: .top)
        .clipped()
        .overlay(Rectangle().stroke(ink, lineWidth: frameLine))
        .padding(g.m)
        .frame(width: g.w, height: g.h, alignment: .topLeading)
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
            VStack(alignment: .leading, spacing: 0.5) {
                // Bill to as on a Marg bill: "M/s" and the party in bold, then address, state code and phone, GSTIN, PAN / FSSAI
                t(hc(partyTitle), 10.5, bold: true).lineLimit(1).minimumScaleFactor(0.6)
                ForEach(Array(buyerLines.enumerated()), id: \.offset) { _, l in
                    t(hc(l.0), 7.5, weight: l.1 ? .bold : .regular).lineLimit(1).minimumScaleFactor(0.65)
                }
            }
            .padding(.horizontal, 5).padding(.vertical, 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: g.sellerBand)
        .clipped()
    }

    /// "M/s Party" (Settings › Printing › “M/s” before the party's name), or "Supplier: …" on a debit note.
    private var partyTitle: String {
        let name = inv.str("party_name").isEmpty ? "Cash customer" : inv.str("party_name")
        if inv.str("doc_title") == "DEBIT NOTE" { return "Supplier: " + name }
        return (inv.str("party_name").isEmpty || co.str("print_marg_ms") == "0" ? "" : "M/s ") + name
    }

    /// Buyer details under the name as on a Marg bill, at most four lines: (text, bold); empty details are left out.
    private var buyerLines: [(String, Bool)] {
        if !on("print_party") { return [] }   // Settings › Printing › party's address and numbers
        var mob: [String] = []
        for m in ([inv.str("party_phone")] + inv.str("party_mobiles").split(whereSeparator: { ",;/".contains($0) }).map(String.init)) {
            let x = m.trimmingCharacters(in: .whitespaces)
            if !x.isEmpty && !mob.contains(x) { mob.append(x) }
        }
        if !inv.str("party_tel").isEmpty { mob.append(inv.str("party_tel")) }
        func join(_ parts: [(String, String)]) -> String {
            parts.filter { !$0.1.trimmingCharacters(in: .whitespaces).isEmpty }.map { "\($0.0) : \($0.1)" }.joined(separator: "   ")
        }
        var out: [(String, Bool)] = []
        let addr = inv.str("party_address").trimmingCharacters(in: .whitespacesAndNewlines)
        if !addr.isEmpty { out.append((addr, false)) }
        let sp = join([("State code", inv.str("party_state")), ("Ph.No.", mob.joined(separator: ", "))])
        if !sp.isEmpty { out.append((sp, false)) }
        out.append(("GSTIN : \(inv.str("party_gstin").isEmpty ? "Unregistered" : inv.str("party_gstin"))", true))
        let more = join([("PAN", inv.str("party_pan")), ("FSSAI", inv.str("party_fssai"))])
        if !more.isEmpty { out.append((more, false)) }
        return Array(out.prefix(4))
    }

    /// One shaded line: title, number, date, salesman, payment (or a debit note's reference), and which copy it is.
    private var infoRow: some View {
        let d = details
        let left = Array(d.prefix(2)), right = Array(d.dropFirst(2))
        func item(_ kv: (String, String, Bool)) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                t(kv.0 + ":", 6.5).foregroundStyle(muted)
                t(kv.1, 7.5, bold: kv.2).lineLimit(1).minimumScaleFactor(0.6)
            }
        }
        // three parts on one baseline: the outer two take equal widths, so the title stays in the centre of the row
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                ForEach(Array(left.enumerated()), id: \.offset) { _, kv in item(kv) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            t(docTitle, 8.5, bold: true).lineLimit(1).fixedSize()
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                ForEach(Array(right.enumerated()), id: \.offset) { _, kv in item(kv) }
                if !copy.isEmpty { t(copy, 6, bold: true).lineLimit(1).minimumScaleFactor(0.7) }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
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
                if co.str("print_balance") == "1" && inv.has("party_prev_balance") {
                    t("Previous balance \(balanceText(inv.num("party_prev_balance")))   ·   This bill \(Fmt.money(inv.num("total") - inv.num("paid")))   ·   Now due \(balanceText(inv.num("party_balance_after")))", 6.5, weight: .semibold)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                if on("print_words") || bankTab {
                    // the bank details sit beside "Amount in words" (the words take the left 42%), so they need no extra height
                    let leftW = g.contentW - sumW - 12 - (sigHere ? signatureBandWidth(g) : 0) - (recvHere ? receiverBandWidth(g) : 0)   // inside the margins and the 6 pt padding each side
                    HStack(alignment: .bottom, spacing: 0) {
                        if on("print_words") {
                            VStack(alignment: .leading, spacing: 1.5) {
                                t("Amount in words", 5.5, bold: true).foregroundStyle(muted)
                                t(inv.str("amount_words"), recvHere ? 6.5 : 7, weight: .semibold).lineLimit(recvHere ? 3 : 2).minimumScaleFactor(0.65).fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(width: bankTab ? leftW * (1 - bankShare - 0.02) : nil, alignment: .topLeading)
                        }
                        // the bank details start right after the words (Settings › Printing › Bank details size sets how much room they get)
                        if bankTab { bankTabBlock.frame(width: leftW * bankShare, alignment: .topLeading).padding(.leading, leftW * 0.02) }
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .layoutPriority(1)
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
            .frame(width: bandLeftW, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            if recvHere {
                // an empty box for the buyer to sign, between the bank details and the company's signature
                VStack(spacing: 2) {
                    Spacer(minLength: 0)
                    Rectangle().fill(muted.opacity(0.7)).frame(height: 0.5).padding(.horizontal, 6)
                    t("Receiver's Signature", 6.5).foregroundStyle(muted).lineLimit(1).minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 4).padding(.vertical, 4)
                .frame(width: receiverBandWidth(g))
                .frame(maxHeight: .infinity)
                .overlay(alignment: .leading) { vRule(0.5, color: muted).padding(.vertical, 4) }
            }
            if sigHere {
                // the company's signature, beside the bank details behind a ruled line: the footer keeps only the terms
                VStack(spacing: 2) {
                    t(hc("For \(companyName)"), 7, bold: true).lineLimit(2).minimumScaleFactor(0.7).multilineTextAlignment(.center)
                    Spacer(minLength: 0)
                    Rectangle().fill(muted.opacity(0.7)).frame(height: 0.5).padding(.horizontal, 6)
                    t("Authorised Signatory", 6.5).foregroundStyle(muted).lineLimit(1).minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 5).padding(.vertical, 4)
                .frame(width: signatureBandWidth(g))
                .frame(maxHeight: .infinity)
                .overlay(alignment: .leading) { vRule(0.5, color: muted).padding(.vertical, 4) }
            }
            sumColumn
                .frame(maxHeight: .infinity)
                // the line between "Amount in words" and the totals, down beside GRAND TOTAL to the frame
                .overlay(alignment: .leading) { vRule(frameLine) }
        }
        .frame(height: g.totals, alignment: .top)
    }

    /// The bank details sit in the totals band, left of the totals, on the last page when they fit there.
    private var bankTab: Bool { page == pages - 1 && bankTabFits(co, inv, g) }
    /// The signature prints in the totals band (last page) instead of the footer.
    private var sigHere: Bool { page == pages - 1 && signatureInBand(co) }
    private var recvHere: Bool { page == pages - 1 && receiverInBand(co) }
    /// Width of the totals column: a little narrower when the signature boxes share the band.
    private var sumW: CGFloat { (sigHere || recvHere ? 176 : 186) * g.cw }
    /// Width of the band's left side (GST table, words, bank): what the signature boxes and the totals column leave.
    private var bandLeftW: CGFloat { g.contentW - sumW - (sigHere ? signatureBandWidth(g) : 0) - (recvHere ? receiverBandWidth(g) : 0) }
    /// The bank block's share of the band's left side; with the signature boxes beside it the words wrap narrower so the bank keeps its width.
    private var bankShare: CGFloat { recvHere ? 0.66 : sigHere ? min(0.8, bankSize(co).width + 0.12) : bankSize(co).width }

    /// The bank details as a small table: one column when every row fits the free height of the band (above and beside "Amount in
    /// words"), else two; labels, a tab, then the values, lined up, behind a fine divider.
    private var bankTabBlock: some View {
        let rows = bankTabRows(co)
        let per = max(1, bankTabPer(co, inv, g))
        let sc = bankSize(co).scale
        let cols = stride(from: 0, to: rows.count, by: per).map { Array(rows[$0..<min($0 + per, rows.count)]) }
        return HStack(alignment: .top, spacing: 8) {
            ForEach(0..<cols.count, id: \.self) { c in
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(cols[c].enumerated()), id: \.offset) { _, r in
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            t(r.0 + ":", 6 * sc, bold: true).lineLimit(1).minimumScaleFactor(0.8).frame(width: 32 * g.cw * sc, alignment: .leading)
                            t(r.1, 7 * sc, weight: .semibold).lineLimit(1).minimumScaleFactor(bankValueMinScale)
                        }
                        .frame(height: bankRowH * g.fs * sc, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(.leading, 6)
        .frame(maxHeight: .infinity, alignment: .bottomLeading)
        .overlay(alignment: .leading) { vRule(0.5, color: muted) }
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

    /// HSN-wise GST: one row per HSN code and rate, with the tax columns of its supply: CGST, SGST and Total GST within the
    /// state, IGST across states (never a column of zeros), then a total line.
    private var gstTable: some View {
            let inter = inv.str("supply") == "INTER" || (inv.num("igst") > 0 && inv.num("cgst") == 0)
            let heads = inter ? ["HSN", "GST %", "Taxable", "IGST"] : ["HSN", "GST %", "Taxable", "CGST", "SGST", "Total GST"]
            let rows = hsnGst(inv)
            let natural = heads.reduce(CGFloat(0)) { $0 + ($1 == "HSN" ? 52 : $1 == "GST %" ? 32 : 50) * g.cw }
            let fit = min(1, (bandLeftW - 12) / natural)   // beside the signature boxes the columns narrow (figures shrink to fit)
            func w(_ h: String) -> CGFloat { (h == "HSN" ? 52 : h == "GST %" ? 32 : 50) * g.cw * fit }
            func vals(_ r: HsnGst) -> [String] {
                inter ? [r.hsn, Fmt.qty(r.rate), Fmt.amount(r.taxable), Fmt.amount(r.igst)]
                      : [r.hsn, Fmt.qty(r.rate), Fmt.amount(r.taxable), Fmt.amount(r.cgst), Fmt.amount(r.sgst), Fmt.amount(r.gst)]
            }
            func line(_ v: [String], bold: Bool) -> AnyView {
                AnyView(HStack(spacing: 0) {
                    ForEach(Array(heads.enumerated()), id: \.offset) { i, h in
                        t(v[i], 6.5, bold: bold).lineLimit(1).minimumScaleFactor(0.7).frame(width: w(h), alignment: i == 0 ? .leading : .trailing)
                    }
                })
            }
            let tot = HsnGst(hsn: "Total", rate: 0, taxable: rows.reduce(0) { $0 + $1.taxable }, cgst: rows.reduce(0) { $0 + $1.cgst },
                             sgst: rows.reduce(0) { $0 + $1.sgst }, igst: rows.reduce(0) { $0 + $1.igst })
            let tv = vals(tot).enumerated().map { $0.offset == 1 ? "" : $0.element }
            return VStack(alignment: .leading, spacing: 1.5) {
                line(heads, bold: true)
                    .padding(.bottom, 1)
                    .overlay(alignment: .bottom) { Rectangle().fill(muted).frame(height: 0.4) }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, r in line(vals(r), bold: false) }
                if rows.count > 1 {
                    line(tv, bold: true).overlay(alignment: .top) { Rectangle().fill(muted).frame(height: 0.4) }
                }
            }
    }

    /// The totals on the right, ending in the grand total.
    private var sumColumn: some View {
            VStack(spacing: 0) {
                VStack(spacing: compactPrint(co) ? 0 : 1) {
                    sumRow("Items total", inv.num("subtotal"))
                    if inv.num("discount") > 0 { sumRow("Less discount", -inv.num("discount")) }
                    // compact: the taxable value only when it differs from the items total
                    if !compactPrint(co) || inv.num("discount") > 0 || abs(inv.num("taxable") - inv.num("subtotal")) > 0.005 { sumRow("Taxable value", inv.num("taxable")) }
                    if gstByRate(co) {
                        ForEach(Array(gstRateLines(inv).enumerated()), id: \.offset) { _, r in sumRow(r.0, r.1) }
                    } else {
                        if inv.num("cgst") > 0 { sumRow("CGST", inv.num("cgst")); sumRow("SGST", inv.num("sgst")) }
                        if inv.num("igst") > 0 { sumRow("IGST", inv.num("igst")) }
                    }
                    // the total stays rounded; the round-off line is not printed
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
                .frame(height: (compactPrint(co) ? 17 : 19) * g.fs)
                .background(shade)
            }
            .frame(width: sumW)
    }

    private func sumRow(_ a: String, _ v: Double) -> some View {
        HStack { t(a, 7).foregroundStyle(muted); Spacer(); t(Fmt.amount(v), 7.5) }
            .frame(height: compactPrint(co) ? 9 * g.fs : nil)
    }

    /// Terms (and your own lines) on the left, the bank details in the middle, the company's signature block on the right.
    private var footer: some View {
        let slim = signatureInBand(co)
        // slim footer: the bank lines print here only on the last page when they did not fit the totals band
        let bank: [[(String, String)]] = bankTab || (slim && page != pages - 1) ? [] : bankLines(co)
        // fixed shares of the width, so long bank lines can never push the terms or the signature off the page
        let W = g.contentW - 12
        let sigW: CGFloat = slim ? 0 : bank.isEmpty ? (W - 16) / 3 : 130 * g.cw
        let leftW: CGFloat = bank.isEmpty ? (slim ? (W - 16) * 0.6 : (W - 16) / 3) : (W - sigW - 16) * 0.40
        let midW: CGFloat = W - sigW - leftW - 16
        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                if slim && on("print_terms") && !co.str("invoice_terms").isEmpty {
                    (Text("Terms: ").font(.system(size: 6, weight: .bold)).foregroundColor(muted) + Text(co.str("invoice_terms")).font(.system(size: 6.5)))
                        .lineLimit(1).minimumScaleFactor(0.7)
                } else if on("print_terms") && !co.str("invoice_terms").isEmpty {
                    t("Terms", 6, bold: true).foregroundStyle(muted)
                    t(co.str("invoice_terms"), 6.5).lineLimit(co.str("print_bank").isEmpty ? 2 : 1).fixedSize(horizontal: false, vertical: true)
                }
                if !co.str("print_bank").isEmpty { t(co.str("print_bank"), 6.5, weight: .semibold).lineLimit(1).minimumScaleFactor(0.7) }
                if !bank.isEmpty && !co.str("print_note").isEmpty { t(co.str("print_note"), 6.5, bold: true).lineLimit(1).minimumScaleFactor(0.7) }
            }
            .frame(width: leftW, alignment: .leading)
            if bank.isEmpty {
                VStack(spacing: 1) {
                    if !co.str("print_note").isEmpty { t(co.str("print_note"), 7, bold: true).lineLimit(1).minimumScaleFactor(0.7) }
                    t(pages > 1 ? "Page \(page + 1) of \(pages)" : "", 6.5).foregroundStyle(muted)
                }
                .frame(width: midW)
            } else {
                // the bank details, in three short lines in the footer: no room is taken from the items
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(bank.enumerated()), id: \.offset) { _, l in
                        bankLineText(l, size: 6.3 * g.fs, serif: serif).lineLimit(1).minimumScaleFactor(0.65)
                    }
                    if pages > 1 { t("Page \(page + 1) of \(pages)", 6).foregroundStyle(muted) }
                }
                .frame(width: midW, alignment: .leading)
            }
            if !slim { VStack(alignment: .trailing, spacing: 0) {
                if on("print_signature") {
                    t(hc("For \(companyName)"), 7, bold: true).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    t("Authorised Signatory", 6.5).foregroundStyle(muted)
                }
            }
            .frame(width: sigW, alignment: .trailing) }
        }
        .padding(.horizontal, 6).padding(.top, 3).padding(.bottom, 2)
        .frame(width: g.contentW, height: g.foot, alignment: .top)
        .clipped()
    }
}

/// Two copies on one A4 sheet with a dashed cut line between them.
@MainActor struct TwoUpView: View {
    let inv: JSON, co: JSON
    var g: Spec = .half
    var body: some View {
        VStack(spacing: 0) {
            billSheet(inv, co, rows: 0..<inv.list("lines").count, page: 0, pages: 1, copy: copyLabelsFor(co)[0], g: g)
            billSheet(inv, co, rows: 0..<inv.list("lines").count, page: 0, pages: 1, copy: copyLabelsFor(co)[1], g: g)
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

/// Draws SwiftUI pages into a vector PDF.
@MainActor
func renderPDF(pages: [AnyView], size: CGSize) -> PDFDocument? {
    let data = NSMutableData()
    var box = CGRect(origin: .zero, size: size)
    guard let consumer = CGDataConsumer(data: data as CFMutableData), let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
    for page in pages {
        let r = ImageRenderer(content: page.frame(width: size.width, height: size.height).environment(\.colorScheme, .light))
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

/// The page measurements for the company's bill design (Settings › Printing › Bill design) and text size.
func billSpec(_ inv: JSON, _ co: JSON, full: Bool) -> Spec {
    let base = (full ? Spec.full : Spec.half).scaled(printScale(co))
    return printStyle(co) != "classic" ? margSpec(base, inv, co) : base.withMargin(full ? 7 : 5).withBank(co, inv)
}

/// One copy of one page of a bill, in the company's bill design.
@MainActor
func billSheet(_ inv: JSON, _ co: JSON, rows: Range<Int>, page: Int, pages: Int, copy copyLabel: String, g: Spec) -> AnyView {
    // Settings › Printing › "ORIGINAL / DUPLICATE on each copy": off prints the copies without the words
    let copy = co.str("print_copy_label") == "0" ? "" : copyLabel
    return printStyle(co) != "classic"
        ? AnyView(MargSheetView(inv: inv, co: co, rows: rows, page: page, pages: pages, copy: copy, g: g))
        : AnyView(InvoiceSheetView(inv: inv, co: co, rows: rows, page: page, pages: pages, copy: copy, g: g))
}

/// A half-sheet copy pinned to the TOP of an A4 page (the lower half stays blank), so the original prints at the top of
/// one page and the duplicate at the top of the next.
@MainActor
func topOfA4Page(_ page: AnyView) -> AnyView { AnyView(VStack(spacing: 0) { page; Spacer(minLength: 0) }) }

@MainActor
func invoicePDF(_ inv: JSON, company: JSON, layout: PrintLayout, topOfA4: Bool = false) -> PDFDocument? {
    let n = inv.list("lines").count
    let g = billSpec(inv, company, full: layout.isFullPage)
    if layout == .a4TwoUp && paginate(n, g).count == 1 {
        return renderPDF(pages: [AnyView(TwoUpView(inv: inv, co: company, g: g))], size: CGSize(width: g.w, height: g.h * 2))
    }
    // a long invoice does not fit twice on one sheet: fall back to one copy per half sheet
    let labels = copyLabelsFor(company)
    let copies = (layout == .single || layout == .a4FullOriginal) ? [labels[0]] : labels
    let ranges = paginate(n, g)
    // for printing: a half-sheet copy sits at the top of its own A4 page (original on one page, duplicate on the next)
    let pin = topOfA4 && !layout.isFullPage
    var pages: [AnyView] = []
    for c in copies {
        for (i, r) in ranges.enumerated() {
            let sheet = billSheet(inv, company, rows: r, page: i, pages: ranges.count, copy: c, g: g)
            pages.append(pin ? topOfA4Page(sheet) : sheet)
        }
    }
    return renderPDF(pages: pages, size: pin ? CGSize(width: g.w, height: g.h * 2) : g.size)
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
            guard let pdf = invoicePDF(inv, company: app.settings, layout: layout, topOfA4: false) else { continue }
            for k in 0..<pdf.pageCount { if let pg = pdf.page(at: k) { all.insert(pg, at: all.pageCount) } }
            nos.append(inv.str("invoice_no"))
        }
        guard all.pageCount > 0 else { throw APIError(message: "Could not prepare the bills for printing", status: 0, code: nil) }
        let job = PrintJob(title: "\(nos.count) bills (\(nos.first ?? "") … \(nos.last ?? ""))", fileName: "Bills-\(nos.count).pdf", document: all, invoiceIds: ids)
        app.printJob = job
    }
}

/// The printer picked on this iPhone (decision D7: kept on the device, the Mac's printer setting is left alone).
enum DevicePrinter {
    static var url: URL? {
        get { UserDefaults.standard.url(forKey: "ios_printer_url") }
        set { UserDefaults.standard.set(newValue, forKey: "ios_printer_url") }
    }
    static var name: String {
        get { UserDefaults.standard.string(forKey: "ios_printer_name") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "ios_printer_name") }
    }
    static var auto: Bool {
        get { UserDefaults.standard.bool(forKey: "ios_print_auto") }
        set { UserDefaults.standard.set(newValue, forKey: "ios_print_auto") }
    }
}

/// Picks the paper for the page size: A5 for half sheets (a half-A4 bill fed landscape on a cut sheet), A4 otherwise.
final class PaperChooser: NSObject, UIPrintInteractionControllerDelegate {
    static var current: PaperChooser?
    let pageSize: CGSize
    init(pageSize: CGSize) { self.pageSize = pageSize }
    func printInteractionController(_ c: UIPrintInteractionController, choosePaper paperList: [UIPrintPaper]) -> UIPrintPaper {
        // AirPrint lists paper portrait; a landscape half sheet is asked for as its portrait A5 paper and printed rotated
        let want = pageSize.width > pageSize.height ? CGSize(width: pageSize.height, height: pageSize.width) : pageSize
        return UIPrintPaper.bestPaper(forPageSize: want, withPapersFrom: paperList)
    }
}

/// Draws each page of a PDF into the printable area of the paper the printer gives, turned a quarter if the page and the
/// paper lie differently (a landscape half sheet on portrait A5), scaled to fit and centred, on white.
final class PDFFitRenderer: UIPrintPageRenderer {
    let doc: PDFDocument
    init(_ doc: PDFDocument) { self.doc = doc; super.init() }
    override var numberOfPages: Int { doc.pageCount }
    override func drawPage(at index: Int, in printableRect: CGRect) {
        guard let page = doc.page(at: index), let ctx = UIGraphicsGetCurrentContext() else { return }
        let box = page.bounds(for: .mediaBox)
        let w = box.width, h = box.height
        guard w > 0, h > 0, printableRect.width > 0, printableRect.height > 0 else { return }
        let turn = (w > h) != (printableRect.width > printableRect.height)
        let cw = turn ? h : w, ch = turn ? w : h
        let scale = min(printableRect.width / cw, printableRect.height / ch)
        ctx.saveGState()
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(paperRect)
        // centred across, from the top edge down (a half sheet at the top of A4 must stay at the top)
        ctx.translateBy(x: printableRect.midX, y: printableRect.minY + ch * scale / 2)
        if turn { ctx.rotate(by: .pi / 2) }
        ctx.scaleBy(x: scale, y: scale)
        // the print context has y going down; a PDF page has y going up from its bottom-left corner
        ctx.translateBy(x: -w / 2, y: h / 2)
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: -box.minX, y: -box.minY)
        page.draw(with: .mediaBox, to: ctx)
        ctx.restoreGState()
    }
}

/// The half-sheet pages for the printer: each A5-landscape bill upright at the top edge of a portrait A4 page, at its real size.
/// An HP LaserJet 1020 (and most office laser printers) is fed the A5 sheet sideways, long edge first, and prints it as the top
/// part of an A4 page: a bill turned onto portrait A5 came out enlarged and cut off at the HSN column.
func halfSheetsOnA4(_ pdf: PDFDocument) -> PDFDocument? {
    let data = NSMutableData()
    var box = CGRect(origin: .zero, size: Paper.a4)
    guard let consumer = CGDataConsumer(data: data as CFMutableData), let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
    for i in 0..<pdf.pageCount {
        guard let page = pdf.page(at: i) else { continue }
        let b = page.bounds(for: .mediaBox)
        ctx.beginPDFPage(nil)
        ctx.saveGState()
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(box)
        // PDF y goes up: the bill's top edge on the page's top edge, centred across the width
        ctx.translateBy(x: (Paper.a4.width - b.width) / 2 - b.minX, y: Paper.a4.height - b.height - b.minY)
        page.draw(with: .mediaBox, to: ctx)
        ctx.restoreGState()
        ctx.endPDFPage()
    }
    ctx.closePDF()
    return PDFDocument(data: data as Data)
}

/// Prints through AirPrint. `silent` prints straight to the saved printer without the print panel.
/// Half-sheet bills go out on A5 / half-A4 paper (one copy per sheet), landscape; A4 layouts on A4.
@MainActor
func runPrint(_ pdf: PDFDocument, jobName: String, silent: Bool, done: ((Bool) -> Void)? = nil) {
    guard pdf.pageCount > 0 else { done?(false); return }
    // a half-sheet bill goes out upright at the top of a portrait A4 page, where the A5 sheet fed sideways catches it whole
    var pdf = pdf
    if let s = pdf.page(at: 0)?.bounds(for: .mediaBox).size, s.width > s.height, let top = halfSheetsOnA4(pdf) { pdf = top }
    let size = pdf.page(at: 0)?.bounds(for: .mediaBox).size ?? Paper.a4
    let pc = UIPrintInteractionController.shared
    let info = UIPrintInfo(dictionary: nil)
    info.outputType = .general
    info.jobName = jobName
    // always portrait A4: half sheets arrive here already placed at the top of an A4 page (see halfSheetsOnA4)
    info.orientation = .portrait
    pc.printInfo = info
    let chooser = PaperChooser(pageSize: size)
    PaperChooser.current = chooser
    pc.delegate = chooser
    // Drawn page by page, fitted to the paper the printer reports (not handed over as a PDF file): a USB printer shared
    // from a Mac printed the raw half-sheet PDF as a blank page, because the Mac placed the sideways page off the paper.
    pc.printingItem = nil
    pc.printPageRenderer = PDFFitRenderer(pdf)
    if silent, let url = DevicePrinter.url {
        pc.print(to: UIPrinter(url: url)) { _, ok, _ in done?(ok) }
        return
    }
    pc.present(animated: true) { _, ok, _ in done?(ok) }
}

@MainActor
func printInvoice(_ id: Int, app: AppModel, forcePreview: Bool = false) async {
    await app.guarded {
        let inv = try await API.obj("GET", "/invoices/\(id)")
        let layout = PrintLayout.parse(app.settings.str("print_layout"))
        guard let pdf = invoicePDF(inv, company: app.settings, layout: layout, topOfA4: false) else { throw APIError(message: "Could not prepare the invoice for printing", status: 0, code: nil) }
        if DevicePrinter.auto && !forcePreview && DevicePrinter.url != nil {
            let no = inv.str("invoice_no")
            runPrint(pdf, jobName: no, silent: true) { ok in
                if ok { markPrinted([id], app: app); app.notify("Sent \(no) to \(DevicePrinter.name).") } else { app.notify("Could not print \(no) on \(DevicePrinter.name).", error: true) }
            }
            return
        }
        app.printJob = PrintJob(title: "Invoice \(inv.str("invoice_no"))", fileName: "\(inv.str("invoice_no")).pdf", document: pdf, invoiceIds: [id])
    }
}

/// A debit note printed on the bill layouts, headed DEBIT NOTE, its rows in pieces like a sale bill.
@MainActor
func debitNotePDF(_ d: JSON, company: JSON, layout: PrintLayout) -> PDFDocument? {
    var raw = d.raw
    raw["lines"] = d.raw["print_lines"] ?? [Any]()
    return invoicePDF(JSON(raw), company: company, layout: layout, topOfA4: false)
}

@MainActor
func printDebitNote(_ id: Int, app: AppModel) async {
    await app.guarded {
        let d = try await API.obj("GET", "/debit-notes/\(id)")
        guard let pdf = debitNotePDF(d, company: app.settings, layout: PrintLayout.parse(app.settings.str("print_layout"))) else {
            throw APIError(message: "Could not prepare the debit note for printing", status: 0, code: nil)
        }
        app.printJob = PrintJob(title: "Debit note \(d.str("note_no"))", fileName: "\(d.str("note_no").replacingOccurrences(of: "/", with: "-")).pdf", document: pdf)
    }
}

@MainActor
func printVoucher(_ no: String, app: AppModel) async {
    await app.guarded {
        let v = try await API.obj("GET", "/vouchers/\(API.seg(no))")
        let pages = copyLabels.map { AnyView(VoucherSheetView(v: v, copy: $0)) }
        guard let pdf = renderPDF(pages: pages, size: Spec.half.size) else { return }
        app.printJob = PrintJob(title: "Receipt \(no)", fileName: "\(no).pdf", document: pdf)
    }
}

/// The in-app print preview: pages, Save PDF (share sheet / Files), Close, Print (AirPrint).
@MainActor struct PrintPreviewSheet: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    let job: PrintJob

    var body: some View {
        NavigationStack {
            PDFPreview(document: job.document)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(job.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.keyboardShortcut(.cancelAction) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Print…") { let ids = job.invoiceIds; runPrint(job.document, jobName: job.title, silent: false) { ok in if ok { markPrinted(ids, app: app); dismiss() } } }.keyboardShortcut(.defaultAction)
                    }
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button { if let d = job.document.dataRepresentation() { Files.save(job.fileName, data: d) } } label: { Label("Save PDF…", systemImage: "square.and.arrow.up") }
                        Spacer()
                        Text("\(job.document.pageCount) page\(job.document.pageCount == 1 ? "" : "s")").font(.footnote).foregroundStyle(.secondary)
                    }
                }
        }
    }
}
