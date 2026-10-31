import SwiftUI

/// An item found in a price list, ready to be checked before it is added.
struct FoundItem: Identifiable {
    let id: Int
    var name: String
    var mrp: String
    var include: Bool
    let exists: String?

    init(_ i: Int, _ r: JSON) {
        id = i
        name = r.str("name")
        mrp = r.num("mrp") > 0 ? Fmt.rate(r.num("mrp")) : ""
        exists = r.str("exists_name").isEmpty ? nil : r.str("exists_name")
        include = exists == nil
    }
}

/// Items of one company (and category) from its price list on the internet: search, pick the page or PDF, check the
/// tidied names (the same item listed twice is kept once, items you already have are marked) and add them together.
@MainActor struct OnlineItemsSheet: View {
    @EnvironmentObject private var app: AppModel
    let done: () async -> Void
    @State private var company = ""
    @State private var category = ""
    @State private var results: [JSON] = []
    @State private var link = ""
    @State private var pasted = ""
    @State private var nameCase = "title"
    @State private var found: [FoundItem] = []
    @State private var summary = ""
    @State private var gst = "18"
    @State private var working = ""
    @State private var problem: String?

    private var chosen: [FoundItem] { found.filter { $0.include && !$0.name.trimmingCharacters(in: .whitespaces).isEmpty } }

    var body: some View {
        FormSheet(title: "Items from the internet", saveLabel: chosen.isEmpty ? "Add" : "Add \(chosen.count) item\(chosen.count == 1 ? "" : "s")", width: 680, canSave: !chosen.isEmpty, onSave: save) {
            Section {
                Field("Company / brand (e.g. Bikano)", text: $company)
                Field("Category (e.g. Namkeen)", text: $category)
                HStack {
                    Button { Task { await search() } } label: { Label("Search online", systemImage: "magnifyingglass") }
                        .disabled(company.trimmingCharacters(in: .whitespaces).isEmpty || !working.isEmpty)
                    if !working.isEmpty { ProgressView().padding(.leading, 6); Text(working).font(.caption).foregroundStyle(.secondary) }
                }
                if let problem { Text(problem).font(.callout).foregroundStyle(.red) }
            } header: { Text("1. Find the company's price list") } footer: {
                Text("Searches the web for “company category price list MRP”. Pick the company's own page or PDF where you can.")
            }
            if !results.isEmpty {
                Section("Results") {
                    ForEach(results.indices, id: \.self) { i in
                        let r = results[i]
                        Button { Task { await open(r.str("url")) } } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text((r.bool("pdf") ? "PDF · " : "") + r.str("title")).lineLimit(2)
                                Text(r.str("url")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .disabled(!working.isEmpty)
                    }
                }
            }
            Section {
                Field("Web address of a price list page or PDF", text: $link)
                Button("Read this page") { Task { await open(link) } }.disabled(link.trimmingCharacters(in: .whitespaces).isEmpty || !working.isEmpty)
                TextEditor(text: $pasted).frame(minHeight: 70).font(.callout)
                Button("Read the pasted list") { Task { await readText() } }.disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !working.isEmpty)
            } header: { Text("…or give the page yourself") } footer: { Text("Or paste the list (one item per line, MRP after the name) into the box.") }
            Section {
                Picker("Names", selection: $nameCase) {
                    Text("Title Case (Bikano Bhujia 200g)").tag("title")
                    Text("CAPITALS (BIKANO BHUJIA 200G)").tag("upper")
                    Text("As written").tag("keep")
                }
            }
            if !found.isEmpty {
                Section {
                    ForEach(found.indices, id: \.self) { i in row($found[i]) }
                } header: { Text("2. Check the items") } footer: { Text(summary) }
                Section {
                    Field("Category to put them in", text: $category)
                    Field("GST %", text: $gst)
                } header: { Text("3. Add them") } footer: { Text("Prices other than the MRP, HSN codes and stock can be filled in later under Stock.") }
            }
        }
    }

