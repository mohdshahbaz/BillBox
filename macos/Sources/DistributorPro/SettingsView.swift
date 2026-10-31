import SwiftUI
import AppKit

@MainActor struct SettingsView: View {
    /// the tab stays chosen when the window is redrawn (a theme change) and when Settings is opened again
    @AppStorage("settingsTab") private var tab = "appearance"

    var body: some View {
        TabView(selection: $tab) {
            AppearanceSettings().tabItem { Label("Appearance", systemImage: "paintpalette") }.tag("appearance")
            CompanySettings().tabItem { Label("Companies", systemImage: "building.2") }.tag("companies")
            PrintSettings().tabItem { Label("Printing", systemImage: "printer") }.tag("printing")
            WhatsAppSettings().tabItem { Label("WhatsApp", systemImage: "message") }.tag("whatsapp")
            BillingDashboardSettings().tabItem { Label("Billing & Dashboard", systemImage: "gauge") }.tag("billing")
            PartiesPaymentsSettings().tabItem { Label("Parties & Payments", systemImage: "person.2") }.tag("parties")
            StockSettings().tabItem { Label("Stock", systemImage: "archivebox") }.tag("stock")
            BackupSettings().tabItem { Label("Backup", systemImage: "externaldrive") }.tag("backup")
            MargImportView().tabItem { Label("Import from Marg", systemImage: "square.and.arrow.down.on.square") }.tag("marg")
            LicenseSettings().tabItem { Label("Licence", systemImage: "key") }.tag("licence")
        }
        .padding(16)
        .navigationTitle("Settings")
    }
}

@MainActor struct CompanySettings: View {
    @EnvironmentObject private var app: AppModel
    @State private var editing: JSON?
    @State private var creating = false
    @State private var deleting: JSON?
    @State private var yearStart = AppModel.currentFYStart + 1

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Each company has its own books (stock, parties, bills). Switch company from the top of the sidebar.").foregroundStyle(.secondary)
            List(app.companies) { c in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.str("name") + (c.str("fy").isEmpty ? "" : "  · FY \(c.str("fy")) file")).fw(.medium)
                        Text([c.str("company_gstin"), c.str("company_address")].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if c.id == app.companyId { Label("Open", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption) }
                    else { Button("Open") { Task { await app.switchCompany(c.id) } } }
                    Button("Edit…") { editing = c }
                    Button("Delete…", role: .destructive) { deleting = c }
                }
            }
            .frame(minHeight: 200)
            HStack { Button("New company…") { creating = true }; Spacer() }
            GroupBox("Financial years of \(app.companyName)") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Picker("Financial year", selection: $yearStart) {
                            ForEach((AppModel.currentFYStart - 6)...(AppModel.currentFYStart + 1), id: \.self) { Text("FY " + fyLabelFor($0)).tag($0) }
                        }
                        .frame(width: 230)
                        Button("Start as its own file, carrying forward") { Task { await app.addYearBooks(fy: fyLabelFor(yearStart), carry: true) } }
                        Button("Add as an empty file (for Marg data)") { Task { await app.addYearBooks(fy: fyLabelFor(yearStart), carry: false) } }
                        Spacer()
                    }
                    Text("Like Marg, each year can be kept in its own file. “Carrying forward” copies items, parties, schemes, stock in hand and closing balances into the new year’s opening balances. An empty file is for an earlier year: open it, then Settings › Import from Marg ERP brings that year’s Marg data in. Switch years from the year menu; years with their own file open that file.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(6)
            }
        }
        .sheet(isPresented: $creating) { CompanySheet(company: nil) }
        .sheet(item: $editing) { c in CompanySheet(company: c) }
        .sheet(item: $deleting) { c in DeleteCompanySheet(company: c) }
    }
}

@MainActor struct CompanySheet: View {
    @EnvironmentObject private var app: AppModel
    let company: JSON?
    @State private var f: [String: String] = [:]

