import SwiftUI

/// One row of a debit note being written.
struct DNLine: Identifiable, Equatable {
    let id = UUID()
    var itemId = 0
    var qty = "1"
    var unit = "PCS"
    var rate = ""
    /// 0 = take the pieces from the earliest-expiring batches
    var batchId = 0
}

/// Debit notes: goods sent back to a supplier. Each note takes the pieces out of stock, debits the supplier's ledger
/// (you owe them that much less) and takes its GST off the month's input tax credit.
@MainActor struct DebitNotesView: View {
    @EnvironmentObject private var app: AppModel
    @State private var query = ""
    @State private var searchDelay = Debouncer()
    @State private var rows: [JSON] = []
    @State private var totals = JSON()
    @State private var loading = true
    @State private var viewing: JSON?
    @State private var editing: DNEdit?
    @State private var deleting: JSON?

    var body: some View {
        VStack(spacing: 0) {
            table
            footer
        }
        .background(Theme.page)
        .navigationTitle("Debit Notes")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search note no, supplier or bill")
        .onChange(of: query) { _ in searchDelay.run { await load() } }   // typing loads once, 250 ms after the last key
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { editing = DNEdit() } label: { Label("New debit note", systemImage: "plus") }
                    .keyboardShortcut("n", modifiers: .command)
            }
        }
        .task(id: app.fy) { await load() }
        .onChange(of: app.section) { s in if s == .debitNotes { Task { await takePending() } } }
        .task { await takePending() }
        .sheet(item: $viewing) { r in
            DebitNoteDetailSheet(id: r.id, onEdit: { viewing = nil; editing = DNEdit(noteId: r.id) },
                                 onDelete: { viewing = nil; Task { await pause(ms: 500); deleting = r } })
        }
        .sheet(item: $editing) { e in
            DebitNoteEditor(editId: e.noteId, fromPurchase: e.purchaseId) { await load() }
        }
        .confirmationDialog("Delete debit note \(deleting?.str("note_no") ?? "")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete debit note", role: .destructive) { if let r = deleting { Task { await delete(r) } } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The returned pieces go back into stock and its ledger entry is removed. This cannot be undone.") }
    }

    private var table: some View {
        DataGrid(rows, layoutKey: "debitnotes", onOpen: { viewing = $0 }, menu: { r in AnyView(Group {
            Button { viewing = r } label: { Label("View", systemImage: "doc.text.magnifyingglass") }
            Button { Task { await printDebitNote(r.id, app: app) } } label: { Label("Print…", systemImage: "printer") }
            Button { editing = DNEdit(noteId: r.id) } label: { Label("Edit…", systemImage: "pencil") }
            Divider()
            Button(role: .destructive) { deleting = r } label: { Label("Delete…", systemImage: "trash") }
        }) }) {
            GridColumn("Date", id: "date", min: 122, ideal: 124) { (r: JSON) in Text(Fmt.dmy(r.str("date"))).monospacedDigit() }
            GridColumn("Note no", id: "no", min: 120, ideal: 140, sort: { (r: JSON) -> Any? in r.str("note_no") }) { (r: JSON) in Text(r.str("note_no")).monospacedDigit() }
            GridColumn("Supplier", id: "party", min: 140, ideal: 200) { (r: JSON) in Text(r.str("party")).lineLimit(2) }
            GridColumn("Against bill", id: "ref", min: 90, ideal: 120, sort: { (r: JSON) -> Any? in r.str("against_bill") }) { (r: JSON) in Text(r.str("against_bill")) }
            GridColumn("Reason", id: "reason", min: 90, ideal: 140) { (r: JSON) in Text(r.str("reason")).lineLimit(2) }
            GridColumn("Taxable", id: "taxable", min: 90, ideal: 110, align: .trailing) { (r: JSON) in Text(Fmt.money(r, "taxable")).monospacedDigit() }
            GridColumn("GST", id: "gst", min: 80, ideal: 100, align: .trailing, sort: { (r: JSON) -> Any? in r.num("cgst") + r.num("sgst") + r.num("igst") }) { (r: JSON) in Text(Fmt.money(r.num("cgst") + r.num("sgst") + r.num("igst"))).monospacedDigit() }
            GridColumn("Total", id: "total", min: 90, ideal: 110, align: .trailing) { (r: JSON) in Text(Fmt.money(r, "total")).monospacedDigit().fontWeight(.semibold) }
        }
        .overlay {
            if loading && rows.isEmpty { SkeletonRows() }
            else if loading { ProgressView() }
            else if rows.isEmpty { EmptyState(title: "No debit notes in \(app.fy)", symbol: "arrow.uturn.backward.square") }
        }
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
        Text("\(totals.int("count")) notes").foregroundStyle(.secondary)
        Text("Taxable \(Fmt.money(totals, "taxable"))").monospacedDigit()
        Text("GST reversed \(Fmt.money(totals.num("cgst") + totals.num("sgst") + totals.num("igst")))").monospacedDigit()
        Text("Total \(Fmt.money(totals, "total"))").monospacedDigit().fontWeight(.bold)
    }

    private func load() async {
        await app.guarded {
            let r = try await API.obj("GET", "/debit-notes", query: ["q": query])
            rows = r.list("rows")
            totals = r.obj("totals")
        }
        loading = false
    }

    /// "Return goods…" on a purchase bill, or Edit in All Bills, lands here.
    private func takePending() async {
        guard let e = app.pendingEdit else { return }
        if e.type == "DEBIT_NOTE" { app.pendingEdit = nil; editing = DNEdit(noteId: e.id) }
        else if e.type == "RETURN_PURCHASE" { app.pendingEdit = nil; editing = DNEdit(purchaseId: e.id) }
    }

    private func delete(_ r: JSON) async {
        var done = false
        await app.guarded {
            _ = try await API.obj("DELETE", "/debit-notes/\(r.id)")
            done = true
        }
        if done { app.notify("Deleted \(r.str("note_no")).") }
        await load()
    }
}