    @ViewBuilder private func row(_ f: Binding<FoundItem>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Toggle("", isOn: f.include).labelsHidden()
                TextField("Name", text: f.name)
                TextField("MRP", text: f.mrp).frame(width: 80).multilineTextAlignment(.trailing)
            }
            if let ex = f.wrappedValue.exists { Text("Already in your items as \(ex)").font(.caption).foregroundStyle(.orange) }
        }
    }

    private func run(_ label: String, _ work: () async throws -> Void) async {
        problem = nil
        working = label
        defer { working = "" }
        do { try await work() } catch { problem = error.localizedDescription }
    }

    private func search() async {
        await run("Searching…") {
            let r = try await API.obj("POST", "/items/online/search", body: ["company": company, "category": category])
            results = r.list("results")
            if results.isEmpty { problem = "Nothing found. Try other words, or paste the address of the company's price list." }
        }
    }

    private func open(_ url: String) async {
        await run("Reading the page…") {
            var r = try await API.obj("POST", "/items/online/fetch", body: ["url": url, "company": company, "case": nameCase])
            if !r.str("pdf_base64").isEmpty {
                guard let data = Data(base64Encoded: r.str("pdf_base64")) else { throw PDFText.Failure(message: "This PDF could not be read.") }
                working = "Reading the PDF…"
                let text = try await pdfText(data)
                r = try await API.obj("POST", "/items/online/extract", body: ["text": text, "company": company, "case": nameCase])
            }
            show(r)
        }
    }

    private func readText() async {
        await run("Reading…") {
            show(try await API.obj("POST", "/items/online/extract", body: ["text": pasted, "company": company, "case": nameCase]))
        }
    }

    private func show(_ r: JSON) {
        let list = r.list("items")
        found = list.enumerated().map { FoundItem($0.offset, $0.element) }
        summary = "\(r.int("found")) items found, \(r.int("new")) new" + (r.int("duplicates_merged") > 0 ? ", \(r.int("duplicates_merged")) listed twice kept once" : "") + "."
        if list.isEmpty { problem = "No items with a pack size or MRP were found on that page. Try another result, or paste the list." }
    }

    private func save() async throws {
        let items: [[String: Any]] = chosen.map { ["name": $0.name, "mrp": Double($0.mrp) ?? 0] }
        let r = try await API.objRaw("POST", "/items/bulk-add", body: ["category": category, "gst_rate": gst, "items": items])
        let skipped = r.list("skipped").count
        app.notify("Added \(r.list("added").count) items" + (skipped > 0 ? " (\(skipped) skipped: already in your items)." : "."))
        await done()
    }
}

/// Tidy item names (pack sizes, spacing, capitals) and merge items entered more than once — the same name, or similar names
/// (spelling, word order, capitals, a generic word such as "biscuit"). Different pack sizes, MRPs and boxes are never grouped.
/// Every bill, purchase, batch and scheme of a merged item moves to the item kept, and the merged item is archived.
@MainActor struct TidyItemsSheet: View {
    @EnvironmentObject private var app: AppModel
    let done: () async -> Void
    @State private var nameCase = "keep"
    @State private var match = "similar"
    @State private var data: JSON?
    @State private var keepFor: [String: Int] = [:]
    @State private var leaveOut = Set<Int>()
    @State private var skip = Set<Int>()
    @State private var working = false

    private var renames: [JSON] { data?.list("renames") ?? [] }
    private var groups: [JSON] { data?.list("groups") ?? [] }

