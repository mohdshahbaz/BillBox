import SwiftUI

enum Page: String, CaseIterable, Identifiable, Hashable {
    case dashboard, billing, purchases, bills, stock, parties, salesmen, reports, settings, debitNotes
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .billing: return "Billing"
        case .purchases: return "Purchases"
        case .bills: return "All Bills"
        case .stock: return "Stock"
        case .parties: return "Parties"
        case .salesmen: return "Salesmen"
        case .reports: return "Books & GST"
        case .settings: return "Settings"
        case .debitNotes: return "Debit Notes"
        }
    }
    var symbol: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.67percent"
        case .billing: return "cart"
        case .purchases: return "shippingbox"
        case .bills: return "doc.text"
        case .stock: return "archivebox"
        case .parties: return "person.2"
        case .salesmen: return "figure.walk"
        case .reports: return "books.vertical"
        case .settings: return "gearshape"
        case .debitNotes: return "arrow.uturn.backward.square"
        }
    }
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isError: Bool
}

/// App-wide state: which company is open, which financial year is being viewed, its settings, navigation and the toast banner.
@MainActor
final class AppModel: ObservableObject {
    @Published var companies: [JSON] = []
    @Published var companyId: Int?
    @Published var settings = JSON()
    @Published var ready = false
    @Published var serverError: String?
    @Published var section: Page = .billing
    @Published var toast: Toast?
    @Published var printJob: PrintJob?
    /// Set by "Edit" in All Bills: the target screen opens that bill.
    @Published var pendingEdit: (type: String, id: Int)?

    // Financial year (1 April - 31 March). Every list, report and the dashboard show only the selected year.
    @Published var fy: String = "" { didSet { API.fy = fy.isEmpty ? nil : fy } }
    @Published var fyYears: [JSON] = []

    var company: JSON? { companies.first { $0.id == companyId } }
    var companyName: String { company.map { $0.str("name") } ?? "BillBox" }
    /// Settings › Billing: what a new bill starts with.
    var defaultPayMode: String { ["CASH", "UPI", "CARD", "CREDIT"].contains(settings.str("bill_pay_mode")) ? settings.str("bill_pay_mode") : "CREDIT" }
    var defaultSaleType: String { settings.str("bill_sale_type") == "VAN" ? "VAN" : "COUNTER" }
    /// Settings › Dashboard: sections switched off ("charts,daily,dues,...").
    var dashboardHidden: Set<String> { Set(settings.str("dash_hide").split(separator: ",").map(String.init)) }
    /// All Bills opens with "Not printed" on (the dashboard's "bills to print" card).
    @Published var openUnprinted = false
    /// Goes up whenever items, prices or stock change anywhere (the billing screen reloads its item list then).
    @Published var itemsVersion = 0
    /// Bumped (after a short pause, so a burst of writes reloads once) whenever data changed; list screens reload on it.
    @Published var dataVersion = 0
    private var dataBump: Task<Void, Never>?
    var lowStockQty: Double { settings.has("low_stock_qty") ? settings.num("low_stock_qty") : 10 }

    var fyInfo: JSON? { fyYears.first { $0.str("label") == fy } ?? fyYears.first { $0.bool("current") } }
    var fyLabel: String { fyInfo?.str("label") ?? "" }
    var fyFrom: String { fyInfo?.str("from") ?? "" }
    var fyTo: String { fyInfo?.str("to") ?? "" }
    var isCurrentFY: Bool { fyInfo?.bool("current") ?? true }
    /// Today, or the last day of the year when an earlier year is open (so new entries land inside that year).
    var dateInFY: String {
        let t = Fmt.today
        guard !fyFrom.isEmpty else { return t }
        return t < fyFrom ? fyFrom : (t > fyTo ? fyTo : t)
    }
    /// First day for "this month" style filters, kept inside the open year.
    var monthStartInFY: String { String(dateInFY.prefix(7)) + "-01" }