    private func b(_ k: String, _ d: String = "") -> Binding<String> {
        Binding(get: { f[k] ?? (company?.has(k) == true ? company!.str(k) : d) }, set: { f[k] = $0 })
    }

    var body: some View {
        FormSheet(title: company == nil ? "New company" : "Edit \(company!.str("name"))", width: 540, canSave: !b("name").wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty, onSave: {
            var body: [String: Any?] = [:]
            for k in ["name", "company_gstin", "state_code", "company_address", "company_phone", "invoice_terms"] {
                body[k] = b(k, k == "state_code" ? "09" : (k == "invoice_terms" ? "Goods once sold will not be taken back." : "")).wrappedValue
            }
            if let company {
                _ = try await API.obj("PUT", "/companies/\(company.id)", body: body)
            } else {
                let r = try await API.obj("POST", "/companies", body: body)
                try await app.reloadCompanies()
                await app.switchCompany(r.int("id"))
                return
            }
            try await app.reloadCompanies()
        }) {
            TextField("Company / business name", text: b("name"))
            TextField("GSTIN (blank if unregistered)", text: b("company_gstin"))
            TextField("State code (09 = Uttar Pradesh, 07 = Delhi)", text: b("state_code", "09"))
            TextField("Address", text: b("company_address"))
            TextField("Phone", text: b("company_phone"))
            TextField("Terms printed on invoices", text: b("invoice_terms", "Goods once sold will not be taken back."))
        }
    }
}

@MainActor struct PrintSettings: View {
    @EnvironmentObject private var app: AppModel
    @State private var layout = PrintLayout.halfSheets
    @State private var afterSave = "print"
    @State private var title = ""
    @State private var hidden: Set<String> = []
    @State private var words = true
    @State private var signature = true
    @State private var copy1 = ""
    @State private var copy2 = ""
    @State private var printer = ""
    @State private var auto = false
    @State private var loaded = false

    var body: some View {
        Form {
            Picker("Invoice layout", selection: $layout) {
                ForEach(PrintLayout.allCases) { Text($0.label).tag($0) }
            }
            Picker("Printer", selection: $printer) {
                Text("Ask every time").tag("")
                ForEach(NSPrinter.printerNames, id: \.self) { Text($0).tag($0) }
            }
            Toggle("Print straight to this printer after saving a bill (no preview)", isOn: $auto)
                .disabled(printer.isEmpty)
                Picker("After saving a bill", selection: $afterSave) {
                    Text("Print it now").tag("print"); Text("Ask: print now or later").tag("ask"); Text("Keep it to print later").tag("later")
                }
                TextField("Bill title (blank = TAX INVOICE; GST INVOICE in Marg style)", text: $title)
                ForEach(optionalColumns, id: \.key) { c in
                    Toggle("Print the \(c.title) column", isOn: Binding(get: { !hidden.contains(c.key) }, set: { on in if on { hidden.remove(c.key) } else { hidden.insert(c.key) } }))
                }
                Toggle("Print the amount in words", isOn: $words)
                Toggle("Print \u{201C}For company / Authorised Signatory\u{201D}", isOn: $signature)
                TextField("First copy label (blank = ORIGINAL FOR RECIPIENT)", text: $copy1)
                TextField("Second copy label (blank = DUPLICATE FOR TRANSPORTER/SUPPLIER)", text: $copy2)
            PrintOptionsSections()
            Text("“Half sheets”: cut A4 sheets in two (or use A5) and load them in the printer’s tray; BillBox asks the printer for A5 paper and prints the Original on one sheet and the Duplicate on the next, across the sheet. If your printer has no A5 setting, choose A5 (or 148 x 210 mm) in its print panel once. “Original on top, Duplicate below” fits both copies on one uncut A4 sheet. “Full A4 page” prints each copy on its own A4 sheet, with room for many more item rows.")
                .font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Save") { Task { await save() } }.buttonStyle(.borderedProminent) }
        }
        .groupedForm()
        .onAppear {
            guard !loaded else { return }
            loaded = true
            layout = PrintLayout.parse(app.settings.str("print_layout"))
            printer = app.settings.str("print_printer")
            auto = app.settings.str("print_auto") == "1"
            afterSave = app.settings.str("bill_after_save").isEmpty ? "print" : app.settings.str("bill_after_save")
            title = app.settings.str("print_title")
            hidden = Set(app.settings.str("print_hide_cols").split(separator: ",").map(String.init))
            words = app.settings.str("print_words") != "0"
            signature = app.settings.str("print_signature") != "0"
            copy1 = app.settings.str("print_copy1")
            copy2 = app.settings.str("print_copy2")
        }
    }