    var body: some View {
        FormSheet(title: "Tidy names & merge duplicates", saveLabel: "Done", width: 720, onSave: { await done() }) {
            Section {
                Picker("Find", selection: $match) {
                    Text("Same name").tag("exact"); Text("Similar names").tag("similar"); Text("Loosely similar").tag("loose")
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Similar: Bhujia / Bhujiya, “Bikano Bhujia” / “Bhujia Bikano”, “Parle G” / “Parle-G Biscuit”. Loosely similar also groups names that share most words (check those). Different pack sizes (200g / 400g), MRPs or box sizes are never grouped.")
            }
            Section {
                if data == nil { ProgressView() } else if groups.isEmpty { Text("No duplicates found.").foregroundStyle(.secondary) }
                ForEach(groups.indices, id: \.self) { i in groupRow(groups[i]) }
                if groups.count > 1 {
                    Button("Merge all \(groups.count) groups as shown") { Task { await mergeAll() } }.disabled(working).buttonStyle(.borderless)
                }
            } header: { Text(groups.isEmpty ? "Duplicates" : "\(groups.count) groups") } footer: {
                Text("Untick an item to leave it out of its group. Bills, purchases, stock batches and schemes move to the item kept; the others are archived. This cannot be undone, so take a backup first if unsure.")
            }
            Section {
                Picker("Names", selection: $nameCase) {
                    Text("Pack sizes and spacing").tag("keep"); Text("Title Case").tag("title"); Text("CAPITALS").tag("upper")
                }
                if renames.isEmpty { Text("All names are already tidy.").foregroundStyle(.secondary) }
                ForEach(renames.indices, id: \.self) { i in
                    let r = renames[i]
                    Toggle(isOn: Binding(get: { !skip.contains(r.int("id")) }, set: { on in if on { skip.remove(r.int("id")) } else { skip.insert(r.int("id")) } })) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.str("clean"))
                            Text("was " + r.str("name")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if !renames.isEmpty {
                    Button("Rename \(renames.count - renames.filter { skip.contains($0.int("id")) }.count) items") { Task { await rename() } }
                        .disabled(working || renames.allSatisfy { skip.contains($0.int("id")) }).buttonStyle(.borderless)
                }
            } header: { Text("Tidier names") } footer: { Text("“200 GM”, “200gms” and “200 grams” all become 200g (200G in capitals); extra spaces go.") }
        }
        .task(id: "\(nameCase)|\(match)") { await load() }
    }

    private func members(_ g: JSON) -> [JSON] { [g.obj("keep")] + g.list("merge") }
    private func keepId(_ g: JSON) -> Int {
        let chosen = keepFor[g.str("key")] ?? g.obj("keep").int("id")
        return leaveOut.contains(chosen) ? (members(g).first { !leaveOut.contains($0.int("id")) }?.int("id") ?? chosen) : chosen
    }
    private func mergeIds(_ g: JSON) -> [Int] { members(g).map { $0.int("id") }.filter { $0 != keepId(g) && !leaveOut.contains($0) } }

    @ViewBuilder private func groupRow(_ g: JSON) -> some View {
        let k = keepId(g)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(g.str("match") == "same" ? "Same name" : "Similar (\(Int(g.num("score") * 100))% words alike)")
                    .font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 3)
                    .background((g.str("match") == "same" ? Color.green : Color.orange).opacity(0.15), in: Capsule())
                    .foregroundStyle(g.str("match") == "same" ? Color.green : Color.orange)
                if !g.strings("warnings").isEmpty { Text(g.strings("warnings").joined(separator: " · ")).font(.caption).foregroundStyle(.orange) }
                Spacer()
            }
            ForEach(members(g)) { m in
                let id = m.int("id")
                HStack(spacing: 10) {
                    Button { if leaveOut.contains(id) { leaveOut.remove(id) } else { leaveOut.insert(id) } } label: {
                        Image(systemName: leaveOut.contains(id) ? "circle" : "checkmark.circle.fill").foregroundStyle(leaveOut.contains(id) ? Color.secondary : Theme.accent)
                    }
                    .buttonStyle(.borderless)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(m.str("name")).lineLimit(2).foregroundStyle(leaveOut.contains(id) ? .secondary : .primary)
                        Text("MRP \(m.num("mrp") > 0 ? Fmt.money(m.num("mrp")) : "–") · \(max(1, m.int("pcs_per_box"))) per box · \(m.int("used")) bill lines · \(m.int("stock")) pcs")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if id == k {
                        Text("Keep").font(.caption.weight(.semibold)).foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 3).background(Theme.accent, in: Capsule())
                    } else if !leaveOut.contains(id) {
                        Button("Keep this") { keepFor[g.str("key")] = id }.buttonStyle(.borderless).font(.caption)
                    }
                }
            }
            HStack {
                Spacer()
                Button(mergeIds(g).isEmpty ? "Nothing to merge" : "Merge \(mergeIds(g).count) into the kept item") { Task { await merge(g) } }
                    .buttonStyle(.borderedProminent).disabled(working || mergeIds(g).isEmpty)
            }
        }
        .padding(.vertical, 4)
    }

    private func load() async {
        await app.guarded { data = try await API.obj("GET", "/items/clean-preview", query: ["case": nameCase, "match": match]) }
    }

    private func merge(_ g: JSON) async {
        working = true
        defer { working = false }
        await app.guarded {
            let r = try await API.objRaw("POST", "/items/merge", body: ["keep_id": keepId(g), "merge_ids": mergeIds(g)])
            app.notify("Merged \(r.list("merged").count) item(s) into \(r.str("name")).")
        }
        await load()
    }

    private func mergeAll() async {
        working = true
        defer { working = false }
        var n = 0
        await app.guarded {
            for g in groups where !mergeIds(g).isEmpty { _ = try await API.objRaw("POST", "/items/merge", body: ["keep_id": keepId(g), "merge_ids": mergeIds(g)]); n += 1 }
        }
        app.notify("Merged \(n) groups of duplicates.")
        await load()
    }

    private func rename() async {
        working = true
        defer { working = false }
        await app.guarded {
            let ids = renames.map { $0.int("id") }.filter { !skip.contains($0) }
            let r = try await API.objRaw("POST", "/items/clean-names", body: ["case": nameCase, "ids": ids])
            let sk = r.list("skipped").count
            app.notify("Renamed \(r.int("renamed")) items" + (sk > 0 ? "; \(sk) left as they are because another item has that name (merge them)." : "."))
        }
        skip = []
        await load()
    }
}

