import SwiftUI

@MainActor struct ReportsView: View {
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("Report", selection: $tab) {
                Text("Sales Book").tag(0); Text("Purchase Book").tag(1); Text("Debit Notes").tag(3); Text("GST Outward").tag(2)
            }
            .pickerStyle(.segmented).labelsHidden()
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            switch tab {
            case 0: BookView(type: "sales").id("sales")
            case 1: BookView(type: "purchase").id("purchase")
            case 3: BookView(type: "debit").id("debit")
            default: GstView()
            }
        }
        .background(Theme.page)
        .navigationTitle("Books & GST")
        .navigationBarTitleDisplayMode(.inline)
    }
}

@MainActor struct BookView: View {
    @EnvironmentObject private var app: AppModel
    let type: String
    @State private var from = ""
    @State private var to = ""
    @State private var data: JSON?

    private var sales: Bool { type == "sales" }

    var body: some View {
        let rows = data?.list("rows") ?? []
        let tot = data?.obj("totals") ?? JSON()
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                DateField(title: "From", iso: $from)
                DateField(title: "To", iso: $to)
                Spacer(minLength: 0)
                Button {
                    Files.copy(tsv(["Date", "No", "Supplier bill", "Party", "GSTIN", "Taxable", "CGST", "SGST", "IGST", "Round off", "Total"],
                                   rows.map { [Fmt.dmy($0.str("date")), $0.str("no"), $0.str("ref"), $0.str("party"), $0.str("gstin"), $0.str("taxable"), $0.str("cgst"), $0.str("sgst"), $0.str("igst"), $0.str("round_off"), $0.str("total")] }))
                    app.notify("Copied. Paste into Excel or Numbers.")
                } label: { Label("Copy", systemImage: "doc.on.doc").labelStyle(.iconOnly).font(.title3) }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            DataGrid(rows, layoutKey: "book-\(type)") {
                GridColumn("Date", id: "date", min: 122, ideal: 124) { (r: JSON) in Text(Fmt.dmy(r.str("date"))).mono() }
                GridColumn(sales ? "Invoice" : type == "debit" ? "Note no" : "Our ref", id: "no", min: 90, ideal: 120) { (r: JSON) in Text(r.str("no")).mono() }
                GridColumn(type == "debit" ? "Against bill" : "Supplier bill", id: "ref", min: 80, ideal: 110) { (r: JSON) in Text(r.str("ref")) }
                GridColumn("Party", id: "party", min: 140, ideal: 220) { (r: JSON) in Text(r.str("party")).lineLimit(2) }
                GridColumn("GSTIN", id: "gstin", min: 110, ideal: 150) { (r: JSON) in Text(r.str("gstin")).mono() }
                GridColumn("Taxable", id: "taxable", min: 90, ideal: 110, align: .trailing) { (r: JSON) in Text(Fmt.money(r, "taxable")).mono() }
                GridColumn("CGST", id: "cgst", min: 80, ideal: 100, align: .trailing) { (r: JSON) in Text(Fmt.money(r, "cgst")).mono() }
                GridColumn("SGST", id: "sgst", min: 80, ideal: 100, align: .trailing) { (r: JSON) in Text(Fmt.money(r, "sgst")).mono() }
                GridColumn("IGST", id: "igst", min: 80, ideal: 100, align: .trailing) { (r: JSON) in Text(Fmt.money(r, "igst")).mono() }
                GridColumn("Round off", id: "round", min: 70, ideal: 90, align: .trailing, sort: { (r: JSON) -> Any? in r.num("round_off") }) { (r: JSON) in Text(Fmt.money(r, "round_off")).mono() }
                GridColumn("Total", id: "total", min: 90, ideal: 110, align: .trailing) { (r: JSON) in Text(Fmt.money(r, "total")).mono().fw(.semibold) }
            }
            .overlay {
                if data == nil { ProgressView() }
                else if rows.isEmpty { EmptyState(title: "No entries in this period", symbol: "books.vertical") }
            }
            // totals wrap onto as many lines as the screen needs
            SummaryCard(items: [
                .init(label: "Entries", value: "\(tot.int("count"))"),
                .init(label: "Taxable", value: Fmt.money(tot, "taxable")),
                .init(label: "CGST", value: Fmt.money(tot, "cgst")),
                .init(label: "SGST", value: Fmt.money(tot, "sgst")),
                .init(label: "IGST", value: Fmt.money(tot, "igst")),
                .init(label: "Total", value: Fmt.money(tot, "total"), strong: true),
            ])
        }
        .task(id: "\(from)|\(to)") {
            if from.isEmpty {
                from = app.isCurrentFY ? app.monthStartInFY : app.fyFrom
                to = app.isCurrentFY ? app.dateInFY : app.fyTo
                return
            }
            await app.guarded { data = try await API.obj("GET", "/reports/book/\(type)", query: ["from": from, "to": to]) }
        }
    }
}

@MainActor struct GstView: View {
    @EnvironmentObject private var app: AppModel
    @State private var month = ""
    @State private var d: JSON?
    @State private var exporting = false

