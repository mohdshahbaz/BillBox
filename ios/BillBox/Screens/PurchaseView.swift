import SwiftUI
import UniformTypeIdentifiers

struct PLine: Identifiable {
    let id = UUID()
    var itemId = 0
    var desc = ""
    var hsn = ""
    var qty = "1"
    var unit = "PCS"
    var rate = ""
    var amount = ""
    var amountManual = false
    var matched = true
    var created = false

    var q: Double { Double(qty.trimmingCharacters(in: .whitespaces)) ?? 0 }
    var r: Double { Double(rate.trimmingCharacters(in: .whitespaces)) ?? 0 }
    mutating func autoAmount() {
        guard !amountManual else { return }
        let v = q * r
        amount = v == 0 ? "" : String(format: "%.2f", v)
    }
}

/// Purchase bill entry. "Scan PDF bill" fills everything in: supplier, items (created with HSN, GST rate, MRP and pieces per box),
/// quantities, prices, discount, CGST/SGST, round off and the printed grand total.
@MainActor struct PurchaseView: View {
    @EnvironmentObject private var app: AppModel

    @State private var suppliers: [JSON] = []
    @State private var items: [JSON] = []
    @State private var itemChoices: [Choice] = []
    @State private var lines: [PLine] = [PLine()]
    @State private var supplierId = 0
    @State private var invoiceNo = ""
    @State private var date = ""
    @State private var source = "MANUAL"
    @State private var paid = ""
    @State private var payMode = "CASH"
    @State private var disc = ""
    @State private var cgst = ""
    @State private var sgst = ""
    @State private var igst = ""
    @State private var roundOff = ""
    @State private var printedTotal: Double?
    @State private var parsed: JSON?
    @State private var warnings: [String] = []
    @State private var pendingSupplier: JSON?
    @State private var preview: JSON?
    @State private var errorText: String?
    @State private var editingId: Int?
    @State private var editingNo = ""
    @State private var scanning = false
    @State private var busy = false
    @State private var showText = false
    @State private var newItemFor: PLine?
    @State private var editItem: JSON?
    @State private var cats: [JSON] = []
    @State private var showSupplierSheet = false
    @State private var duplicateMessage: String?

    private var inter: Bool { preview?.str("supply") == "INTER" }

    private var recalcKey: String {
        [String(supplierId), invoiceNo, date, paid, payMode, disc, cgst, sgst, igst, roundOff, String(printedTotal ?? -1)].joined(separator: "|") + "#"
            + lines.map { "\($0.itemId):\($0.hsn):\($0.qty):\($0.unit):\($0.rate):\($0.amount)" }.joined(separator: ",")
    }

    var body: some View { dialogs(chrome(content)) }

