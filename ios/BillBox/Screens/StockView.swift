import SwiftUI

@MainActor struct StockView: View {
    @EnvironmentObject private var app: AppModel
    @State private var items: [JSON] = []
    @State private var cats: [JSON] = []
    @State private var query = ""
    @State private var searchDelay = Debouncer()
    @State private var catId = 0
    @State private var selection = Set<JSON.ID>()
    @State private var selecting = false
    @State private var loading = true
    @State private var busy = false

    @State private var editing: JSON?
    @State private var creating = false
    @State private var stockFor: JSON?
    @State private var setStockFor: JSON?
    @State private var schemeFor: JSON?
    @State private var showBulk = false
    @State private var showCategory = false
    @State private var showOnline = false
    @State private var showTidy = false
    @State private var showMerge = false
    @State private var mrpReport: JSON?
    @State private var deleteTarget: JSON?
    @State private var forceTarget: (item: JSON, message: String)?
    @State private var confirmBulkDelete = false
    @State private var confirmZeroStockDelete = false

    private var zeroStockItems: [JSON] { items.filter { $0.num("stock") <= 0 } }
    private func stockText(_ it: JSON) -> String { Fmt.boxPcs(it.int("stock"), it.int("pcs_per_box")) }

    var body: some View { dialogs(chrome(content)) }

    private var content: some View {
        VStack(spacing: 0) {
            SelectionBar(ids: items.map(\.id), selection: $selection, selecting: $selecting, busy: busy) { confirmBulkDelete = true }
            grid
        }
        .background(Theme.page)
    }

    private var grid: some View {
        DataGrid(items, layoutKey: "stock", selection: $selection, selecting: $selecting, onOpen: { editing = $0 }, menu: { AnyView(itemMenu($0)) }) {
            GridColumn("Item", id: "item", min: 160, ideal: 260) { (it: JSON) in Text(it.str("name")).lineLimit(2) }
            GridColumn("Category", id: "category", min: 90, ideal: 140) { (it: JSON) in
                Text(it.str("category")).foregroundStyle(it.str("category").isEmpty ? .secondary : .primary).lineLimit(1)
            }
            GridColumn("HSN", id: "hsn", min: 60, ideal: 80) { (it: JSON) in Text(it.str("hsn")).monospacedDigit() }
            GridColumn("Stock (box + pcs)", id: "stock", min: 110, ideal: 140) { (it: JSON) in
                Text(stockText(it)).monospacedDigit().fontWeight(.semibold)
                    .foregroundStyle(it.num("stock") <= app.lowStockQty ? Color.orange : Color.primary)
            }
            GridColumn("Pcs per box", id: "box", min: 70, ideal: 90) { (it: JSON) in Text(it.int("pcs_per_box") > 1 ? "\(it.int("pcs_per_box"))" : "–") }
            GridColumn("Total pcs", id: "pcs", min: 70, ideal: 90, align: .trailing, hidden: true) { (it: JSON) in Text(it.str("stock")).monospacedDigit() }
            GridColumn("MRP", id: "mrp", min: 70, ideal: 90) { (it: JSON) in Text(Fmt.money(it, "mrp")).monospacedDigit() }
            GridColumn("Retail / pc (ex-GST)", id: "retail", min: 90, ideal: 120, align: .trailing) { (it: JSON) in Text(Fmt.rate(it.num("retail_price"))).monospacedDigit() }
            GridColumn("Wholesale / pc (ex-GST)", id: "wholesale", min: 90, ideal: 120, align: .trailing) { (it: JSON) in Text(Fmt.rate(it.num("wholesale_price"))).monospacedDigit() }
            // what one whole box sells for, GST included: shows at once if a stored piece price was rounded
            GridColumn("Retail / box (incl. GST)", id: "retailbox", min: 130, ideal: 150, align: .trailing) { (it: JSON) in
                Text(it.int("pcs_per_box") > 1 ? Fmt.money(it.num("retail_price") * Double(it.int("pcs_per_box")) * (1 + it.num("gst_rate") / 100)) : "–").monospacedDigit()
            }
            GridColumn("Wholesale / box (incl. GST)", id: "wholesalebox", min: 140, ideal: 160, align: .trailing) { (it: JSON) in
                Text(it.int("pcs_per_box") > 1 ? Fmt.money(it.num("wholesale_price") * Double(it.int("pcs_per_box")) * (1 + it.num("gst_rate") / 100)) : "–").monospacedDigit()
            }
            GridColumn("Cost", id: "cost", min: 70, ideal: 90) { (it: JSON) in Text(Fmt.money(it, "purchase_price")).monospacedDigit() }
            GridColumn("GST", id: "gst", min: 44, ideal: 55) { (it: JSON) in Text("\(Fmt.qty(it.num("gst_rate")))%").monospacedDigit() }
            GridColumn("Your margin", id: "margin", min: 70, ideal: 90) { (it: JSON) in Text("\(it.str("dist_margin_pct"))%").monospacedDigit() }
            GridColumn("Retailer margin", id: "rmargin", min: 80, ideal: 110) { (it: JSON) in Text("\(it.str("retailer_margin_pct"))%").monospacedDigit() }
        }
        .overlay {
            if loading { ProgressView() }
            else if items.isEmpty { EmptyState(title: "No items", symbol: "archivebox", message: "Add an item, or scan a supplier bill in Purchases and items are created for you.") }
        }
    }

