import SwiftUI
import PDFKit

/// The iPhone Simulator self-test on GitHub (.github/workflows/ios-selftest.yml). Only runs when the app is launched with
/// `-BillBoxPrintTest 1`: once the books are open, the newest sale bills are drawn exactly as they print and saved in
/// Documents/selftest (bill_1.pdf …, and done.txt with a line per bill), where the workflow collects them.
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
            for (n, row) in r.list("rows").prefix(4).enumerated() {
                let inv = try await API.obj("GET", "/invoices/\(row.int("id"))")
                if let data = invoicePDF(inv, company: app.settings, layout: layout)?.dataRepresentation() {
                    try data.write(to: dir.appendingPathComponent("bill_\(n + 1).pdf"))
                    log.append("bill_\(n + 1).pdf \(inv.str("invoice_no")) \(inv.str("party_name")) \(data.count) bytes")
                } else {
                    log.append("bill_\(n + 1): no PDF for \(inv.str("invoice_no"))")
                }
            }
        } catch {
            log.append("failed: \(error.localizedDescription)")
        }
        try? (log.joined(separator: "\n") + "\n").write(to: dir.appendingPathComponent("done.txt"), atomically: true, encoding: .utf8)
    }
}
