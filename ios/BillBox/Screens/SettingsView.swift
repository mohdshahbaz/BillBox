import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The Mac's six settings tabs become a list of sections, each opening its own page.
@MainActor struct SettingsView: View {
    /// (key, title, symbol, colour) of each Settings page
    static let pages: [(key: String, title: String, symbol: String, color: Color)] = [
        ("appearance", "Appearance", "paintpalette", .pink), ("companies", "Companies", "building.2", .blue), ("printing", "Printing", "printer", .gray),
        ("whatsapp", "WhatsApp", "message", .green), ("billing", "Billing & Dashboard", "gauge.with.dots.needle.33percent", .orange),
        ("parties", "Parties & Payments", "person.2.fill", .purple), ("stock", "Stock", "archivebox", .brown), ("backup", "Backup", "externaldrive", .teal),
        ("marg", "Import from Marg ERP", "square.and.arrow.down.on.square", .indigo), ("licence", "Licence", "key.fill", .yellow),
    ]

    var body: some View {
        List {
            BackupSafetyRow()
            // value links: the open page is part of the More tab's path, so redrawing (a theme change, Save) keeps it open
            ForEach(SettingsView.pages, id: \.key) { p in
                NavigationLink(value: MoreRoute.settings(p.key)) { SettingsRow(title: p.title, symbol: p.symbol, color: p.color) }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder static func page(_ key: String) -> some View {
        switch key {
        case "appearance": AppearanceSettings().navigationTitle("Appearance").navigationBarTitleDisplayMode(.inline)
        case "companies": CompanySettings()
        case "printing": PrintSettings()
        case "whatsapp": WhatsAppSettings().navigationTitle("WhatsApp").navigationBarTitleDisplayMode(.inline)
        case "billing": BillingDashboardSettings().navigationTitle("Billing & Dashboard").navigationBarTitleDisplayMode(.inline)
        case "parties": PartiesPaymentsSettings().navigationTitle("Parties & Payments").navigationBarTitleDisplayMode(.inline)
        case "stock": StockSettings()
        case "backup": BackupSettings()
        case "licence": LicenseSettings().navigationBarTitleDisplayMode(.inline)
        default: MargImportView().navigationTitle("Import from Marg ERP").navigationBarTitleDisplayMode(.inline)
        }
    }
}

@MainActor struct CompanySettings: View {
    @EnvironmentObject private var app: AppModel
    @State private var editing: JSON?
    @State private var creating = false
    @State private var deleting: JSON?
    @State private var yearStart = AppModel.currentFYStart + 1

    var body: some View {
        List {
            Section {
                ForEach(app.companies) { c in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.str("name") + (c.str("fy").isEmpty ? "" : "  · FY \(c.str("fy")) file")).fw(.medium)
                            Text([c.str("company_gstin"), c.str("company_address")].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if c.id == app.companyId { Label("Open", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption) }
                        else { Button("Open") { Task { await app.switchCompany(c.id) } }.buttonStyle(.bordered) }
                        Button("Edit…") { editing = c }.buttonStyle(.bordered)
                        Button(role: .destructive) { deleting = c } label: { Image(systemName: "trash") }.buttonStyle(.bordered)
                    }
                }
            } footer: {
                Text("Each company has its own books (stock, parties, bills). Switch company from the company menu at the top left.")
            }
            Section { Button { creating = true } label: { Label("New company…", systemImage: "plus") } }
            Section {
                Picker("Financial year", selection: $yearStart) {
                    ForEach((AppModel.currentFYStart - 6)...(AppModel.currentFYStart + 1), id: \.self) { Text("FY " + fyLabelFor($0)).tag($0) }
                }
                Button { Task { await app.addYearBooks(fy: fyLabelFor(yearStart), carry: true) } } label: {
                    Label("Start FY \(fyLabelFor(yearStart)) as its own file, carrying forward", systemImage: "arrow.right.doc.on.clipboard")
                }
                Button { Task { await app.addYearBooks(fy: fyLabelFor(yearStart), carry: false) } } label: {
                    Label("Add FY \(fyLabelFor(yearStart)) as an empty file (for Marg data)", systemImage: "doc.badge.plus")
                }
            } header: { Text("Financial years of \(app.companyName)") } footer: {
                Text("Like Marg, each year can be kept in its own file. “Carrying forward” copies items, parties, schemes, stock in hand and closing balances into the new year’s opening balances. An empty file is for an earlier year: open it, then Settings › Import from Marg ERP brings that year’s Marg data in. Switch years from the menu at the top left; years with their own file open that file.")
            }
        }
        .navigationTitle("Companies")
        .navigationBarTitleDisplayMode(.inline)
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
            Field("Company / business name", text: b("name")).textInputAutocapitalization(.words)
            Field("GSTIN (blank if unregistered)", text: b("company_gstin")).textInputAutocapitalization(.characters).autocorrectionDisabled()
            Field("State code (09 = Uttar Pradesh, 07 = Delhi)", text: b("state_code", "09")).keyboardType(.numberPad)
            Field("Address", text: b("company_address"), axis: .vertical)
            Field("Phone", text: b("company_phone")).keyboardType(.phonePad)
            Field("Terms printed on invoices", text: b("invoice_terms", "Goods once sold will not be taken back."), axis: .vertical)
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
    @State private var printerURL: URL?
    @State private var printerName = ""
    @State private var auto = false
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                Picker("Invoice layout", selection: $layout) {
                    ForEach(PrintLayout.allCases) { Text($0.label).tag($0) }
                }
            }
            Section {
                Picker("After saving a bill", selection: $afterSave) {
                    Text("Print it now").tag("print"); Text("Ask: print now or later").tag("ask"); Text("Keep it to print later").tag("later")
                }
                Field("Bill title (blank = TAX INVOICE; GST INVOICE in Marg style)", text: $title)
                ForEach(optionalColumns, id: \.key) { c in
                    Toggle("Print the \(c.title) column", isOn: Binding(get: { !hidden.contains(c.key) }, set: { on in if on { hidden.remove(c.key) } else { hidden.insert(c.key) } }))
                }
                Toggle("Print the amount in words", isOn: $words)
                Toggle("Print \u{201C}For company / Authorised Signatory\u{201D}", isOn: $signature)
                Field("First copy label (blank = ORIGINAL FOR RECIPIENT)", text: $copy1)
                Field("Second copy label (blank = DUPLICATE FOR TRANSPORTER/SUPPLIER)", text: $copy2)
            } header: { Text("What the bill shows") } footer: {
                Text("“Keep it to print later”: saved bills wait under All Bills › Not printed; select them and print them together.")
            }
            PrintOptionsSections()
            Section {
                // iOS has no list of installed printers: the AirPrint picker chooses one and this iPhone remembers it (decision D7)
                HStack {
                    Text("Printer")
                    Spacer()
                    Text(printerURL == nil ? "Ask every time" : printerName).foregroundStyle(.secondary).lineLimit(1)
                }
                Button(printerURL == nil ? "Choose printer…" : "Change printer…") { pickPrinter() }
                if printerURL != nil {
                    Button("Ask every time") { printerURL = nil; printerName = ""; auto = false }
                }
                Toggle("Print straight to this printer after saving a bill (no preview)", isOn: $auto)
                    .disabled(printerURL == nil)
            } footer: {
                Text("“Half sheets”: cut A4 sheets in two (or use A5) and load them in the printer’s tray; BillBox asks the printer for A5 paper and prints the Original on one sheet and the Duplicate on the next, across the sheet. If your printer has no A5 setting, choose A5 (or 148 x 210 mm) in its print panel once. “Original on top, Duplicate below” fits both copies on one uncut A4 sheet. “Full A4 page” prints each copy on its own A4 sheet, with room for many more item rows.")
            }
            Section {
                Button("Save") { Task { await save() } }.frame(maxWidth: .infinity).buttonStyle(.borderedProminent)
                    .keyboardShortcut("s", modifiers: .command)
            }
            .listRowBackground(Color.clear)
        }
        .groupedForm()
        .navigationTitle("Printing")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            layout = PrintLayout.parse(app.settings.str("print_layout"))
            afterSave = app.settings.str("bill_after_save").isEmpty ? "print" : app.settings.str("bill_after_save")
            title = app.settings.str("print_title")
            hidden = Set(app.settings.str("print_hide_cols").split(separator: ",").map(String.init))
            words = app.settings.str("print_words") != "0"
            signature = app.settings.str("print_signature") != "0"
            copy1 = app.settings.str("print_copy1")
            copy2 = app.settings.str("print_copy2")
            printerURL = DevicePrinter.url
            printerName = DevicePrinter.name
            auto = DevicePrinter.auto
        }
    }

    private func pickPrinter() {
        let picker = UIPrinterPickerController(initiallySelectedPrinter: printerURL.map { UIPrinter(url: $0) })
        let done: UIPrinterPickerController.CompletionHandler = { c, picked, _ in
            guard picked, let p = c.selectedPrinter else { return }
            printerURL = p.url
            printerName = p.displayName
        }
        if UIDevice.current.userInterfaceIdiom == .pad, let top = Files.topController() {
            picker.present(from: CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1), in: top.view, animated: true, completionHandler: done)
        } else {
            picker.present(animated: true, completionHandler: done)
        }
    }

    private func save() async {
        // the layout belongs to the company's books, as on the Mac; the printer stays on this iPhone and the Mac's printer name is left untouched
        DevicePrinter.url = printerURL
        DevicePrinter.name = printerName
        DevicePrinter.auto = auto && printerURL != nil
        await app.saveSettings(["print_layout": layout.rawValue, "bill_after_save": afterSave, "print_title": title.trimmingCharacters(in: .whitespaces),
                                "print_hide_cols": optionalColumns.map(\.key).filter { hidden.contains($0) }.joined(separator: ","),
                                "print_words": words ? "1" : "0", "print_signature": signature ? "1" : "0",
                                "print_copy1": copy1.trimmingCharacters(in: .whitespaces), "print_copy2": copy2.trimmingCharacters(in: .whitespaces)])
        app.notify("Print settings saved.")
    }
}

