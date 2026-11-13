import SwiftUI

/// The day's business at a glance: today, this month or the whole year; every card and row opens the screen behind it.
@MainActor struct DashboardView: View {
    @EnvironmentObject private var app: AppModel
    @State private var d: JSON?
    @State private var period = "month"
    @State private var metric = "sales"
    @State private var pickedMonth: String?
    @State private var photoPayments = false

    private var hidden: Set<String> { app.dashboardHidden }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 12 ? "Good morning" : (h < 17 ? "Good afternoon" : "Good evening")
    }

    static func monthName(_ ym: String) -> String {
        let names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let m = Int(ym.suffix(2)) ?? 1
        return names[max(0, min(11, m - 1))]
    }

    var body: some View {
        ScrollView {
            if let x = d {
                VStack(alignment: .leading, spacing: 16) {
                    hero(x)
                    if !x.bool("is_current") {
                        Banner(text: "You are looking at a past financial year. Figures show that year only; \"today\" means its last day, \(Fmt.dmy(x.str("as_of"))). Switch year from the sidebar.", symbol: "calendar.badge.clock")
                    }
                    if !hidden.contains("alerts") { alerts(x) }
                    Picker("Period", selection: $period) {
                        Text(x.bool("is_current") ? "Today" : "Last day").tag("today"); Text("This month").tag("month"); Text("Whole year").tag("year")
                    }
                    .pickerStyle(.segmented)
                    kpis(x)
                    if !hidden.contains("charts") { monthChart(x) }
                    if !hidden.contains("daily") { dailyChart(x) }
                    lists(x)
                }
                .padding(24)
                .animation(.easeInOut(duration: 0.2), value: period)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 300)
            }
        }
        .navigationTitle("Dashboard")
        .toolbar {
            ToolbarItem { Button { Task { await load() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }.keyboardShortcut("r", modifiers: .command) }
        }
        .sheet(isPresented: $photoPayments) { PaymentPhotoSheet { await load() } }
        .onChange(of: app.dataVersion) { _ in Task { await load() } }
        .task {
            if let p = ["today", "month", "year"].first(where: { $0 == app.settings.str("dash_period") }) { period = p }
            await load()
        }
    }

    private func load() async {
        await app.guarded { d = try await API.obj("GET", "/reports/dashboard") }
    }

    private func go(_ p: Page) { app.section = p }

    // MARK: header

    private func hero(_ x: JSON) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(greeting).font(.subheadline).opacity(0.85)
                    Text(app.companyName).font(.title.weight(.bold)).lineLimit(2).minimumScaleFactor(0.7)
                    Text("FY \(x.str("fy")) · \(Fmt.dmy(x.str("as_of")))").font(.caption).opacity(0.85)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(x.bool("is_current") ? "Sales today" : "Sales on the last day").font(.caption).opacity(0.85)
                    Text(Fmt.money(x.num("today_sales"))).font(.system(.title2, design: .rounded).weight(.bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                    Text("\(x.int("today_bills")) bills · collected \(Fmt.money(x.num("today_collections")))").font(.caption).opacity(0.85).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    quick("New bill", "cart.badge.plus") { go(.billing) }
                    quick("Payments from photo", "camera.viewfinder") { photoPayments = true }
                    quick("Purchase", "shippingbox") { go(.purchases) }
                    quick("All bills", "doc.text") { go(.bills) }
                    quick("Stock", "archivebox") { go(.stock) }
                    quick("Parties", "person.2") { go(.parties) }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(LinearGradient(colors: [Theme.accent, Theme.accent.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 16))
    }

    private func quick(_ title: String, _ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.callout.weight(.medium)).padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.white.opacity(0.2), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: alerts

    private func alerts(_ x: JSON) -> some View {
        let chips: [(String, String, Color, () -> Void)] = [
            x.int("unprinted_bills") > 0 ? ("\(x.int("unprinted_bills")) bills to print", "printer", Color.blue, { app.openUnprinted = true; go(.bills) }) : nil,
            x.int("low_stock_count") > 0 ? ("\(x.int("low_stock_count")) items low on stock", "exclamationmark.triangle", Theme.negative, { go(.stock) }) : nil,
            x.int("expiring_30d") > 0 ? ("\(x.int("expiring_30d")) batches expire within \(x.has("expiry_days") ? x.int("expiry_days") : 30) days", "clock.badge.exclamationmark", Theme.warning, { go(.reports) }) : nil,
            x.int("expired_stock") > 0 ? ("\(x.int("expired_stock")) expired batches in stock", "xmark.octagon", Theme.negative, { go(.reports) }) : nil,
        ].compactMap { $0 }
        return Group {
            if !chips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(chips.indices, id: \.self) { i in
                            let c = chips[i]
                            Button(action: c.3) {
                                Label(c.0, systemImage: c.1).font(.callout).padding(.horizontal, 12).padding(.vertical, 7)
                                    .foregroundStyle(c.2).background(c.2.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: figures

    private func pick(_ x: JSON, today: Double, month: Double, year: Double) -> Double { period == "today" ? today : (period == "month" ? month : year) }
    private var periodWord: String { period == "today" ? "today" : (period == "month" ? "this month" : "this year") }

    private func kpis(_ x: JSON) -> some View {
        let todayPurchases = x.list("series").last { $0.str("date") == x.str("as_of") }?.num("purchases") ?? 0
        let sales = pick(x, today: x.num("today_sales"), month: x.num("month_sales"), year: x.num("fy_sales"))
        let bills = pick(x, today: Double(x.int("today_bills")), month: Double(x.int("month_bills")), year: Double(x.int("fy_bills")))
        let profit = pick(x, today: x.num("today_profit"), month: x.num("month_profit"), year: x.num("fy_profit"))
        let purchases = pick(x, today: todayPurchases, month: x.num("month_purchases"), year: x.num("fy_purchases"))
        let collected = pick(x, today: x.num("today_collections"), month: x.num("month_collections"), year: x.num("fy_collections"))
        let gst = period == "year" ? x.num("fy_gst_liability") : x.num("gst_liability")
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
            Kpi(title: "Sales", symbol: "indianrupeesign.circle", value: Fmt.money(sales), note: "\(Int(bills)) bills \(periodWord)", tint: .teal) { go(.bills) }
            Kpi(title: "Profit", symbol: "chart.line.uptrend.xyaxis", value: Fmt.money(profit),
                note: period == "year" ? "Margin \(Fmt.qty(x.num("fy_margin_pct")))%" : "Before expenses, \(periodWord)", tint: profit >= 0 ? Theme.positive : Theme.negative) { go(.reports) }
            Kpi(title: "Collections", symbol: "banknote", value: Fmt.money(collected), note: "Payments received \(periodWord)", tint: Theme.positive) { go(.parties) }
            Kpi(title: "Purchases", symbol: "shippingbox", value: Fmt.money(purchases), note: "Supplier bills \(periodWord)", tint: Theme.warning) { go(.purchases) }
            Kpi(title: "To receive", symbol: "person.crop.circle.badge.exclamationmark", value: Fmt.money(x.num("receivable")),
                note: "You owe suppliers \(Fmt.money(x.num("payable")))", tint: Theme.warning) { go(.parties) }
            Kpi(title: period == "year" ? "GST for the year" : "GST this month", symbol: "building.columns", value: Fmt.money(abs(gst)),
                note: gst >= 0 ? "To pay (output less input)" : "Credit carried forward", tint: gst >= 0 ? Theme.negative : Theme.positive) { go(.reports) }
        }
    }

    // MARK: charts

    private func monthChart(_ x: JSON) -> some View {
        let rows = x.list("monthly")
        let key = metric == "sales" ? "sales" : (metric == "purchases" ? "purchases" : "profit")
        let color: Color = metric == "sales" ? .teal : (metric == "purchases" ? Theme.warning : Theme.positive)
        let sel = pickedMonth ?? x.str("month")
        let chosen = rows.first { $0.str("month") == sel }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Month by month").font(.headline)
                Spacer()
                Picker("Show", selection: $metric) { Text("Sales").tag("sales"); Text("Purchases").tag("purchases"); Text("Profit").tag("profit") }
                    .pickerStyle(.segmented).frame(maxWidth: 270)
            }
            MonthBars(values: rows.map { (id: $0.str("month"), label: Self.monthName($0.str("month")), value: $0.num(key)) }, color: color, selected: sel) { pickedMonth = $0 }
                .frame(height: 200)
                .animation(.easeOut(duration: 0.25), value: metric)
            if let c = chosen {
                HStack(spacing: 14) {
                    Text(Self.monthName(c.str("month")) + " " + String(c.str("month").prefix(4))).fw(.semibold)
                    Text("Sales \(Fmt.money(c.num("sales")))").foregroundStyle(.teal)
                    Text("Purchases \(Fmt.money(c.num("purchases")))").foregroundStyle(Theme.warning)
                    Text("Profit \(Fmt.money(c.num("profit")))").foregroundStyle(c.num("profit") >= 0 ? Theme.positive : Theme.negative)
                }
                .font(.caption).mono().lineLimit(1).minimumScaleFactor(0.6)
            }
        }
        .padding(14)
        .card(14)
    }

    private func dailyChart(_ x: JSON) -> some View {
        let data = x.list("series").map { BarPair(id: $0.str("date"), label: String(Fmt.dmy($0.str("date")).prefix(5)), a: $0.num("sales"), b: $0.num("purchases")) }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Last 14 days").font(.headline)
                Spacer()
                HStack(spacing: 4) { Circle().fill(Color.teal).frame(width: 8, height: 8); Text("Sales").font(.caption).foregroundStyle(.secondary) }
                HStack(spacing: 4) { Circle().fill(Theme.warning).frame(width: 8, height: 8); Text("Purchases").font(.caption).foregroundStyle(.secondary) }
            }
            BarChartView(data: data).frame(height: 160)
        }
        .padding(14)
        .card(14)
    }

    // MARK: lists

    private func lists(_ x: JSON) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 12)], alignment: .leading, spacing: 12) {
            if !hidden.contains("items") {
                ListCard(title: "Best sellers this month", symbol: "star", rows: x.list("top_items").map { ($0.str("name"), Fmt.money($0.num("amount"))) }) { _ in go(.stock) }
            }
            if !hidden.contains("dues") {
                ListCard(title: "Top dues", symbol: "person.crop.circle.badge.exclamationmark", rows: x.list("top_dues").map { ($0.str("name"), Fmt.money($0.num("balance"))) }) { _ in go(.parties) }
            }
            if !hidden.contains("low") {
                ListCard(title: "Low stock", symbol: "exclamationmark.triangle", rows: x.list("low_stock").prefix(8).map { ($0.str("name"), Fmt.boxPcs($0.int("stock"), max(1, $0.int("pcs_per_box")))) }) { _ in go(.stock) }
            }
            if !hidden.contains("recent") {
                let bills = x.list("recent_bills")
                ListCard(title: "Latest bills", symbol: "doc.text", rows: bills.map { ("\($0.str("invoice_no")) · \($0.str("party"))" + ($0.bool("printed") ? "" : " · not printed"), Fmt.money($0.num("total"))) }) { i in
                    app.pendingEdit = ("INVOICE", bills[i].int("id"))
                    go(.billing)
                }
            }
        }
    }
}

