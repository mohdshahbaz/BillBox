import SwiftUI
import AppKit

@MainActor struct BillsView: View {
    @EnvironmentObject private var app: AppModel
    @State private var type = "ALL"
    @State private var from = ""
    @State private var to = ""
    @State private var query = ""
    @State private var searchDelay = Debouncer()
    @State private var unpaid = false
    @State private var unprinted = false
    @State private var rows: [JSON] = []
    @State private var totals = JSON()
    @State private var selection = Set<JSON.ID>()
    @State private var loading = true
    @State private var busy = false
    @State private var viewing: JSON?
    @State private var ewbRow: JSON?
    @State private var confirmBulkDelete = false

    var body: some View {
        VStack(spacing: 0) {
            filters
            SelectionBar(ids: rows.map(\.id), selection: $selection, actionLabel: "Delete selected bills…", busy: busy, extra: selectedActions) { confirmBulkDelete = true }
            table
            footer
        }
        .navigationTitle("All Bills")
        .searchable(text: $query, prompt: "Search bill no or party")
        .onChange(of: query) { _ in searchDelay.run { await load() } }   // typing loads once, 250 ms after the last key
        .onChange(of: type) { _ in Task { await load() } }
        .onChange(of: from) { _ in Task { await load() } }
        .onChange(of: to) { _ in Task { await load() } }
        .onChange(of: unpaid) { _ in Task { await load() } }
        .onChange(of: unprinted) { _ in Task { await load() } }
        .onChange(of: app.dataVersion) { _ in Task { await load() } }
        .task {
            if from.isEmpty {
                from = app.isCurrentFY ? app.monthStartInFY : app.fyFrom
                to = app.isCurrentFY ? app.dateInFY : app.fyTo
            }
            if app.openUnprinted { app.openUnprinted = false; from = app.fyFrom; to = app.dateInFY; unprinted = true }
            await load()
        }
        .sheet(item: $ewbRow) { r in EwayBillSheet(billId: r.int("bill_id")) }
        .sheet(item: $viewing) { r in
            if r.str("type") == "DEBIT_NOTE" {
                DebitNoteDetailSheet(id: r.int("bill_id"), onEdit: { edit(r) }, onDelete: { viewing = nil; Task { await delete(r) } })
            } else {
                BillDetailSheet(row: r, onEdit: { edit(r) }, onEway: { viewing = nil; Task { await pause(ms: 500); ewbRow = r } }, onDelete: { viewing = nil; Task { await delete(r) } })
            }
        }
        .confirmationDialog("Delete \(selection.count) selected bill\(selection.count == 1 ? "" : "s")?", isPresented: $confirmBulkDelete, titleVisibility: .visible) {
            Button("Delete \(selection.count)", role: .destructive) { Task { await bulkDeleteSelected() } }
        } message: {
            Text("A sale puts its stock back on the shelf and removes its ledger and receipt entries. A purchase takes its stock out again and is skipped if some of that stock was already sold. This cannot be undone.")
        }
    }