    @ViewBuilder private func itemMenu(_ it: JSON) -> some View {
        Button { editing = it } label: { Label("Edit…", systemImage: "pencil") }
        Button { stockFor = it } label: { Label("Add stock…", systemImage: "plus.square") }
        Button { setStockFor = it } label: { Label("Set stock qty…", systemImage: "square.and.pencil") }
        Button { schemeFor = it } label: { Label("Add scheme…", systemImage: "gift") }
        Divider()
        Button(role: .destructive) { deleteTarget = it } label: { Label("Delete…", systemImage: "trash") }
        if selection.count > 1 && selection.contains(it.id) {
            Button { showMerge = true } label: { Label("Merge \(selection.count) selected…", systemImage: "arrow.triangle.merge") }
            Button(role: .destructive) { confirmBulkDelete = true } label: { Label("Delete \(selection.count) selected…", systemImage: "trash") }
        }
    }

    @ViewBuilder private func chrome<V: View>(_ v: V) -> some View {
        v
        .navigationTitle("Stock")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search item or HSN")
        .onSubmit(of: .search) { Task { await load() } }
        .onChange(of: query) { _ in searchDelay.run { await load() } }   // typing loads once, 250 ms after the last key
        .onChange(of: catId) { _ in Task { await load() } }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Menu {
                    Picker("Category", selection: $catId) {
                        Text("All categories").tag(0)
                        ForEach(cats) { c in Text(c.str("name")).tag(c.id) }
                    }
                } label: { Label("Category", systemImage: catId == 0 ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill") }
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
                    Divider()
                    Button("Delete items with zero/negative stock…", role: .destructive) { confirmZeroStockDelete = true }.disabled(zeroStockItems.isEmpty)
                } label: { Label("More", systemImage: "ellipsis.circle") }
            }
            ToolbarItem(placement: .bottomBar) {
                Text("\(items.count) items" + (catId == 0 ? "" : " in \(cats.first { $0.id == catId }?.str("name") ?? "")")).font(.footnote).foregroundStyle(.secondary)
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
        .sheet(isPresented: $showOnline) { OnlineItemsSheet { await load() } }
        .sheet(isPresented: $showTidy) { TidyItemsSheet { await load() } }
        .sheet(isPresented: $showMerge) { MergeSelectedSheet(items: items.filter { selection.contains($0.id) }) { selection = []; await load() } }
        .sheet(item: $mrpReport) { r in MRPReportSheet(report: r) }
        .confirmationDialog("Delete \(deleteTarget?.str("name") ?? "")?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let t = deleteTarget { Task { await delete(t, force: false) } } }
        } message: {
            Text("Items that were ever bought or sold are archived instead, so history stays intact.")
        }
        .alert("Still in stock", isPresented: Binding(get: { forceTarget != nil }, set: { if !$0 { forceTarget = nil } })) {
            Button("Delete anyway", role: .destructive) { if let t = forceTarget { Task { await delete(t.item, force: true) } } }
            Button("Cancel", role: .cancel) {}
        } message: { Text((forceTarget?.message ?? "") + "\n\nDelete it anyway?") }
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
    }

    private func load() async {
        await app.guarded {
            async let i = API.list("/items", query: ["q": query, "category_id": catId == 0 ? nil : catId])
            async let c = API.list("/categories")
            items = try await i
            cats = try await c
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
            forceTarget = (it, e.message)
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
        selecting = false
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
