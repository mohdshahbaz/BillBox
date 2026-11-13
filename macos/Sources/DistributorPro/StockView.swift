import SwiftUI
import AppKit

@MainActor struct StockView: View {
    @EnvironmentObject private var app: AppModel
    @State private var items: [JSON] = []
    @State private var cats: [JSON] = []
    @State private var query = ""
    @State private var searchDelay = Debouncer()
    @State private var catId = 0
    @State private var selection = Set<JSON.ID>()
    @State private var loading = true
    @State private var loadError: String?
    @State private var busy = false

    @State private var editing: JSON?
    @State private var creating = false
    @State private var stockFor: JSON?
    @State private var setStockFor: JSON?
    @State private var schemeFor: JSON?
    @State private var showBulk = false
    @State private var showCategory = false
    @State private var renamingCat: JSON?
    @State private var deletingCat: JSON?
    @State private var showOnline = false
    @State private var showTidy = false
    @State private var showMerge = false
    @State private var mrpReport: JSON?
    @State private var deleteTarget: JSON?
    @State private var confirmBulkDelete = false
    @State private var confirmZeroStockDelete = false
    @State private var confirmDeleteAll = false

    private var zeroStockItems: [JSON] { items.filter { $0.num("stock") <= 0 } }
    private var currentCat: JSON? { catId == 0 ? nil : cats.first { $0.id == catId } }

    private func stockText(_ it: JSON) -> String { Fmt.boxPcs(it.int("stock"), it.int("pcs_per_box")) }

    var body: some View { dialogs(chrome(content)) }

