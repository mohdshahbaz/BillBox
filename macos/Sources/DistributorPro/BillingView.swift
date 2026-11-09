import SwiftUI
import AppKit

struct BillLine: Identifiable {
    let id = UUID()
    let itemId: Int
    let name: String
    let ppb: Int
    var stock: Double
    var boxes = 0
    var pcs = 1
    var disc = ""
    /// Typed selling rate per piece (ex-GST). Blank = the party's price list rate.
    var rate = ""
    var totalPcs: Int { BillMath.totalPcs(boxes: boxes, ppb: ppb, pcs: pcs) }

    /// A new line starts as ONE BOX when the item is packed in boxes (and a full box is in stock); otherwise one loose piece.
    static func fresh(_ item: JSON, disc: String = "", unit: String = "box") -> BillLine {
        let ppb = max(1, item.int("pcs_per_box"))
        var l = BillLine(itemId: item.id, name: item.str("name"), ppb: ppb, stock: item.num("stock"))
        if (Double(disc) ?? 0) > 0 { l.disc = disc }   // Settings › Billing & Dashboard › discount on every new line
        if ppb > 1 && unit != "piece" { l.boxes = 1; l.pcs = 0 } else { l.boxes = 0; l.pcs = 1 }   // Settings › Billing › new line starts as
        return l
    }

    /// Pieces are kept exactly as typed; the bill uses boxes x pieces-per-box + pieces, so the amount always follows.
    mutating func setPcs(_ v: Int) {
        let v = max(0, v)
        pcs = v
    }
}

/// The counter screen: type-ahead item search, editable bill lines, live totals from the server (same engine as save).
@MainActor struct BillingView: View {
    @EnvironmentObject private var app: AppModel

    @State private var parties: [JSON] = []
    @State private var salesmen: [JSON] = []
    @State private var routes: [JSON] = []
    @State private var newPartyOpen = false
    @State private var allItems: [JSON] = []
    @State private var mixBoxes: [JSON] = []
    @State private var mixEdit = false
    @StateObject private var model = BillModel()
    @State private var partyId = 0
    @State private var salesmanId = 0
    @State private var saleType = "COUNTER"
    @State private var payMode = "CREDIT"
    @State private var billDate = ""
    @State private var paid = ""
    @State private var preview: JSON?
    @State private var errorText: String?
    @State private var busy = false
    @State private var calcGen = 0
    @State private var previewKey = ""
    @State private var calculating = false
    @State private var editingId: Int?
    @State private var editingNo = ""
    @State private var query = ""
    @State private var highlight = 0
    @FocusState private var searchFocus: Bool
    /// The Box (or Pcs) field the cursor goes to when an item is added, so its quantity can be typed straight away.
    @FocusState private var qtyFocus: QtyField?
    @State private var qtySelect: QtyField?

    /// The lines live in the model so every change recalculates the bill immediately.
    private var lines: [BillLine] {
        get { model.lines }
        nonmutating set { model.lines = newValue }
    }

    private var party: JSON? { partyId == 0 ? nil : parties.first { $0.id == partyId } }

    // MARK: Calculation
    // Two layers. 1) The amounts are worked out on this Mac the instant a box, pcs, rate or discount changes, with the same rules as the
    // server (rate x pieces, discount, GST split, round off), so the screen never waits. 2) The server's own answer (which also knows about
    // schemes and free pieces) replaces it as soon as it arrives for exactly this bill. Whatever is on screen is therefore always the
    // amount of the bill as it stands now.

    struct LineCalc { var rate = 0.0, free = 0.0, amount = 0.0, schemes: [String] = [] }
    struct BillTotals {
        var subtotal = 0.0, discount = 0.0, taxable = 0.0, cgst = 0.0, sgst = 0.0, igst = 0.0, roundOff = 0.0, total = 0.0
        var lines: [LineCalc] = []
        var supply = "INTRA"
        var fromServer = false
        var gst: Double { cgst + sgst + igst }
    }

    private func localTotals() -> BillTotals {
        let m = model.currentResult()
        var t = BillTotals()
        t.supply = model.supply
        t.subtotal = m.subtotal; t.discount = m.discount; t.taxable = m.taxable
        t.cgst = m.cgst; t.sgst = m.sgst; t.igst = m.igst; t.roundOff = m.roundOff; t.total = m.total
        t.lines = m.lines.map { LineCalc(rate: $0.rate, free: 0, amount: $0.amount, schemes: []) }
        return t
    }