@MainActor struct StockSettings: View {
    @EnvironmentObject private var app: AppModel
    @State private var low = ""
    @State private var loaded = false

    var body: some View {
        Form {
            Field("Low-stock warning at or below (pieces)", text: $low).keyboardType(.decimalPad)
            SettingNumberField(title: "Warn about expiry this many days ahead", key: "expiry_days", placeholder: "30", range: 1...365)
            Section {
                Button("Save") {
                    Task { await app.saveSettings(["low_stock_qty": low.trimmingCharacters(in: .whitespaces)]); app.notify("Saved.") }
                }
                .frame(maxWidth: .infinity).buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: .command)
            }
            .listRowBackground(Color.clear)
        }
        .groupedForm()
        .navigationTitle("Stock")
        .navigationBarTitleDisplayMode(.inline)
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
    @State private var selecting = false

    @State private var restoreTarget: RestoreTarget?
    @State private var deleteNames: [String] = []

    private struct RestoreTarget { var name: String?; var folder: String?; var file: String?; var label: String }

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
        List {
            settingsSection
            DriveBackupSection(onRestore: { n in Task { await load() }; restoreTarget = RestoreTarget(name: n, label: n) })
            restoreSection
            backupsSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Backup")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .confirmationDialog(restoreTarget.map { "Restore \($0.label)?" } ?? "", isPresented: Binding(get: { restoreTarget != nil }, set: { if !$0 { restoreTarget = nil } }), titleVisibility: .visible) {
            Button("Replace", role: .destructive) { if let t = restoreTarget { Task { await restore(t, mode: "replace") } } }
            Button("Merge") { if let t = restoreTarget { Task { await restore(t, mode: "merge") } } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text((restoreTarget?.file != nil ? "This goes into the company that file belongs to (matched by name). " : "Each company goes into the company with the same name here (it is created if missing). ")
                 + "\n\nReplace: the current books of that company are replaced by the backup.\nMerge: only what is missing is added from the backup (parties, items, bills, receipts and so on); nothing that already exists is changed or removed.\n\nA safety backup of the current data is made first either way.")
        }
        .confirmationDialog(deleteNames.count == 1 ? "Delete backup \(deleteNames[0])?" : "Delete \(deleteNames.count) selected backups?",
                            isPresented: Binding(get: { !deleteNames.isEmpty }, set: { if !$0 { deleteNames = [] } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) { let n = deleteNames; Task { await deleteBackups(n) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteNames.count == 1 ? "The backup folder is removed for good. Your current books are not affected."
                 : "The backup folders are removed for good. Your current books are not affected.")
        }
    }

    /// Inside BillBox's own folder the backups go when BillBox is deleted (iOS removes an app's folder with the app).
    private var insideApp: Bool { !dir.isEmpty && dir.hasPrefix(NSHomeDirectory()) }

    private var settingsSection: some View {
        Section {
            if insideApp {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Deleting BillBox deletes these backups", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.callout.weight(.semibold))
                    Text("iPhone removes an app's own folder together with the app. Choose a folder in iCloud Drive, or make one in Files › On My iPhone (outside BillBox): backups there stay when BillBox is deleted, and “Restore from a backup folder or .zip…” reads them after installing again.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button { Task { await chooseFolder() } } label: { Label("Choose a safe folder…", systemImage: "icloud.and.arrow.up") }
                        .buttonStyle(.borderedProminent).disabled(busy)
                }
                .padding(.vertical, 4)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Backup folder").font(.subheadline).foregroundStyle(.secondary)
                Text(folderName).font(.callout.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                Text(dir).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            Button { Task { await chooseFolder() } } label: { Label("Choose another folder…", systemImage: "folder.badge.gearshape") }
                .disabled(busy)
            if !isDefaultFolder {
                Button { Task { await setFolder(EngineHost.defaultBackupFolder, label: "BillBox's own folder") } } label: {
                    Label("Use BillBox's own folder on this iPhone", systemImage: "iphone")
                }
                .disabled(busy)
            }
            Toggle("Back up automatically every day while the app is open", isOn: $enabled)
            // iOS has no quit: this runs each time BillBox goes to the background (decision D2)
            Toggle("Also back up whenever I quit the app", isOn: $onExit)
            DatePicker("Time", selection: timeDate, displayedComponents: .hourAndMinute)
            if !lastRun.isEmpty {
                Text("Last backup: \(Fmt.ist(lastRun)) · \(istStatus(lastStatus))").font(.caption).foregroundStyle(.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack { saveButton; Spacer(); runButton }
                VStack(alignment: .leading, spacing: 8) { saveButton; runButton }
            }
        } footer: {
            Text("BillBox's own folder is in the Files app: On My iPhone › BillBox › DistributorProBackups. Another folder (iCloud Drive, a USB drive…) is used from the moment you choose it.\n\nEvery backup is kept for good; nothing is deleted automatically.\n\nOn iPhone, the daily backup runs while BillBox is open, when you open it, and when you return to it. When BillBox is closed, iOS decides when (or whether) it lets the backup run, so it can be late. Leaving the app counts as quitting.")
        }
    }

    private var saveButton: some View {
        Button("Save settings") { Task { await saveConfig() } }.buttonStyle(.bordered)
    }

    private var runButton: some View {
        Button { Task { await runNow() } } label: { Text(busy ? "Backing up…" : "Back up now") }
            .buttonStyle(.borderedProminent).disabled(busy)
    }

    private var restoreSection: some View {
        Section("Restore") {
            Button("Restore selected backup…") {
                if let b = backups.first(where: { sel.contains($0.id) }) { restoreTarget = RestoreTarget(name: b.str("name"), label: b.str("name")) }
            }
            .disabled(!backups.contains(where: { sel.contains($0.id) }))
            Button("Restore from a backup folder or .zip…") { Task { await restoreFromFiles(single: false) } }
            Button("Restore one company file (.db)…") { Task { await restoreFromFiles(single: true) } }
        }
        .disabled(busy)
    }

    private var backupsSection: some View {
        Section {
            SelectionBar(ids: backups.map(\.id), selection: $sel, selecting: $selecting, actionLabel: "Delete selected backups…", busy: busy) {
                deleteNames = backups.filter { sel.contains($0.id) }.map { $0.str("name") }
            }
            .listRowInsets(EdgeInsets())
            DataGrid(backups, layoutKey: "backups", selection: $sel, selecting: $selecting, onOpen: { b in sel = [b.id] }, menu: { b in
                AnyView(Group {
                    Button { restoreTarget = RestoreTarget(name: b.str("name"), label: b.str("name")) } label: { Label("Restore this backup…", systemImage: "arrow.counterclockwise") }
                    Button(role: .destructive) { deleteNames = [b.str("name")] } label: { Label("Delete this backup…", systemImage: "trash") }
                    if sel.count > 1 && sel.contains(b.id) {
                        Button(role: .destructive) { deleteNames = backups.filter { sel.contains($0.id) }.map { $0.str("name") } } label: { Label("Delete \(sel.count) selected…", systemImage: "trash") }
                    }
                })
            }) {
                GridColumn("Backup", id: "name", min: 200, ideal: 250) { (b: JSON) in
                    Text(b.str("name")).fontWeight(sel.contains(b.id) && !selecting ? .semibold : .regular)
                }
                GridColumn("Companies", id: "companies", min: 160, ideal: 220) { (b: JSON) in Text(b.strings("companies").joined(separator: ", ")).lineLimit(2) }
                GridColumn("Created", id: "created", min: 140, ideal: 170) { (b: JSON) in Text(Fmt.ist(b.str("created"))) }
                GridColumn("Company files", id: "files", min: 80, ideal: 100, align: .trailing) { (b: JSON) in Text(b.str("files")) }
                GridColumn("Size", id: "size", min: 80, ideal: 100, align: .trailing) { (b: JSON) in Text(ByteCountFormatter.string(fromByteCount: Int64(b.num("bytes")), countStyle: .file)) }
            }
            .frame(height: min(420, CGFloat(max(backups.count, 3)) * 40 + 60))
            .listRowInsets(EdgeInsets())
        } header: {
            Text("Backups")
        } footer: {
            Text("Each backup is a new folder named FMCG_Backup_YYYYMMDD_HHMMSS holding a verified copy of every company's database. Each company is restored into the company with the same name (it is created if it is missing); other companies are not touched. The files are checked first, and a safety backup of today's data is made before anything is replaced.")
        }
    }

    /// Inside BillBox's own Documents folder: shown the way the Files app shows it.
    private var isDefaultFolder: Bool { dir == EngineHost.defaultBackupFolder }
    private var folderName: String {
        let docs = (EngineHost.defaultBackupFolder as NSString).deletingLastPathComponent
        if dir.hasPrefix(docs + "/") || dir == docs {
            return "On My iPhone › BillBox" + dir.dropFirst(docs.count).replacingOccurrences(of: "/", with: " › ")
        }
        let parts = dir.split(separator: "/").suffix(2)
        return parts.joined(separator: " › ")
    }

    private func chooseFolder() async {
        guard let url = await Files.pick([.folder]) else { return }
        // keeps access to the folder across launches (decision D4)
        FolderAccess.remember(url)
        await setFolder(url.path, label: url.lastPathComponent)
    }

    /// The folder is used at once (no separate Save needed).
    private func setFolder(_ path: String, label: String) async {
        await app.guarded {
            _ = try await API.obj("PUT", "/backup/config", body: ["dir": path])
            fill(try await API.obj("GET", "/backup"))
            app.notify("Backups will be saved in “\(label)”.")
        }
    }

    /// Picks a backup folder, a .zip of one, or one company .db (from this iPhone, iCloud Drive, AirDrop / Downloads …).
    private func restoreFromFiles(single: Bool) async {
        let types: [UTType] = single ? [UTType(filenameExtension: "db") ?? .data, .data, .zip] : [.folder, .zip]
        guard let url = await Files.pick(types) else { return }
        busy = true
        defer { busy = false }
        do {
            let copy = try await Task.detached(priority: .userInitiated) { try Files.importPicked(url) }.value
            let found = Backup.locate(in: copy)
            if let folder = found.folder, !single {
                restoreTarget = RestoreTarget(folder: folder, label: url.lastPathComponent)
            } else if let file = found.file {
                restoreTarget = RestoreTarget(file: file, label: (file as NSString).lastPathComponent)
            } else if let folder = found.folder {
                restoreTarget = RestoreTarget(folder: folder, label: url.lastPathComponent)
            } else {
                app.notify("“\(url.lastPathComponent)” has no BillBox backup in it (no manifest.json and no company .db file).", error: true)
            }
        } catch {
            app.notify("Could not read “\(url.lastPathComponent)”: \(error.localizedDescription)", error: true)
        }
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
            BackupScheduler.scheduleBackground()
        }
    }

    private func restore(_ t: RestoreTarget, mode: String) async {
        busy = true
        await app.guarded {
            _ = try await API.obj("PUT", "/backup/config", body: ["dir": dir.trimmingCharacters(in: .whitespaces)])
            let r = try await API.obj("POST", "/backup/restore", body: ["name": t.name, "folder": t.folder, "file": t.file, "company_id": t.file != nil ? app.companyId : nil, "mode": mode])
            for f in [t.folder, t.file].compactMap({ $0 }) where f.hasPrefix(FileManager.default.temporaryDirectory.path) {
                try? FileManager.default.removeItem(atPath: f)   // the private copy of what was picked
            }
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

    private func deleteBackups(_ names: [String]) async {
        guard !names.isEmpty else { return }
        busy = true
        var deleted = 0
        for name in names {
            await app.guarded {
                _ = try await API.obj("DELETE", "/backup/\(API.seg(name))")
                deleted += 1
            }
        }
        await app.guarded { backups = try await API.obj("GET", "/backup").list("backups") }
        sel = []
        busy = false
        if names.count == 1 && deleted == 1 { app.notify("Deleted \(names[0]).") }
        else if deleted > 0 { app.notify("Deleted \(deleted) backup\(deleted == 1 ? "" : "s").") }
    }

    private func runNow() async {
        busy = true
        await app.guarded {
            _ = try await API.obj("PUT", "/backup/config", body: ["dir": dir.trimmingCharacters(in: .whitespaces)])
            let r = try await API.obj("POST", "/backup/run", body: [:])
            app.notify("Backup complete: \((r.str("folder") as NSString).lastPathComponent)")
            fill(try await API.obj("GET", "/backup"))
        }
        if let r = try? await API.obj("GET", "/backup") { fill(r) }   // shows the reason on the status line if it failed
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

/// A settings list row with a coloured icon tile, as in the iPhone's own Settings.
struct SettingsRow: View {
    let title: String
    let symbol: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 30, height: 30).background(Theme.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))   // the theme colour, like every icon
            Text(title)
        }
        .padding(.vertical, 2)
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


/// Settings' first row while backups are still inside BillBox's own folder (lost if BillBox is deleted).
@MainActor struct BackupSafetyRow: View {
    @State private var inside = false

    var body: some View {
        Group {
            if inside {
                NavigationLink { BackupSettings() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Backups are inside BillBox").font(.callout.weight(.semibold))
                            Text("Deleting the app deletes them. Choose a folder in iCloud Drive.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .task {
            if let r = try? await API.obj("GET", "/backup") {
                let d = r.obj("config").str("dir")
                inside = !d.isEmpty && d.hasPrefix(NSHomeDirectory())
            }
        }
    }
}