    private func save() async {
        await app.saveSettings(["bill_after_save": afterSave, "print_title": title.trimmingCharacters(in: .whitespaces),
                                "print_hide_cols": optionalColumns.map(\.key).filter { hidden.contains($0) }.joined(separator: ","),
                                "print_words": words ? "1" : "0", "print_signature": signature ? "1" : "0",
                                "print_copy1": copy1.trimmingCharacters(in: .whitespaces), "print_copy2": copy2.trimmingCharacters(in: .whitespaces), "print_layout": layout.rawValue, "print_printer": printer, "print_auto": (auto && !printer.isEmpty) ? "1" : "0"])
        app.notify("Print settings saved.")
    }
}

@MainActor struct StockSettings: View {
    @EnvironmentObject private var app: AppModel
    @State private var low = ""
    @State private var loaded = false

    var body: some View {
        Form {
            TextField("Low-stock warning at or below (pieces)", text: $low).frame(maxWidth: 360)
            SettingNumberField(title: "Warn about expiry this many days ahead", key: "expiry_days", placeholder: "30", range: 1...365).frame(maxWidth: 460)
            HStack { Spacer(); Button("Save") {
                Task { await app.saveSettings(["low_stock_qty": low.trimmingCharacters(in: .whitespaces)]); app.notify("Saved.") }
            }.buttonStyle(.borderedProminent) }
        }
        .groupedForm()
        .onAppear { if !loaded { loaded = true; low = Fmt.qty(app.lowStockQty) } }
    }
}

@MainActor struct BackupSettings: View {
    @EnvironmentObject private var app: AppModel
    @State private var dir = ""
    @State private var enabled = false
    @State private var onExit = false
    @State private var time = "22:00"
    @State private var lastRun = ""
    @State private var lastStatus = ""
    @State private var backups: [JSON] = []
    @State private var busy = false
    @State private var sel = Set<JSON.ID>()