    private var content: some View {
        VStack(spacing: 0) {
            SelectionBar(ids: items.map(\.id), selection: $selection, busy: busy) { confirmBulkDelete = true }
            grid
            if !items.isEmpty { summary.padding(.top, 8) }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    /// Out / Low against the low-stock level in Settings (the same rule as the stock figure's colour).
    private func stockPill(_ it: JSON) -> StatusPill {
        let s = it.num("stock")
        if s <= 0 { return StatusPill(text: "Out", tint: Theme.negative) }
        if s <= app.lowStockQty { return StatusPill(text: "Low", tint: Theme.warning) }
        return StatusPill(text: "")
    }

    private var summary: some View {
        let value = items.reduce(0.0) { $0 + max($1.num("stock"), 0) * $1.num("purchase_price") }
        let out = items.filter { $0.num("stock") <= 0 }.count
        let low = items.filter { $0.num("stock") > 0 && $0.num("stock") <= app.lowStockQty }.count
        return SummaryCard(items: [
            SummaryCard.Item(label: "Items", value: "\(items.count)"),
            SummaryCard.Item(label: "Stock value (cost)", value: Fmt.money(value), strong: true),
            SummaryCard.Item(label: "Low stock", value: "\(low)", tint: low > 0 ? Theme.warning : nil),
            SummaryCard.Item(label: "Out of stock", value: "\(out)", tint: out > 0 ? Theme.negative : nil),
        ])
    }

    private var grid: some View {
        DataGrid(items, layoutKey: "stock", selection: $selection, onOpen: { editing = $0 }, menu: { AnyView(itemMenu($0)) }) {
            GridColumn("Item", id: "item", min: 180, ideal: 300) { (it: JSON) in
                Text(it.str("name")).lineLimit(1)
            }

            GridColumn("Category", id: "category", min: 90, ideal: 140) { (it: JSON) in
                Text(it.str("category")).foregroundStyle(it.str("category").isEmpty ? .secondary : .primary)
            }

            GridColumn("HSN", id: "hsn", min: 60, ideal: 80) { (it: JSON) in Text(it.str("hsn")).mono() }

            GridColumn("Stock (box + pcs)", id: "stock", min: 110, ideal: 140) { (it: JSON) in
                Text(stockText(it)).mono().fw(.semibold)
                    .foregroundStyle(it.num("stock") <= app.lowStockQty ? Theme.warning : Color.primary)
            }

            GridColumn("Status", id: "status", min: 60, ideal: 70) { (it: JSON) in stockPill(it) }

            GridColumn("Pcs per box", id: "box", min: 70, ideal: 90) { (it: JSON) in Text(it.int("pcs_per_box") > 1 ? "\(it.int("pcs_per_box"))" : "–") }
            GridColumn("Total pcs", id: "pcs", min: 70, ideal: 90, align: .trailing, hidden: true) { (it: JSON) in Text(it.str("stock")).mono() }

            GridColumn("MRP", id: "mrp", min: 70, ideal: 90) { (it: JSON) in Text(Fmt.money(it, "mrp")).mono() }

            GridColumn("Retail / pc (ex-GST)", id: "retail", min: 90, ideal: 120, align: .trailing) { (it: JSON) in Text(Fmt.rate(it.num("retail_price"))).mono() }
                GridColumn("Wholesale / pc (ex-GST)", id: "wholesale", min: 90, ideal: 120, align: .trailing) { (it: JSON) in Text(Fmt.rate(it.num("wholesale_price"))).mono() }

                // what one whole box sells for, GST included: this is the figure that shows at once if a stored piece price was rounded
                GridColumn("Retail / box (incl. GST)", id: "retailbox", min: 130, ideal: 150, align: .trailing) { (it: JSON) in
                    Text(it.int("pcs_per_box") > 1 ? Fmt.money(it.num("retail_price") * Double(it.int("pcs_per_box")) * (1 + it.num("gst_rate") / 100)) : "–").mono()
                }
                GridColumn("Wholesale / box (incl. GST)", id: "wholesalebox", min: 140, ideal: 160, align: .trailing) { (it: JSON) in
                    Text(it.int("pcs_per_box") > 1 ? Fmt.money(it.num("wholesale_price") * Double(it.int("pcs_per_box")) * (1 + it.num("gst_rate") / 100)) : "–").mono()
                }

                GridColumn("Cost", id: "cost", min: 70, ideal: 90) { (it: JSON) in Text(Fmt.money(it, "purchase_price")).mono() }

                GridColumn("GST", id: "gst", min: 40, ideal: 55) { (it: JSON) in Text("\(Fmt.qty(it.num("gst_rate")))%").mono() }
                GridColumn("Your margin", id: "margin", min: 70, ideal: 90) { (it: JSON) in Text("\(it.str("dist_margin_pct"))%").mono() }

                GridColumn("Retailer margin", id: "rmargin", min: 80, ideal: 110) { (it: JSON) in Text("\(it.str("retailer_margin_pct"))%").mono() }
            
        }
        .overlay {
            if loading && items.isEmpty { SkeletonRows() }
            else if loading { ProgressView() }
            else if let e = loadError, items.isEmpty { ErrorState(message: e) { Task { await load() } } }
            else if items.isEmpty { EmptyState(title: "No items", symbol: "archivebox", message: "Add an item, or scan a supplier bill in Purchases and items are created for you.") }
        }
    }

    @ViewBuilder private func itemMenu(_ it: JSON) -> some View {
        Button("Edit…") { editing = it }
        Button("Add stock…") { stockFor = it }
        Button("Set stock qty…") { setStockFor = it }
        Button("Add scheme…") { schemeFor = it }
        Divider()
        Button("Delete…", role: .destructive) { deleteTarget = it }
        if selection.count > 1 && selection.contains(it.id) {
            Button("Merge \(selection.count) selected…") { showMerge = true }
            Button("Delete \(selection.count) selected…", role: .destructive) { confirmBulkDelete = true }
        }
    }

    @ViewBuilder private func chrome<V: View>(_ v: V) -> some View {
        v
        .navigationTitle("Stock")
        .navigationSubtitle("\(items.count) items")
        .searchable(text: $query, prompt: "Search item or HSN")
        .onSubmit(of: .search) { Task { await load() } }
        .onChange(of: query) { _ in searchDelay.run { await load() } }   // typing loads once, 250 ms after the last key
        .onChange(of: catId) { _ in Task { await load() } }
        .toolbar {
            ToolbarItem {
                Picker("Category", selection: $catId) {
                    Text("All categories").tag(0)
                    ForEach(cats) { c in Text(c.str("name")).tag(c.id) }
                }
                .frame(width: 190)
            }
            ToolbarItemGroup {
                Button { creating = true } label: { Label("New item", systemImage: "plus") }
                Menu {
                    Section {
                        Button("Auto categories (from item names)") { Task { await autoCategorise() } }
                        Button("Auto-fill missing MRPs") { Task { await autoMRP() } }
                        Button("Set prices from MRP…") { showBulk = true }
                    }
                    Divider()
                    Section {
                        Button("Items from the internet…") { showOnline = true }
                        Button("Tidy names & merge duplicates…") { showTidy = true }
                        Button("Merge selected items…") { showMerge = true }.disabled(selection.count < 2)
                    }
                    Divider()
                    Button("New category…") { showCategory = true }
                    Button("Rename category “\(currentCat?.str("name") ?? "")”…") { renamingCat = currentCat }.disabled(currentCat == nil)
                    Button("Delete category “\(currentCat?.str("name") ?? "")”…") { deletingCat = currentCat }.disabled(currentCat == nil)
                    Divider()
                    Button("Delete items with zero/negative stock…") { confirmZeroStockDelete = true }.disabled(zeroStockItems.isEmpty)
                    Button("Delete ALL items, even those in stock…") { confirmDeleteAll = true }
                } label: { Label("More", systemImage: "ellipsis.circle") }
            }
        }
        .task { await load() }
        .onChange(of: app.dataVersion) { _ in Task { await load() } }
    }

    @ViewBuilder private func dialogs<V: View>(_ v: V) -> some View {
        v
        .sheet(isPresented: $creating) { ItemSheet(item: nil, cats: cats) { await load() } }
        .sheet(item: $editing) { it in ItemSheet(item: it, cats: cats) { await load() } }
        .sheet(item: $stockFor) { it in AddStockSheet(item: it) { await load() } }
        .sheet(item: $setStockFor) { it in SetStockSheet(item: it) { await load() } }
        .sheet(item: $schemeFor) { it in SchemeSheet(item: it) }
        .sheet(isPresented: $showBulk) { BulkPriceSheet(cats: cats, initialCat: catId) { await load() } }
        .sheet(isPresented: $showCategory) { CategorySheet { await load() } }
        .sheet(item: $renamingCat) { c in CategorySheet(existing: c) { await load() } }
        .confirmationDialog("Delete category \(deletingCat?.str("name") ?? "")?", isPresented: Binding(get: { deletingCat != nil }, set: { if !$0 { deletingCat = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                guard let c = deletingCat else { return }
                Task {
                    await app.guarded {
                        let r = try await API.obj("DELETE", "/categories/\(c.id)")
                        if catId == c.id { catId = 0 }
                        app.notify("\(c.str("name")) deleted; \(r.int("uncategorised")) items moved to Uncategorised.")
                        await load()
                    }
                }
            }
        } message: {
            Text("Its items are kept and moved to Uncategorised.")
        }
        .sheet(isPresented: $showOnline) { OnlineItemsSheet { await load() } }
        .sheet(isPresented: $showTidy) { TidyItemsSheet { await load() } }
        .sheet(isPresented: $showMerge) { MergeSelectedSheet(items: items.filter { selection.contains($0.id) }) { selection = []; await load() } }
        .sheet(item: $mrpReport) { r in MRPReportSheet(report: r) }
        .confirmationDialog("Delete \(deleteTarget?.str("name") ?? "")?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let t = deleteTarget { Task { await delete(t, force: false) } } }
        } message: {
            Text("Items that were ever bought or sold are archived instead, so history stays intact.")
        }
        .confirmationDialog("Delete \(selection.count) selected item\(selection.count == 1 ? "" : "s")?", isPresented: $confirmBulkDelete, titleVisibility: .visible) {
            Button("Delete \(selection.count)", role: .destructive) { Task { await bulkDeleteSelected() } }
        } message: {
            Text("Items that were ever bought or sold are archived instead, so history stays intact. An item still in stock is skipped.")
        }
        .confirmationDialog("Delete \(zeroStockItems.count) item\(zeroStockItems.count == 1 ? "" : "s") with zero or negative stock?", isPresented: $confirmZeroStockDelete, titleVisibility: .visible) {
            Button("Delete \(zeroStockItems.count)", role: .destructive) { Task { await bulkDeleteZeroStock() } }
        } message: {
            Text("Items that were ever bought or sold are archived instead, so history stays intact.")
        }
        .confirmationDialog("Delete ALL items, even those still in stock?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Delete all items", role: .destructive) { Task { await bulkDeleteAll() } }
        } message: {
            Text("Every item in every category is deleted, including items that still have stock. Items that were ever bought or sold are archived instead, so old bills stay intact. Back up first (Settings › Backup): this cannot be undone.")
        }
    }

    private func load() async {
        do {
            async let i = API.list("/items", query: ["q": query, "category_id": catId == 0 ? nil : catId])
            async let c = API.list("/categories")
            items = try await i
            cats = try await c
            loadError = nil
        } catch {
            loadError = error.localizedDescription
            if !items.isEmpty { app.notify(error.localizedDescription, error: true) }   // the list stays; say why it did not refresh
        }
        loading = false
    }

    private func autoCategorise() async {
        await app.guarded {
            let r = try await API.obj("POST", "/items/auto-categorize", body: [:])
            app.notify("\(r.int("categorised")) of \(r.int("checked")) items categorised" + (r.int("from_internet") > 0 ? " (\(r.int("from_internet")) found on the internet)." : "."))
            await load()
        }
    }

    private func autoPack() async {
        await app.guarded {
            let r = try await API.obj("POST", "/items/auto-pack", body: [:])
            app.notify("\(r.int("changed")) of \(r.int("checked")) items with a pack size in the name were updated.")
            await load()
        }
    }

    private func autoMRP() async {
        await app.guarded {
            let r = try await API.obj("POST", "/items/auto-mrp", body: [:])
            mrpReport = r
            await load()
        }
    }

    private func delete(_ it: JSON, force: Bool) async {
        do {
            let r = try await API.obj("DELETE", "/items/\(it.id)", query: ["force": force ? 1 : nil])
            app.notify(r.str("result") == "archived" ? "\(it.str("name")) archived (it has history)." : "\(it.str("name")) deleted.")
            await load()
        } catch let e as APIError where e.code == "HAS_STOCK" && !force {
            let a = NSAlert()
            a.messageText = "Still in stock"
            a.informativeText = e.message + "\n\nDelete it anyway?"
            a.addButton(withTitle: "Delete anyway")
            a.addButton(withTitle: "Cancel")
            if a.runModal() == .alertFirstButtonReturn { await delete(it, force: true) }
        } catch {
            app.notify(error.localizedDescription, error: true)
        }
    }

    private func deleteOutcome(_ id: JSON.ID) async -> BulkOutcome {
        guard let it = items.first(where: { $0.id == id }) else { return .failed(label: "#\(id)", reason: "not found") }
        do {
            let r = try await API.obj("DELETE", "/items/\(it.id)", query: ["force": nil])
            return r.str("result") == "archived" ? .archived : .deleted
        } catch let e as APIError where e.code == "HAS_STOCK" {
            return .failed(label: it.str("name"), reason: "still in stock")
        } catch {
            return .failed(label: it.str("name"), reason: error.localizedDescription)
        }
    }

    private func bulkDeleteSelected() async {
        busy = true
        await bulkDelete(Array(selection), notify: { app.notify($0) }, delete: deleteOutcome)
        selection = []
        busy = false
        await load()
    }

    /// Every active item (all categories, not only the ones on screen), deleted even when it still has stock.
    private func bulkDeleteAll() async {
        busy = true
        let all = (try? await API.list("/items", query: ["all": "1"])) ?? []
        await bulkDelete(all.map(\.id), notify: { app.notify($0) }) { id -> BulkOutcome in
            let name = all.first { $0.id == id }?.str("name") ?? "#\(id)"
            do {
                let r = try await API.obj("DELETE", "/items/\(id)", query: ["force": 1])
                return r.str("result") == "archived" ? .archived : .deleted
            } catch {
                return .failed(label: name, reason: error.localizedDescription)
            }
        }
        selection = []
        busy = false
        await load()
    }

    private func bulkDeleteZeroStock() async {
        busy = true
        await bulkDelete(zeroStockItems.map(\.id), notify: { app.notify($0) }, delete: deleteOutcome)
        selection = []
        busy = false
        await load()
    }
}

// MARK: - Sheets

@MainActor struct ItemSheet: View {
    @EnvironmentObject private var app: AppModel
    /// Settings › Billing & Dashboard › GST % for new items (18 unless changed).
    private var defaultGst: String { app.settings.str("item_default_gst").isEmpty ? "18" : app.settings.str("item_default_gst") }
    let item: JSON?
    let cats: [JSON]
    let done: () async -> Void
    @State private var f: [String: String] = [:]

    private func binding(_ k: String, _ d: String = "") -> Binding<String> {
        Binding(get: { f[k] ?? (item?.has(k) == true ? item!.str(k) : d) }, set: { f[k] = $0 })
    }

    /// What was typed in a box-price field (GST included, the way a box is quoted). It is kept exactly as typed, so "2500." or
    /// "2,499.5" stay on screen while typing; the piece price is worked out from it with the pieces per box BillBox will save
    /// (the "(1X144)" in the name wins over the typed number, exactly as the save does) and the GST rate on screen.
    @State private var boxText: [String: String] = [:]

    private static func number(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces))
    }

    private func factors() -> (ppb: Double, gst: Double) {
        let typed = max(1, Int(binding("pcs_per_box", "1").wrappedValue.trimmingCharacters(in: .whitespaces)) ?? 1)
        let ppb = Fmt.packFromName(binding("name").wrappedValue) ?? typed
        return (Double(ppb), 1 + (Self.number(binding("gst_rate", defaultGst).wrappedValue) ?? 0) / 100)
    }

    /// The exact piece price (ex-GST) to save for a price field: from the typed box price when one was typed, kept to 8 decimals,
    /// so a box of 300 at 2500 is billed back as exactly 2500.
    private func exactPiece(_ k: String) -> String {
        guard let bt = boxText[k] else { return binding(k).wrappedValue }
        if bt.trimmingCharacters(in: .whitespaces).isEmpty { return "" }
        guard let b = Self.number(bt) else { return bt }
        let x = factors()
        return String(format: "%.8f", b / x.ppb / x.gst)
    }

    /// Piece price field (ex-GST). Shows the piece price that follows from a typed box price (to 4 decimals); typing here
    /// replaces the box price.
    private func pieceBinding(_ k: String) -> Binding<String> {
        Binding(
            get: {
                guard boxText[k] != nil else { return binding(k).wrappedValue }
                let v = exactPiece(k)
                return Double(v).map { Fmt.rate($0) } ?? v
            },
            set: { boxText[k] = nil; f[k] = $0 })
    }

    /// Box price field (GST included) for a per-piece ex-GST price.
    private func boxBinding(_ k: String) -> Binding<String> {
        Binding(
            get: {
                if let bt = boxText[k] { return bt }
                let x = factors()
                guard let p = Self.number(binding(k).wrappedValue), p > 0 else { return "" }
                return Fmt.qty((p * x.ppb * x.gst * 100).rounded() / 100)
            },
            set: { boxText[k] = $0 })
    }

    var body: some View {
        FormSheet(title: item == nil ? "New item" : "Edit \(item!.str("name"))", width: 560, canSave: !binding("name").wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty, onSave: save) {
            TextField("Item name", text: binding("name"))
            Picker("Category", selection: binding("category_id")) {
                Text("Choose automatically from the name").tag("")
                ForEach(cats) { c in Text(c.str("name")).tag(String(c.id)) }
            }
            TextField("HSN code", text: binding("hsn"))
            TextField("GST rate %", text: binding("gst_rate", defaultGst))
            TextField("Pieces in one box (1 if sold loose only)", text: binding("pcs_per_box", "1"))
            if let n = Fmt.packFromName(binding("name").wrappedValue) {
                Text("The name says 1 box = \(n) pieces. That is used automatically.").font(.caption).foregroundStyle(.secondary)
            }
            Text("Stock and prices are kept per piece; bills show boxes and pieces.").font(.caption).foregroundStyle(.secondary)
            TextField("MRP per piece (incl. GST)", text: binding("mrp"))
            TextField("Retail price per piece (ex-GST)", text: pieceBinding("retail_price"))
            TextField("Retail price per box (incl. GST)", text: boxBinding("retail_price"))
            TextField("Wholesale price per piece (ex-GST)", text: pieceBinding("wholesale_price"))
            TextField("Wholesale price per box (incl. GST)", text: boxBinding("wholesale_price"))
            Text("Type either the box price (with GST) or the piece price (ex-GST); the other follows. The box price uses the pieces per box from the name when it has one. Prices are kept to 8 decimals, so a box of 300 at 2500 is billed as exactly 2500.").font(.caption).foregroundStyle(.secondary)
            TextField("Purchase price per piece (ex-GST)", text: binding("purchase_price"))
        }
    }

    private func save() async throws {
        var body: [String: Any?] = [:]
        for k in ["name", "category_id", "hsn", "gst_rate", "pcs_per_box", "mrp", "retail_price", "wholesale_price", "purchase_price"] {
            body[k] = binding(k, k == "gst_rate" ? defaultGst : (k == "pcs_per_box" ? "1" : "")).wrappedValue
        }
        for k in ["retail_price", "wholesale_price"] where boxText[k] != nil { body[k] = exactPiece(k) }
        if let item { _ = try await API.obj("PUT", "/items/\(item.id)", body: body) } else { _ = try await API.obj("POST", "/items", body: body) }
        app.notify(item == nil ? "Item added. Record a purchase (or add stock) to start selling it." : "Item saved.")
        await done()
    }
}

@MainActor struct AddStockSheet: View {
    @EnvironmentObject private var app: AppModel
    let item: JSON
    let done: () async -> Void
    @State private var boxes = ""
    @State private var pcs = ""
    @State private var price = ""