    /// What the screen shows: the server's answer when it is for exactly this bill, otherwise the local calculation.
    private var totals: BillTotals? {
        if lines.isEmpty { return nil }
        if let p = preview, previewKey == recalcKey {
            var t = BillTotals()
            t.fromServer = true
            t.subtotal = p.num("subtotal"); t.discount = p.num("discount"); t.taxable = p.num("taxable")
            t.cgst = p.num("cgst"); t.sgst = p.num("sgst"); t.igst = p.num("igst"); t.roundOff = p.num("round_off"); t.total = p.num("total")
            t.supply = p.str("supply")
            t.lines = p.list("lines").map { LineCalc(rate: $0.num("rate"), free: $0.num("free_qty"), amount: $0.num("amount"), schemes: $0.strings("schemes")) }
            // the screen's own working is exact for plain lines; the server's answer is used only when a scheme or free pieces apply
            if t.lines.count == lines.count, t.lines.contains(where: { $0.free > 0 || !$0.schemes.isEmpty }) { return t }
        }
        return localTotals()
    }

    private var recalcKey: String {
        "\(partyId)|\(billDate)|\(saleType)|\(payMode)|\(paid)|" + lines.map { "\($0.itemId):\($0.boxes):\($0.pcs):\($0.disc):\($0.rate)" }.joined(separator: ",")
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                if editingId != nil {
                    Banner(text: "Editing \(editingNo). Saving replaces the old bill; stock and ledger are corrected automatically.", symbol: "pencil.circle.fill")
                }
                searchField
                ZStack(alignment: .top) {
                    linesTable
                    if !suggestions.isEmpty { suggestionList.zIndex(2) }
                }
                if let errorText { Banner(text: errorText, symbol: "exclamationmark.triangle.fill", tint: .red) }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            bottomBar
        }
        // Billing stays alive (hidden) behind the other screens; on macOS 12 its title won over theirs ("Billing" above Settings)
        .navigationTitle(app.section != .billing ? app.section.title : editingId != nil ? "Editing \(editingNo)" : "Billing")
        .toolbar {
            ToolbarItemGroup {
                Button { clear() } label: { Label(editingId != nil ? "Cancel edit" : "New bill", systemImage: "doc.badge.plus") }
                    .keyboardShortcut("n", modifiers: .command)
                Button { searchFocus = true } label: { Label("Find item", systemImage: "magnifyingglass") }
                    .keyboardShortcut("k", modifiers: .command)
            }
        }
        .sheet(isPresented: $newPartyOpen) {
            PartySheet(party: nil, defaultType: "RETAILER", routes: routes, salesmen: salesmen) { await addedParty() }
        }
        .task {
            if billDate.isEmpty { billDate = app.dateInFY }
            if lines.isEmpty && editingId == nil { payMode = app.defaultPayMode; saleType = app.defaultSaleType }
            await reload()
            if app.settings.str("wa_auto") == "1" { WhatsAppWeb.shared.warmUp() }
            searchFocus = true
        }
        .background(KeyCatcher(active: searchFocus && app.section == .billing) { key in
            switch key {
            case 125: highlight = min(highlight + 1, max(0, suggestions.count - 1)); return true
            case 126: highlight = max(0, highlight - 1); return true
            case 53: if query.isEmpty { return false }; query = ""; return true
            default: return false
            }
        })
        .onChange(of: partyId) { _ in syncModel() }
        // prices or items changed elsewhere (Set prices, item edits, imports, merges): bill with the new ones at once
        .onChange(of: app.itemsVersion) { _ in Task { await reload() } }
        .task(id: recalcKey) {
            await pause(ms: 200)
            await recalc()
        }
        .onChange(of: app.section) { new in
            guard new == .billing else { return }
            Task {
                await reload()
                if let e = app.pendingEdit, e.type == "INVOICE" {
                    app.pendingEdit = nil
                    await loadForEdit(e.id)
                }
                searchFocus = true
            }
        }
    }

    // MARK: Search

    private var suggestions: [JSON] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return [] }
        let words = q.split(separator: " ").map(String.init)
        var hits = allItems.filter { i in
            let n = i.str("name").lowercased()
            return words.allSatisfy { n.contains($0) } || i.str("barcode").lowercased() == q || i.str("hsn").hasPrefix(q)
        }
        hits.sort { a, b in
            let sa = a.num("stock") > 0 ? 0 : 1, sb = b.num("stock") > 0 ? 0 : 1
            if sa != sb { return sa < sb }
            let ia = a.str("name").lowercased().range(of: words[0])?.lowerBound.utf16Offset(in: a.str("name").lowercased()) ?? 0
            let ib = b.str("name").lowercased().range(of: words[0])?.lowerBound.utf16Offset(in: b.str("name").lowercased()) ?? 0
            return ia != ib ? ia < ib : a.str("name") < b.str("name")
        }
        return Array(hits.prefix(8))
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            TextField("Type an item name or scan a barcode", text: $query)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .focused($searchFocus)
                .onSubmit { Task { await submitSearch() } }
                .onChange(of: query) { _ in highlight = 0 }
            // Mix box: a box of N pieces made of 12 (or 10) pieces of every matching item in stock, added in one click
            Menu {
                ForEach(Array(mixBoxes.enumerated()), id: \.offset) { i, m in
                    Button(mixLabel(m)) { Task { await addMix(i) } }
                }
                Divider()
                Button("Edit mix boxes…") { mixEdit = true }
            } label: { Label("Mix box", systemImage: "shippingbox") }
            .menuStyle(.borderedButton)
            .fixedSize()
            .controlSize(.large)
        }
        .sheet(isPresented: $mixEdit) { MixBoxEditor(boxes: mixBoxes) { await loadMix() } }
    }

    private func mixLabel(_ m: JSON) -> String {
        let each = max(1, m.int("each"))
        return m.int("box") > 0 ? "\(m.str("name"))  ·  \(m.int("box")) pc, \(each) pc each" : "\(m.str("name"))  ·  \(each) pc each"
    }

    private func loadMix() async {
        if let m = try? await API.list("/mixboxes") { mixBoxes = m }
    }

    /// Adds the mix box's lines (pieces) to the bill; an item already on the bill gets the pieces added to it.
    private func addMix(_ index: Int) async {
        await app.guarded {
            let plan = try await API.obj("POST", "/mixboxes/plan", body: ["index": index])
            let rows = plan.list("lines")
            if rows.isEmpty { app.notify("No item in stock matches \(plan.str("name")).", error: true); return }
            for r in rows {
                let q = r.int("pcs")
                if let i = lines.firstIndex(where: { $0.itemId == r.id }) {
                    lines[i].pcs += q
                } else {
                    var l = BillLine.fresh(r, disc: app.settings.str("bill_default_disc"), unit: "piece")
                    l.boxes = 0; l.pcs = q
                    lines.append(l)
                }
            }
            let short = plan.int("short")
            app.notify("\(plan.str("name")): \(plan.int("filled")) pc of \(plan.int("items")) items added" + (short > 0 ? " — \(short) pc short (not enough stock)." : "."), error: short > 0)
        }
    }

    private var suggestionList: some View {
        VStack(spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { i, it in
                Button { add(it) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(it.str("name")).lineLimit(1)
                            Text("Stock \(Fmt.boxPcs(it.int("stock"), max(1, it.int("pcs_per_box"))))  ·  MRP \(Fmt.money(it, "mrp"))  ·  GST \(Fmt.qty(it.num("gst_rate")))%")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if it.num("stock") <= 0 { Text("Out of stock").font(.caption).foregroundStyle(.red) }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(i == highlight ? Theme.accent.opacity(0.18) : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if i < suggestions.count - 1 { Divider() }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line))
        .shadow(radius: 10, y: 4)
    }

    private func submitSearch() async {
        let s = suggestions
        if !s.isEmpty { add(s[min(highlight, s.count - 1)]); return }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        query = ""
        await app.guarded {
            let r = try await API.list("/items", query: ["q": q])
            if let first = r.first, r.count == 1 { add(first) } else { app.notify("No item matches \"\(q)\"", error: true) }
        }
        searchFocus = true
    }

    private func add(_ item: JSON) {
        let id: UUID
        if let i = lines.firstIndex(where: { $0.itemId == item.id }) {
            // same item again: one more box (or one more piece for loose items)
            if lines[i].ppb > 1 { lines[i].boxes += 1 } else { lines[i].pcs += 1 }
            id = lines[i].id
        } else {
            let l = BillLine.fresh(item, disc: app.settings.str("bill_default_disc"), unit: app.settings.str("bill_new_unit"))
            lines.append(l)
            id = l.id
        }
        query = ""
        // the cursor goes to the line's Box (Pcs for loose items): type the quantity, Return goes back to the search
        guard let l = lines.first(where: { $0.id == id }) else { searchFocus = true; return }
        let target: QtyField = l.ppb > 1 ? .box(id) : .pcs(id)
        qtySelect = target
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)   // the new row's field exists after this redraw
            searchFocus = false
            qtyFocus = target
        }
    }

    // MARK: Lines

    private func lb<V>(_ id: UUID, _ kp: WritableKeyPath<BillLine, V>, _ fallback: V) -> Binding<V> {
        Binding(
            get: { lines.first(where: { $0.id == id })?[keyPath: kp] ?? fallback },
            set: { v in if let i = lines.firstIndex(where: { $0.id == id }) { lines[i][keyPath: kp] = v } }
        )
    }

    private func pc(_ l: BillLine) -> LineCalc? {
        guard let t = totals, let i = lines.firstIndex(where: { $0.id == l.id }), i < t.lines.count else { return nil }
        return t.lines[i]
    }

    private var linesTable: some View {
        DataGrid(lines, layoutKey: "billing", rowHeight: 38) {
            GridColumn("S.No", id: "sno", min: 36, ideal: 44) { (l: BillLine) in
                Text("\((lines.firstIndex(where: { $0.id == l.id }) ?? 0) + 1)").mono().foregroundStyle(.secondary)
            }

            GridColumn("Item", id: "item", min: 180, ideal: 320, flex: true) { (l: BillLine) in
                VStack(alignment: .leading, spacing: 1) {
                    Text(l.name).fw(.medium).lineLimit(1)
                    let schemes = pc(l)?.schemes ?? []
                    Text(([l.ppb > 1 ? "\(l.ppb) pcs / box" : nil, "Stock \(Fmt.boxPcs(Int(l.stock), l.ppb))"] .compactMap { $0 } + schemes).joined(separator: "  ·  "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }

            GridColumn("Box", id: "box", min: 56, ideal: 70) { (l: BillLine) in
                if l.ppb > 1 {
                    IntCell(value: lb(l.id, \.boxes, 0), field: .box(l.id), focus: $qtyFocus, select: $qtySelect) { qtyFocus = nil; searchFocus = true }
                } else {
                    Text("–").foregroundStyle(.secondary)
                }
            }

            GridColumn("Pcs", id: "pcs", min: 64, ideal: 80) { (l: BillLine) in
                IntCell(value: lb(l.id, \.pcs, 0), field: .pcs(l.id), focus: $qtyFocus, select: $qtySelect) { qtyFocus = nil; searchFocus = true }
            }

            GridColumn("Total pcs", id: "total", min: 56, ideal: 72, align: .trailing) { (l: BillLine) in
                Text("\(l.totalPcs)").mono().foregroundStyle(.secondary)
            }

            GridColumn("Disc %", id: "disc", min: 54, ideal: 70) { (l: BillLine) in
                TextField("0", text: lb(l.id, \.disc, "")).multilineTextAlignment(.trailing)
            }

            GridColumn("Rate / pc (ex-GST)", id: "rate", min: 100, ideal: 120, align: .trailing) { (l: BillLine) in
                TextField("", text: lb(l.id, \.rate, ""), prompt: Text(pc(l).map { Fmt.rate($0.rate) } ?? "rate"))
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(l.rate.isEmpty ? Color.primary : Color.orange)
                    .help("Type a different rate to override the price list for this line. Clear it to go back to the price list.")
            }

            GridColumn("Rate / box", id: "boxrate", min: 90, ideal: 110, align: .trailing) { (l: BillLine) in
                if l.ppb > 1 {
                    // typing a box rate sets the piece rate to box rate / pieces per box (kept to 4 decimals)
                    let shown = Double(l.rate) ?? (pc(l)?.rate ?? 0)
                    TextField("", text: Binding(
                        get: { l.rate.isEmpty ? "" : Fmt.qty(((Double(l.rate) ?? 0) * Double(l.ppb) * 100).rounded() / 100) },
                        set: { v in
                            guard let i = lines.firstIndex(where: { $0.id == l.id }) else { return }
                            if let d = Double(v.trimmingCharacters(in: .whitespaces)), d >= 0 { lines[i].rate = String(format: "%.8f", d / Double(l.ppb)) } else { lines[i].rate = "" }
                        }), prompt: Text(Fmt.amount(shown * Double(l.ppb))))
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(l.rate.isEmpty ? Color.primary : Color.orange)
                } else {
                    Text("–").foregroundStyle(.secondary)
                }
            }

            GridColumn("Free", id: "free", min: 50, ideal: 76) { (l: BillLine) in
                let f = pc(l)?.free ?? 0
                Text(f > 0 ? "+\(Fmt.qty(f)) pcs free" : "").foregroundStyle(.green).fw(.semibold)
            }

            GridColumn("Amount", id: "amount", min: 90, ideal: 110, align: .trailing) { (l: BillLine) in
                Text(pc(l).map { Fmt.money($0.amount) } ?? "").mono().fw(.semibold)
            }

            GridColumn("", id: "remove", min: 28, ideal: 28) { (l: BillLine) in
                Button { lines.removeAll { $0.id == l.id } } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Remove")
            }
        }
        .overlay {
            if lines.isEmpty {
                EmptyState(title: "Start a bill", symbol: "cart", message: "Search an item above and press Return.")
            }
        }
    }

    // MARK: Summary
    // Three cards of the same height sit side by side under the table: who/how, the working, and the total with its buttons.

    private let barHeight: CGFloat = 150

    private var bottomBar: some View {
        let t = totals
        let ready = preview != nil && previewKey == recalcKey
        return HStack(alignment: .top, spacing: 12) {
            customerCard.frame(minWidth: 400, maxWidth: .infinity)
            workingCard(t).frame(width: 210)
            totalCard(t, ready: ready).frame(width: 230)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Theme.card)
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: barHeight, maxHeight: barHeight, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
    }

    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 52, height: 24, alignment: .leading)
            content()
        }
        .controlSize(.regular)
        .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24, alignment: .leading)
    }

    private var customerCard: some View {
        card {
            VStack(alignment: .leading, spacing: 6) {
                field("Party") {
                    SearchPicker(title: "Party", placeholder: "Walk-in cash customer",
                                 choices: [Choice(id: 0, label: "Walk-in cash customer")] + parties.map { Choice(id: $0.id, label: $0.str("name"), detail: $0.str("route_name")) },
                                 selection: $partyId)
                    Button { newPartyOpen = true } label: { Image(systemName: "person.badge.plus") }
                        .help("Create a new party without leaving the bill")
                }
                field("Date") {
                    DateField(iso: $billDate).frame(width: 130, height: 24, alignment: .leading)
                    Picker("Salesman", selection: $salesmanId) {
                        Text("No salesman (counter)").tag(0)
                        ForEach(salesmen) { s in Text(s.str("name")).tag(s.id) }
                    }
                    .labelsHidden().frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                }
                field("Sale") {
                    Picker("Sale type", selection: $saleType) {
                        Text("Counter").tag("COUNTER"); Text("Van sale").tag("VAN")
                    }
                    .labelsHidden().frame(width: 100)
                    Picker("Payment", selection: $payMode) {
                        Text("Cash").tag("CASH"); Text("UPI").tag("UPI"); Text("Card").tag("CARD"); Text("Credit").tag("CREDIT")
                    }
                    .labelsHidden().frame(width: 90)
                    TextField("Paid now", text: $paid, prompt: Text(partyId == 0 && payMode == "CREDIT" ? "Walk-in: paid in full" : (payMode == "CREDIT" ? "Paid now (blank = on credit)" : "Paid now (blank = full)")))
                        .multilineTextAlignment(.trailing)
                }
                if let n = tierNote { Text(n).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
                Text(duesLine)
                    .font(.caption)
                    .foregroundStyle(duesOver ? Color.red : Color.secondary)
                    .lineLimit(1)
                    .frame(height: 16, alignment: .leading)
            }
        }
    }

    private var duesLine: String {
        guard let pt = party else { return "Walk-in customer · retail price · paid in full" }
        let limit = pt.num("credit_limit")
        return "Dues \(Fmt.money(pt, "balance"))\(limit > 0 ? " of \(Fmt.money(limit)) limit" : "") · \(pt.str("price_tier").capitalized) price"
    }

    /// A wholesale customer, but items on the bill have no wholesale price of their own (none set, or the same as retail —
    /// Marg backups usually carry one sale rate only), so the bill shows the retail price for them.
    private var tierNote: String? {
        guard let pt = party, pt.str("price_tier") == "WHOLESALE" else { return nil }
        let ids = Set(lines.map { $0.itemId })
        let same = allItems.filter { ids.contains($0.id) && ($0.num("wholesale_price") <= 0 || abs($0.num("wholesale_price") - $0.num("retail_price")) < 0.000001) }
        if same.isEmpty { return nil }
        return "\(same.count) item\(same.count == 1 ? " has" : "s have") no separate wholesale price, so \(same.count == 1 ? "it is" : "they are") billed at the retail price. Set wholesale prices in Stock › More › Set prices from MRP."
    }

    private var duesOver: Bool {
        guard let pt = party else { return false }
        let limit = pt.num("credit_limit")
        return limit > 0 && pt.num("balance") > limit
    }

    private func workingCard(_ t: BillTotals?) -> some View {
        card {
            VStack(spacing: 0) {
                row("Items", t.map { Fmt.money($0.subtotal) } ?? "–")
                row("Discount", t.map { "- " + Fmt.money($0.discount) } ?? "–")
                row("Taxable", t.map { Fmt.money($0.taxable) } ?? "–")
                row("GST", t.map { Fmt.money($0.gst) } ?? "–")
                row("Round off", t.map { Fmt.money($0.roundOff) } ?? "–")
            }
        }
    }

    private func totalCard(_ t: BillTotals?, ready: Bool) -> some View {
        card {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(editingId != nil ? "EDITING \(editingNo)" : "BILL TOTAL").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    ProgressView().controlSize(.small).opacity(calculating ? 1 : 0)
                }
                Text(t.map { Fmt.money($0.total) } ?? "₹0.00")
                    .font(.system(size: 28, weight: .bold, design: .rounded)).mono().foregroundStyle(Theme.accent)
                    .lineLimit(1).minimumScaleFactor(0.5)
                Text("\(lines.count) item\(lines.count == 1 ? "" : "s") · \(lines.reduce(0) { $0 + $1.totalPcs }) pcs").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 2)
                HStack(spacing: 8) {
                    Button { Task { await save() } } label: {
                        Label(editingId != nil ? "Update" : "Save & print", systemImage: "printer").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(busy || lines.isEmpty || (!ready && errorText != nil))
                    Button(editingId != nil ? "Cancel" : "New") { clear() }
                }
            }
        }
    }

    private func row(_ a: String, _ b: String) -> some View {
        HStack { Text(a).foregroundStyle(.secondary); Spacer(); Text(b).mono() }
            .font(.callout)
            .frame(maxHeight: .infinity)
    }

    // MARK: Server

    /// A bill is on credit unless money is entered. A walk-in customer has no account, so they always pay at the counter.
    private var effectiveMode: String {
        let amount = Double(paid.trimmingCharacters(in: .whitespaces)) ?? 0
        if payMode == "CREDIT" && (partyId == 0 || amount > 0) { return "CASH" }
        return payMode
    }

    private func payload(override: Bool = false) -> [String: Any] {
        var d: [String: Any] = [
            "date": billDate, "sale_type": saleType, "pay_mode": effectiveMode,
            "lines": lines.map { l -> [String: Any] in
                var d: [String: Any] = ["item_id": l.itemId, "boxes": l.boxes, "pcs": l.pcs, "disc_pct": Double(l.disc) ?? 0]
                if let r = Double(l.rate.trimmingCharacters(in: .whitespaces)), r >= 0, !l.rate.isEmpty { d["rate"] = r }
                return d
            },
        ]
        if partyId != 0 { d["party_id"] = partyId }
        if salesmanId != 0 { d["salesman_id"] = salesmanId }
        if let v = Double(paid.trimmingCharacters(in: .whitespaces)) { d["paid_amount"] = v }
        if override { d["override_credit"] = true }
        return d
    }

    /// Creates a customer without leaving the bill; the new party is selected as soon as it is saved.
    private func addedParty() async {
        let before = Set(parties.map { $0.id })
        await reload()
        if let n = parties.filter({ !before.contains($0.id) }).max(by: { $0.id < $1.id }) { partyId = n.id }
    }

    private func reload() async {
        await app.guarded {
            async let p = API.list("/parties", query: ["kind": "CUSTOMER"])
            async let s = API.list("/salesmen")
            async let i = API.list("/items", query: ["all": "1"])
            async let r = API.list("/routes")
            parties = try await p
            routes = try await r
            salesmen = try await s
            allItems = try await i
            syncModel()
        }
        await loadMix()
    }

    /// Hands the model the prices, party and tax state it needs; called whenever any of them changes.
    private func syncModel() {
        model.roundTotal = app.settings.str("bill_round") != "0"
        model.configure(items: allItems, party: party, myState: app.settings.str("state_code"))
    }

    /// Asks the server for the totals of the bill as it stands now. Only the newest request is allowed to show its answer.
    private func recalc() async {
        if lines.isEmpty { preview = nil; errorText = nil; calculating = false; return }
        calcGen += 1
        let mine = calcGen
        let key = recalcKey
        calculating = true
        do {
            let r = try await API.objRaw("POST", "/invoices/preview", body: payload())
            guard mine == calcGen else { return }
            preview = r
            previewKey = key
            errorText = nil
        } catch {
            guard mine == calcGen else { return }
            preview = nil
            previewKey = ""
            errorText = error.localizedDescription
        }
        calculating = false
    }

    private func loadForEdit(_ id: Int) async {
        await app.guarded {
            let inv = try await API.obj("GET", "/invoices/\(id)")
            lines = inv.list("edit_lines").map { l -> BillLine in
                var bl = BillLine(itemId: l.int("item_id"), name: l.str("item_name"), ppb: max(1, l.int("pcs_per_box")),
                                  stock: allItems.first { $0.id == l.int("item_id") }?.num("stock") ?? 0)
                let q = Int(l.num("qty"))
                bl.boxes = bl.ppb > 1 ? q / bl.ppb : 0
                bl.pcs = bl.ppb > 1 ? q % bl.ppb : q
                if l.has("rate") { bl.rate = Fmt.qty(l.num("rate")) }
                let md = l.num("manual_disc")
                bl.disc = md == 0 ? "" : Fmt.qty(md)
                return bl
            }
            editingId = id
            editingNo = inv.str("invoice_no")
            partyId = inv.optInt("party_id") ?? 0
            salesmanId = inv.optInt("salesman_id") ?? 0
            saleType = inv.str("sale_type").isEmpty ? "COUNTER" : inv.str("sale_type")
            payMode = inv.str("pay_mode").isEmpty ? "CASH" : inv.str("pay_mode")
            paid = String(format: "%.2f", inv.num("paid"))
            billDate = inv.str("date").isEmpty ? app.dateInFY : String(inv.str("date").prefix(10))
        }
    }

    private func clear() {
        lines = []
        preview = nil
        errorText = nil
        partyId = 0
        paid = ""
        payMode = app.defaultPayMode
        saleType = app.defaultSaleType
        billDate = app.dateInFY
        editingId = nil
        editingNo = ""
        query = ""
        searchFocus = true
    }

    private func save(override: Bool = false) async {
        guard !busy, !lines.isEmpty else { return }
        busy = true
        defer { busy = false }
        await recalc()
        guard preview != nil, previewKey == recalcKey else { return }
        do {
            let wasEdit = editingId
            let r: JSON
            if let wasEdit {
                r = try await API.objRaw("PUT", "/invoices/\(wasEdit)", body: payload(override: override || app.settings.str("bill_credit_check") == "0"))
            } else {
                r = try await API.objRaw("POST", "/invoices", body: payload(override: override || app.settings.str("bill_credit_check") == "0"))
            }
            app.notify("\(wasEdit != nil ? "Updated" : "Saved") \(r.str("invoice_no")) · \(Fmt.money(r, "total"))")
            let keptParty = partyId
            clear()
            if app.settings.str("bill_keep_party") == "1" && wasEdit == nil { partyId = keptParty }   // Settings › Billing › next bill for the same party
            await reload()
            await WhatsApp.sendIfEnabled(r.int("id"), app: app)   // starts in the background first, so it runs while the print window opens
            switch app.settings.str("bill_after_save") {
            case "later": app.notify("\(r.str("invoice_no")) kept to print later (All Bills › Not printed).")
            case "ask":
                let a = NSAlert()
                a.messageText = "Print \(r.str("invoice_no")) now?"
                a.informativeText = "Later: it waits under All Bills › Not printed, to print with others."
                a.addButton(withTitle: "Print now")
                a.addButton(withTitle: "Later")
                if a.runModal() == .alertFirstButtonReturn { await printInvoice(r.int("id"), app: app) }
            default: await printInvoice(r.int("id"), app: app)
            }
        } catch let e as APIError where e.code == "CREDIT_LIMIT" && !override {
            let a = NSAlert()
            a.messageText = "Credit limit exceeded"
            a.informativeText = e.message
            a.alertStyle = .warning
            a.addButton(withTitle: "Bill anyway")
            a.addButton(withTitle: "Cancel")
            busy = false
            if a.runModal() == .alertFirstButtonReturn { await save(override: true) }
        } catch {
            app.notify(error.localizedDescription, error: true)
        }
    }
}

