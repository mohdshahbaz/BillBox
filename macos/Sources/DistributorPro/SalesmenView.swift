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

    var body: some View {
        HSplitView {
            List(people, selection: $sel) { s in
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.str("name")).fw(.medium)
                    if !s.str("phone").isEmpty { Text(s.str("phone")).font(.caption).foregroundStyle(.secondary) }
                }
                .tag(s.id)
            }
            .listStyle(.inset)
            .frame(minWidth: 200, idealWidth: 230, maxWidth: 300)

            detail
        }
        .navigationTitle("Salesmen and routes")
        .toolbar {
            ToolbarItemGroup {
                Button { newRoute = true } label: { Label("New route", systemImage: "point.topleft.down.curvedto.point.bottomright.up") }.disabled(people.isEmpty)
                Button { newSalesman = true } label: { Label("New salesman", systemImage: "person.badge.plus") }
            }
        }
        .task { await load() }
        .onChange(of: sel) { _ in Task { await loadSelected() } }
        .onChange(of: day) { _ in Task { await loadSelected() } }
        .sheet(isPresented: $newSalesman) { SalesmanSheet { await load() } }
        .sheet(isPresented: $newRoute) { RouteSheet(people: people) }
    }

    private var detail: some View {
        ScrollView {
            if let p = perf {
                let ach: Double? = p.has("achievement_pct") ? p.num("achievement_pct") : nil
                VStack(alignment: .leading, spacing: 16) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                        StatCard(title: "Target for \(p.str("month"))", value: Fmt.money(p, "target"))
                        StatCard(title: "Sales (\(p.int("invoices")) bills)", value: Fmt.money(p, "sales"), tint: .teal)
                        StatCard(title: "Achievement", value: ach.map { "\(Fmt.qty($0))%" } ?? "No target set", tint: (ach ?? 0) >= 100 ? .green : .orange)
                        StatCard(title: "Collections this month", value: Fmt.money(p, "collections"), tint: .green)
                    }
                    if let ach { ProgressView(value: min(max(ach / 100, 0), 1)).tint(.teal) }
                    let d = p.obj("day")
                    if p.has("day") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Today").font(.headline)
                            let modes = d.list("collected_by_mode")
                            Text("\(d.int("bills")) bills · \(Fmt.money(d, "sales")) sold · \(Fmt.money(d, "credit_given")) given on credit · collected: "
                                 + (modes.isEmpty ? "nothing yet" : modes.map { "\($0.str("mode")) \(Fmt.money($0, "amount"))" }.joined(separator: ", ")))
                        }
                    }
                    HStack {
                        Text("Beat plan").font(.headline)
                        Picker("Day", selection: $day) { ForEach(0..<7, id: \.self) { Text(String(dayNames[$0].prefix(3))).tag($0) } }
                            .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 420)
                    }
                    let outlets = beat?.list("outlets") ?? []
                    if outlets.isEmpty {
                        Text("No outlets on \(dayNames[day]). Create a route for this day and assign parties to it.").foregroundStyle(.secondary)
                    } else {
                        DataGrid(outlets, layoutKey: "beat") {
                            GridColumn("Outlet", id: "outlet", min: 160, ideal: 260) { (o: JSON) in Text(o.str("name")) }
                            GridColumn("Route", id: "route", min: 100, ideal: 160) { (o: JSON) in Text(o.str("route_name")) }
                            GridColumn("Last order", id: "last", min: 90, ideal: 110) { (o: JSON) in Text(o.has("last_order") ? Fmt.dmy(o.str("last_order")) : "Never") }
                            GridColumn("Outstanding to collect", id: "outstanding", min: 140, ideal: 170, align: .trailing) { (o: JSON) in
                                Text(Fmt.money(o, "outstanding")).mono().fw(.semibold)
                                    .foregroundStyle(o.num("outstanding") > 0 ? Color.orange : Color.primary)
                            }
                        }
                        .frame(height: min(CGFloat(outlets.count) * 28 + 40, 420))
                        Text("To collect on this beat: \(Fmt.money(beat?.num("total_outstanding") ?? 0))").foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            } else {
                EmptyState(title: "No salesman selected", symbol: "person.fill", message: "Add a salesman to start tracking targets, beats and collections.")
                    .frame(maxWidth: .infinity, minHeight: 300)
            }
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
    let done: () async -> Void
    @State private var name = ""
    @State private var phone = ""
    @State private var target = "0"

    var body: some View {
        FormSheet(title: "New salesman", width: 440, canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty, onSave: {
            _ = try await API.obj("POST", "/salesmen", body: ["name": name, "phone": phone, "monthly_target": target])
            await done()
        }) {
            TextField("Name", text: $name)
            TextField("Phone", text: $phone)
            TextField("Monthly sales target (₹)", text: $target)
        }
    }
}

@MainActor struct RouteSheet: View {
    @EnvironmentObject private var app: AppModel
    let people: [JSON]
    @State private var name = ""
    @State private var salesman = ""
    @State private var days = "1"

    var body: some View {
        FormSheet(title: "New route", width: 440, canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty, onSave: {
            _ = try await API.obj("POST", "/routes", body: ["name": name, "salesman_id": salesman.isEmpty ? (people.first.map { String($0.id) } ?? "") : salesman, "days": days])
            app.notify("Route added.")
        }) {
            TextField("Route name", text: $name)
            Picker("Salesman", selection: $salesman) { ForEach(people) { Text($0.str("name")).tag(String($0.id)) } }
            Labeled("Visit days") { DayPicker(days: $days) }
        }
    }
}
