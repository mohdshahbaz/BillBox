import SwiftUI

let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

@MainActor struct PartiesView: View {
    @EnvironmentObject private var app: AppModel
    @State private var kind = "CUSTOMER"
    @State private var query = ""
    @State private var searchDelay = Debouncer()
    @State private var parties: [JSON] = []
    @State private var routes: [JSON] = []
    @State private var salesmen: [JSON] = []
    @State private var selection = Set<JSON.ID>()
    @State private var loading = true
    @State private var editing: JSON?
    @State private var creating = false
    @State private var autoRoutes = false
    @State private var ledgerFor: JSON?
    @State private var voucherFor: JSON?
    /// Set when "Record receipt / payment" was started from the ledger: the ledger opens again afterwards, showing the new line.
    @State private var ledgerReturn: JSON?
    @State private var ledgerYear = ""
    @State private var photoPayments = false
    @AppStorage("showPhotoCard") private var showPhotoCard = true
    @State private var deleteTarget: JSON?
    @State private var confirmBulkDelete = false
    @State private var busy = false

    private var supplier: Bool { kind == "SUPPLIER" }

    var body: some View { dialogs(chrome(content)) }

    private var content: some View {
        VStack(spacing: 0) {
            if !supplier && showPhotoCard { PhotoPaymentsCard { photoPayments = true }.padding(.bottom, 8) }
            SelectionBar(ids: parties.map(\.id), selection: $selection, busy: busy) { confirmBulkDelete = true }
            grid
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var grid: some View {
        DataGrid(parties, layoutKey: "parties", selection: $selection, onOpen: { openLedger($0) }, menu: { AnyView(partyMenu($0)) }) {
            GridColumn("Party", id: "name", min: 160, ideal: 260) { (p: JSON) in Text(p.str("name")).fw(.medium).lineLimit(1) }
            GridColumn("Type", id: "type", min: 70, ideal: 90) { (p: JSON) in Text(p.str("type").capitalized) }
            GridColumn("GSTIN", id: "gstin", min: 110, ideal: 150) { (p: JSON) in Text(p.str("gstin")).mono() }
            GridColumn("Route", id: "route", min: 80, ideal: 140) { (p: JSON) in Text(p.str("route_name")) }
            GridColumn("Price tier", id: "tier", min: 70, ideal: 90) { (p: JSON) in Text(p.str("price_tier").capitalized) }
            GridColumn("Contact", id: "contact", min: 100, ideal: 150) { (p: JSON) in Text(p.str("mobiles").isEmpty ? (p.str("phone").isEmpty ? p.str("tel") : p.str("phone")) : p.str("mobiles")).lineLimit(1) }
            GridColumn("Credit limit", id: "limit", min: 90, ideal: 110, align: .trailing) { (p: JSON) in Text(p.num("credit_limit") > 0 ? Fmt.money(p, "credit_limit") : "–").mono() }
            GridColumn("Balance", id: "balance", min: 110, ideal: 130, align: .trailing) { (p: JSON) in
                Text(balanceText(p.num("balance"))).mono().fw(.semibold)
                    .foregroundStyle(p.num("balance") > 0.5 ? Color.orange : (p.num("balance") < -0.5 ? Color.red : Color.secondary))
            }
        }
        .overlay {
            if loading { ProgressView() }
            else if parties.isEmpty { EmptyState(title: supplier ? "No suppliers" : "No customers", symbol: "person.2", message: supplier ? "Suppliers are added automatically when you scan their bill." : "Add your first customer.") }
        }
    }

    @ViewBuilder private func partyMenu(_ p: JSON) -> some View {
        Button("Ledger…") { openLedger(p) }
        Button(supplier ? "Record payment…" : "Record receipt…") { voucherFor = p }
        Divider()
        if selection.count > 1 && selection.contains(p.id) {
            Button("Delete \(selection.count) selected…", role: .destructive) { confirmBulkDelete = true }
        }
        Button("Edit…") { editing = p }
        Button("Delete…", role: .destructive) { deleteTarget = p }
    }

    @ViewBuilder private func chrome<V: View>(_ v: V) -> some View {
        v
        .navigationTitle("Parties")
        .navigationSubtitle("\(parties.count) \(supplier ? "suppliers" : "customers")")
        .searchable(text: $query, prompt: "Search name, phone or GSTIN")
        .onChange(of: query) { _ in searchDelay.run { await load() } }   // typing loads once, 250 ms after the last key
        .onChange(of: kind) { _ in Task { selection = []; await load() } }
        .toolbar {
            ToolbarItem {
                Picker("Show", selection: $kind) {
                    Text("Customers").tag("CUSTOMER")
                    Text("Suppliers").tag("SUPPLIER")
                }
                .pickerStyle(.segmented)
                .frame(width: 210)
            }
            ToolbarItemGroup {
                Button { creating = true } label: { Label(supplier ? "New supplier" : "New customer", systemImage: "person.badge.plus") }
                if !supplier { Button { autoRoutes = true } label: { Label("Assign routes", systemImage: "point.topleft.down.curvedto.point.bottomright.up") }.help("Give customers without a route the route named in their name or address") }
            }
        }
        .task { await load() }
        .onChange(of: app.dataVersion) { _ in Task { await load() } }
    }

    @ViewBuilder private func dialogs<V: View>(_ v: V) -> some View {
        v
        .sheet(isPresented: $autoRoutes) { AutoRouteSheet { await load() } }
        .sheet(isPresented: $creating) { PartySheet(party: nil, defaultType: supplier ? "SUPPLIER" : "RETAILER", routes: routes, salesmen: salesmen) { await load() } }
        .sheet(item: $editing) { p in PartySheet(party: p, defaultType: "RETAILER", routes: routes, salesmen: salesmen) { await load() } }
        .sheet(item: $ledgerFor) { p in
            LedgerSheet(party: p, initialYear: ledgerYear, onVoucher: { ledgerReturn = p; ledgerYear = ""; voucherFor = p }, onChanged: { await load() })
        }
        .sheet(item: $voucherFor) { p in VoucherSheet(party: p, saved: { ledgerYear = fyLabelOf($0) }, done: { await load() }) }
        .onChange(of: voucherFor?.id) { id in
            // the voucher sheet closed (saved or cancelled): bring the ledger back, on the year of the new line
            guard id == nil, let p = ledgerReturn else { return }
            ledgerReturn = nil
            Task { await pause(ms: 600); openLedger(p, year: ledgerYear) }
        }

        .sheet(isPresented: $photoPayments) { PaymentPhotoSheet { await load() } }
        .confirmationDialog("Delete \(deleteTarget?.str("name") ?? "")?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let t = deleteTarget {
                    Task {
                        await app.guarded {
                            let r = try await API.obj("DELETE", "/parties/\(t.id)")
                            app.notify(r.str("result") == "archived" ? "\(t.str("name")) archived (it has history)." : "\(t.str("name")) deleted.")
                            await load()
                        }
                    }
                }
            }
        } message: { Text("Parties with bills or ledger entries are archived instead.") }
        .confirmationDialog("Delete \(selection.count) selected part\(selection.count == 1 ? "y" : "ies")?", isPresented: $confirmBulkDelete, titleVisibility: .visible) {
            Button("Delete \(selection.count)", role: .destructive) { Task { await bulkDeleteSelected() } }
        } message: { Text("Parties with bills or ledger entries are archived instead.") }
    }