    private var title: String { "\(month.suffix(2))-\(month.prefix(4))" }

    private func shift(_ by: Int) {
        let y = Int(month.prefix(4)) ?? 2026, m = Int(month.suffix(2)) ?? 1
        let n = (y * 12 + (m - 1)) + by
        let next = String(format: "%04d-%02d", n / 12, n % 12 + 1)
        // stay inside the open financial year (April to March)
        if next >= String(app.fyFrom.prefix(7)) && next <= String(app.fyTo.prefix(7)) { month = next }
    }

    var body: some View {
        let rows = d?.list("rows") ?? []
        let tot = d?.obj("totals") ?? JSON()
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { monthStepper; exportButton; Spacer() }
                    VStack(alignment: .leading, spacing: 10) { monthStepper; exportButton }
                }
                if d == nil {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    DataGrid(rows + [JSON(["rate": "Total", "taxable": tot.num("taxable"), "cgst": tot.num("cgst"), "sgst": tot.num("sgst"), "igst": tot.num("igst"), "tax": tot.num("tax"), "value": tot.num("value"), "is_total": true], rid: 9999)], layoutKey: "gst-rates", numbered: false) {
                        GridColumn("GST rate", id: "rate", min: 70, ideal: 80) { (r: JSON) in Text(r.bool("is_total") ? "Total" : "\(r.str("rate"))%").fw(.semibold) }
                        GridColumn("Taxable value", id: "taxable", min: 100, ideal: 120, align: .trailing) { (r: JSON) in Text(Fmt.money(r, "taxable")).mono() }
                        GridColumn("CGST", id: "cgst", min: 90, ideal: 100, align: .trailing) { (r: JSON) in Text(Fmt.money(r, "cgst")).mono() }
                        GridColumn("SGST", id: "sgst", min: 90, ideal: 100, align: .trailing) { (r: JSON) in Text(Fmt.money(r, "sgst")).mono() }
                        GridColumn("IGST (CGST+SGST)", id: "igst", min: 120, ideal: 130, align: .trailing) { (r: JSON) in Text(Fmt.money(r, "igst")).mono() }
                        GridColumn("Total tax", id: "tax", min: 90, ideal: 100, align: .trailing) { (r: JSON) in Text(Fmt.money(r, "tax")).mono() }
                        GridColumn("Invoice value", id: "value", min: 100, ideal: 120, align: .trailing) { (r: JSON) in Text(Fmt.money(r, "value")).mono().fw(.semibold) }
                    }
                    .frame(height: CGFloat(rows.count + 1) * 36 + 50)
                    let x = d!
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                        StatCard(title: "Invoices in \(x.str("month"))", value: "\(x.int("invoices"))")
                        StatCard(title: "B2B (party has GSTIN)", value: Fmt.money(x.obj("b2b").num("taxable")), tint: .green)
                        StatCard(title: "B2C (no GSTIN)", value: Fmt.money(x.obj("b2c").num("taxable")), tint: .orange)
                        StatCard(title: x.obj("input_credit").num("debit_notes") > 0 ? "Input tax credit (purchases less \(Fmt.money(x.obj("input_credit").num("debit_notes"))) on debit notes)" : "Input tax credit (purchases)", value: Fmt.money(x.obj("input_credit").num("total")), tint: .green)
                        StatCard(title: x.num("net_payable") >= 0 ? "Net GST payable (estimate)" : "Credit carried forward", value: Fmt.money(abs(x.num("net_payable"))), tint: x.num("net_payable") >= 0 ? .red : .green)
                    }
                    Text("The Excel file has four sheets: Summary, B2B Bills, B2C Bills and Rate-wise Summary. Rates are taken from each invoice line. Round-off is excluded from taxable value. The net figure is an estimate; check it with your accountant.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(12)
        }
        .task(id: month) {
            if month.isEmpty { month = String(app.dateInFY.prefix(7)); return }
            d = nil
            await app.guarded { d = try await API.obj("GET", "/reports/gst-outward", query: ["month": month]) }
        }
    }

    private var monthStepper: some View {
        HStack(spacing: 10) {
            Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44) }
                .accessibilityLabel("Previous month")
                .keyboardShortcut(.leftArrow, modifiers: .command)
            Text(title).font(.title3.weight(.semibold)).mono().fixedSize()
            Button { shift(1) } label: { Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44) }
                .accessibilityLabel("Next month")
                .keyboardShortcut(.rightArrow, modifiers: .command)
        }
    }

    private var exportButton: some View {
        Button {
            Task {
                exporting = true
                await app.guarded {
                    let (bytes, _) = try await API.bytes("/reports/gst-outward.xlsx", query: ["month": month])
                    // the share sheet's "Save to Files" takes the place of the Mac's save panel
                    Files.save("GST-Outward-\(month).xlsx", data: bytes)
                }
                exporting = false
            }
        } label: { Label(exporting ? "Preparing…" : "Export month to Excel", systemImage: "tablecells") }
        .disabled(d == nil || exporting)
        .buttonStyle(.borderedProminent)
    }
}
