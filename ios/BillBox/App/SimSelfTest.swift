import SwiftUI
import PDFKit

/// The iPhone Simulator self-test on GitHub (.github/workflows/ios-selftest.yml). Only runs when the app is launched with
/// `-BillBoxPrintTest 1`: once the books are open, the newest sale bills are drawn exactly as they print and saved in
/// Documents/selftest (bill_1.pdf …, the Marg design as marg_1.pdf …, and done.txt with a line per bill), where the workflow collects them.
@MainActor
enum SimSelfTest {
    static var asked: Bool { UserDefaults.standard.bool(forKey: "BillBoxPrintTest") }

    static func runIfAsked(_ app: AppModel) async {
        guard asked else { return }
        for _ in 0..<150 where !app.ready { await pause(ms: 200) }
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("selftest", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var log: [String] = []
        do {
            let r = try await API.obj("GET", "/bills", query: ["type": "SALE", "from": "2000-01-01", "to": "2100-12-31"])
            let layout = PrintLayout.parse(app.settings.str("print_layout"))
            // the first bill's drawings by "design|layout", so the every-layout set below does not draw them twice
            var drawn: [String: Data] = [:]
            for (n, row) in r.list("rows").prefix(4).enumerated() {
                let inv = try await API.obj("GET", "/invoices/\(row.int("id"))")
                if let data = invoicePDF(inv, company: app.settings, layout: layout)?.dataRepresentation() {
                    if n == 0 { drawn["\(printStyle(app.settings))|\(layout.rawValue)"] = data }
                    try data.write(to: dir.appendingPathComponent("bill_\(n + 1).pdf"))
                    log.append("bill_\(n + 1).pdf \(inv.str("invoice_no")) \(inv.str("party_name")) \(data.count) bytes")
                } else {
                    log.append("bill_\(n + 1): no PDF for \(inv.str("invoice_no"))")
                }
                // the Marg design too (half sheet; the first bill also on a full A4 page, in black only)
                var marg = app.settings.raw
                marg["print_style"] = "marg"
                if let data = invoicePDF(inv, company: JSON(marg), layout: .single)?.dataRepresentation() {
                    if n == 0 { drawn["marg|single"] = data }
                    try data.write(to: dir.appendingPathComponent("marg_\(n + 1).pdf"))
                    log.append("marg_\(n + 1).pdf \(data.count) bytes")
                }
                // the Busy and Bizom designs too
                for design in ["busy", "bizom"] {
                    var c = app.settings.raw
                    c["print_style"] = design
                    if let data = invoicePDF(inv, company: JSON(c), layout: .single)?.dataRepresentation() {
                        if n == 0 { drawn["\(design)|single"] = data }
                        try data.write(to: dir.appendingPathComponent("\(design)_\(n + 1).pdf"))
                        log.append("\(design)_\(n + 1).pdf \(data.count) bytes")
                    }
                }
                if n == 0 {
                    // every design in every paper layout (docs/UI_OVERHAUL_PROMPT.md §2.4): layout_<design>_<layout>.pdf
                    for design in ["classic", "marg", "busy", "bizom"] {
                        var c = app.settings.raw
                        c["print_style"] = design
                        for lay in PrintLayout.allCases {
                            if let data = drawn["\(design)|\(lay.rawValue)"] ?? invoicePDF(inv, company: JSON(c), layout: lay)?.dataRepresentation() {
                                try data.write(to: dir.appendingPathComponent("layout_\(design)_\(lay.rawValue).pdf"))
                                log.append("layout_\(design)_\(lay.rawValue).pdf \(data.count) bytes")
                            } else {
                                log.append("layout_\(design)_\(lay.rawValue): no PDF")
                            }
                        }
                    }
                    marg["print_marg_colour"] = "mono"; marg["print_marg_classes"] = "used"; marg["print_marg_font"] = "sans"
                    if let data = invoicePDF(inv, company: JSON(marg), layout: .a4FullOriginal)?.dataRepresentation() {
                        try data.write(to: dir.appendingPathComponent("marg_a4.pdf"))
                        log.append("marg_a4.pdf \(data.count) bytes")
                    }
                }
            }
            // the bill with the most lines, in both designs
            var busy: JSON?
            for row in r.list("rows").prefix(25) {
                let inv = try await API.obj("GET", "/invoices/\(row.int("id"))")
                if inv.list("lines").count > (busy?.list("lines").count ?? 0) { busy = inv }
            }
            if let inv = busy {
                var marg = app.settings.raw
                marg["print_style"] = "marg"
                for (name, co) in [("busy_classic", app.settings), ("busy_marg", JSON(marg))] {
                    if let data = invoicePDF(inv, company: co, layout: .single)?.dataRepresentation() {
                        try data.write(to: dir.appendingPathComponent("\(name).pdf"))
                        log.append("\(name).pdf \(inv.str("invoice_no")) \(inv.list("lines").count) lines")
                    }
                }
            }
        } catch {
            log.append("failed: \(error.localizedDescription)")
        }
        try? (log.joined(separator: "\n") + "\n").write(to: dir.appendingPathComponent("done.txt"), atomically: true, encoding: .utf8)
    }
}