    private func bulkDeleteSelected() async {
        busy = true
        await bulkDelete(Array(selection), notify: { app.notify($0) }) { id -> BulkOutcome in
            guard let p = parties.first(where: { $0.id == id }) else { return .failed(label: "#\(id)", reason: "not found") }
            do {
                let r = try await API.obj("DELETE", "/parties/\(p.id)")
                return r.str("result") == "archived" ? .archived : .deleted
            } catch {
                return .failed(label: p.str("name"), reason: error.localizedDescription)
            }
        }
        selection = []
        busy = false
        await load()
    }

    private func load() async {
        await app.guarded {
            async let p = API.list("/parties", query: ["q": query, "kind": kind])
            async let r = API.list("/routes")
            async let s = API.list("/salesmen")
            parties = try await p
            routes = try await r
            salesmen = try await s
        }
        loading = false
    }
}

@MainActor struct PartySheet: View {
    @EnvironmentObject private var app: AppModel
    let party: JSON?
    let defaultType: String
    let routes: [JSON]
    let salesmen: [JSON]
    let done: () async -> Void

    @State private var f: [String: String] = [:]
    @State private var type = ""
    @State private var tier = ""
    @State private var route = ""
    @State private var newRoute = ""
    @State private var newSalesman = ""
    @State private var newDays = "1"
    @State private var newPerson = ""        // "" = not assigned, "__new__" = create one now
    @State private var personName = ""
    @State private var personPhone = ""
    @State private var loaded = false