    private var perBox: Int { max(1, item.int("pcs_per_box")) }
    private var total: Int { (Int(boxes) ?? 0) * perBox + (Int(pcs) ?? 0) }

    var body: some View {
        FormSheet(title: "Add stock · \(item.str("name"))", canSave: total > 0, onSave: {
            _ = try await API.obj("POST", "/batches", body: ["item_id": item.id, "qty": total, "purchase_price": price.isEmpty ? item.str("purchase_price") : price])
            app.notify("Added \(Fmt.boxPcs(total, perBox)) of \(item.str("name")).")
            await done()
        }) {
            if perBox > 1 { TextField("Boxes (1 box = \(perBox) pcs)", text: $boxes) }
            TextField(perBox > 1 ? "Loose pieces" : "Pieces", text: $pcs)
            if total > 0 { Text("Total \(total) pcs = \(Fmt.boxPcs(total, perBox))").foregroundStyle(.secondary) }
            TextField("Purchase price per piece (ex-GST)", text: $price, prompt: Text(item.str("purchase_price")))
        }
    }
}

@MainActor struct SchemeSheet: View {
    @EnvironmentObject private var app: AppModel
    let item: JSON
    @State private var type = "FREE_QTY"
    @State private var buy = "10"
    @State private var free = "1"
    @State private var percent = "0"
    @State private var from = ""
    @State private var to = ""