/// A figure card that opens the screen behind it.
@MainActor struct Kpi: View {
    let title: String
    let symbol: String
    let value: String
    let note: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: symbol).foregroundStyle(tint).frame(width: 30, height: 30).background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                Text(value).font(.system(.title2, design: .rounded).weight(.semibold)).monospacedDigit().foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.5)
                // two lines kept for every note, so all cards are the same height
                Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(2).frame(minHeight: 30, alignment: .topLeading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(title)")
    }
}

/// A short list; tapping a row opens the screen behind it.
@MainActor struct ListCard: View {
    let title: String
    let symbol: String
    let rows: [(String, String)]
    let open: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.headline)
            if rows.isEmpty { Text("Nothing to show.").foregroundStyle(.secondary).font(.callout) }
            ForEach(rows.indices, id: \.self) { i in
                Button { open(i) } label: {
                    HStack {
                        Text(rows[i].0).lineLimit(1)
                        Spacer()
                        Text(rows[i].1).mono().fw(.medium)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if i < rows.count - 1 { Divider() }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(14)
    }
}

/// Twelve bars, April to March; tap one to read that month. Negative values (a loss) are drawn in red from the base line.
@MainActor struct MonthBars: View {
    let values: [(id: String, label: String, value: Double)]
    let color: Color
    let selected: String
    let pick: (String) -> Void

    var body: some View {
        let top = max(1, values.map { abs($0.value) }.max() ?? 1)
        VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(values.indices, id: \.self) { i in
                    let v = values[i]
                    let on = v.id == selected
                    VStack(spacing: 4) {
                        if on { Text(Fmt.money(v.value)).font(.system(size: 9).weight(.semibold)).lineLimit(1).minimumScaleFactor(0.5).fixedSize() }
                        GeometryReader { g in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(v.value < 0 ? Theme.negative : color)
                                .opacity(on ? 1 : 0.45)
                                .frame(height: max(v.value != 0 ? 3 : 0, g.size.height * CGFloat(abs(v.value) / top)))
                                .frame(maxHeight: .infinity, alignment: .bottom)
                        }
                        Text(v.label).font(.system(size: 10)).foregroundStyle(on ? .primary : .secondary).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { pick(v.id) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(v.label): \(Fmt.money(v.value))")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }
}