    /// The whole bill scrolls (the item table keeps its own height and scroll), so the totals and Save stay reachable with the
    /// keyboard up; dragging the page down puts the keyboard away.
    private var content: some View {
        ScrollView {
            form
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.page)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 8) {
            if editingId != nil {
                Banner(text: "Editing a saved bill. Updating reverses the old stock and ledger entries and writes the corrected bill under the same number.", symbol: "pencil.circle.fill")
            }
            if source == "PDF", let parsed {
                let usedCount = max(1, (parsed.obj("pages").raw["used"] as? [Any])?.count ?? 1)
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(warnings.enumerated()), id: \.offset) { _, w in Text("• \(w)").foregroundStyle(.red).font(.callout) }
                    }
                } label: {
                    Text("Filled in from the PDF (\(usedCount) Original page\(usedCount == 1 ? "" : "s") read). Check every field against the paper bill before saving.")
                        .fontWeight(.semibold).font(.callout)
                }
                .padding(10)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
            header
            linesTable
                .frame(height: min(460, max(220, CGFloat(lines.count) * 56 + 46)))
            totals
        }
        .padding(12)
    }

    @ViewBuilder private func chrome<V: View>(_ v: V) -> some View {
        v
        .navigationTitle(editingId != nil ? "Edit purchase bill \(editingNo)" : "Purchase bill")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { addRow() } label: { Label("Add row", systemImage: "plus") }
                Menu {
                    if editingId == nil {
                        Button { Task { if let u = await Files.pick([.pdf]) { await scanPdf(u) } } } label: { Label(scanning ? "Reading PDF…" : "Scan PDF bill", systemImage: "doc.viewfinder") }.disabled(scanning)
                    }
                    if parsed != nil { Button { showText = true } label: { Label("View PDF text", systemImage: "doc.plaintext") } }
                    Button(editingId != nil ? "Cancel edit" : "Clear", role: .destructive) { reset() }
                } label: { Label("More", systemImage: "ellipsis.circle") }
            }
        }
        // the number pad has no Return key: Done above it puts the keyboard away
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                    .fontWeight(.semibold)
            }
        }
        .overlay { if scanning { ProgressView("Reading the bill and adding items…").padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
        .task {
            if date.isEmpty { date = app.dateInFY }
            await loadLists()
            await takeEdit()
        }
        .task(id: recalcKey) {
            await pause(ms: 250)
            if Task.isCancelled { return }
            await recalc()
        }
    }

    @ViewBuilder private func dialogs<V: View>(_ v: V) -> some View {
        v
        .sheet(isPresented: $showText) {
            InfoSheet(title: "Text read from the PDF") {
                ScrollView { Text(parsed?.str("raw_text") ?? "").font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            }
        }
        .sheet(isPresented: $showSupplierSheet) {
            SupplierFromBillSheet(supplier: pendingSupplier ?? JSON()) { id in
                supplierId = id
                pendingSupplier = nil
                await loadLists()
            }
        }
        .sheet(item: $editItem) { it in ItemSheet(item: it, cats: cats) { await loadLists() } }
        .sheet(item: $newItemFor) { l in
            NewItemSheet(line: l) { id in
                if let i = lines.firstIndex(where: { $0.id == l.id }) { lines[i].itemId = id; lines[i].matched = true }
                await loadLists()
            }
        }
        .alert("Possible duplicate", isPresented: Binding(get: { duplicateMessage != nil }, set: { if !$0 { duplicateMessage = nil } })) {
            Button("Save anyway") { Task { await save(dup: true) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text((duplicateMessage ?? "") + "\n\nSave it again anyway?") }
        .onChange(of: app.section) { new in if new == .purchases { Task { await takeEdit() } } }
    }

    // MARK: Header and table

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { headerFields }
            VStack(alignment: .leading, spacing: 8) { headerFields }
        }
    }

    @ViewBuilder private var headerFields: some View {
        SearchPicker(title: "Supplier", placeholder: "Select supplier…", choices: suppliers.map { Choice(id: $0.id, label: $0.str("name"), detail: $0.str("gstin")) }, selection: $supplierId)
            .frame(minWidth: 220)
        TextField("Supplier invoice no.", text: $invoiceNo)
            .textFieldStyle(.roundedBorder).textInputAutocapitalization(.characters).autocorrectionDisabled()
            .frame(minWidth: 160)
        DateField(title: "Bill date", iso: $date)
        if let ps = pendingSupplier {
            Button("Create supplier “\(ps.str("name"))”") { showSupplierSheet = true }
        }
    }

    private func lb<V>(_ id: UUID, _ kp: WritableKeyPath<PLine, V>, _ fallback: V, after: ((inout PLine) -> Void)? = nil) -> Binding<V> {
        Binding(
            get: { lines.first(where: { $0.id == id })?[keyPath: kp] ?? fallback },
            set: { v in
                if let i = lines.firstIndex(where: { $0.id == id }) {
                    lines[i][keyPath: kp] = v
                    after?(&lines[i])
                }
            }
        )
    }

    /// Only two units exist in the app: BOX and PCS. Carton / case / dozen style units on a bill count as boxes.
    private func normUnit(_ u: String) -> String {
        u.range(of: "^(BOX|CTN|CASE|CARTON|DOZ|DZN|BX)", options: [.regularExpression, .caseInsensitive]) != nil ? "BOX" : "PCS"
    }

    private func item(_ id: Int) -> JSON? { id == 0 ? nil : items.first { $0.id == id } }

    private func hint(_ l: PLine) -> String {
        var parts: [String] = []
        if l.created { parts.append("New item added") }
        if !l.desc.isEmpty { parts.append("On the bill: \(l.desc)") }
        if let it = item(l.itemId) {
            let perBox = it.int("pcs_per_box")
            let isBox = l.unit.range(of: "^(BOX|CTN|CASE|CARTON|DOZ|DZN)", options: [.regularExpression, .caseInsensitive]) != nil
            if isBox && perBox > 1 && l.q > 0 { parts.append("\(l.qty) box × \(perBox) = \(Int((l.q * Double(perBox)).rounded())) pcs go into stock") }
            else if perBox > 1 { parts.append("1 box = \(perBox) pcs  ·  \(Fmt.boxPcs(Int(l.q.rounded()), perBox)) in stock terms") }
        }
        return parts.joined(separator: "   ·   ")
    }

    private var linesTable: some View {
        DataGrid(lines, layoutKey: "purchase", rowHeight: 56) {
            GridColumn("S.No", id: "sno", min: 36, ideal: 44) { (l: PLine) in
                Text("\((lines.firstIndex(where: { $0.id == l.id }) ?? 0) + 1)").monospacedDigit().foregroundStyle(.secondary)
            }
            GridColumn("Item name", id: "item", min: 240, ideal: 320, flex: true) { (l: PLine) in
                VStack(alignment: .leading, spacing: 2) {
                    if !l.matched && !l.desc.isEmpty {
                        HStack {
                            Text("“\(l.desc)” is not in your stock list.").font(.caption).foregroundStyle(.red).lineLimit(1)
                            Button("Create this item") { newItemFor = l }.controlSize(.small)
                        }
                    }
                    HStack(spacing: 6) {
                        SearchPicker(title: "Item", placeholder: "Select item…", choices: itemChoices, selection: lb(l.id, \.itemId, 0)) { picked in
                            guard let i = lines.firstIndex(where: { $0.id == l.id }), let it = item(picked) else { return }
                            lines[i].matched = true
                            if lines[i].hsn.isEmpty { lines[i].hsn = it.str("hsn") }
                            if lines[i].rate.isEmpty, it.num("purchase_price") > 0 { lines[i].rate = it.str("purchase_price") }
                            lines[i].autoAmount()
                        }
                        // edit the stock item itself (name, HSN, pack, prices…), e.g. to fix a spelling
                        if let it = item(l.itemId) {
                            Button { editItem = it } label: { Image(systemName: "pencil.circle") }
                                .buttonStyle(.borderless).accessibilityLabel("Edit item")
                        }
                    }
                    let h = hint(l)
                    if !h.isEmpty { Text(h).font(.caption).foregroundStyle(l.created ? Color.teal : Color.secondary).lineLimit(1) }
                }
            }
            GridColumn("HSN code", id: "hsn", min: 76, ideal: 96) { (l: PLine) in
                TextField("HSN", text: lb(l.id, \.hsn, "")).keyboardType(.numberPad)
            }
            GridColumn("Qty", id: "qty", min: 56, ideal: 72, align: .trailing) { (l: PLine) in
                TextField("1", text: lb(l.id, \.qty, "1", after: { $0.autoAmount() })).multilineTextAlignment(.trailing).keyboardType(.numberPad)
            }
            GridColumn("Unit", id: "unit", min: 80, ideal: 90) { (l: PLine) in
                Picker("Unit", selection: lb(l.id, \.unit, "PCS")) {
                    Text("BOX").tag("BOX")
                    Text("PCS").tag("PCS")
                }
                .labelsHidden()
            }
            GridColumn("Price (per unit)", id: "price", min: 90, ideal: 110, align: .trailing) { (l: PLine) in
                TextField("0.00", text: lb(l.id, \.rate, "", after: { $0.autoAmount() })).multilineTextAlignment(.trailing).keyboardType(.decimalPad)
            }
            GridColumn("Amount", id: "amount", min: 90, ideal: 110, align: .trailing) { (l: PLine) in
                TextField("0.00", text: lb(l.id, \.amount, "", after: { $0.amountManual = true })).multilineTextAlignment(.trailing).keyboardType(.decimalPad)
            }
            GridColumn("", id: "remove", min: 36, ideal: 36) { (l: PLine) in
                Button { if lines.count > 1 { lines.removeAll { $0.id == l.id } } } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).disabled(lines.count < 2).accessibilityLabel("Remove row")
            }
        }
        .frame(minHeight: 220)
    }

    // MARK: Totals

    private func box(_ title: String, _ text: Binding<String>, _ key: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title, text: text, prompt: Text(preview?.str(key) ?? ""))
                .multilineTextAlignment(.trailing).monospacedDigit().keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
        }
        .frame(minWidth: 96)
    }

    private var totals: some View {
        let p = preview
        let mismatch = p != nil && abs(p!.num("mismatch")) > 0
        return VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], alignment: .leading, spacing: 8) {
                box("Discount", $disc, "discount")
                if !inter { box("CGST", $cgst, "cgst"); box("SGST", $sgst, "sgst") } else { box("IGST", $igst, "igst") }
                box("Rounded off", $roundOff, "round_off")
                Button { cgst = ""; sgst = ""; igst = "" } label: { Label("Auto tax", systemImage: "function") }
                    .accessibilityHint("Work out CGST / SGST / IGST again from each item's GST rate")
            }
            if let p { Text("Items \(Fmt.money(p, "subtotal"))  ·  Taxable \(Fmt.money(p, "taxable"))").foregroundStyle(.secondary).monospacedDigit().font(.callout) }
            HStack(spacing: 8) {
                TextField("Paid now", text: $paid).multilineTextAlignment(.trailing).keyboardType(.decimalPad).textFieldStyle(.roundedBorder).frame(maxWidth: 140)
                Picker("Mode", selection: $payMode) { ForEach(["CASH", "UPI", "BANK", "CHEQUE"], id: \.self) { Text($0).tag($0) } }
                Spacer(minLength: 0)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    if let pt = printedTotal {
                        Text("Printed on bill: \(Fmt.money(pt))").monospacedDigit().font(.callout)
                            .foregroundStyle(mismatch ? Color.red : Color.secondary).fontWeight(mismatch ? .semibold : .regular)
                    }
                    if let p { Text(Fmt.money(p, "total")).font(.system(.title, design: .rounded).weight(.bold)).monospacedDigit().foregroundStyle(.teal) }
                }
                Spacer()
                Button { Task { await save() } } label: {
                    Label(editingId != nil ? "Update bill" : "Save and add to stock", systemImage: editingId != nil ? "square.and.arrow.down" : "tray.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: .command)
                .disabled(busy || p == nil)
            }
            if let errorText { Text(errorText).foregroundStyle(.red).font(.callout) }
        }
        .padding(10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Logic

    private func addRow() { lines.append(PLine()) }

    private func payload(dup: Bool = false) -> [String: Any] {
        var d: [String: Any] = [
            "supplier_invoice_no": invoiceNo.trimmingCharacters(in: .whitespaces), "date": date, "source": source, "pay_mode": payMode,
            "discount": disc, "cgst": cgst, "sgst": sgst, "igst": igst, "round_off": roundOff,
            "lines": lines.map { ["item_id": ($0.itemId == 0 ? NSNull() as Any : $0.itemId as Any), "hsn": $0.hsn, "qty": $0.qty, "unit": $0.unit, "rate": $0.rate, "amount": $0.amount] as [String: Any] },
        ]
        if supplierId != 0 { d["party_id"] = supplierId }
        if let v = Double(paid.trimmingCharacters(in: .whitespaces)) { d["paid_amount"] = v }
        if let printedTotal { d["printed_total"] = printedTotal }
        if dup { d["allow_duplicate"] = true }
        return d
    }

    private func loadLists() async {
        await app.guarded {
            async let s = API.list("/parties", query: ["kind": "SUPPLIER"])
            async let i = API.list("/items")
            async let c = API.list("/categories")
            suppliers = try await s
            items = try await i
            cats = (try? await c) ?? []
            itemChoices = items.map { Choice(id: $0.id, label: $0.str("name"), detail: $0.str("hsn")) }
        }
    }

    private func recalc() async {
        do {
            let r = try await API.objRaw("POST", "/purchases/preview", body: payload())
            if Task.isCancelled { return }
            preview = r
            errorText = nil
        } catch {
            if Task.isCancelled { return }
            preview = nil
            errorText = error.localizedDescription
        }
    }

    private func scanPdf(_ url: URL) async {
        // a coordinated read downloads a PDF that is still in iCloud Drive
        let ok = url.startAccessingSecurityScopedResource()
        var data: Data?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: nil) { u in data = try? Data(contentsOf: u) }
        if ok { url.stopAccessingSecurityScopedResource() }
        guard let data else { app.notify("That file could not be opened.", error: true); return }
        scanning = true
        defer { scanning = false }
        await app.guarded {
            // create_missing: the supplier and every new item (HSN, GST rate, pieces per box, MRP, category) are added automatically.
            let r = try await API.objRaw("POST", "/purchases/parse-pdf", body: ["pdf_base64": data.base64EncodedString(), "create_missing": true])
            await loadLists()
            apply(r)
            let c = r.obj("created")
            app.notify("Bill read: \(r.list("lines").count) items" + (c.int("items") > 0 ? ", \(c.int("items")) new items added to Stock" : "") + (c.bool("supplier") ? ", supplier added." : "."))
        }
    }

    private func apply(_ r: JSON) {
        let sup = r.obj("supplier")
        let t = r.obj("totals")
        func num(_ k: String) -> String { t.num(k) == 0 ? "" : t.str(k) }
        var ls: [PLine] = []
        for x in r.list("lines") {
            var l = PLine()
            l.itemId = x.optInt("item_id") ?? 0
            l.desc = x.str("description")
            l.unit = normUnit(x.str("unit"))
            l.matched = x.has("item_id")
            l.created = x.bool("created")
            l.amountManual = true   // the printed amount is the truth for a scanned bill
            l.hsn = x.str("hsn")
            let q = x.num("qty")
            l.qty = q == q.rounded() ? String(Int(q)) : x.str("qty")
            l.rate = x.str("rate")
            l.amount = x.str("amount")
            ls.append(l)
        }
        source = "PDF"
        parsed = r
        warnings = r.strings("warnings")
        invoiceNo = r.str("invoice_no")
        if r.has("date") { date = r.str("date") }
        supplierId = sup.optInt("matched_party_id") ?? 0
        pendingSupplier = (supplierId == 0 && sup.has("name")) ? sup : nil
        disc = num("discount"); cgst = num("cgst"); sgst = num("sgst"); igst = num("igst")
        roundOff = t.has("round_off") ? t.str("round_off") : ""
        printedTotal = t.has("grand_total") ? t.num("grand_total") : nil
        lines = ls.isEmpty ? [PLine()] : ls
        let pg = r.obj("pages")
        let skipped = pg.list("skipped")
        if !skipped.isEmpty {
            warnings.insert("Skipped page(s) " + skipped.map { "\($0.str("page")) (\($0.str("kind")))" }.joined(separator: ", ") + ".", at: 0)
        }
    }

    private func takeEdit() async {
        guard let e = app.pendingEdit, e.type == "PURCHASE" else { return }
        app.pendingEdit = nil
        await app.guarded {
            let b = try await API.obj("GET", "/purchases/\(e.id)")
            lines = b.list("lines").map { x -> PLine in
                var l = PLine()
                l.itemId = x.int("item_id")
                l.unit = normUnit(x.str("unit"))
                l.amountManual = true
                l.hsn = x.str("hsn")
                l.qty = String(Int(x.num("qty")))
                l.rate = x.str("rate")
                l.amount = x.str("amount")
                return l
            }
            if lines.isEmpty { lines = [PLine()] }
            editingId = e.id
            editingNo = b.str("purchase_no")
            supplierId = b.int("party_id")
            invoiceNo = b.str("supplier_invoice_no")
            date = String(b.str("date").prefix(10))
            payMode = b.str("pay_mode").isEmpty ? "CASH" : b.str("pay_mode")
            paid = String(format: "%.2f", b.num("paid"))
            func n(_ k: String) -> String { b.num(k) == 0 ? "" : b.str(k) }
            disc = n("discount"); cgst = n("cgst"); sgst = n("sgst"); igst = n("igst")
            roundOff = b.str("round_off")
            source = b.str("source").isEmpty ? "MANUAL" : b.str("source")
            parsed = nil; warnings = []; printedTotal = nil
        }
    }

    private func reset() {
        invoiceNo = ""; paid = ""; disc = ""; cgst = ""; sgst = ""; igst = ""; roundOff = ""
        supplierId = 0
        date = app.dateInFY
        source = "MANUAL"
        parsed = nil
        pendingSupplier = nil
        warnings = []
        printedTotal = nil
        editingId = nil
        editingNo = ""
        lines = [PLine()]
        preview = nil
        errorText = nil
    }

    private func save(dup: Bool = false) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let wasEdit = editingId
            let r: JSON
            if let wasEdit {
                r = try await API.objRaw("PUT", "/purchases/\(wasEdit)", body: payload(dup: dup))
            } else {
                r = try await API.objRaw("POST", "/purchases", body: payload(dup: dup))
            }
            app.notify("\(wasEdit != nil ? "Updated" : "Saved") \(r.str("purchase_no")) · \(Fmt.money(r, "total")). Stock and ledger are up to date.")
            reset()
            await loadLists()
        } catch let e as APIError where e.code == "DUPLICATE" && !dup {
            duplicateMessage = e.message
        } catch {
            app.notify(error.localizedDescription, error: true)
        }
    }
}