    var body: some View {
        FormSheet(title: "Scheme · \(item.str("name"))", onSave: {
            _ = try await API.obj("POST", "/schemes", body: [
                "item_id": item.id, "type": type, "buy_qty": buy, "free_qty": free, "percent": percent,
                "valid_from": from.isEmpty ? nil : from, "valid_to": to.isEmpty ? nil : to,
            ])
            app.notify("Scheme saved.")
        }) {
            Picker("Scheme type", selection: $type) {
                Text("Buy X get Y free").tag("FREE_QTY")
                Text("Percent off from a minimum quantity").tag("PERCENT")
            }
            TextField("Buy quantity / minimum quantity (pieces)", text: $buy)
            if type == "FREE_QTY" { TextField("Free pieces", text: $free) } else { TextField("Discount %", text: $percent) }
            Labeled("Valid from (optional)") { DateField(iso: $from, optional: true) }
            Labeled("Valid to (optional)") { DateField(iso: $to, optional: true) }
        }
    }
}

@MainActor struct CategorySheet: View {
    @EnvironmentObject private var app: AppModel
    var existing: JSON? = nil
    let done: () async -> Void
    @State private var name = ""

    var body: some View {
        FormSheet(title: existing == nil ? "New category" : "Rename category", width: 420, canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty, onSave: {
            if let e = existing {
                _ = try await API.obj("PUT", "/categories/\(e.id)", body: ["name": name.trimmingCharacters(in: .whitespaces)])
            } else {
                _ = try await API.obj("POST", "/categories", body: ["name": name])
            }
            await done()
        }) {
            TextField("Category name", text: $name)
        }
        .onAppear { if let e = existing, name.isEmpty { name = e.str("name") } }
    }
}

/// Retail / wholesale prices for many items at once, from the MRP: a % below MRP, or a price for each MRP.
/// Every item in the preview shows what one box will come to on a bill, worked out exactly as billing does.
@MainActor struct BulkPriceSheet: View {
    @EnvironmentObject private var app: AppModel
    let cats: [JSON]
    let initialCat: Int
    let done: () async -> Void
    @State private var mode = "percent"
    @State private var cat = 0
    @State private var retailOff = ""
    @State private var wholesaleOff = ""
    @State private var round = "auto"
    @State private var groups: [JSON] = []
    @State private var retailBy: [String: String] = [:]
    @State private var wholeBy: [String: String] = [:]
    @State private var perBox = true
    @State private var inclGst = true
    @State private var result: JSON?
    @State private var problem: String?
    @State private var loaded = false

