import SwiftUI

@MainActor struct SalesmenView: View {
    @EnvironmentObject private var app: AppModel
    @State private var people: [JSON] = []
    @State private var sel: Int?
    @State private var perf: JSON?
    @State private var beat: JSON?
    @State private var day = Calendar.current.component(.weekday, from: Date()) - 1
    @State private var newSalesman = false
    @State private var newRoute = false
    @State private var showRoutes = false
    @State private var editing: JSON?
    @State private var merging: JSON?
    @State private var deleting: JSON?
    private var current: JSON? { people.first { $0.id == sel } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !people.isEmpty {
                    Picker("Salesman", selection: Binding(get: { sel ?? 0 }, set: { sel = $0 })) {
                        ForEach(people) { s in Text(s.str("name") + (s.str("phone").isEmpty ? "" : " · \(s.str("phone"))")).tag(s.id) }
                    }
                    .pickerStyle(.menu)
                }
                detail
            }
            .padding(12)
        }
        .background(Theme.page)
        .navigationTitle("Salesmen and routes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { showRoutes = true } label: { Label("Routes", systemImage: "list.bullet") }
                Button { newRoute = true } label: { Label("New route", systemImage: "point.topleft.down.curvedto.point.bottomright.up") }.disabled(people.isEmpty)
                Button { newSalesman = true } label: { Label("New salesman", systemImage: "person.badge.plus") }
                Menu {
                    Button { editing = current } label: { Label("Edit salesman…", systemImage: "pencil") }
                    Button { merging = current } label: { Label("Merge into another…", systemImage: "arrow.triangle.merge") }.disabled(people.count < 2)
                    Button(role: .destructive) { deleting = current } label: { Label("Delete salesman…", systemImage: "trash") }
                } label: { Label("Salesman", systemImage: "ellipsis.circle") }
                .disabled(current == nil)
            }
        }
        .task { await load() }
        .onChange(of: app.dataVersion) { _ in Task { await load() } }
        .onChange(of: sel) { _ in Task { await loadSelected() } }
        .onChange(of: day) { _ in Task { await loadSelected() } }
        .sheet(isPresented: $newSalesman) { SalesmanSheet { await load() } }
        .sheet(item: $editing) { s in SalesmanSheet(existing: s) { await load() } }
        .sheet(item: $merging) { s in MergeSalesmanSheet(from: s, people: people) { into in sel = into; await load() } }
        .confirmationDialog("Delete \(deleting?.str("name") ?? "")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                guard let d = deleting else { return }
                Task {
                    await app.guarded {
                        _ = try await API.obj("DELETE", "/salesmen/\(d.id)")
                        if sel == d.id { sel = nil }
                        app.notify("\(d.str("name")) deleted.")
                        await load()
                    }
                }
            }
        } message: {
            Text("Their routes are left without a salesman. Bills and receipts keep the name. To move their bills to someone else, use Merge instead.")
        }
        .sheet(isPresented: $newRoute) { RouteSheet(people: people) { await loadSelected() } }
        .sheet(isPresented: $showRoutes) { RoutesSheet(people: people) { await loadSelected() } }
    }

    @ViewBuilder private var detail: some View {
        if let p = perf {
            let ach: Double? = p.has("achievement_pct") ? p.num("achievement_pct") : nil
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                StatCard(title: "Target for \(p.str("month"))", value: Fmt.money(p, "target"))
                StatCard(title: "Sales (\(p.int("invoices")) bills)", value: Fmt.money(p, "sales"), tint: .teal)
                StatCard(title: "Achievement", value: ach.map { "\(Fmt.qty($0))%" } ?? "No target set", tint: (ach ?? 0) >= 100 ? .green : .orange)
                StatCard(title: "Collections this month", value: Fmt.money(p, "collections"), tint: .green)
            }
            if let ach { ProgressView(value: min(max(ach / 100, 0), 1)).tint(.teal).accessibilityLabel("Achievement \(Fmt.qty(ach)) percent") }
            let d = p.obj("day")
            if p.has("day") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today").font(.headline)
                    let modes = d.list("collected_by_mode")
                    Text("\(d.int("bills")) bills · \(Fmt.money(d, "sales")) sold · \(Fmt.money(d, "credit_given")) given on credit · collected: "
                         + (modes.isEmpty ? "nothing yet" : modes.map { "\($0.str("mode")) \(Fmt.money($0, "amount"))" }.joined(separator: ", ")))
                        .font(.callout)
                }
            }
            Text("Beat plan").font(.headline)
            Picker("Day", selection: $day) { ForEach(0..<7, id: \.self) { Text(String(dayNames[$0].prefix(3))).tag($0) } }
                .pickerStyle(.segmented).labelsHidden()
            let outlets = beat?.list("outlets") ?? []
            if outlets.isEmpty {
                Text("No outlets on \(dayNames[day]). Create a route for this day and assign parties to it.").foregroundStyle(.secondary)
            } else {
                DataGrid(outlets, layoutKey: "beat") {
                    GridColumn("Outlet", id: "outlet", min: 150, ideal: 220) { (o: JSON) in Text(o.str("name")).lineLimit(2) }
                    GridColumn("Route", id: "route", min: 100, ideal: 150) { (o: JSON) in Text(o.str("route_name")) }
                    GridColumn("Last order", id: "last", min: 90, ideal: 110) { (o: JSON) in Text(o.has("last_order") ? Fmt.dmy(o.str("last_order")) : "Never") }
                    GridColumn("Outstanding to collect", id: "outstanding", min: 140, ideal: 170, align: .trailing) { (o: JSON) in
                        Text(Fmt.money(o, "outstanding")).monospacedDigit().fontWeight(.semibold)
                            .foregroundStyle(o.num("outstanding") > 0 ? Color.orange : Color.primary)
                    }
                }
                .frame(height: min(CGFloat(outlets.count) * 40 + 44, 440))
                Text("To collect on this beat: \(Fmt.money(beat?.num("total_outstanding") ?? 0))").foregroundStyle(.secondary)
            }
        } else {
            EmptyState(title: "No salesman selected", symbol: "person.fill", message: "Add a salesman to start tracking targets, beats and collections.")
                .frame(maxWidth: .infinity, minHeight: 300)
        }
    }

    private func load() async {
        await app.guarded {
            people = try await API.list("/salesmen")
            if sel == nil { sel = people.first?.id }
            await loadSelected()
        }
    }

    private func loadSelected() async {
        guard let sel else { perf = nil; beat = nil; return }
        await app.guarded {
            async let p = API.obj("GET", "/salesmen/\(sel)/performance")
            async let b = API.obj("GET", "/salesmen/\(sel)/beat", query: ["day": day])
            perf = try await p
            beat = try await b
        }
    }
}

