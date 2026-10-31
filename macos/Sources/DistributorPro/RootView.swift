import SwiftUI

/// Waits for the backend, then shows the sidebar + detail window.
@MainActor struct RootView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        ZStack {
            Group {
                if !app.ready {
                    ProgressView("Opening your books…")
                } else if let err = app.serverError {
                    ServerGate(message: err)
                } else {
                    MainView()
                }
            }
            ToastOverlay()
        }
        .task { await app.start() }
    }
}

/// Shown when the backend is not running: start it from here, or from a terminal.
@MainActor struct ServerGate: View {
    @EnvironmentObject private var app: AppModel
    let message: String
    @State private var busy = false
    @State private var detail: String?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "bolt.horizontal.circle").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("Server is not running").font(.title.weight(.semibold))
            Text(detail ?? message).multilineTextAlignment(.center).frame(maxWidth: 520)
            if !Backend.shared.isBundled {
                Text("This copy is not the built app, so it needs the project's backend folder (pick it once; it is remembered). Build the real app with build_app.sh.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 520)
            }
            HStack {
                Button("Start server") {
                    Task {
                        busy = true
                        if !Backend.shared.isBundled, Backend.shared.guessFolder() == nil, Backend.shared.chooseFolder() == nil {
                            detail = "That folder does not contain src/server.js."
                            busy = false
                            return
                        }
                        if let err = await Backend.shared.start() { detail = err } else { await app.start() }
                        busy = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy)
                if !Backend.shared.isBundled { Button("Choose backend folder…") {
                    if Backend.shared.chooseFolder() == nil { detail = "That folder does not contain src/server.js." }
                } }
                Button("Try again") { Task { await app.start() } }
            }
            if busy { ProgressView().controlSize(.small) }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor struct MainView: View {
    @EnvironmentObject private var app: AppModel

    private var selection: Binding<Page?> {
        Binding(get: { app.section }, set: { if let p = $0 { app.section = p } })
    }

    var body: some View {
        NavigationView {
            sidebar
            detailArea
        }
    }

    private var sidebar: some View {
        List(selection: selection) {
            SwiftUI.Section("Sell") {
                row(.billing); row(.bills)
            }
            SwiftUI.Section("Buy & Stock") {
                row(.purchases); row(.debitNotes); row(.stock)
            }
            SwiftUI.Section("People") {
                row(.parties); row(.salesmen)
            }
            SwiftUI.Section("Accounts") {
                row(.dashboard); row(.reports)
            }
            SwiftUI.Section {
                row(.settings)
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 190, idealWidth: 210, maxWidth: 260)
        .safeAreaInset(edge: .top) {
            VStack(spacing: 6) {
                CompanyMenu()
                YearMenu()
            }
            .padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 4)
        }
    }

    private var detailArea: some View {
        // Billing stays alive while you look at other screens, so a half-made bill is never lost.
        ZStack {
            BillingView()
                .opacity(app.section == .billing ? 1 : 0)
                .allowsHitTesting(app.section == .billing)
                .accessibilityHidden(app.section != .billing)
            if app.section != .billing { detail(app.section) }
        }
        .id("\(app.companyId ?? 0)-\(app.fy)")
        .frame(minWidth: 700, maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.page)
    }

    private func row(_ p: Page) -> some View {
        Label(p.title, systemImage: p.symbol).tag(p)
    }

    @ViewBuilder
    private func detail(_ p: Page) -> some View {
        switch p {
        case .dashboard: DashboardView()
        case .purchases: PurchaseView()
        case .bills: BillsView()
        case .stock: StockView()
        case .parties: PartiesView()
        case .salesmen: SalesmenView()
        case .reports: ReportsView()
        case .settings: SettingsView()
        case .billing: EmptyView()
        case .debitNotes: DebitNotesView()
        }
    }
}

/// Financial-year switcher: April to March. Past years stay fully browsable.
@MainActor struct YearMenu: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        Menu {
            ForEach(app.yearChoices) { y in
                Button {
                    Task { await app.chooseYear(y) }
                } label: {
                    let t = y.title + (y.bookId != app.companyId && !y.label.isEmpty ? "  · own file" : "")
                    if y.bookId == app.companyId && y.label == app.fyLabel { Label(t, systemImage: "checkmark") } else { Text(t) }
                }
            }
        } label: {
            HStack {
                Image(systemName: "calendar")
                VStack(alignment: .leading, spacing: 0) {
                    Text("Financial year \(app.fyLabel)").fw(.medium).lineLimit(1)
                    Text(app.isCurrentFY ? "Current year" : "Past year · view and edit").font(.caption2).foregroundStyle(app.isCurrentFY ? Color.secondary : Color.orange)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("Switch financial year (1 April to 31 March)")
    }
}

@MainActor struct CompanyMenu: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        Menu {
            ForEach(app.companyGroups) { c in
                Button {
                    if !app.isOpenGroup(c) { Task { await app.switchCompany(c.id) } }
                } label: {
                    if app.isOpenGroup(c) { Label(c.str("name"), systemImage: "checkmark") } else { Text(c.str("name")) }
                }
            }
        } label: {
            HStack {
                Image(systemName: "building.2")
                Text(app.companyName).lineLimit(1).fw(.medium)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("Switch company")
    }
}
