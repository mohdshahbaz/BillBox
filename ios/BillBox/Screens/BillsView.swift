import SwiftUI

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
    @State private var selecting = false
    @State private var loading = true
    @State private var busy = false
    @State private var viewing: JSON?
    @State private var ewbRow: JSON?
    @State private var deleting: JSON?
    @State private var confirmBulkDelete = false

    var body: some View {
        VStack(spacing: 0) {
            filters
            SelectionBar(ids: rows.map(\.id), selection: $selection, selecting: $selecting, actionLabel: "Delete selected bills…", busy: busy, extra: selectedActions) { confirmBulkDelete = true }
            table
            footer
        }
        .background(Theme.page)
        .navigationTitle("")   // the tab bar already says which tab this is
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search bill no or party")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { Task { await printSelected() } } label: { Label(printLabel, systemImage: "printer") }
                    .disabled(printIds.isEmpty)
                    .keyboardShortcut("p", modifiers: .command)
            }
        }
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
                DebitNoteDetailSheet(id: r.int("bill_id"), onEdit: { edit(r) }, onDelete: { viewing = nil; Task { await pause(ms: 500); deleting = r } })
            } else {
                BillDetailSheet(row: r, onEdit: { edit(r) }, onEway: { viewing = nil; Task { await pause(ms: 500); ewbRow = r } }, onDelete: { viewing = nil; Task { await pause(ms: 500); deleting = r } })
            }
        }
        .confirmationDialog(deleteTitle, isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete bill", role: .destructive) { if let r = deleting { Task { await delete(r) } } }
            Button("Cancel", role: .cancel) {}
        } message: { Text(deleteMessage) }
        .confirmationDialog("Delete \(selection.count) selected bill\(selection.count == 1 ? "" : "s")?", isPresented: $confirmBulkDelete, titleVisibility: .visible) {
            Button("Delete \(selection.count)", role: .destructive) { Task { await bulkDeleteSelected() } }
        } message: {
            Text("A sale puts its stock back on the shelf and removes its ledger and receipt entries. A purchase takes its stock out again and is skipped if some of that stock was already sold. This cannot be undone.")
        }
    }

    private var deleteTitle: String {
        guard let r = deleting else { return "" }
        return "Delete \(r.str("type") == "SALE" ? "bill" : r.str("type") == "DEBIT_NOTE" ? "debit note" : "purchase bill") \(r.str("no"))?"
    }
    private var deleteMessage: String {
        guard let r = deleting else { return "" }
        return r.str("type") == "SALE"
            ? "Its stock goes back on the shelf, and its ledger and receipt entries are removed. This cannot be undone."
            : r.str("type") == "DEBIT_NOTE" ? "The returned pieces go back into stock and its ledger entry is removed. This cannot be undone."
            : "The stock it brought in is taken out again and its ledger entries are removed. It is refused if some of that stock was already sold. This cannot be undone."
    }

    private var table: some View {
        DataGrid(rows, layoutKey: "bills", selection: $selection, selecting: $selecting, onOpen: { viewing = $0 }, menu: { r in AnyView(Group {
            Button { viewing = r } label: { Label("View", systemImage: "doc.text.magnifyingglass") }
            Button { edit(r) } label: { Label("Edit…", systemImage: "pencil") }
            if r.str("type") == "SALE" { Button { ewbRow = r } label: { Label("E-way bill…", systemImage: "truck.box") } }
            Divider()
            Button(role: .destructive) { deleting = r } label: { Label("Delete…", systemImage: "trash") }
            if selection.count > 1 && selection.contains(r.id) {
                Button(role: .destructive) { confirmBulkDelete = true } label: { Label("Delete \(selection.count) selected…", systemImage: "trash") }
            }
        }) }) {
            GridColumn("Date", id: "date", min: 86, ideal: 96) { (r: JSON) in Text(Fmt.dmy(r.str("date"))).monospacedDigit() }
            GridColumn("Type", id: "type", min: 70, ideal: 80) { (r: JSON) in
                Text(billTypeName(r)).fontWeight(.semibold).foregroundStyle(billTypeColor(r))
            }
            GridColumn("Bill no", id: "no", min: 110, ideal: 130) { (r: JSON) in Text(r.str("no")).monospacedDigit() }
            GridColumn("Supplier bill", id: "ref", min: 80, ideal: 110) { (r: JSON) in Text(r.str("ref")) }
            GridColumn("Party", id: "party", min: 140, ideal: 200) { (r: JSON) in Text(r.str("party")).lineLimit(2) }
            GridColumn("Total", id: "total", min: 90, ideal: 110, align: .trailing) { (r: JSON) in Text(Fmt.money(r, "total")).monospacedDigit() }
            GridColumn("Paid", id: "paid", min: 90, ideal: 110, align: .trailing) { (r: JSON) in Text(Fmt.money(r, "paid")).monospacedDigit() }
            GridColumn("Printed", id: "printed", min: 54, ideal: 64) { (r: JSON) in
                Text(r.str("type") != "SALE" ? "" : r.int("printed") == 1 ? "Yes" : "Not yet").foregroundStyle(r.int("printed") == 1 ? Color.secondary : Color.orange)
            }
            GridColumn("Due", id: "due", min: 90, ideal: 110, align: .trailing) { (r: JSON) in
                let due = r.num("total") - r.num("paid")
                Text(Fmt.money(due)).monospacedDigit().fontWeight(.semibold).foregroundStyle(due > 0.5 ? Color.red : Color.primary)
            }
        }
        .overlay {
            if loading { ProgressView() }
            else if rows.isEmpty { EmptyState(title: "No bills match these filters", symbol: "doc.text.magnifyingglass") }
        }
    }

    private var filters: some View {
        VStack(spacing: 6) {
            Picker("Type", selection: $type) {
                Text("All").tag("ALL"); Text("Sales").tag("SALE"); Text("Purchases").tag("PURCHASE"); Text("Debit notes").tag("DEBIT_NOTE")
            }
            .pickerStyle(.segmented).labelsHidden()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    DateField(title: "From", iso: $from); DateField(title: "To", iso: $to)
                    Toggle("Unpaid only", isOn: $unpaid).fixedSize(); Toggle("Not printed", isOn: $unprinted).fixedSize()
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) { DateField(title: "From", iso: $from); DateField(title: "To", iso: $to) }
                    HStack(spacing: 16) { Toggle("Unpaid only", isOn: $unpaid).fixedSize(); Toggle("Not printed", isOn: $unprinted).fixedSize() }
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { footerItems }
            VStack(alignment: .leading, spacing: 2) { footerItems }
        }
        .font(.callout)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
    }

    @ViewBuilder private var footerItems: some View {
        Text("\(rows.count) bills").foregroundStyle(.secondary)
        Text("Sales \(Fmt.money(totals, "sales"))").monospacedDigit()
        Text("Purchases \(Fmt.money(totals, "purchases"))").monospacedDigit()
        if totals.num("debit_notes") > 0 { Text("Debit notes \(Fmt.money(totals, "debit_notes"))").monospacedDigit() }
        Text("Due \(Fmt.money(totals, "due"))").monospacedDigit().fontWeight(.bold)
    }

    private func delete(_ r: JSON) async {
        let sale = r.str("type") == "SALE"
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
        selecting = false
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
        .labelStyle(.iconOnly)   // a phone row is narrow: icons, with their names for VoiceOver
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
        InfoSheet(title: "\(sale ? b.str("invoice_no") : b.str("purchase_no")) · \(b.str("party_name").isEmpty ? "Cash customer" : b.str("party_name"))", trailing: AnyView(
            HStack {
                if sale { Button { Task { await WhatsApp.send(row.int("bill_id"), app: app) } } label: { Label("WhatsApp", systemImage: "paperplane") } }
                if sale { Button { dismiss(); Task { await printInvoice(row.int("bill_id"), app: app, forcePreview: true) } } label: { Label("Print…", systemImage: "printer") } }
                if sale { Button { dismiss(); onEway() } label: { Label("E-way bill", systemImage: "truck.box") } }
                Spacer()
                if !sale { Button { dismiss(); app.pendingEdit = ("RETURN_PURCHASE", row.int("bill_id")); app.section = .debitNotes } label: { Label("Return goods…", systemImage: "arrow.uturn.backward") } }
                Button { dismiss(); onEdit() } label: { Label("Edit…", systemImage: "pencil") }
                Button(role: .destructive) { dismiss(); onDelete() } label: { Label("Delete…", systemImage: "trash") }
            }
        )) {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(Fmt.dmy(b.str("date")))\(sale ? "" : "   ·   Supplier bill \(b.str("supplier_invoice_no"))")   ·   Total \(Fmt.money(b, "total"))   ·   Paid \(Fmt.money(b, "paid"))   ·   Due \(Fmt.money(b.num("total") - b.num("paid")))")
                    .foregroundStyle(.secondary).font(.callout)
                DataGrid(b.list("lines"), layoutKey: "billdetail") {
                    GridColumn("S.No", id: "sno", min: 44, ideal: 48, align: .trailing) { (l: JSON) in Text("\(l.rid)").monospacedDigit().foregroundStyle(.secondary) }
                    GridColumn("Item", id: "item", min: 150, ideal: 240) { (l: JSON) in Text(l.str("item_name")).lineLimit(2) }
                    GridColumn("Qty (box + pcs)", id: "qty", min: 90, ideal: 120, align: .trailing) { (l: JSON) in // a purchase line's qty is in its unit (boxes for BOX); pcs_qty is the pieces
                        Text(Fmt.boxPcs(l.has("pcs_qty") ? l.int("pcs_qty") : l.int("qty"), l.int("pcs_per_box"))).monospacedDigit() }
                    GridColumn("Free pcs", id: "free", min: 44, ideal: 60, align: .trailing) { (l: JSON) in Text(l.str("free_qty")).monospacedDigit() }
                    GridColumn("Rate", id: "rate", min: 70, ideal: 90, align: .trailing) { (l: JSON) in Text(Fmt.money(l, "rate")).monospacedDigit() }
                    GridColumn("Taxable", id: "taxable", min: 80, ideal: 100, align: .trailing) { (l: JSON) in Text(Fmt.money(l, "taxable")).monospacedDigit() }
                    GridColumn("GST", id: "gst", min: 44, ideal: 55, align: .trailing) { (l: JSON) in Text("\(l.str("gst_rate"))%").monospacedDigit() }
                    GridColumn("Amount", id: "amount", min: 90, ideal: 110, align: .trailing) { (l: JSON) in Text(Fmt.money(l, "amount")).monospacedDigit().fontWeight(.semibold) }
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