@MainActor struct SalesmanSheet: View {
    @EnvironmentObject private var app: AppModel
    var existing: JSON? = nil
    let done: () async -> Void
    @State private var name = ""
    @State private var phone = ""
    @State private var target = "0"

    var body: some View {
        FormSheet(title: existing == nil ? "New salesman" : "Edit salesman", width: 440, canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty, onSave: {
            if let e = existing {
                _ = try await API.obj("PUT", "/salesmen/\(e.id)", body: ["name": name.trimmingCharacters(in: .whitespaces), "phone": phone, "monthly_target": target, "active": true])
            } else {
                _ = try await API.obj("POST", "/salesmen", body: ["name": name, "phone": phone, "monthly_target": target])
            }
            await done()
        }) {
            Field("Name", text: $name)
            Field("Phone", text: $phone).keyboardType(.phonePad)
            Field("Monthly sales target (₹)", text: $target).keyboardType(.decimalPad)
        }
        .onAppear {
            if let e = existing { name = e.str("name"); phone = e.str("phone"); target = Fmt.qty(e.num("monthly_target")) }
        }
    }
}

/// Merge: one salesman's bills, receipts and routes move to the one chosen here, and the first leaves the list.
@MainActor struct MergeSalesmanSheet: View {
    @EnvironmentObject private var app: AppModel
    let from: JSON
    let people: [JSON]
    let done: (Int) async -> Void
    @State private var into = ""

