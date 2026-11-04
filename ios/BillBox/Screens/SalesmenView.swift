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
                Button { newRoute = true } label: { Label("New route", systemImage: "point.topleft.down.curvedto.point.bottomright.up") }.disabled(people.isEmpty)
                Button { newSalesman = true } label: { Label("New salesman", systemImage: "person.badge.plus") }
            }
        }
        .task { await load() }
        .onChange(of: app.dataVersion) { _ in Task { await load() } }
        .onChange(of: sel) { _ in Task { await loadSelected() } }
        .onChange(of: day) { _ in Task { await loadSelected() } }
        .sheet(isPresented: $newSalesman) { SalesmanSheet { await load() } }
        .sheet(isPresented: $newRoute) { RouteSheet(people: people) }
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
    let done: () async -> Void
    @State private var name = ""
    @State private var phone = ""
    @State private var target = "0"

    var body: some View {
        FormSheet(title: "New salesman", width: 440, canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty, onSave: {
            _ = try await API.obj("POST", "/salesmen", body: ["name": name, "phone": phone, "monthly_target": target])
            await done()
        }) {
            Field("Name", text: $name)
            Field("Phone", text: $phone).keyboardType(.phonePad)
            Field("Monthly sales target (₹)", text: $target).keyboardType(.decimalPad)
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
            Field("Route name", text: $name)
            Picker("Salesman", selection: $salesman) { ForEach(people) { Text($0.str("name")).tag(String($0.id)) } }
            VStack(alignment: .leading) { Text("Visit days"); DayPicker(days: $days) }
        }
    }
}
