import SwiftUI

/// Opens the books, then shows the tabs. Billing, All Bills, Stock and Parties have their own tab; the rest are under More.
@MainActor struct RootView: View {
    @EnvironmentObject private var app: AppModel
    @ObservedObject private var wa = WhatsAppWeb.shared
    @State private var shownJob: PrintJob?
    @State private var crashReport: String? = CrashCatcher.pendingReport()

    var body: some View {
        ZStack {
            Group {
                if !app.ready {
                    ProgressView("Opening your books…")
                } else if let err = app.startError {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle").font(.system(size: 40)).foregroundStyle(.orange)
                        Text("The books could not be opened").font(.title3.weight(.semibold))
                        Text(err).multilineTextAlignment(.center).foregroundStyle(.secondary)
                        Button("Try again") { Task { await app.start() } }.buttonStyle(.borderedProminent)
                    }
                    .padding(30)
                } else {
                    MainTabs()
                }
            }
            ToastOverlay()
        }
        .task { await app.start(); await SimSelfTest.runIfAsked(app) }
        // A print preview opens only once the bill / voucher sheet has closed (the Mac waits for the popup in the same way).
        .onChange(of: app.printJob?.id) { _ in
            guard let job = app.printJob else { return }
            Task {
                await pause(ms: 650)
                app.printJob = nil
                shownJob = job
            }
        }
        .sheet(item: $shownJob) { job in PrintPreviewSheet(job: job).environmentObject(app) }
        .sheet(isPresented: $wa.showing) { WhatsAppPageSheet() }
        .sheet(isPresented: Binding(get: { crashReport != nil }, set: { if !$0 { crashReport = nil; CrashCatcher.clearReport() } })) {
            CrashReportSheet(report: crashReport ?? "") { crashReport = nil; CrashCatcher.clearReport() }
        }
    }
}

@MainActor struct MainTabs: View {
    @EnvironmentObject private var app: AppModel
    private var tab: Page { app.tab }
    private var morePath: [MoreRoute] { app.morePath }

    static let tabs: [Page] = [.billing, .bills, .stock, .parties]
    static let more: [Page] = [.purchases, .debitNotes, .salesmen, .dashboard, .reports, .settings]

    var body: some View {
        TabView(selection: tabBinding) {
            NavigationStack { BillingView().companyYearToolbar() }
                .tabItem { Label(Page.billing.title, systemImage: Page.billing.symbol) }.tag(Page.billing)
            NavigationStack { BillsView().companyYearToolbar() }
                .tabItem { Label(Page.bills.title, systemImage: Page.bills.symbol) }.tag(Page.bills)
            NavigationStack { StockView().companyYearToolbar() }
                .tabItem { Label(Page.stock.title, systemImage: Page.stock.symbol) }.tag(Page.stock)
            NavigationStack { PartiesView().companyYearToolbar() }
                .tabItem { Label(Page.parties.title, systemImage: Page.parties.symbol) }.tag(Page.parties)
            NavigationStack(path: $app.morePath) {
                List {
                    ForEach(MainTabs.more) { p in
                        NavigationLink(value: MoreRoute.page(p)) { Label(p.title, systemImage: p.symbol) }
                    }
                }
                .navigationTitle("More")
                .companyYearToolbar()
                .navigationDestination(for: MoreRoute.self) { r in
                    switch r {
                    case .page(let p): screen(p).companyYearToolbar()
                    case .settings(let k): SettingsView.page(k)
                    }
                }
            }
            .tabItem { Label("More", systemImage: "ellipsis.circle") }.tag(Page.dashboard)
        }
        .id("\(app.companyId ?? 0)-\(app.fy)")
        .onChange(of: app.section) { s in show(s) }
        .onAppear { if app.section != .billing { show(app.section) } }
        .background(shortcuts)
    }

    /// The tab bar's selection; the More tab stands for every page inside it.
    private var tabBinding: Binding<Page> {
        Binding(get: { MainTabs.tabs.contains(tab) ? tab : .dashboard },
                set: { t in
                    app.tab = t
                    if MainTabs.tabs.contains(t) { app.section = t } else { app.section = lastPage ?? .dashboard }
                })
    }

    /// The screen open in More (the Settings pages count as Settings).
    private var lastPage: Page? {
        for r in morePath.reversed() {
            switch r { case .page(let p): return p; case .settings: return .settings }
        }
        return nil
    }

    private func show(_ s: Page) {
        if MainTabs.tabs.contains(s) {
            app.tab = s
        } else {
            app.tab = .dashboard
            if lastPage != s { app.morePath = [.page(s)] }
        }
    }

    @ViewBuilder private func screen(_ p: Page) -> some View {
        switch p {
        case .dashboard: DashboardView()
        case .purchases: PurchaseView()
        case .salesmen: SalesmenView()
        case .reports: ReportsView()
        case .settings: SettingsView()
        case .billing: BillingView()
        case .bills: BillsView()
        case .stock: StockView()
        case .parties: PartiesView()
        case .debitNotes: DebitNotesView()
        }
    }

    /// ⌘1 … ⌘9 go to the screens in the Mac's order (Dashboard, Billing, Purchases, All Bills, Stock, Parties, Salesmen, Books & GST, Settings); ⌘0 Debit Notes.
    private var shortcuts: some View {
        ZStack {
            ForEach(Array(Page.allCases.enumerated()), id: \.element) { i, p in
                Button(p.title) { app.section = p; show(p) }
                    .keyboardShortcut(KeyEquivalent(Character(i < 9 ? "\(i + 1)" : "0")), modifiers: .command)
            }
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Company and financial-year switchers in the navigation bar of every screen.
    @MainActor func companyYearToolbar() -> some View {
        // an opaque bar: when the keyboard pushes the screen up, nothing slides underneath the company name
        self.toolbar { ToolbarItem(placement: .navigationBarLeading) { CompanyYearMenu() } }
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

/// Switch company and financial year (1 April to 31 March). Past years stay fully browsable.
@MainActor struct CompanyYearMenu: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        Menu {
            Section("Company") {
                ForEach(app.companyGroups) { c in
                    Button {
                        if !app.isOpenGroup(c) { Task { await app.switchCompany(c.id) } }
                    } label: {
                        if app.isOpenGroup(c) { Label(c.str("name"), systemImage: "checkmark") } else { Text(c.str("name")) }
                    }
                }
            }
            Section("Financial year \(app.fyLabel) · " + (app.isCurrentFY ? "Current year" : "Past year · view and edit")) {
                ForEach(app.yearChoices) { y in
                    Button {
                        Task { await app.chooseYear(y) }
                    } label: {
                        let t = y.title + (y.bookId != app.companyId && !y.label.isEmpty ? "  · own file" : "")
                        if y.bookId == app.companyId && y.label == app.fyLabel { Label(t, systemImage: "checkmark") } else { Text(t) }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "building.2")
                VStack(alignment: .leading, spacing: 0) {
                    Text(app.companyName).font(.caption.weight(.semibold)).lineLimit(1)
                    Text("FY \(app.fyLabel) · " + (app.isCurrentFY ? "Current year" : "Past year · view and edit")).font(.caption2)
                        .foregroundStyle(app.isCurrentFY ? Color.secondary : Color.orange).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: 180, alignment: .leading)
        }
        .accessibilityLabel("Company \(app.companyName), financial year \(app.fyLabel)\(app.isCurrentFY ? "" : ", past year, view and edit")")
        .accessibilityHint("Switch company or financial year")
    }
}