/// A whole-number field for Box / Pcs. It keeps what is typed (so clearing the field is allowed) and pushes every keystroke
/// straight into the bill; if the bill changes the number from elsewhere (a repeated scan adds a box) the text follows.
/// Which quantity field of which line has the cursor.
enum QtyField: Hashable { case box(UUID), pcs(UUID) }

private struct IntCell: View {
    @Binding var value: Int
    let field: QtyField
    var focus: FocusState<QtyField?>.Binding
    @Binding var select: QtyField?
    var next: () -> Void = {}
    @State private var text = ""
    /// Reached by adding the item: the first digit typed replaces the number (shown greyed meanwhile); leaving without typing keeps it.
    @State private var replacing = false

    var body: some View {
        TextField("0", text: $text, prompt: Text(replacing ? String(value) : "0"))
            .multilineTextAlignment(.trailing)
            .focused(focus, equals: field)
            .onSubmit { next() }
            .onAppear { text = String(value) }
            .onChange(of: text) { t in
                let digits = String(t.filter(\.isNumber).prefix(7))
                if digits != t { text = digits }
                if replacing && digits.isEmpty { return }
                replacing = false
                let n = Int(digits) ?? 0
                if n != value { value = n }
            }
            .onChange(of: value) { v in
                if !replacing && (Int(text) ?? 0) != v { text = String(v) }
            }
            .onChange(of: focus.wrappedValue) { f in
                if f == field && select == field {
                    select = nil
                    replacing = true
                    text = ""
                } else if f != field && replacing {
                    replacing = false
                    text = String(value)
                }
            }
    }
}