    private func key(_ g: JSON) -> String { Fmt.qty((g.num("mrp") * 100).rounded() / 100) }

    private var tiers: [[String: Any]] {
        groups.compactMap { g in
            let r = (retailBy[key(g)] ?? "").trimmingCharacters(in: .whitespaces), w = (wholeBy[key(g)] ?? "").trimmingCharacters(in: .whitespaces)
            if r.isEmpty && w.isEmpty { return nil }
            var t: [String: Any] = ["mrp": g.num("mrp")]
            if !r.isEmpty { t["retail"] = r }
            if !w.isEmpty { t["wholesale"] = w }
            return t
        }
    }

    private var ready: Bool { mode == "percent" ? !(retailOff.trimmingCharacters(in: .whitespaces).isEmpty && wholesaleOff.trimmingCharacters(in: .whitespaces).isEmpty) : !tiers.isEmpty }

    private func request(_ preview: Bool) -> [String: Any] {
        var b: [String: Any] = ["mode": mode, "preview": preview, "round": round]
        if cat != 0 { b["category_id"] = cat }
        if mode == "percent" {
            if !retailOff.trimmingCharacters(in: .whitespaces).isEmpty { b["retail_off"] = retailOff.trimmingCharacters(in: .whitespaces) }
            if !wholesaleOff.trimmingCharacters(in: .whitespaces).isEmpty { b["wholesale_off"] = wholesaleOff.trimmingCharacters(in: .whitespaces) }
        } else {
            b["tiers"] = tiers
            b["per"] = perBox ? "box" : "piece"
            b["include_gst"] = inclGst
        }
        return b
    }