// MARK: - Sheets

@MainActor struct SupplierFromBillSheet: View {
    @EnvironmentObject private var app: AppModel
    let supplier: JSON
    let done: (Int) async -> Void
    @State private var f: [String: String] = [:]

    private func b(_ k: String, _ d: String = "") -> Binding<String> {
        Binding(get: {
            if let v = f[k] { return v }
            if supplier.raw[k] is [Any] { return supplier.strings(k).joined(separator: ", ") }
            return supplier.has(k) ? supplier.str(k) : d
        }, set: { f[k] = $0 })
    }

    var body: some View {
        FormSheet(title: "Create supplier from the bill", onSave: {
            var body: [String: Any?] = ["type": "SUPPLIER", "price_tier": "WHOLESALE"]
            for k in ["name", "address", "gstin", "state_code", "tel", "phone", "mobiles", "fssai", "pan", "email"] { body[k] = b(k, k == "state_code" ? "09" : "").wrappedValue }
            let r = try await API.obj("POST", "/parties", body: body)
            app.notify("Supplier added.")
            await done(r.int("id"))
        }) {
            Field("Supplier name", text: b("name"))
            Field("Address", text: b("address"), axis: .vertical)
            Field("GSTIN", text: b("gstin")).textInputAutocapitalization(.characters)
            Field("State code", text: b("state_code", "09")).keyboardType(.numberPad)
            Field("Tel", text: b("tel")).keyboardType(.phonePad)
            Field("Phone", text: b("phone")).keyboardType(.phonePad)
            Field("Mobile numbers (comma separated)", text: b("mobiles")).keyboardType(.numbersAndPunctuation)
            Field("FSSAI number", text: b("fssai")).keyboardType(.numberPad)
            Field("PAN number", text: b("pan")).textInputAutocapitalization(.characters)
            Field("Email", text: b("email")).keyboardType(.emailAddress).textInputAutocapitalization(.never)
        }
    }
}

