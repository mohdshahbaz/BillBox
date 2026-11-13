import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Settings › Import from Marg ERP: reads a Marg CSV backup (the .zip, or the folder it unzips to), shows what it holds and
/// checks it against Marg's own figures (every bill total, every party's closing balance, every item's closing stock), then
/// imports items, customers and suppliers with opening balances, sale and purchase bills, debit notes, receipts and payments
/// into the open company. Importing the same backup again adds nothing twice.
@MainActor struct MargImportView: View {
    @EnvironmentObject private var app: AppModel
    @State private var path: String?
    @State private var picked = ""
    @State private var report: JSON?
    @State private var result: JSON?
    @State private var busy = false
    @State private var confirm = false
    @State private var errorText: String?

    var body: some View {
        SettingsForm {
            Section {
                Text("In Marg: Reports › Management Report › Data Transfer Utility › Export All Data › CSV. Pick the folder Marg wrote the CSV files to (or a .zip of it). Nothing is changed until you press Import.")
                    .font(.callout).foregroundStyle(.secondary)
                Button { Task { await choose() } } label: { Label(report == nil ? "Choose the Marg backup…" : "Choose another backup…", systemImage: "square.and.arrow.down.on.square") }
                    .disabled(busy)
                if !picked.isEmpty { Text(picked).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                if busy { ProgressView() }
            }
            if let errorText { Section { Text(errorText).foregroundStyle(Theme.negative) } }
            if let r = result ?? report { summary(r) }
            if let path { MargPriceFix(path: path) }
        }
        .confirmationDialog("Import this Marg backup into \(app.companyName)?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Import") { Task { await run() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Items, parties, bills, debit notes, receipts and payments that are not already here are added. Anything with the same name or number is left as it is.")
        }
    }

    private func line(_ a: String, _ b: String) -> some View {
        HStack { Text(a); Spacer(); Text(b).mono().foregroundStyle(.secondary) }
    }

    private func check(_ title: String, _ c: JSON) -> some View {
        let problems = c.strings("problems")
        let ok = problems.isEmpty
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill").foregroundStyle(ok ? Theme.positive : Theme.warning)
                Text(title)
                Spacer()
                Text("\(c.int("ok")) of \(c.int("checked")) match").mono().foregroundStyle(.secondary)
            }
            if !ok {
                DisclosureGroup("\(problems.count) differ") {
                    ForEach(Array(problems.prefix(50).enumerated()), id: \.offset) { _, p in Text(p).font(.caption) }
                }
                .font(.callout)
            }
        }
    }

    @ViewBuilder private func summary(_ r: JSON) -> some View {
        let f = r.obj("found"), t = r.obj("totals"), per = r.obj("period")
        Section(per.str("from").isEmpty ? "In the backup" : "In the backup: \(Fmt.dmy(per.str("from"))) to \(Fmt.dmy(per.str("to")))") {
            line("Items", "\(f.int("items"))")
            line("Customers", "\(f.int("customers"))")
            line("Suppliers", "\(f.int("suppliers"))")
            line("Sale bills", "\(f.int("sales"))  ·  \(Fmt.money(t, "sales"))")
            line("Purchase bills", "\(f.int("purchases"))  ·  \(Fmt.money(t, "purchases"))")
            line("Debit notes", "\(f.int("debit_notes"))  ·  \(Fmt.money(t, "debit_notes"))")
            line("Receipts", "\(f.int("receipts"))  ·  \(Fmt.money(t, "receipts"))")
            line("Payments", "\(f.int("payments"))  ·  \(Fmt.money(t, "payments"))")
            line("Opening: customers owe", Fmt.money(t, "opening_receivable"))
            line("Opening: you owe suppliers", Fmt.money(t, "opening_payable"))
        }
        let c = r.obj("checks")
        Section("Checked against Marg") {
            check("Bill totals", c.obj("bills"))
            check("Party closing balances", c.obj("party_balances"))
            check("Item closing stock", c.obj("stock"))
        }
        let cleaning = r.strings("cleaning"), warnings = r.strings("warnings")
        if !cleaning.isEmpty || !warnings.isEmpty {
            Section("Cleaned up") {
                ForEach(Array(cleaning.enumerated()), id: \.offset) { _, s in Text(s).font(.callout) }
                ForEach(Array(warnings.enumerated()), id: \.offset) { _, s in Text(s).font(.callout).foregroundStyle(Theme.warning) }
            }
        }
        let done = result != nil
        let a = r.obj(done ? "added" : "would_add"), h = r.obj("already_here")
        Section(done ? "Imported into \(app.companyName)" : "Importing adds to \(app.companyName)") {
            line("Items", "\(a.int("items"))\(h.int("items") > 0 ? "  (\(h.int("items")) already here)" : "")")
            line("Categories", "\(a.int("categories"))")
            line("Customers / suppliers", "\(a.int("customers")) / \(a.int("suppliers"))\(h.int("parties") > 0 ? "  (\(h.int("parties")) already here)" : "")")
            line("Sale / purchase bills", "\(a.int("sales")) / \(a.int("purchases"))\(h.int("bills") > 0 ? "  (\(h.int("bills")) already here)" : "")")
            line("Debit notes", "\(a.int("debit_notes"))")
            line("Receipts / payments", "\(a.int("receipts")) / \(a.int("payments"))\(h.int("vouchers") > 0 ? "  (\(h.int("vouchers")) already here)" : "")")
            if !done {
                Button { confirm = true } label: { Label("Import into \(app.companyName)", systemImage: "tray.and.arrow.down") }
                    .buttonStyle(.borderedProminent).disabled(busy || path == nil)
            } else {
                Text("Done. Stock, ledgers, All Bills and the GST books now include the Marg data.").font(.callout).foregroundStyle(.secondary)
                let nb = r.obj("numbering")
                if !nb.str("INV").isEmpty || !nb.str("PUR").isEmpty || !nb.str("DN").isEmpty {
                    Text("New bills carry on Marg's numbering: " + [("sale bill", "INV"), ("purchase", "PUR"), ("debit note", "DN")].filter { !nb.str($0.1).isEmpty }.map { "next \($0.0) \(nb.str($0.1))" }.joined(separator: ", ") + ". Change it in Settings › Billing & Dashboard › Numbering.")
                        .font(.callout)
                }
            }
        }
    }