    var body: some View {
        FormSheet(title: "Merge \(from.str("name"))", saveLabel: "Merge", width: 460, canSave: !into.isEmpty, onSave: {
            let r = try await API.obj("POST", "/salesmen/\(from.id)/merge", body: ["into": into])
            let m = r.obj("moved")
            app.notify("Merged: \(m.int("invoices")) bills, \(m.int("receipts")) receipts and \(m.int("routes")) routes moved.")
            await done(Int(into) ?? 0)
        }) {
            Picker("Keep", selection: $into) {
                Text("Choose…").tag("")
                ForEach(people.filter { $0.id != from.id }) { Text($0.str("name")).tag(String($0.id)) }
            }
            Text("All of \(from.str("name"))'s bills, receipts and routes move to the salesman you keep; \(from.str("name")) is then removed.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// New route, or edit one (`existing`): name, salesman, visit days (PUT /routes/:id). Its outlets stay on it.
@MainActor struct RouteSheet: View {
    @EnvironmentObject private var app: AppModel
    let people: [JSON]
    var existing: JSON? = nil
    var done: () async -> Void = {}
    @State private var name = ""
    @State private var salesman = ""
    @State private var days = "1"
    @State private var loaded = false

    var body: some View {
        FormSheet(title: existing == nil ? "New route" : "Edit route", width: 440, canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty, onSave: {
            let body: [String: Any?] = ["name": name.trimmingCharacters(in: .whitespaces), "salesman_id": salesman, "days": days]
            if let e = existing {
                _ = try await API.obj("PUT", "/routes/\(e.id)", body: body)
                app.notify("Route saved.")
            } else {
                _ = try await API.obj("POST", "/routes", body: body)
                app.notify("Route added.")
            }
            await done()
        }) {
            Field("Route name", text: $name)
            Picker("Salesman", selection: $salesman) {
                Text("Not assigned").tag("")
                ForEach(people) { Text($0.str("name")).tag(String($0.id)) }
            }
            VStack(alignment: .leading) { Text("Visit days"); DayPicker(days: $days) }
            if existing != nil {
                Text("A route's name lists its places, separated by commas (e.g. Qazipara, Mandi, Mandawar Road): Parties › Assign routes uses them. Its outlets stay on it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let e = existing {
                name = e.str("name")
                salesman = e.has("salesman_id") ? String(e.int("salesman_id")) : ""
                days = e.str("days").isEmpty ? (e.has("day_of_week") ? String(e.int("day_of_week")) : "") : e.str("days")
            } else {
                salesman = people.first.map { String($0.id) } ?? ""
            }
        }
    }
}

/// Every route: its salesman, visit days and outlets, with Edit and Delete.
@MainActor struct RoutesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppModel
    let people: [JSON]
    let done: () async -> Void
    @State private var routes: [JSON]? = nil
    @State private var editing: JSON?
    @State private var deleting: JSON?

    private func detail(_ r: JSON) -> String {
        let days = dayList(r.str("days"))
        let d = !days.isEmpty ? days : (r.has("day_of_week") ? String(dayNames[min(6, max(0, r.int("day_of_week")))].prefix(3)) : "no visit day")
        let sm = r.str("salesman_name").isEmpty ? "no salesman" : r.str("salesman_name")
        return "\(sm) · \(d) · \(r.int("outlets")) outlet\(r.int("outlets") == 1 ? "" : "s")"
    }

    var body: some View {
        NavigationStack {
            list
                .navigationTitle("Routes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .task { await load() }
        .sheet(item: $editing) { r in RouteSheet(people: people, existing: r) { await load(); await done() } }
        .confirmationDialog("Delete \(deleting?.str("name") ?? "")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                guard let d = deleting else { return }
                Task {
                    await app.guarded {
                        _ = try await API.obj("DELETE", "/routes/\(d.id)")
                        app.notify("\(d.str("name")) deleted.")
                        await load(); await done()
                    }
                }
            }
        } message: {
            Text("Its outlets stay: those on other routes too keep them, the others are left without a route.")
        }
    }

    @ViewBuilder private var list: some View {
        if let routes {
            if routes.isEmpty {
                Text("No routes yet. Add one with New route.").foregroundStyle(.secondary)
            } else {
                List(routes) { r in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.str("name")).fw(.medium)
                            Text(detail(r)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Edit") { editing = r }.buttonStyle(.borderless)
                        Button(role: .destructive) { deleting = r } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                            .accessibilityLabel("Delete \(r.str("name"))")
                    }
                }
            }
        } else {
            ProgressView()
        }
    }

    private func load() async {
        await app.guarded { routes = try await API.list("/routes") }
    }
}