@MainActor struct NewItemSheet: View {
    @EnvironmentObject private var app: AppModel
    let line: PLine
    let done: (Int) async -> Void
    @State private var f: [String: String] = [:]

    private func b(_ k: String, _ d: String = "") -> Binding<String> {
        Binding(get: { f[k] ?? d }, set: { f[k] = $0 })
    }

    var body: some View {
        FormSheet(title: "Create item from the bill", onSave: {
            var body: [String: Any?] = [:]
            for k in ["name", "hsn", "gst_rate", "pcs_per_box", "purchase_price", "mrp", "retail_price", "wholesale_price"] { body[k] = defaultFor(k) }
            let r = try await API.obj("POST", "/items", body: body)
            await done(r.int("id"))
        }) {
            Field("Item name", text: b("name", line.desc))
            Field("HSN code", text: b("hsn", line.hsn)).keyboardType(.numberPad)
            Field("GST rate %", text: b("gst_rate", "18")).keyboardType(.decimalPad)
            Field("Pieces in one box", text: b("pcs_per_box", defaultPack)).keyboardType(.numberPad)
            Field("Purchase price per piece (ex-GST)", text: b("purchase_price", defaultCost)).keyboardType(.decimalPad)
            Field("MRP per piece (incl. GST)", text: b("mrp")).keyboardType(.decimalPad)
            Field("Retail price (ex-GST)", text: b("retail_price")).keyboardType(.decimalPad)
            Field("Wholesale price (ex-GST)", text: b("wholesale_price")).keyboardType(.decimalPad)
        }
    }

    private var defaultPack: String { String(Fmt.packFromName(line.desc) ?? 1) }
    /// The bill price is per box when the unit is BOX; items are priced per piece.
    private var defaultCost: String {
        let r = Double(line.rate) ?? 0
        let n = Double(Fmt.packFromName(line.desc) ?? 1)
        return line.unit == "BOX" && n > 1 ? String(format: "%.4f", r / n) : line.rate
    }

    private func defaultFor(_ k: String) -> String {
        let d: [String: String] = ["name": line.desc, "hsn": line.hsn, "gst_rate": "18", "pcs_per_box": defaultPack, "purchase_price": defaultCost]
        return f[k] ?? d[k] ?? ""
    }
}