/// Bill screen › Mix box › Edit: the boxes offered (Settings key mix_boxes). Name words: the item name must contain one of
/// them (none = every item); "-WORD" leaves out items whose name has it. MRP 0 = any; box 0 = one lot of every match.
@MainActor struct MixBoxEditor: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    let boxes: [JSON]
    let done: () async -> Void
    struct Box: Identifiable { let id = UUID(); var name = "", match = "", mrp = "0", box = "0", each = "12" }
    @State private var rows: [Box] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mix boxes").font(.title3.bold())
            Text("Name words: the item name must have one of them (empty = every item); -WORD leaves out names with it. MRP 0 = any MRP. Box 0 = one lot of every item in stock. When stock is short, more lots of the same items fill the box.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack { Text("Name").frame(width: 220, alignment: .leading); Text("Name words").frame(width: 170, alignment: .leading)
                Text("MRP ₹").frame(width: 60); Text("Box pc").frame(width: 60); Text("Each pc").frame(width: 60); Spacer() }
                .font(.caption.bold()).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach($rows) { $r in
                        HStack {
                            TextField("₹10 Namkeen mix box", text: $r.name).frame(width: 220)
                            TextField("-CHIPS -PAPAD", text: $r.match).frame(width: 170)
                            TextField("0", text: $r.mrp).frame(width: 60)
                            TextField("0", text: $r.box).frame(width: 60)
                            TextField("12", text: $r.each).frame(width: 60)
                            Button(role: .destructive) { rows.removeAll { $0.id == r.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                            Spacer()
                        }
                        .textFieldStyle(.roundedBorder)
                    }
                }
            }
            .frame(minHeight: 220)
            HStack {
                Button { rows.append(Box()) } label: { Label("Add a box", systemImage: "plus") }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { Task { await save() } }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 720, height: 460)
        .onAppear {
            rows = boxes.map { Box(name: $0.str("name"), match: $0.str("match"), mrp: Fmt.qty($0.num("mrp")), box: String($0.int("box")), each: String(max(1, $0.int("each")))) }
        }
    }

    private func save() async {
        let list: [[String: Any]] = rows.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }.map {
            ["name": $0.name.trimmingCharacters(in: .whitespaces), "match": $0.match.trimmingCharacters(in: .whitespaces),
             "mrp": Double($0.mrp) ?? 0, "box": Int($0.box) ?? 0, "each": max(1, Int($0.each) ?? 12)]
        }
        guard let d = try? JSONSerialization.data(withJSONObject: list), let json = String(data: d, encoding: .utf8) else { return }
        await app.guarded {
            _ = try await API.obj("PUT", "/settings", body: ["mix_boxes": json])
            await done()
            dismiss()
        }
    }
}