/// What the editor sheet opens with: a saved note to edit, or a purchase bill to return goods from.
struct DNEdit: Identifiable {
    let id = UUID()
    var noteId: Int?
    var purchaseId: Int?
}

/// Writes or edits one debit note.
@MainActor struct DebitNoteEditor: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    let editId: Int?
    var fromPurchase: Int?
    let done: () async -> Void

    @State private var suppliers: [JSON] = []
    @State private var items: [JSON] = []
    @State private var itemChoices: [Choice] = []
    @State private var bills: [JSON] = []
    @State private var batches: [Int: [JSON]] = [:]
    @State private var partyId = 0
    @State private var date = ""
    @State private var purchaseId = 0
    @State private var against = ""
    @State private var reason = ""
    @State private var notes = ""
    @State private var discount = ""
    @State private var lines: [DNLine] = [DNLine()]
    @State private var noteNo = ""
    @State private var preview: JSON?
    @State private var errorText: String?
    @State private var busy = false
    @State private var loaded = false

    static let reasons = ["Damaged", "Expired / near expiry", "Short supply", "Wrong item sent", "Rate difference", "Excess supply"]

    private var payload: [String: Any] {
        var b: [String: Any] = ["party_id": partyId, "date": date, "against_bill": against, "reason": reason, "notes": notes, "discount": discount]
        if purchaseId > 0 { b["purchase_id"] = purchaseId }
        b["lines"] = lines.filter { $0.itemId > 0 }.map { l -> [String: Any] in
            var x: [String: Any] = ["item_id": l.itemId, "qty": l.qty, "unit": l.unit, "rate": l.rate]
            if l.batchId > 0 { x["batch_id"] = l.batchId }
            return x
        }
        return b
    }

    private var recalcKey: String {
        "\(partyId)|\(date)|\(discount)|" + lines.map { "\($0.itemId):\($0.qty):\($0.unit):\($0.rate):\($0.batchId)" }.joined(separator: ",")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SearchPicker(title: "Supplier", placeholder: "Select supplier…", choices: suppliers.map { Choice(id: $0.id, label: $0.str("name"), detail: $0.str("gstin")) },
                                 selection: $partyId) { _ in purchaseId = 0; Task { await loadBills() } }
                    DateField(title: "Date", iso: $date)
                    Picker("Against purchase bill", selection: $purchaseId) {
                        Text("None").tag(0)
                        ForEach(bills) { b in Text("\(b.str("ref").isEmpty ? b.str("no") : b.str("ref"))  ·  \(Fmt.dmy(b.str("date")))  ·  \(Fmt.money(b, "total"))").tag(b.int("bill_id")) }
                    }
                    if purchaseId > 0 {
                        Button { Task { await fillFromPurchase(purchaseId) } } label: { Label("Fill the rows from this bill", systemImage: "arrow.down.doc") }
                    }
                    Field("Supplier's bill no. (if not picked above)", text: $against).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    HStack {
                        Field("Reason", text: $reason)
                        Menu { ForEach(Self.reasons, id: \.self) { r in Button(r) { reason = r } } } label: { Image(systemName: "list.bullet") }
                            .accessibilityLabel("Pick a reason")
                    }
                } footer: {
                    if !noteNo.isEmpty { Text("Editing \(noteNo). Saving puts the old pieces back first, then takes the corrected rows out of stock.") }
                }

                Section {
                    ForEach(lines) { l in lineEditor(lineBinding(l.id)) }
                    Button { lines.append(DNLine()) } label: { Label("Add row", systemImage: "plus") }
                } header: { Text("Goods returned") } footer: {
                    Text("Rate is ex-GST, per box for a row in boxes. Pieces come out of the batch you pick, or the earliest-expiring batches.")
                }

                Section("Totals") {
                    Field("Discount", text: $discount, prompt: Text("0")).keyboardType(.decimalPad)
                    if let p = preview {
                        row("Items", p.num("subtotal"))
                        row("Taxable", p.num("taxable"))
                        if p.str("supply") == "INTER" { row("IGST", p.num("igst")) } else { row("CGST", p.num("cgst")); row("SGST", p.num("sgst")) }
                        if p.num("round_off") != 0 { row("Round off", p.num("round_off")) }
                        HStack { Text("Debit note total").fontWeight(.bold); Spacer(); Text(Fmt.money(p, "total")).fontWeight(.bold).monospacedDigit().foregroundStyle(.teal) }
                    }
                    Field("Notes", text: $notes, axis: .vertical)
                }
                if let errorText { Section { Text(errorText).font(.callout).foregroundStyle(.red) } }
            }
            .groupedForm()
            .navigationTitle(editId == nil ? "New debit note" : "Edit \(noteNo)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editId == nil ? "Save" : "Update") { Task { await save(print: false) } }.keyboardShortcut(.defaultAction).disabled(busy || preview == nil)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button { Task { await save(print: true) } } label: { Label("Save and print", systemImage: "printer") }.disabled(busy || preview == nil)
                }
            }
            .overlay { if busy { ProgressView() } }
        }
        .task {
            guard !loaded else { return }
            loaded = true
            if date.isEmpty { date = app.dateInFY }
            await loadLists()
            if let editId { await loadNote(editId) } else if let fromPurchase { await startFromPurchase(fromPurchase) }
        }
        .task(id: recalcKey) {
            await pause(ms: 250)
            if Task.isCancelled { return }
            await recalc()
        }
    }

    private func lineBinding(_ id: UUID) -> Binding<DNLine> {
        Binding(get: { lines.first(where: { $0.id == id }) ?? DNLine() },
                set: { v in if let i = lines.firstIndex(where: { $0.id == id }) { lines[i] = v } })
    }

    private func row(_ a: String, _ v: Double) -> some View {
        HStack { Text(a).foregroundStyle(.secondary); Spacer(); Text(Fmt.money(v)).monospacedDigit() }
    }

    @ViewBuilder private func lineEditor(_ l: Binding<DNLine>) -> some View {
        let it = items.first { $0.id == l.wrappedValue.itemId }
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SearchPicker(title: "Item", placeholder: "Select item…", choices: itemChoices, selection: l.itemId) { picked in
                    l.wrappedValue.batchId = 0
                    if l.wrappedValue.rate.isEmpty, let x = items.first(where: { $0.id == picked }), x.num("purchase_price") > 0 {
                        l.wrappedValue.rate = Fmt.rate(x.num("purchase_price") * (l.wrappedValue.unit == "BOX" ? Double(max(1, x.int("pcs_per_box"))) : 1))
                    }
                    Task { await loadBatches(picked) }
                }
                Button(role: .destructive) { if lines.count > 1 { lines.removeAll { $0.id == l.wrappedValue.id } } } label: { Image(systemName: "minus.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.red).disabled(lines.count < 2).accessibilityLabel("Remove row")
            }
            HStack(spacing: 8) {
                Field("Qty", text: l.qty).keyboardType(.numberPad).frame(maxWidth: 70)
                Picker("Unit", selection: l.unit) { Text("Pcs").tag("PCS"); Text("Box").tag("BOX") }.pickerStyle(.segmented).frame(maxWidth: 120)
                Field(l.wrappedValue.unit == "BOX" ? "Rate / box" : "Rate / pc", text: l.rate).keyboardType(.decimalPad)
            }
            if let it {
                let ppb = max(1, it.int("pcs_per_box"))
                let q = Int(l.wrappedValue.qty.trimmingCharacters(in: .whitespaces)) ?? 0
                let pcs = l.wrappedValue.unit == "BOX" ? q * ppb : q
                Picker("Batch", selection: l.batchId) {
                    Text("Earliest expiry first").tag(0)
                    ForEach(batches[it.id] ?? []) { b in
                        Text("\(b.str("batch_no"))  ·  \(Fmt.boxPcs(b.int("qty"), ppb))\(b.str("exp_date") < "2099-01-01" ? "  ·  exp \(Fmt.dmy(b.str("exp_date")))" : "")").tag(b.id)
                    }
                }
                Text("\(Fmt.boxPcs(pcs, ppb)) out of stock  ·  in stock \(Fmt.boxPcs(it.int("stock"), ppb))  ·  GST \(Fmt.qty(it.num("gst_rate")))%")
                    .font(.caption).foregroundStyle(pcs > it.int("stock") ? Color.red : Color.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func loadLists() async {
        await app.guarded {
            async let s = API.list("/parties", query: ["kind": "SUPPLIER"])
            async let i = API.list("/items")
            suppliers = try await s
            items = try await i
            itemChoices = items.map { Choice(id: $0.id, label: $0.str("name"), detail: "\($0.str("hsn"))  ·  stock \(Fmt.boxPcs($0.int("stock"), $0.int("pcs_per_box")))") }
        }
    }

    private func loadBills() async {
        guard let name = suppliers.first(where: { $0.id == partyId })?.str("name") else { bills = []; return }
        await app.guarded {
            let r = try await API.obj("GET", "/bills", query: ["type": "PURCHASE", "q": name, "from": "2000-01-01", "to": "2100-12-31"])
            bills = r.list("rows").filter { $0.str("party") == name }.map { x in var y = x; y.raw["bill_id"] = x.int("id"); return y }
        }
    }

    private func loadBatches(_ itemId: Int) async {
        guard itemId > 0, batches[itemId] == nil else { return }
        do { batches[itemId] = try await API.list("/items/\(itemId)/batches").filter { $0.int("qty") > 0 } } catch {}
    }

    private func fillFromPurchase(_ id: Int) async {
        await app.guarded {
            let p = try await API.obj("GET", "/purchases/\(id)")
            lines = p.list("lines").map { x in
                var l = DNLine()
                l.itemId = x.int("item_id")
                let box = x.str("unit").range(of: "^(BOX|BOXES|BX|CASE|CS|CTN|CARTON)$", options: [.regularExpression, .caseInsensitive]) != nil
                l.unit = box ? "BOX" : "PCS"
                l.qty = String(Int(x.num("qty")))
                l.rate = x.str("rate")
                l.batchId = x.int("batch_id")
                return l
            }
            if lines.isEmpty { lines = [DNLine()] }
            for l in lines { await loadBatches(l.itemId) }
        }
    }

    private func startFromPurchase(_ id: Int) async {
        await app.guarded {
            let p = try await API.obj("GET", "/purchases/\(id)")
            partyId = p.int("party_id")
            await loadBills()
            purchaseId = id
        }
        await fillFromPurchase(id)
    }

    private func loadNote(_ id: Int) async {
        await app.guarded {
            let d = try await API.obj("GET", "/debit-notes/\(id)")
            noteNo = d.str("note_no")
            partyId = d.int("party_id")
            date = d.str("date")
            await loadBills()
            purchaseId = d.int("purchase_id")
            against = purchaseId > 0 ? "" : d.str("against_bill")
            reason = d.str("reason")
            notes = d.str("notes")
            discount = d.num("discount") == 0 ? "" : d.str("discount")
            lines = d.list("lines").map { x in
                var l = DNLine()
                l.itemId = x.int("item_id")
                l.qty = String(Int(x.num("qty")))
                l.unit = x.str("unit") == "BOX" ? "BOX" : "PCS"
                l.rate = x.str("rate")
                l.batchId = x.int("batch_id")
                return l
            }
            if lines.isEmpty { lines = [DNLine()] }
            for l in lines { await loadBatches(l.itemId) }
        }
    }

    private func recalc() async {
        guard partyId > 0, lines.contains(where: { $0.itemId > 0 }) else { preview = nil; errorText = nil; return }
        do {
            let r = try await API.objRaw("POST", "/debit-notes/preview", body: payload)
            if Task.isCancelled { return }
            preview = r
            errorText = nil
        } catch {
            if Task.isCancelled { return }
            preview = nil
            errorText = error.localizedDescription
        }
    }

    private func save(print: Bool) async {
        busy = true
        defer { busy = false }
        do {
            let r = editId == nil ? try await API.objRaw("POST", "/debit-notes", body: payload) : try await API.objRaw("PUT", "/debit-notes/\(editId!)", body: payload)
            app.notify("\(editId == nil ? "Saved" : "Updated") debit note \(r.str("note_no")) for \(Fmt.money(r, "total")). The pieces are out of stock.")
            await done()
            dismiss()
            if print { await pause(ms: 500); await printDebitNote(r.int("id"), app: app) }
        } catch {
            errorText = error.localizedDescription
        }
    }
}

/// A saved debit note: its rows and totals, with Print, Edit and Delete.
@MainActor struct DebitNoteDetailSheet: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    let id: Int
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var d: JSON?

    var body: some View {
        let n = d ?? JSON()
        InfoSheet(title: "\(n.str("note_no")) · \(n.str("party_name"))", trailing: AnyView(
            HStack {
                Button { dismiss(); Task { await printDebitNote(id, app: app) } } label: { Label("Print…", systemImage: "printer") }
                Spacer()
                Button { dismiss(); onEdit() } label: { Label("Edit…", systemImage: "pencil") }
                Button(role: .destructive) { dismiss(); onDelete() } label: { Label("Delete…", systemImage: "trash") }
            }
        )) {
            VStack(alignment: .leading, spacing: 8) {
                Text([Fmt.dmy(n.str("date")), n.str("against_bill").isEmpty ? "" : "Against bill \(n.str("against_bill"))", n.str("reason"),
                      "Total \(Fmt.money(n, "total"))"].filter { !$0.isEmpty }.joined(separator: "   ·   "))
                    .foregroundStyle(.secondary).font(.callout)
                DataGrid(n.list("lines"), layoutKey: "debitnotedetail") {
                    GridColumn("Item", id: "item", min: 150, ideal: 240, sort: { (l: JSON) -> Any? in l.str("item_name") }) { (l: JSON) in Text(l.str("item_name")).lineLimit(2) }
                    GridColumn("Qty", id: "qty", min: 90, ideal: 120, align: .trailing, sort: { (l: JSON) -> Any? in l.int("pcs_qty") }) { (l: JSON) in Text(Fmt.boxPcs(l.int("pcs_qty"), l.int("pcs_per_box"))).monospacedDigit() }
                    GridColumn("Rate", id: "rate", min: 80, ideal: 100, align: .trailing) { (l: JSON) in Text("\(Fmt.money(l, "rate")) / \(l.str("unit") == "BOX" ? "box" : "pc")").monospacedDigit() }
                    GridColumn("Batch", id: "batch", min: 80, ideal: 110, sort: { (l: JSON) -> Any? in l.str("batch_no") }) { (l: JSON) in Text(l.str("batch_no")).lineLimit(2) }
                    GridColumn("Taxable", id: "taxable", min: 80, ideal: 100, align: .trailing) { (l: JSON) in Text(Fmt.money(l, "taxable")).monospacedDigit() }
                    GridColumn("GST", id: "gst", min: 44, ideal: 55, align: .trailing, sort: { (l: JSON) -> Any? in l.num("gst_rate") }) { (l: JSON) in Text("\(Fmt.qty(l.num("gst_rate")))%").monospacedDigit() }
                    GridColumn("Tax", id: "tax", min: 70, ideal: 90, align: .trailing, sort: { (l: JSON) -> Any? in l.num("cgst") + l.num("sgst") + l.num("igst") }) { (l: JSON) in Text(Fmt.money(l.num("cgst") + l.num("sgst") + l.num("igst"))).monospacedDigit() }
                }
                HStack(spacing: 16) {
                    Text("Taxable \(Fmt.money(n, "taxable"))")
                    if n.num("igst") > 0 { Text("IGST \(Fmt.money(n, "igst"))") } else { Text("CGST \(Fmt.money(n, "cgst"))"); Text("SGST \(Fmt.money(n, "sgst"))") }
                    Text("Total \(Fmt.money(n, "total"))").fontWeight(.bold)
                }
                .font(.callout).monospacedDigit()
            }
        }
        .task { await app.guarded { d = try await API.obj("GET", "/debit-notes/\(id)") } }
    }
}