/// Stock › select items › Merge selected: choose the item to keep; the others' bills, purchases, batches and schemes move to it.
@MainActor struct MergeSelectedSheet: View {
    @EnvironmentObject private var app: AppModel
    let items: [JSON]
    let done: () async -> Void
    @State private var keep: Int?

    var body: some View {
        FormSheet(title: "Merge \(items.count) items", saveLabel: "Merge into the kept item", width: 600, canSave: items.count >= 2, onSave: {
            let k = keep ?? items.first?.id ?? 0
            let r = try await API.objRaw("POST", "/items/merge", body: ["keep_id": k, "merge_ids": items.map { $0.id }.filter { $0 != k }])
            app.notify("Merged \(r.list("merged").count) item(s) into \(r.str("name")).")
            await done()
        }) {
            Section {
                ForEach(items) { it in
                    Button { keep = it.id } label: {
                        HStack {
                            Image(systemName: (keep ?? items.first?.id) == it.id ? "largecircle.fill.circle" : "circle").foregroundStyle(Theme.accent)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(it.str("name")).foregroundStyle(.primary)
                                Text("MRP \(it.num("mrp") > 0 ? Fmt.money(it.num("mrp")) : "–") · \(max(1, it.int("pcs_per_box"))) per box · stock \(Fmt.qty(it.num("stock")))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                }
            } header: { Text("Keep which one?") } footer: {
                Text("The others are archived after their bills, purchases, stock batches and schemes move to the item kept. Prices or HSN the kept item lacks are taken from the others. This cannot be undone.")
            }
        }
    }
}

/// A price-list PDF's text, read on this iPhone the way the Mac reads it.
@MainActor fileprivate func pdfText(_ data: Data) async throws -> String {
    try await PDFText.read(data).pages.joined(separator: "\n")
}