    private func b(_ k: String, _ d: String = "") -> Binding<String> {
        Binding(get: { f[k] ?? (party?.has(k) == true ? party!.str(k) : d) }, set: { f[k] = $0 })
    }
    private var isSupplier: Bool { type == "SUPPLIER" }

    var body: some View {
        FormSheet(title: party == nil ? "New party" : "Edit \(party!.str("name"))", width: 580, canSave: !b("name").wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty, onSave: save) {
            TextField("Party name", text: b("name"))
            Picker("Type", selection: $type) {
                Text("Retailer").tag("RETAILER")
                Text("Wholesaler").tag("WHOLESALER")
                Text("Supplier / vendor").tag("SUPPLIER")
            }
            TextField("GSTIN (blank if unregistered)", text: Binding(get: { b("gstin").wrappedValue }, set: { v in
                let g = v.uppercased()
                f["gstin"] = g
                if g.count >= 2, g.prefix(2).allSatisfy(\.isNumber) { f["state_code"] = String(g.prefix(2)) }
                if g.count == 15, b("pan").wrappedValue.isEmpty { f["pan"] = String(g.dropFirst(2).prefix(10)) }
            }))
            TextField("State code (09 UP, 07 Delhi)", text: b("state_code", "09"))
            TextField("Address", text: b("address"))
            if isSupplier {
                TextField("Tel (landline)", text: b("tel"))
                TextField("Phone", text: b("phone"))
                TextField("Mobile numbers (comma separated)", text: b("mobiles"))
                TextField("Email", text: b("email"))
                TextField("FSSAI number (14 digits)", text: b("fssai"))
                TextField("PAN number", text: b("pan"))
            } else {
                TextField("Phone", text: b("phone"))
                Picker("Price tier", selection: $tier) {
                    Text("Retail price").tag("RETAIL")
                    Text("Wholesale price").tag("WHOLESALE")
                    Text("MRP").tag("MRP")
                }
                TextField("Credit limit (0 = no limit)", text: b("credit_limit", "0"))
                TextField("Credit days", text: b("credit_days", "0"))
                Picker("Delivery / sales route", selection: $route) {
                    Text("No route").tag("")
                    ForEach(routes) { r in
                        Text(r.str("name") + (dayList(r.str("days")).isEmpty ? (r.has("day_of_week") ? " · \(String(dayNames[min(6, max(0, r.int("day_of_week")))].prefix(3)))" : "") : " · " + dayList(r.str("days")))).tag(String(r.id))
                    }
                    Text("+ New route…").tag("__new__")
                }
                if route == "__new__" {
                    TextField("New route name", text: $newRoute)
                    Picker("Salesman for this route", selection: $newSalesman) {
                        Text("Not assigned yet").tag("")
                        ForEach(salesmen) { s in Text(s.str("name")).tag(String(s.id)) }
                        Text("+ New salesman…").tag("__new__")
                    }
                    if newSalesman == "__new__" {
                        TextField("New salesman name", text: $personName)
                        TextField("Salesman phone (optional)", text: $personPhone)
                    }
                    Labeled("Visit days") { DayPicker(days: $newDays) }
                }
            }
            if party == nil {
                TextField(isSupplier ? "Opening balance (negative = you owe them)" : "Opening balance (they owe you)", text: b("opening_balance", "0"))
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            type = party == nil ? defaultType : (party!.str("type").isEmpty ? "RETAILER" : party!.str("type"))
            let defTier = ["RETAIL", "WHOLESALE", "MRP"].contains(app.settings.str("party_default_tier")) ? app.settings.str("party_default_tier") : "RETAIL"
            tier = party?.str("price_tier").isEmpty == false ? party!.str("price_tier") : defTier
            if party == nil {   // Settings › Parties & Payments › new customers start with
                if !app.settings.str("party_default_limit").isEmpty { f["credit_limit"] = app.settings.str("party_default_limit") }
                if !app.settings.str("party_default_days").isEmpty { f["credit_days"] = app.settings.str("party_default_days") }
            }
            route = party?.has("route_id") == true ? party!.str("route_id") : ""
        }
    }

    private func save() async throws {
        var body: [String: Any?] = [:]
        for k in ["name", "gstin", "state_code", "phone", "address", "credit_limit", "credit_days", "tel", "mobiles", "email", "fssai", "pan"] {
            body[k] = b(k, (k == "state_code" ? "09" : (k == "credit_limit" || k == "credit_days" ? "0" : ""))).wrappedValue.trimmingCharacters(in: .whitespaces)
        }
        body["type"] = type
        body["price_tier"] = tier
        body["route_id"] = route == "__new__" ? "" : route
        if party == nil { body["opening_balance"] = b("opening_balance", "0").wrappedValue }
        if route == "__new__" {
            if newRoute.trimmingCharacters(in: .whitespaces).isEmpty { throw APIError(message: "Enter a name for the new route", status: 0, code: nil) }
            var sid = newSalesman
            if newSalesman == "__new__" {
                if personName.trimmingCharacters(in: .whitespaces).isEmpty { throw APIError(message: "Enter the new salesman's name", status: 0, code: nil) }
                let made = try await API.obj("POST", "/salesmen", body: ["name": personName, "phone": personPhone, "monthly_target": "0"])
                sid = String(made.int("id"))
            }
            body["new_route"] = ["name": newRoute, "salesman_id": sid, "days": newDays]
        }
        if let party { _ = try await API.obj("PUT", "/parties/\(party.id)", body: body) } else { _ = try await API.obj("POST", "/parties", body: body) }
        app.notify("Party saved.")
        await done()
    }
}

extension PartiesView {
    func openLedger(_ p: JSON, year: String = "") { ledgerYear = year; ledgerFor = p }