    private func preview(_ p: String) async {
        busy = true
        defer { busy = false }
        errorText = nil; report = nil; result = nil
        do { report = try await API.objRaw("POST", "/import/marg/preview", body: ["path": p]); path = p } catch { errorText = error.localizedDescription }
    }

    private func run() async {
        guard let path else { return }
        busy = true
        defer { busy = false }
        do {
            let r = try await API.objRaw("POST", "/import/marg", body: ["path": path])
            result = r
            let a = r.obj("added")
            app.notify("Imported from Marg: \(a.int("items")) items, \(a.int("customers") + a.int("suppliers")) parties, \(a.int("sales") + a.int("purchases")) bills, \(a.int("debit_notes")) debit notes.")
        } catch { errorText = error.localizedDescription }
    }

    private func choose() async {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = true
        p.allowedContentTypes = [.zip]
        p.allowsMultipleSelection = false
        p.message = "Choose the Marg CSV backup: the .zip file, or the folder it unzips to"
        guard p.runModal() == .OK, let u = p.url else { return }
        picked = u.path
        await preview(u.path)
    }
}

/// Settings › Import from Marg › Correct item prices: items already in the books whose price is far off the Marg backup
/// (an earlier BillBox worked some out per box instead of per piece) are listed, then put right on Correct.
@MainActor struct MargPriceFix: View {
    @EnvironmentObject private var app: AppModel
    let path: String
    @State private var check: JSON?
    @State private var busy = false
    @State private var errorText: String?

    var body: some View {
        Section {
            Button { Task { await run(apply: false) } } label: { Label("Check item prices against this backup", systemImage: "indianrupeesign.circle") }
                .disabled(busy)
            if let errorText { Text(errorText).foregroundStyle(Theme.negative).font(.callout) }
            if let c = check {
                let rows = c.list("items")
                if c.bool("applied") {
                    Text("Corrected the prices of \(c.int("changed")) items.").font(.callout)
                } else if rows.isEmpty {
                    Text("All \(c.int("checked")) items already here match the backup.").font(.callout).foregroundStyle(.secondary)
                } else {
                    Text("\(rows.count) of \(c.int("checked")) items have a price far off the backup (per piece, ex-GST):").font(.callout)
                    ForEach(Array(rows.prefix(40).enumerated()), id: \.offset) { _, r in
                        HStack {
                            Text(r.str("name")).lineLimit(1)
                            Spacer()
                            Text("\(Fmt.rate(r.num("retail_old"))) → \(Fmt.rate(r.num("retail_new")))").monospacedDigit().foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    }
                    if rows.count > 40 { Text("…and \(rows.count - 40) more").font(.caption).foregroundStyle(.secondary) }
                    Button { Task { await run(apply: true) } } label: { Label("Correct \(rows.count) prices", systemImage: "checkmark.circle") }
                        .buttonStyle(.borderedProminent).disabled(busy)
                }
            }
        } header: { Text("Prices of items already here") } footer: {
            Text("Only prices at least twice or half of what Marg says are changed (an earlier BillBox read some Marg rates per box instead of per piece). Prices you changed by a little are kept.")
        }
    }

    private func run(apply: Bool) async {
        busy = true
        defer { busy = false }
        errorText = nil
        do {
            check = try await API.objRaw("POST", "/import/marg/prices", body: ["path": path, "apply": apply])
            if apply { app.notify("Corrected the prices of \(check?.int("changed") ?? 0) items.") }
        } catch { errorText = error.localizedDescription }
    }
}