    /// Changes whenever anything that affects the preview changes.
    private var inputs: String {
        "\(mode)|\(cat)|\(retailOff)|\(wholesaleOff)|\(round)|\(perBox)|\(inclGst)|" + tiers.map { "\($0["mrp"] ?? "")=\($0["retail"] ?? "")/\($0["wholesale"] ?? "")" }.joined(separator: ",")
    }

    var body: some View {
        FormSheet(title: "Set prices from MRP", saveLabel: (result?.int("would_update") ?? 0) > 0 ? "Update \(result!.int("would_update")) items" : "Update prices",
                  width: 760, canSave: ready && problem == nil && (result?.int("would_update") ?? 0) > 0, onSave: save) {
            Section {
                Picker("How", selection: $mode) {
                    Text("% below MRP").tag("percent")
                    Text("Price for each MRP").tag("table")
                }
                .pickerStyle(.segmented)
                Picker("Items", selection: $cat) {
                    Text("Every category").tag(0)
                    ForEach(cats) { c in Text(c.str("name")).tag(c.id) }
                }
            }
            if mode == "percent" {
                Section {
                    PriceField(title: "Retail: % below MRP", text: $retailOff, prompt: "e.g. 16.67")
                    PriceField(title: "Wholesale: % below MRP", text: $wholesaleOff, prompt: "e.g. 20")
                    Picker("Round the box price (GST included)", selection: $round) {
                        Text("To the rupee (under ₹50: to the paisa)").tag("auto")
                        Text("To ₹5").tag("5"); Text("To ₹10").tag("10"); Text("Do not round").tag("none")
                    }
                } footer: {
                    Text("MRP includes GST, so the price is worked out with GST included and GST is then taken out for billing: 16.67% below a ₹3,000 box is a ₹2,500 box, and a bill for that box comes to exactly ₹2,500. Leave a field empty to keep that price.")
                }
            } else {
                Section {
                    Picker("Prices typed for", selection: $perBox) { Text("A whole box").tag(true); Text("One piece").tag(false) }.pickerStyle(.segmented)
                    Toggle("Typed prices include GST", isOn: $inclGst)
                    if groups.isEmpty { Text(loaded ? "No items with an MRP here yet. Use Auto-fill missing MRPs first." : "Loading…").foregroundStyle(.secondary) }
                    ForEach(groups.indices, id: \.self) { i in tierRow(groups[i]) }
                } footer: {
                    Text("Every item whose MRP (per piece) matches gets the price. Greyed numbers are today's prices in the same units. Leave a field empty to keep that price.")
                }
            }
            Section {
                if let problem { Text(problem).foregroundStyle(Theme.negative).font(.callout) }
                if let r = result {
                    Text("\(r.int("would_update")) items will change" + (r.int("skipped_no_mrp") > 0 ? " · \(r.int("skipped_no_mrp")) without an MRP left as they are" : "") + ".")
                        .font(.callout.weight(.medium))
                    ForEach(r.list("items").prefix(150)) { it in previewRow(it) }
                    if r.list("items").count > 150 { Text("…and \(r.list("items").count - 150) more.").font(.caption).foregroundStyle(.secondary) }
                } else if ready && problem == nil {
                    ProgressView()
                } else if problem == nil {
                    Text("Enter a percentage or a price to see every item's new price and bill total.").foregroundStyle(.secondary).font(.callout)
                }
            } header: { Text("Preview: what one box will come to on a bill") }
        }
        .task {
            if !loaded { cat = initialCat }
            await loadGroups()
            loaded = true
        }
        .onChange(of: cat) { _ in retailBy = [:]; wholeBy = [:]; Task { await loadGroups() } }
        .task(id: inputs) {
            guard ready else { result = nil; problem = nil; return }
            await pause(ms: 300)
            if Task.isCancelled { return }
            do {
                let r = try await API.objRaw("POST", "/items/set-prices", body: request(true))
                if Task.isCancelled { return }
                result = r
                problem = nil
            } catch {
                result = nil
                problem = error.localizedDescription
            }
        }
    }