    /// "2026-27" for a date like 2026-11-02 (the financial year runs 1 April to 31 March).
    func fyLabelOf(_ iso: String) -> String {
        let q = iso.split(separator: "-")
        guard q.count >= 2, let y = Int(q[0]), let m = Int(q[1]) else { return "" }
        let s = m >= 4 ? y : y - 1
        return "\(s)-\(String(format: "%02d", (s + 1) % 100))"
    }
}

@MainActor struct LedgerSheet: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    let party: JSON
    var initialYear = ""
    let onVoucher: () -> Void
    /// Called after a line is deleted, so the party list shows the new balance.
    var onChanged: (() async -> Void)? = nil
    @State private var data: JSON?
    @State private var deleteTarget: JSON?
    /// The financial year shown; earlier years too (Year menu).
    @State private var year = ""

    var body: some View {
        let entries = data?.list("entries") ?? []
        let bal = data?.num("balance") ?? 0
        InfoSheet(title: "\(party.str("name")) · ledger · FY \(shownYear)", width: 900, height: 560, trailing: AnyView(
            HStack {
                Picker("Year", selection: $year) {
                    ForEach(app.yearChoices.filter { !$0.label.isEmpty }) { y in Text("FY \(y.label)").tag(y.label) }
                }
                .pickerStyle(.menu).fixedSize()
                Button("Record receipt / payment…") { dismiss(); onVoucher() }
                Button("Copy") {
                    Files.copy(tsv(["Date", "Type", "Reference", "Narration", "Debit", "Credit", "Balance"],
                                   entries.map { [Fmt.dmy($0.str("date")), $0.str("type"), $0.str("ref_no"), $0.str("narration"), $0.str("debit"), $0.str("credit"), $0.str("balance")] }))
                    app.notify("Ledger copied. Paste into Excel or Numbers.")
                }
            }
        )) {
            VStack(alignment: .leading, spacing: 8) {
                Text(balanceText(bal) + (bal > 0.005 ? "  (they owe you)" : (bal < -0.005 ? "  (you owe them)" : "")))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(bal > 0.5 ? Color.orange : (bal < -0.5 ? Color.red : Color.green))
                if let d = data, abs(d.num("opening_balance")) > 0.005 {
                    Text("Opening balance for FY \(shownYear), brought forward from earlier years: \(balanceText(d.num("opening_balance")))")
                        .font(.callout).foregroundStyle(.secondary)
                }
                DataGrid(entries, layoutKey: "ledger", onOpen: { askDelete($0) }, menu: { AnyView(rowMenu($0)) }) {
                    GridColumn("Date", id: "date", min: 80, ideal: 95) { (r: JSON) in Text(Fmt.dmy(r.str("date"))).mono() }
                    GridColumn("Type", id: "type", min: 70, ideal: 90) { (r: JSON) in Text(r.str("type")) }
                    GridColumn("Reference", id: "ref", min: 80, ideal: 120) { (r: JSON) in Text(r.str("ref_no")) }
                    GridColumn("Narration", id: "narration", min: 120, ideal: 220) { (r: JSON) in Text(r.str("narration")).lineLimit(1) }
                    GridColumn("Debit", id: "debit", min: 80, ideal: 100, align: .trailing) { (r: JSON) in Text(r.num("debit") > 0 ? Fmt.money(r, "debit") : "").mono() }
                    GridColumn("Credit", id: "credit", min: 80, ideal: 100, align: .trailing) { (r: JSON) in Text(r.num("credit") > 0 ? Fmt.money(r, "credit") : "").mono() }
                    GridColumn("Balance", id: "balance", min: 100, ideal: 120, align: .trailing) { (r: JSON) in Text(balanceText(r.num("balance"))).mono().fw(.semibold) }
                }
                Text("Dr = they owe you. Cr = you owe them. (Click a receipt, payment or opening line to delete it.)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .task { if year.isEmpty { year = initialYear.isEmpty ? app.fyLabel : initialYear }; await load() }
        .onChange(of: year) { _ in Task { await load() } }
        .confirmationDialog(deleteTitle, isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), titleVisibility: .visible) {
            Button("Delete this line", role: .destructive) { if let t = deleteTarget { Task { await delete(t) } } }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("The voucher behind it is removed too and the balance is worked out again. This cannot be undone.")
        }
    }

    private var shownYear: String { year.isEmpty ? app.fyLabel : year }

    /// Receipts, payments and opening balances can be deleted here; a bill's own line is removed by deleting or editing the bill.
    private func deletable(_ e: JSON) -> Bool { ["RECEIPT", "PAYMENT", "OPENING"].contains(e.str("type")) }

    private func askDelete(_ e: JSON) {
        if deletable(e) { deleteTarget = e }
        else { app.notify("That line belongs to a bill. Delete or edit the bill to remove it.") }
    }

    @ViewBuilder private func rowMenu(_ e: JSON) -> some View {
        if deletable(e) { Button("Delete this line…", role: .destructive) { askDelete(e) } }
    }

    private var deleteTitle: String {
        guard let t = deleteTarget else { return "Delete this line?" }
        let amt = t.num("credit") > 0 ? t.num("credit") : t.num("debit")
        return "Delete \(t.str("type").capitalized) \(t.str("ref_no")) · \(Fmt.money(amt))?"
    }

    private func delete(_ e: JSON) async {
        deleteTarget = nil
        let book = app.yearChoices.first { $0.label == shownYear }?.bookId
        await app.guarded {
            _ = try await API.obj("DELETE", "/ledger/\(e.id)", company: book == app.companyId ? nil : book)
            app.notify("Deleted \(e.str("type").capitalized) \(e.str("ref_no")).")
            await load()
            await onChanged?()
        }
    }

    private func load() async {
        do { data = try await app.ledger(for: party, year: shownYear) } catch { data = JSON(); app.notify(error.localizedDescription, error: true) }
    }
}

@MainActor struct VoucherSheet: View {
    @EnvironmentObject private var app: AppModel
    let party: JSON
    var saved: ((String) -> Void)? = nil
    let done: () async -> Void
    @State private var direction = ""
    @State private var amount = ""
    @State private var mode = "CASH"
    @State private var loadedMode = false
    @State private var date = ""
    @State private var reference = ""
    @State private var printNo: String?

    private var supplier: Bool { party.str("type") == "SUPPLIER" }

    var body: some View {
        FormSheet(title: "\(supplier ? "Payment to" : "Receipt from") \(party.str("name"))", saveLabel: app.settings.str("voucher_print") == "0" ? "Save" : "Save and print", canSave: (Double(amount) ?? 0) > 0, onSave: {
            let r = try await API.obj("POST", "/vouchers", body: [
                "party_id": String(party.id), "direction": direction.isEmpty ? (supplier ? "PAID" : "RECEIVED") : direction,
                "amount": amount, "mode": mode, "date": date, "reference": reference,
            ])
            app.notify("Saved \(r.str("voucher_no")).")
            saved?(date)
            await done()
            let no = r.str("voucher_no")
            if !no.isEmpty && app.settings.str("voucher_print") != "0" { await printVoucher(no, app: app) }   // Settings › Parties & Payments
        }) {
            Picker("Direction", selection: $direction) {
                Text("Received from them (money in)").tag("RECEIVED")
                Text("Paid to them (money out)").tag("PAID")
            }
            TextField("Amount", text: $amount)
            Picker("Mode", selection: $mode) {
                ForEach(["CASH": "Cash", "UPI": "UPI", "CARD": "Card", "CHEQUE": "Cheque", "BANK": "Bank transfer"].sorted(by: { $0.key < $1.key }), id: \.key) { Text($0.value).tag($0.key) }
            }
            Labeled("Date") { DateField(iso: $date) }
            TextField("Reference / cheque no. (optional)", text: $reference)
        }
        .onAppear {
            if direction.isEmpty { direction = supplier ? "PAID" : "RECEIVED" }
            if date.isEmpty { date = app.dateInFY }
            if !loadedMode { loadedMode = true; let m = app.settings.str("pay_default_mode"); if !m.isEmpty { mode = m } }
        }
    }
}

/// Outlets without a route get the route named in their name or address (POST /routes/auto-assign): preview, untick, apply.
@MainActor struct AutoRouteSheet: View {
    @EnvironmentObject private var app: AppModel
    let done: () async -> Void
    @State private var preview: JSON?
    @State private var skip = Set<Int>()

    private var matches: [JSON] { preview?.list("matches") ?? [] }
    private var chosen: [Int] { matches.map { $0.int("party_id") }.filter { !skip.contains($0) } }

    var body: some View {
        FormSheet(title: "Assign routes from name and address", saveLabel: "Assign \(chosen.count)", width: 600, canSave: !chosen.isEmpty, onSave: {
            let r = try await API.obj("POST", "/routes/auto-assign", body: ["apply": true, "party_ids": chosen])
            app.notify("\(r.int("assigned")) outlets assigned to routes.")
            await done()
        }) {
            if let p = preview {
                Text(matches.isEmpty ? "No customer without a route has a route name in their name or address."
                     : "\(matches.count) customers without a route have a route name in their name or address. Untick any that are wrong.")
                    .foregroundStyle(.secondary)
                if p.int("unclear") > 0 || p.int("unmatched") > 0 {
                    Text("Left as they are: \(p.int("unmatched")) with no route name found\(p.int("unclear") > 0 ? ", \(p.int("unclear")) matching more than one route" : "").")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(matches) { m in
                    let id = m.int("party_id")
                    Toggle(isOn: Binding(get: { !skip.contains(id) }, set: { if $0 { skip.remove(id) } else { skip.insert(id) } })) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(m.str("party_name")).fw(.medium)
                                if !m.str("address").isEmpty { Text(m.str("address")).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                            }
                            Spacer()
                            Text("→ \(m.str("route_name"))").fw(.semibold)
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .task {
            await app.guarded { preview = try await API.obj("POST", "/routes/auto-assign", body: ["apply": false]) }
        }
    }
}