    private var timeDate: Binding<Date> {
        Binding(get: {
            let p = time.split(separator: ":").compactMap { Int($0) }
            return Calendar.current.date(bySettingHour: p.first ?? 22, minute: p.count > 1 ? p[1] : 0, second: 0, of: Date()) ?? Date()
        }, set: { d in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            time = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
          // this Mac's backups on the left, Google Drive on the right: both always in view
          HStack(alignment: .top, spacing: 12) {
            Form {
                HStack {
                    TextField("Backup folder", text: $dir)
                    Button("Choose…") { if let p = Files.chooseFolder() { dir = p } }
                }
                Toggle("Back up automatically every day while the app is open", isOn: $enabled)
                Toggle("Also back up whenever I quit the app", isOn: $onExit)
                DatePicker("Time", selection: timeDate, displayedComponents: .hourAndMinute)
                Text("Every backup is kept for good; nothing is deleted automatically.").font(.caption).foregroundStyle(.secondary)
                if !lastRun.isEmpty { Text("Last backup: \(Fmt.ist(lastRun)) · \(istStatus(lastStatus))").font(.caption).foregroundStyle(.secondary) }
                HStack {
                    Spacer()
                    Button("Save settings") { Task { await saveConfig() } }
                    Button { Task { await runNow() } } label: { Text(busy ? "Backing up…" : "Back up now") }
                        .buttonStyle(.borderedProminent).disabled(busy)
                }
            }
            .groupedForm()
            .frame(minWidth: 380, maxWidth: .infinity)
            Form { DriveBackupSection(onRestore: { n in Task { await load(); await restore(name: n, label: n) } }) }
                .groupedForm()
                .frame(minWidth: 340, maxWidth: .infinity)
          }
          .frame(height: 330)
            HStack {
                Text("Restore").font(.headline)
                Spacer()
                Button("Restore selected backup…") { if let b = backups.first(where: { sel.contains($0.id) }) { Task { await restore(name: b.str("name"), label: b.str("name")) } } }
                    .disabled(!backups.contains(where: { sel.contains($0.id) }))
                Button("Restore from a backup folder…") { if let p = Files.chooseFolder() { Task { await restore(folder: p, label: URL(fileURLWithPath: p).lastPathComponent) } } }
                Button("Restore one company file (.db)…") {
                    if let u = Files.open(types: ["db"]) { Task { await restore(file: u.path, label: u.lastPathComponent) } }
                }
            }
            SelectionBar(ids: backups.map(\.id), selection: $sel, actionLabel: "Delete selected backups…", busy: busy) { Task { await deleteSelectedBackups() } }
            DataGrid(backups, layoutKey: "backups", selection: $sel, menu: { b in
                AnyView(Group {
                    Button("Restore this backup…") { Task { await restore(name: b.str("name"), label: b.str("name")) } }
                    Button("Delete this backup…") { Task { await deleteBackup(b.str("name")) } }
                    if sel.count > 1 && sel.contains(b.id) {
                        Button("Delete \(sel.count) selected…", role: .destructive) { Task { await deleteSelectedBackups() } }
                    }
                })
            }) {
                GridColumn("Backup", id: "name", min: 200, ideal: 280) { (b: JSON) in Text(b.str("name")) }
                GridColumn("Companies", id: "companies", min: 160, ideal: 240) { (b: JSON) in Text(b.strings("companies").joined(separator: ", ")).lineLimit(1) }
                GridColumn("Created", id: "created", min: 120, ideal: 160) { (b: JSON) in Text(Fmt.ist(b.str("created"))) }
                GridColumn("Company files", id: "files", min: 80, ideal: 100, align: .trailing) { (b: JSON) in Text(b.str("files")) }
                GridColumn("Size", id: "size", min: 80, ideal: 100, align: .trailing) { (b: JSON) in Text(ByteCountFormatter.string(fromByteCount: Int64(b.num("bytes")), countStyle: .file)) }
            }
            Text("Each backup is a new folder named FMCG_Backup_YYYYMMDD_HHMMSS holding a verified copy of every company's database. Each company is restored into the company with the same name (it is created if it is missing); other companies are not touched. The files are checked first, and a safety backup of today's data is made before anything is replaced.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .task { await load() }
    }

    private func fill(_ r: JSON) {
        let c = r.obj("config")
        dir = c.str("dir")
        enabled = c.bool("enabled") || c.str("enabled") == "1"
        onExit = c.bool("on_exit") || c.str("on_exit") == "1"
        time = c.str("time").isEmpty ? "22:00" : c.str("time")
        lastRun = c.str("last_run")
        lastStatus = c.str("last_status")
        backups = r.list("backups")
    }

    private func load() async { await app.guarded { fill(try await API.obj("GET", "/backup")) } }

    private func saveConfig() async {
        await app.guarded {
            _ = try await API.obj("PUT", "/backup/config", body: ["dir": dir.trimmingCharacters(in: .whitespaces), "enabled": enabled, "on_exit": onExit, "time": time])
            app.notify(enabled ? "Saved. A backup will run every day at \(time) while the app is open." : "Saved. Automatic backup is off.")
        }
    }

    private func restore(name: String? = nil, folder: String? = nil, file: String? = nil, label: String) async {
        let a = NSAlert()
        a.messageText = "Restore \(label)?"
        a.informativeText = (file != nil ? "This goes into the company that file belongs to (matched by name). " : "Each company goes into the company with the same name here (it is created if missing). ")
            + "\n\nReplace: the current books of that company are replaced by the backup.\nMerge: only what is missing is added from the backup (parties, items, bills, receipts and so on); nothing that already exists is changed or removed.\n\nA safety backup of the current data is made first either way."
        a.alertStyle = .warning
        a.addButton(withTitle: "Replace")
        a.addButton(withTitle: "Merge")
        a.addButton(withTitle: "Cancel")
        let pick = a.runModal()
        guard pick == .alertFirstButtonReturn || pick == .alertSecondButtonReturn else { return }
        let mode = pick == .alertSecondButtonReturn ? "merge" : "replace"
        busy = true
        await app.guarded {
            _ = try await API.obj("PUT", "/backup/config", body: ["dir": dir.trimmingCharacters(in: .whitespaces)])
            let r = try await API.obj("POST", "/backup/restore", body: ["name": name, "folder": folder, "file": file, "company_id": file != nil ? app.companyId : nil, "mode": mode])
            try await app.reloadCompanies(pick: true)
            fill(try await API.obj("GET", "/backup"))
            if mode == "merge" {
                var added = 0
                var conflicts: [String] = []
                for m in r.list("merged") {
                    for (_, v) in m.obj("added").raw { added += (v as? Int) ?? Int("\(v)") ?? 0 }
                    conflicts += m.strings("conflicts")
                }
                app.notify("Merged \(added) new record\(added == 1 ? "" : "s") into " + r.strings("restored").joined(separator: ", ") + (conflicts.isEmpty ? "." : ". \(conflicts.count) bill number\(conflicts.count == 1 ? "" : "s") clashed and were left as they are."))
            } else {
                app.notify("Restored: " + r.strings("restored").joined(separator: ", ") + ".")
            }
        }
        busy = false
    }

    private func deleteBackup(_ name: String) async {
        let a = NSAlert()
        a.messageText = "Delete backup \(name)?"
        a.informativeText = "The backup folder is removed for good. Your current books are not affected."
        a.alertStyle = .warning
        a.addButton(withTitle: "Delete")
        a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        await app.guarded {
            let r = try await API.obj("DELETE", "/backup/\(name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name)")
            backups = r.list("backups")
            sel = []
            app.notify("Deleted \(name).")
        }
    }

    private func deleteSelectedBackups() async {
        let names = backups.filter { sel.contains($0.id) }.map { $0.str("name") }
        guard !names.isEmpty else { return }
        let a = NSAlert()
        a.messageText = "Delete \(names.count) selected backup\(names.count == 1 ? "" : "s")?"
        a.informativeText = "The backup folder\(names.count == 1 ? "" : "s") \(names.count == 1 ? "is" : "are") removed for good. Your current books are not affected."
        a.alertStyle = .warning
        a.addButton(withTitle: "Delete")
        a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        busy = true
        var deleted = 0
        for name in names {
            await app.guarded {
                _ = try await API.obj("DELETE", "/backup/\(name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name)")
                deleted += 1
            }
        }
        await app.guarded { backups = try await API.obj("GET", "/backup").list("backups") }
        sel = []
        busy = false
        if deleted > 0 { app.notify("Deleted \(deleted) backup\(deleted == 1 ? "" : "s").") }
    }

    private func runNow() async {
        busy = true
        await app.guarded {
            _ = try await API.obj("PUT", "/backup/config", body: ["dir": dir.trimmingCharacters(in: .whitespaces)])
            let r = try await API.obj("POST", "/backup/run", body: [:])
            app.notify("Backup complete: \(r.str("folder"))")
            fill(try await API.obj("GET", "/backup"))
        }
        busy = false
    }
}

/// "FAILED 2026-10-27T11:13:00.000Z: reason" -> the time part in Indian format.
func istStatus(_ s: String) -> String {
    guard s.hasPrefix("FAILED ") else { return s }
    let body = String(s.dropFirst(7))
    guard let r = body.range(of: "Z: ") else { return s }
    let stamp = String(body[..<r.lowerBound]) + "Z"
    let rest = String(body[r.upperBound...])
    return "FAILED " + Fmt.ist(stamp) + ": " + rest
}

/// Label like "2027-28" for a financial year starting in April of `start`.
func fyLabelFor(_ start: Int) -> String { "\(start)-" + String(String(start + 1).suffix(2)) }

/// Settings › Billing & Dashboard: what a new bill starts with, and what the dashboard shows.
@MainActor struct BillingDashboardSettings: View {
    @EnvironmentObject private var app: AppModel
    static let sections: [(key: String, title: String)] = [
        ("alerts", "Alerts (bills to print, low stock, expiry)"), ("charts", "Month-by-month chart"), ("daily", "Last 14 days chart"),
        ("items", "Best sellers"), ("dues", "Top dues"), ("low", "Low stock list"), ("recent", "Latest bills"),
    ]

    static let series: [(key: String, title: String)] = [("INV", "Sale bill"), ("RCT", "Receipt"), ("PUR", "Purchase"), ("PAY", "Payment"), ("DN", "Debit note")]
    @AppStorage("startPage") private var startPage = "billing"

    private func flag(_ k: String, _ dflt: Bool) -> Binding<Bool> {
        Binding(get: { app.settings.str(k).isEmpty ? dflt : app.settings.str(k) != "0" }, set: { v in Task { await app.saveSettings([k: v ? "1" : "0"]) } })
    }

    private func setting(_ k: String, _ dflt: String) -> Binding<String> {
        Binding(get: { app.settings.str(k).isEmpty ? dflt : app.settings.str(k) }, set: { v in Task { await app.saveSettings([k: v]) } })
    }

    private func shown(_ key: String) -> Binding<Bool> {
        Binding(get: { !app.dashboardHidden.contains(key) }, set: { on in
            var h = app.dashboardHidden
            if on { h.remove(key) } else { h.insert(key) }
            let v = Self.sections.map { $0.key }.filter { h.contains($0) }.joined(separator: ",")
            Task { await app.saveSettings(["dash_hide": v]) }
        })
    }

    var body: some View {
        Form {
            Section {
                Picker("Payment on a new bill", selection: setting("bill_pay_mode", "CREDIT")) {
                    Text("Credit").tag("CREDIT"); Text("Cash").tag("CASH"); Text("UPI").tag("UPI"); Text("Card").tag("CARD")
                }
                Picker("Sale type on a new bill", selection: setting("bill_sale_type", "COUNTER")) {
                    Text("Counter").tag("COUNTER"); Text("Van sale").tag("VAN")
                }
                Toggle("Round the bill total to the rupee", isOn: Binding(get: { app.settings.str("bill_round") != "0" }, set: { v in Task { await app.saveSettings(["bill_round": v ? "1" : "0"]) } }))
                SettingNumberField(title: "Discount % on every new line", key: "bill_default_disc", placeholder: "0")
                SettingNumberField(title: "GST % for new items", key: "item_default_gst", placeholder: "18")
                Picker("A new line starts as", selection: setting("bill_new_unit", "box")) { Text("One box").tag("box"); Text("One piece").tag("piece") }
                Toggle("Keep the party for the next bill", isOn: flag("bill_keep_party", false))
                Toggle("Ask before billing over a credit limit", isOn: flag("bill_credit_check", true))
            } header: { Text("Billing") } footer: { Text("Each bill can still be changed before saving. What happens after saving (print now or later) is under Printing.") }
            Section {
                Picker("Dashboard opens on", selection: setting("dash_period", "month")) {
                    Text("Today").tag("today"); Text("This month").tag("month"); Text("Whole year").tag("year")
                }
                ForEach(Self.sections, id: \.key) { s in Toggle(s.title, isOn: shown(s.key)) }
                Picker("Open BillBox on", selection: $startPage) { Text("Billing").tag("billing"); Text("Dashboard").tag("dashboard"); Text("All Bills").tag("bills"); Text("Stock").tag("stock"); Text("Parties").tag("parties") }
            } header: { Text("Dashboard") }
            NumberingSections()
        }
        .groupedForm()
    }
}

/// A number setting saved when editing ends (or on Return).
@MainActor struct SettingNumberField: View {
    @EnvironmentObject private var app: AppModel
    let title: String
    let key: String
    var placeholder = ""
    var range: ClosedRange<Double> = 0...100
    @State private var text = ""
    @State private var loaded = false

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("", text: $text, prompt: Text(placeholder))
                .multilineTextAlignment(.trailing).frame(maxWidth: 90)
                .onSubmit { save() }
            Button("Save") { save() }.buttonStyle(.borderless).disabled(text == app.settings.str(key))
        }
        .onAppear { if !loaded { text = app.settings.str(key); loaded = true } }
    }

    private func save() {
        let t = text.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty, Double(t) == nil || !range.contains(Double(t)!) { app.notify("\(title): enter a number from \(Fmt.qty(range.lowerBound)) to \(Fmt.qty(range.upperBound)).", error: true); return }
        Task { await app.saveSettings([key: t]); app.notify("Saved.") }
    }
}

/// A short text setting saved when editing ends (or on Return).
@MainActor struct SettingTextField: View {
    @EnvironmentObject private var app: AppModel
    let title: String
    let key: String
    var placeholder = ""
    var maxLength = 40
    @State private var text = ""
    @State private var loaded = false

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("", text: $text, prompt: Text(placeholder)).multilineTextAlignment(.trailing).frame(maxWidth: 140).onSubmit { save() }
            Button("Save") { save() }.buttonStyle(.borderless).disabled(text == app.settings.str(key))
        }
        .onAppear { if !loaded { text = app.settings.str(key); loaded = true } }
    }

    private func save() {
        let t = String(text.trimmingCharacters(in: .whitespaces).prefix(maxLength))
        text = t
        Task { await app.saveSettings([key: t]); app.notify("Saved.") }
    }
}