    func start() async {
        // Settings › Billing & Dashboard › Open BillBox on
        if let p = Page(rawValue: UserDefaults.standard.string(forKey: "startPage") ?? ""), !ready { section = p }
        API.onItemsChanged = { [weak self] in Task { @MainActor in self?.itemsVersion += 1 } }
        API.onDataChanged = { [weak self] in Task { @MainActor in
            self?.dataBump?.cancel()
            self?.dataBump = Task { try? await Task.sleep(nanoseconds: 300_000_000); if !Task.isCancelled { self?.dataVersion += 1 } }
        } }
        // the built app carries its own server: start it here, no button needed
        if !(await API.healthy()), Backend.shared.isBundled || Backend.shared.guessFolder() != nil {
            if let err = await Backend.shared.start() { serverError = err; ready = true; return }
        }
        do {
            try await reloadCompanies(pick: true)
            serverError = nil
        } catch {
            serverError = error.localizedDescription
        }
        ready = true
        startSyncLoop()
        // a newer BillBox: said once when the app opens (Settings › Updates installs it)
        Task { [weak self] in
            if let u = try? await AppUpdate.check(), u.bool("available") { self?.notify("BillBox \(u.str("latest")) is available: Settings › Updates.") }
        }
    }

    private var syncLoop: Task<Void, Never>?
    private var syncVersion = -1
    /// Live sync (Settings › Sync): every 3 s the engine swaps changes with the other devices; when some arrived, every
    /// open screen reloads (dataVersion) and the billing lists too.
    func startSyncLoop() {
        guard syncLoop == nil else { return }
        syncLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let r = try? await API.obj("GET", "/sync/tick"), r.bool("on") else { continue }
                let v = r.int("version")
                guard let self else { return }
                if self.syncVersion >= 0 && v != self.syncVersion {
                    API.onDataChanged?()
                    API.onItemsChanged?()
                    if let s = try? await API.obj("GET", "/settings") { self.settings = s }
                }
                self.syncVersion = v
            }
        }
    }

    func reloadCompanies(pick: Bool = false) async throws {
        let r = try await API.obj("GET", "/companies")
        companies = r.list("companies")
        if pick || companyId == nil || company == nil {
            let last = r.optInt("last_used")
            companyId = companies.contains(where: { $0.id == last }) ? last : companies.first?.id
        }
        API.companyId = companyId
        settings = try await API.obj("GET", "/settings")
        try await loadYears()
    }

    func loadYears() async throws {
        let r = try await API.obj("GET", "/fy")
        fyYears = r.list("years")
        if !fyYears.contains(where: { $0.str("label") == fy }) { fy = r.str("current") }
    }

    func setYear(_ label: String) {
        guard label != fy else { return }
        fy = label
    }

    // MARK: Year books (Marg style: each financial year can be its own company file with the same name)

    /// A choice in the year menu: a year inside the open books, or another file's year.
    struct YearChoice: Identifiable {
        let label: String, from: String, to: String, current: Bool
        /// The books that hold this year (the open company, or a sibling year file).
        let bookId: Int
        var id: String { "\(bookId):\(label)" }
        var title: String {
            label.isEmpty ? "Main books (years without their own file)"
                : "FY \(label)  (\(Fmt.dmy(from)) to \(Fmt.dmy(to)))" + (current ? "  · current" : "")
        }
    }

    static func bookKey(_ c: JSON) -> String { c.str("name").split(separator: " ").joined(separator: " ").lowercased() }
    static var currentFYStart: Int {
        let t = Fmt.today, y = Int(t.prefix(4)) ?? 2000, m = Int(t.dropFirst(5).prefix(2)) ?? 4
        return m < 4 ? y - 1 : y
    }

    /// The financial year these books are limited to ("" for main books that hold every year).
    var booksFY: String { company?.str("fy") ?? "" }
    /// Every file kept under the open company's name (main books and year books).
    var siblingBooks: [JSON] {
        guard let c = company else { return [] }
        let k = Self.bookKey(c)
        return companies.filter { Self.bookKey($0) == k }
    }
    /// One entry per company name, for the company menu: the main books, else the newest year file.
    var companyGroups: [JSON] {
        var seen = Set<String>(), out: [JSON] = []
        for c in companies {
            let k = Self.bookKey(c)
            if seen.contains(k) { continue }
            seen.insert(k)
            let same = companies.filter { Self.bookKey($0) == k }
            out.append(same.first { $0.str("fy").isEmpty } ?? same.max { $0.str("fy") < $1.str("fy") } ?? c)
        }
        return out
    }
    func isOpenGroup(_ c: JSON) -> Bool { company.map { Self.bookKey($0) == Self.bookKey(c) } ?? false }

    /// The year menu: years inside the open books plus every sibling year file (a year with its own file opens that file).
    var yearChoices: [YearChoice] {
        guard let cid = companyId else { return [] }
        var byLabel: [String: YearChoice] = [:]
        for y in fyYears { byLabel[y.str("label")] = YearChoice(label: y.str("label"), from: y.str("from"), to: y.str("to"), current: y.bool("current"), bookId: cid) }
        for s in siblingBooks where s.id != cid && !s.str("fy").isEmpty {
            let l = s.str("fy"), start = Int(l.prefix(4)) ?? 0
            byLabel[l] = YearChoice(label: l, from: "\(start)-04-01", to: "\(start + 1)-03-31", current: start == Self.currentFYStart, bookId: s.id)
        }
        var out = byLabel.values.sorted { $0.label > $1.label }
        if !booksFY.isEmpty, let main = siblingBooks.first(where: { $0.str("fy").isEmpty }) {
            out.append(YearChoice(label: "", from: "", to: "", current: false, bookId: main.id))
        }
        return out
    }

    /// A party's ledger for one financial year. A year kept in its own file has its own copy of the party: it is found there
    /// by name (Parties › ledger › Year).
    func ledger(for party: JSON, year: String) async throws -> JSON {
        let choice = yearChoices.first { $0.label == year }
        if choice == nil || choice!.bookId == companyId {
            return try await API.obj("GET", "/parties/\(party.id)/ledger", query: ["fy": year])
        }
        let book = choice!.bookId
        let name = party.str("name").lowercased()
        let found = try await API.list("/parties", query: ["q": party.str("name"), "fy": year], company: book)
        guard let p = found.first(where: { $0.str("name").lowercased() == name }) else {
            throw APIError(message: "\(party.str("name")) is not in the FY \(year) books.", status: 0, code: nil)
        }
        return try await API.obj("GET", "/parties/\(p.id)/ledger", query: ["fy": year], company: book)
    }

    func chooseYear(_ y: YearChoice) async {
        if y.bookId != companyId { await switchCompany(y.bookId) }
        if !y.label.isEmpty { setYear(y.label) }
    }

    /// Settings › Companies: start a financial year as its own file (carry = copy masters, stock and opening balances).
    func addYearBooks(fy: String, carry: Bool) async {
        guard let cid = companyId else { return }
        await guarded {
            let r = try await API.obj("POST", "/companies/\(cid)/years", body: ["fy": fy, "carry": carry])
            try await self.reloadCompanies()
            await self.switchCompany(r.int("id"))
            self.notify("FY \(fy) books are ready" + (carry ? ": items, parties and opening balances carried forward." : " (empty)."))
        }
    }

    func switchCompany(_ id: Int) async {
        guard id != companyId else { return }
        await guarded {
            self.companyId = id
            API.companyId = id
            _ = try await API.obj("POST", "/companies/\(id)/activate", body: [:])
            self.settings = try await API.obj("GET", "/settings")
            self.fy = ""
            try await self.loadYears()
        }
    }

    func saveSettings(_ changes: [String: Any?]) async {
        await guarded { self.settings = try await API.obj("PUT", "/settings", body: changes) }
    }

    func notify(_ text: String, error: Bool = false) {
        let t = Toast(text: text, isError: error)
        toast = t
        Task {
            await pause(ms: error ? 7000 : 3500)
            if self.toast == t { self.toast = nil }
        }
    }

    /// Runs work and shows any failure as a banner instead of crashing or going silent.
    func guarded(_ work: () async throws -> Void) async {
        do { try await work() } catch { notify(error.localizedDescription, error: true) }
    }
}