    private func tierRow(_ g: JSON) -> some View {
        let unit = perBox ? "box" : "piece"
        let today = { (k: String) -> String in
            let v = g.num(k + (perBox ? "_box" : "_piece"))
            guard v > 0 else { return "" }
            return Fmt.qty(v)
        }
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("MRP \(Fmt.money(g.num("mrp")))").fw(.semibold).mono()
                if g.num("mrp_box") > 0 && perBox { Text("· box \(Fmt.money(g.num("mrp_box")))").foregroundStyle(.secondary).mono() }
                Spacer()
                Text("\(g.int("items")) item\(g.int("items") == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                PriceField(title: "Retail / \(unit)", text: Binding(get: { retailBy[key(g)] ?? "" }, set: { retailBy[key(g)] = $0 }), prompt: inclGst ? today("retail") : "")
                PriceField(title: "Wholesale / \(unit)", text: Binding(get: { wholeBy[key(g)] ?? "" }, set: { wholeBy[key(g)] = $0 }), prompt: inclGst ? today("wholesale") : "")
            }
        }
    }

    private func previewRow(_ it: JSON) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(it.str("name")).lineLimit(1)
            HStack(spacing: 12) {
                Text("MRP " + (it.int("pcs_per_box") > 1 ? "\(Fmt.money(it.num("mrp_box"))) (\(it.int("pcs_per_box")) × \(Fmt.money(it.num("mrp"))))" : Fmt.money(it.num("mrp"))))
                    .foregroundStyle(.secondary)
                ForEach(["retail", "wholesale"], id: \.self) { k in
                    if it.has(k + "_bill") {
                        HStack(spacing: 4) {
                            Text(k == "retail" ? "Retail" : "Wholesale").foregroundStyle(.secondary)
                            if it.num(k + "_old_bill") > 0 && abs(it.num(k + "_old_bill") - it.num(k + "_bill")) >= 0.5 {
                                Text(Fmt.money(it.num(k + "_old_bill"))).strikethrough().foregroundStyle(.secondary)
                            }
                            Text(Fmt.money(it.num(k + "_bill"))).fw(.semibold).foregroundStyle(k == "retail" ? Color.teal : Theme.warning)
                            Text("(\(Fmt.qty(it.num(k + "_below_pct")))% below)").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .font(.caption).mono().lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private func loadGroups() async {
        await app.guarded { groups = try await API.list("/items/mrp-table", query: ["category_id": cat == 0 ? nil : cat]) }
    }

    private func save() async throws {
        let r = try await API.objRaw("POST", "/items/set-prices", body: request(false))
        app.notify("Prices set for \(r.int("updated")) items. New bills use them straight away.")
        await done()
    }
}

/// A labelled number field for prices and percentages.
@MainActor struct PriceField: View {
    let title: String
    @Binding var text: String
    var prompt = ""

    var body: some View {
        HStack {
            Text(title).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            TextField("", text: $text, prompt: Text(prompt))
                .multilineTextAlignment(.trailing)
                .mono()
                .frame(maxWidth: 120)
        }
    }
}

@MainActor struct MRPReportSheet: View {
    let report: JSON

    var body: some View {
        let by = report.obj("by_category").raw
        let names = by.keys.sorted()
        InfoSheet(title: "MRP read from item names", width: 640, height: 480) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(report.int("found")) of \(report.int("checked")) items without an MRP were filled in. \(report.int("still_missing")) have no price in their name.")
                    DataGrid(names.enumerated().map { (i, n) in JSON(["id": i + 1, "name": n, "found": (by[n] as? [String: Any])?["found"] ?? 0, "missing": (by[n] as? [String: Any])?["missing"] ?? 0]) }, layoutKey: "mrpreport") {
                        GridColumn("Category") { (r: JSON) in Text(r.str("name")) }
                        GridColumn("MRP found", min: 90, ideal: 90) { (r: JSON) in Text(r.str("found")).mono() }
                        GridColumn("Still missing", min: 100, ideal: 100) { (r: JSON) in Text(r.str("missing")).mono().foregroundStyle(r.int("missing") > 0 ? Theme.warning : Color.primary) }
                    }
                    .frame(height: max(120, CGFloat(names.count) * 28 + 40))
                    let missing = report.list("missing")
                    if !missing.isEmpty {
                        Text("Items still needing an MRP (first \(missing.count)) – open each item and type it in:").font(.headline)
                        ForEach(missing) { m in Text("• \(m.str("name"))  ·  \(m.str("category"))").font(.callout) }
                    }
                }
            }
        }
    }
}

@MainActor struct SetStockSheet: View {
    @EnvironmentObject private var app: AppModel
    let item: JSON
    let done: () async -> Void
    @State private var qty = ""

    var body: some View {
        FormSheet(title: "Set stock · \(item.str("name"))", canSave: Int(qty.trimmingCharacters(in: .whitespaces)) != nil, onSave: {
            guard let n = Int(qty.trimmingCharacters(in: .whitespaces)) else { return }
            _ = try await API.obj("POST", "/items/\(item.id)/set-stock", body: ["qty": n])
            app.notify("Stock of \(item.str("name")) set to \(n) pcs.")
            await done()
        }) {
            Text("Now \(item.str("stock")) pcs").foregroundStyle(.secondary)
            TextField("New stock (total pieces)", text: $qty, prompt: Text(item.str("stock")))
            Text("Total pieces, not boxes. Zero and negative numbers are allowed.").font(.footnote).foregroundStyle(.secondary)
        }
    }
}