/// Settings › Parties & Payments: what new customers start with, and how payments are recorded.
@MainActor struct PartiesPaymentsSettings: View {
    @EnvironmentObject private var app: AppModel
    @AppStorage("showPhotoCard") private var showPhotoCard = true

    private func setting(_ k: String, _ dflt: String) -> Binding<String> {
        Binding(get: { app.settings.str(k).isEmpty ? dflt : app.settings.str(k) }, set: { v in Task { await app.saveSettings([k: v]) } })
    }

    var body: some View {
        Form {
            Section {
                Picker("Price tier", selection: setting("party_default_tier", "RETAIL")) {
                    Text("Retail price").tag("RETAIL"); Text("Wholesale price").tag("WHOLESALE"); Text("MRP").tag("MRP")
                }
                SettingNumberField(title: "Credit limit (0 = no limit)", key: "party_default_limit", placeholder: "0", range: 0...100_000_000)
                SettingNumberField(title: "Credit days", key: "party_default_days", placeholder: "0", range: 0...365)
            } header: { Text("New customers start with") }
            Section {
                Picker("Payment mode", selection: setting("pay_default_mode", "CASH")) {
                    Text("Cash").tag("CASH"); Text("UPI").tag("UPI"); Text("Cheque").tag("CHEQUE"); Text("Bank transfer").tag("BANK"); Text("Card").tag("CARD")
                }
                Toggle("Print the receipt after saving a payment", isOn: Binding(get: { app.settings.str("voucher_print") != "0" }, set: { v in Task { await app.saveSettings(["voucher_print": v ? "1" : "0"]) } }))
                Toggle("Show “Payments from a photo” on Parties", isOn: $showPhotoCard)
            } header: { Text("Payments") }
        }
        .groupedForm()
    }
}