    private var table: some View {
    DataGrid(rows, layoutKey: "bills", selection: $selection, onOpen: { viewing = $0 }, menu: { r in AnyView(Group {
        Button("View") { viewing = r }; Button("Edit…") { edit(r) }; Divider()
        if r.str("type") == "SALE" { Button("E-way bill…") { ewbRow = r } }
        Button("Delete…", role: .destructive) { Task { await delete(r) } }
        if selection.count > 1 && selection.contains(r.id) {
            Button("Delete \(selection.count) selected…", role: .destructive) { confirmBulkDelete = true }
        }
    }) }) {
        GridColumn("Date", id: "date", min: 80, ideal: 95) { (r: JSON) in Text(Fmt.dmy(r.str("date"))).mono() }
        GridColumn("Type", id: "type", min: 60, ideal: 75) { (r: JSON) in
            Text(billTypeName(r)).fw(.semibold).foregroundStyle(billTypeColor(r))
        }
        GridColumn("Bill no", id: "no", min: 90, ideal: 120) { (r: JSON) in Text(r.str("no")).mono() }
        GridColumn("Supplier bill", id: "ref", min: 80, ideal: 110) { (r: JSON) in Text(r.str("ref")) }
        GridColumn("Party", id: "party", min: 140, ideal: 240) { (r: JSON) in Text(r.str("party")).lineLimit(1) }
        GridColumn("Total", id: "total", min: 90, ideal: 110, align: .trailing) { (r: JSON) in Text(Fmt.money(r, "total")).mono() }
        GridColumn("Paid", id: "paid", min: 90, ideal: 110, align: .trailing) { (r: JSON) in Text(Fmt.money(r, "paid")).mono() }
        GridColumn("Printed", id: "printed", min: 54, ideal: 64) { (r: JSON) in
            Text(r.str("type") != "SALE" ? "" : r.int("printed") == 1 ? "Yes" : "Not yet").foregroundStyle(r.int("printed") == 1 ? Color.secondary : Color.orange)
        }
        GridColumn("Due", id: "due", min: 90, ideal: 110, align: .trailing) { (r: JSON) in
            let due = r.num("total") - r.num("paid")
            Text(Fmt.money(due)).mono().fw(.semibold).foregroundStyle(due > 0.5 ? Color.red : Color.primary)
        }
    }
    .overlay {
        if loading { ProgressView() }
        else if rows.isEmpty { EmptyState(title: "No bills match these filters", symbol: "doc.text.magnifyingglass") }
    }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var filters: some View {
        HStack(spacing: 12) {
            Picker("Type", selection: $type) {
                Text("All").tag("ALL"); Text("Sales").tag("SALE"); Text("Purchases").tag("PURCHASE"); Text("Debit notes").tag("DEBIT_NOTE")
            }
            .pickerStyle(.segmented).frame(width: 340).labelsHidden()
            DateField(title: "From", iso: $from)
            DateField(title: "To", iso: $to)
            Toggle("Unpaid only", isOn: $unpaid)
            Toggle("Not printed", isOn: $unprinted).help("Sale bills kept to print later, or not printed since they were edited")
            Spacer()
            Button { Task { await printSelected() } } label: { Label(printLabel, systemImage: "printer") }
                .disabled(printIds.isEmpty)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var footer: some View {
        HStack(spacing: 24) {
            Text("\(rows.count) bills").foregroundStyle(.secondary)
            Spacer()
            Text("Sales \(Fmt.money(totals, "sales"))").mono()
            Text("Purchases \(Fmt.money(totals, "purchases"))").mono()
            if totals.num("debit_notes") > 0 { Text("Debit notes \(Fmt.money(totals, "debit_notes"))").mono() }
            Text("Due \(Fmt.money(totals, "due"))").mono().fw(.bold)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Theme.card)
    }

    /// Asks first; Cancel is the default button, so pressing Return or Escape keeps the bill.
    private func delete(_ r: JSON) async {
        let sale = r.str("type") == "SALE", dn = r.str("type") == "DEBIT_NOTE"
        let a = NSAlert()
        a.messageText = "Delete \(sale ? "bill" : dn ? "debit note" : "purchase bill") \(r.str("no"))?"
        a.informativeText = sale
            ? "Its stock goes back on the shelf, and its ledger and receipt entries are removed. This cannot be undone."
            : dn ? "The returned pieces go back into stock and its ledger entry is removed. This cannot be undone."
            : "The stock it brought in is taken out again and its ledger entries are removed. It is refused if some of that stock was already sold. This cannot be undone."
        a.alertStyle = .warning
        a.addButton(withTitle: "Cancel")
        let del = a.addButton(withTitle: "Delete bill")
        del.hasDestructiveAction = true
        guard a.runModal() == .alertSecondButtonReturn else { return }
        var done = false
        await app.guarded {
            _ = try await API.obj("DELETE", "\(billPath(r))/\(r.int("bill_id"))")
            done = true
        }
        if done { app.notify("Deleted \(r.str("no")).") }
        selection = []
        await load()
    }

    private func bulkDeleteSelected() async {
        busy = true
        await bulkDelete(Array(selection), notify: { app.notify($0) }) { id -> BulkOutcome in
            guard let r = rows.first(where: { $0.id == id }) else { return .failed(label: "#\(id)", reason: "not found") }
            let sale = r.str("type") == "SALE"
            do {
                _ = try await API.obj("DELETE", "\(billPath(r))/\(r.int("bill_id"))")
                return .deleted
            } catch {
                return .failed(label: r.str("no"), reason: error.localizedDescription)
            }
        }
        selection = []
        busy = false
        await load()
    }

    private func edit(_ r: JSON) {
        viewing = nil
        let t = r.str("type")
        app.pendingEdit = (t == "SALE" ? "INVOICE" : t == "DEBIT_NOTE" ? "DEBIT_NOTE" : "PURCHASE", r.int("bill_id"))
        app.section = t == "SALE" ? .billing : t == "DEBIT_NOTE" ? .debitNotes : .purchases
    }

    /// Sale bills to print: the selected ones, or, with "Not printed" on and nothing selected, every bill listed. Oldest first.
    private var printIds: [Int] {
        let sales = rows.filter { $0.str("type") == "SALE" }
        let picked = selection.isEmpty ? (unprinted ? sales : []) : sales.filter { selection.contains($0.id) }
        return picked.sorted { ($0.str("date"), $0.int("bill_id")) < ($1.str("date"), $1.int("bill_id")) }.map { $0.int("bill_id") }
    }
    private var printLabel: String { printIds.isEmpty ? "Print bills" : "Print \(printIds.count) bill\(printIds.count == 1 ? "" : "s")" }

    /// Buttons for the ticked bills (sale bills only: print, mark printed, send each on WhatsApp).
    private var selectedActions: AnyView {
        let sales = rows.filter { selection.contains($0.id) && $0.str("type") == "SALE" }
            .sorted { ($0.str("date"), $0.int("bill_id")) < ($1.str("date"), $1.int("bill_id")) }.map { $0.int("bill_id") }
        return AnyView(HStack(spacing: 12) {
            Button { Task { await printInvoices(sales, app: app) } } label: { Label("Print \(sales.count)", systemImage: "printer") }
            Button { markPrinted(sales, app: app); app.notify("\(sales.count) bill\(sales.count == 1 ? "" : "s") marked printed."); Task { await pause(ms: 400); await load() } } label: {
                Label("Mark printed", systemImage: "checkmark.seal")
            }
            Button {
                Task {
                    busy = true
                    for id in sales { await WhatsApp.send(id, app: app, quiet: true) }
                    busy = false
                    app.notify("Sent \(sales.count) bill\(sales.count == 1 ? "" : "s") on WhatsApp.")
                }
            } label: { Label("WhatsApp", systemImage: "paperplane") }
        }
        .disabled(sales.isEmpty || busy))
    }

    private func printSelected() async {
        let ids = printIds
        guard !ids.isEmpty else { return }
        await printInvoices(ids, app: app)
    }

    private func load() async {
        await app.guarded {
            let r = try await API.obj("GET", "/bills", query: ["type": type, "from": from, "to": to, "q": query, "unpaid": unpaid ? 1 : 0, "unprinted": unprinted ? 1 : 0])
            // a sale, a purchase and a debit note can share the same database id, so rows get a unique table id
            // (purchases negative, debit notes from 1,000,000,000)
            rows = r.list("rows").map { x in
                var y = x
                y.raw["bill_id"] = x.int("id")
                y.raw["id"] = x.str("type") == "SALE" ? x.int("id") : x.str("type") == "DEBIT_NOTE" ? 1_000_000_000 + x.int("id") : -x.int("id")
                return y
            }
            totals = r.obj("totals")
        }
        loading = false
    }
}

@MainActor struct BillDetailSheet: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    let row: JSON
    let onEdit: () -> Void
    var onEway: () -> Void = {}
    let onDelete: () -> Void
    @State private var bill: JSON?

    private var sale: Bool { row.str("type") == "SALE" }

    var body: some View {
        let b = bill ?? JSON()
        InfoSheet(title: "\(sale ? b.str("invoice_no") : b.str("purchase_no")) · \(b.str("party_name").isEmpty ? "Cash customer" : b.str("party_name"))", width: 940, height: 560, trailing: AnyView(
            HStack {
                if sale { Button("WhatsApp") { Task { await WhatsApp.send(row.int("bill_id"), app: app) } } }
                if sale { Button("Print…") { dismiss(); Task { await printInvoice(row.int("bill_id"), app: app, forcePreview: true) } } }
                if sale { Button("E-way bill…") { dismiss(); onEway() } }
                if !sale { Button("Return goods…") { dismiss(); app.pendingEdit = ("RETURN_PURCHASE", row.int("bill_id")); app.section = .debitNotes } }
                Button("Edit…") { dismiss(); onEdit() }
                Button("Delete…", role: .destructive) { dismiss(); onDelete() }
            }
        )) {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(Fmt.dmy(b.str("date")))\(sale ? "" : "   ·   Supplier bill \(b.str("supplier_invoice_no"))")   ·   Total \(Fmt.money(b, "total"))   ·   Paid \(Fmt.money(b, "paid"))   ·   Due \(Fmt.money(b.num("total") - b.num("paid")))")
                    .foregroundStyle(.secondary)
                DataGrid(b.list("lines"), layoutKey: "billdetail") {
                    GridColumn("S.No", id: "sno", min: 44, ideal: 48, align: .trailing) { (l: JSON) in Text("\(l.rid)").mono().foregroundStyle(.secondary) }
                    GridColumn("Item", id: "item", min: 160, ideal: 300) { (l: JSON) in Text(l.str("item_name")).lineLimit(1) }
                    GridColumn("Qty (box + pcs)", id: "qty", min: 90, ideal: 120, align: .trailing) { (l: JSON) in // a purchase line's qty is in its unit (boxes for BOX); pcs_qty is the pieces
                        Text(Fmt.boxPcs(l.has("pcs_qty") ? l.int("pcs_qty") : l.int("qty"), l.int("pcs_per_box"))).mono() }
                    GridColumn("Free pcs", id: "free", min: 40, ideal: 55, align: .trailing) { (l: JSON) in Text(l.str("free_qty")).mono() }
                    GridColumn("Rate", id: "rate", min: 70, ideal: 90, align: .trailing) { (l: JSON) in Text(Fmt.money(l, "rate")).mono() }
                    GridColumn("Taxable", id: "taxable", min: 80, ideal: 100, align: .trailing) { (l: JSON) in Text(Fmt.money(l, "taxable")).mono() }
                    GridColumn("GST", id: "gst", min: 40, ideal: 55, align: .trailing) { (l: JSON) in Text("\(l.str("gst_rate"))%").mono() }
                    GridColumn("Amount", id: "amount", min: 90, ideal: 110, align: .trailing) { (l: JSON) in Text(Fmt.money(l, "amount")).mono().fw(.semibold) }
                }
            }
        }
        .task {
            await app.guarded { bill = try await API.obj("GET", sale ? "/invoices/\(row.int("bill_id"))" : "/purchases/\(row.int("bill_id"))") }
        }
    }
}

/// All Bills: what a row is, its colour, and where it lives in the engine.
func billTypeName(_ r: JSON) -> String { r.str("type") == "SALE" ? "Sale" : r.str("type") == "DEBIT_NOTE" ? "Debit note" : "Purchase" }
func billTypeColor(_ r: JSON) -> Color { r.str("type") == "SALE" ? Color.teal : r.str("type") == "DEBIT_NOTE" ? Color.purple : Color.orange }
func billPath(_ r: JSON) -> String { r.str("type") == "SALE" ? "/invoices" : r.str("type") == "DEBIT_NOTE" ? "/debit-notes" : "/purchases" }
