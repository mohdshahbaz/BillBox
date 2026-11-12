import SwiftUI

// Settings shared by the Mac and the iPhone (the same file is in both apps): more ways to shape the printed bill, and the
// bill numbering with Marg's pattern, the last number used and where the count carries on.

/// Settings › Printing: what else the bill shows, its size, a third copy, and lines of your own. Saved as you change them.
@MainActor struct PrintOptionsSections: View {
    @EnvironmentObject private var app: AppModel

    private func flag(_ k: String, _ dflt: Bool) -> Binding<Bool> {
        Binding(get: { app.settings.str(k).isEmpty ? dflt : app.settings.str(k) != "0" }, set: { v in Task { await app.saveSettings([k: v ? "1" : "0"]) } })
    }
    private func choice(_ k: String, _ dflt: String) -> Binding<String> {
        Binding(get: { app.settings.str(k).isEmpty ? dflt : app.settings.str(k) }, set: { v in Task { await app.saveSettings([k: v]) } })
    }

    /// One Marg-design column on or off (print_marg_cols lists the ones that are on).
    private func margCol(_ key: String) -> Binding<Bool> {
        Binding(get: { margShown(app.settings).contains(key) }, set: { v in
            var on = margShown(app.settings)
            if v { on.insert(key) } else { on.remove(key) }
            let list = margOptionalColumns.map(\.key).filter { on.contains($0) }.joined(separator: ",")
            Task { await app.saveSettings(["print_marg_cols": list.isEmpty ? "none" : list]) }
        })
    }

    private var isMarg: Bool { printStyle(app.settings) != "classic" }

    var body: some View {
        Section {
            Picker("Bill design", selection: choice("print_style", "classic")) {
                ForEach(billDesigns, id: \.key) { Text($0.title).tag($0.key) }
            }
            Button { Task { await previewLatest() } } label: { Label("Preview on my latest bill", systemImage: "eye") }
        } header: { Text("Bill design") } footer: {
            Text("Every design uses the paper layout, copies, text size and everything else on this page. Marg, Busy and Bizom styles share the choices below (colour, typeface, columns…).")
        }
        if !isMarg {
            Section {
                Picker("Typeface", selection: choice("print_marg_font", "serif")) { Text("Classic serif (like Marg)").tag("serif"); Text("Modern").tag("sans") }
                Toggle("“M/s” before the party's name", isOn: flag("print_marg_ms", true))
            } header: { Text("BillBox design") } footer: {
                Text("Bill to prints as on a Marg bill; the tax summary is HSN-wise, with Total GST (or IGST for another state).")
            }
        }
        if isMarg {
            Section {
                Picker("Colour", selection: choice("print_marg_colour", "blue")) { ForEach(margColours, id: \.key) { Text($0.title).tag($0.key) } }
                Picker("Typeface", selection: choice("print_marg_font", printStyle(app.settings) == "marg" ? "serif" : "sans")) { Text("Classic serif (like Marg)").tag("serif"); Text("Modern").tag("sans") }
                Picker("Rate and MRP per", selection: choice("print_marg_rate", "box")) { Text("Box (like Marg)").tag("box"); Text("Piece").tag("pcs") }
                Picker("GST classes at the bottom", selection: choice("print_marg_classes", "all")) {
                    Text("5, 12, 18 and 28 always (like Marg)").tag("all"); Text("Only the rates on the bill").tag("used")
                }
                ForEach(margOptionalColumns, id: \.key) { c in Toggle("\(c.title) column", isOn: margCol(c.key)) }
                Group {
                Toggle("“M/s” before the party's name", isOn: flag("print_marg_ms", true))
                Toggle("Due date on credit bills (party's credit days)", isOn: flag("print_marg_due", true))
                Toggle("Receiver's signature box", isOn: flag("print_marg_receiver", true))
                Toggle("Page number", isOn: flag("print_marg_page", true))
                Toggle("Company e-mail", isOn: flag("print_marg_email", false))
                if app.settings.str("print_marg_email") == "1" {
                    SettingTextField(title: "E-mail", key: "company_email", placeholder: "you@example.com", maxLength: 80)
                }
                }
            } header: { Text(printStyle(app.settings) == "busy" ? "Busy style" : printStyle(app.settings) == "bizom" ? "Bizom style" : "Marg style") } footer: {
                Text("Title: “Bill title” on this page (blank = GST INVOICE). A bill to another state shows IGST instead of SGST and CGST. “Black only” suits printers without colour.")
            }
        }
        Section {
            Toggle("Party's address, GSTIN and phone", isOn: flag("print_party", true))
            Toggle("Salesman", isOn: flag("print_salesman", true))
            Toggle("Payment mode and sale type", isOn: flag("print_payment", true))
            Toggle("GST rate-wise table", isOn: flag("print_gst_table", true))
            Toggle("Terms", isOn: flag("print_terms", true))
            Toggle("Party's previous balance and total due", isOn: flag("print_balance", false))
            Toggle("Item names in CAPITALS", isOn: flag("print_caps", false))
            Toggle("Company and Bill to in CAPITALS", isOn: flag("print_caps_head", false))
            Picker("Quantity as", selection: choice("print_qty", "boxpcs")) {
                Text("Boxes and pieces (6 box 6 pcs)").tag("boxpcs"); Text("Pieces only (150 pcs)").tag("pcs")
            }
        } header: { Text("More on the bill") } footer: {
            Text("Previous balance prints “Previous balance · This bill · Now due” above the amount in words, from the party's ledger.")
        }
        Section {
            Picker("Text size", selection: choice("print_font", "normal")) {
                Text("Smaller (more rows on a page)").tag("small"); Text("Normal").tag("normal"); Text("Larger (easier to read)").tag("large")
            }
            Toggle("Print ORIGINAL / DUPLICATE on each copy", isOn: flag("print_copy_label", true))
            Toggle("Print a third copy", isOn: flag("print_triplicate", false))
            if app.settings.str("print_triplicate") == "1" {
                SettingTextField(title: "Third copy label", key: "print_copy3", placeholder: "TRIPLICATE FOR ASSESSEE", maxLength: 40)
            }
        } header: { Text("Size and copies") } footer: {
            Text("The third copy is printed by the half-sheet and full-A4 layouts (two-on-A4 keeps its two copies).")
        }
        Section {
            SettingTextField(title: "Line under the company name", key: "print_tagline", placeholder: "e.g. Distributor of Parle, Bikano", maxLength: 80)
            SettingTextField(title: "Payment line at the bottom", key: "print_bank", placeholder: "e.g. UPI ak@upi", maxLength: 120)
            SettingTextField(title: "Note at the bottom", key: "print_note", placeholder: "e.g. Thank you for your business", maxLength: 60)
        } header: { Text("Your own lines") } footer: { Text("Leave a line empty to leave it off the bill. These are saved as you press Save beside each.") }
        Section {
            Toggle("Print the bank details", isOn: flag("print_bank_block", true))
            Toggle("Compact totals (more item rows on each page)", isOn: flag("print_compact", true))
            Picker("GST in the totals", selection: choice("print_gst_lines", "split")) {
                Text("CGST and SGST").tag("split"); Text("One line per rate (GST @5%)").tag("rate")
            }
            Picker("Bank details size", selection: choice("print_bank_size", "m")) {
                Text("Small").tag("s"); Text("Normal").tag("m"); Text("Large").tag("l"); Text("Extra large").tag("xl")
            }
            ForEach(bankFields, id: \.key) { f in
                SettingTextField(title: f.title, key: f.key, placeholder: f.key == "bank_address" ? "Branch address" : "", maxLength: f.key == "bank_address" ? 200 : 60)
            }
        } header: { Text("Bank details") } footer: {
            Text("Printed in three short lines (Bank · A/c name / A/c no. · IFSC / Branch · address) where the bill has room anyway: in the footer. Empty ones are left out. Bank details size: the details print right beside “Amount in words”; a bigger size gives them more width and larger text (and “Amount in words” less width). Compact totals: the totals and GST table take only the height they need, the Marg style shows only the bill's GST classes (unless “all” is chosen) and its bank details move to the footer, so more item rows fit on each page. GST in the totals: one line per rate prints “GST @5%” (or “IGST @5%”) with the tax of that rate, instead of separate CGST and SGST lines.")
        }
    }
}

extension PrintOptionsSections {
    /// Prints nothing: opens the newest sale bill in the print preview, in the design chosen now.
    func previewLatest() async {
        await app.guarded {
            let r = try await API.obj("GET", "/bills", query: ["type": "SALE", "from": "2000-01-01", "to": "2100-12-31"])
            guard let id = r.list("rows").first?.int("id") else { app.notify("There is no sale bill yet to show.", error: true); return }
            await printInvoice(id, app: app, forcePreview: true)
        }
    }
}

/// Settings › Billing & Dashboard › Numbering: prefix and digits for each series, the year in the number or not, the last
/// number used and the next one (it carries on after the last bill, Marg's imported bills included), and Marg's pattern.
@MainActor struct NumberingSections: View {
    @EnvironmentObject private var app: AppModel
    @State private var rows: [JSON] = []
    @State private var next: [String: String] = [:]
    static let series: [(key: String, title: String)] = [("INV", "Sale bill"), ("RCT", "Receipt"), ("PUR", "Purchase"), ("PAY", "Payment"), ("DN", "Debit note")]

    private func flag(_ k: String, _ dflt: Bool) -> Binding<Bool> {
        Binding(get: { app.settings.str(k).isEmpty ? dflt : app.settings.str(k) != "0" }, set: { v in Task { await app.saveSettings([k: v ? "1" : "0"]); await load() } })
    }
    private func choice(_ k: String, _ dflt: String) -> Binding<String> {
        Binding(get: { app.settings.str(k).isEmpty ? dflt : app.settings.str(k) }, set: { v in Task { await app.saveSettings([k: v]); await load() } })
    }

    var body: some View {
        // one stable group carries the loading, so the form is not rebuilt each time a section is redrawn
        Group { content }
            .onChange(of: app.settings) { _ in Task { await load() } }
            .task { await load() }
    }

    @ViewBuilder private var content: some View {
        Section {
            Button { Task { await useMarg() } } label: { Label("Use Marg's numbering (A000001, P000001, DNB00001)", systemImage: "number") }
            Toggle("Put the financial year in the number", isOn: flag("num_fy", true))
            Picker("Digits (series without their own)", selection: choice("num_digits", "5")) { ForEach(["3", "4", "5", "6"], id: \.self) { Text($0).tag($0) } }
        } header: { Text("Numbering") } footer: {
            Text("A new number always carries on after the highest one already used with the same prefix — including bills imported from Marg — so numbers never clash. After a Marg import BillBox takes Marg's pattern by itself, unless you chose your own numbering here first.")
        }
        ForEach(Self.series, id: \.key) { x in
            let r = rows.first { $0.str("series") == x.key }
            Section {
                SettingTextField(title: "Prefix", key: "num_\(x.key)_prefix", placeholder: x.key, maxLength: 8)
                Picker("Digits", selection: choice("num_\(x.key)_digits", "")) {
                    Text("Same as above").tag("")
                    ForEach(["3", "4", "5", "6", "7", "8"], id: \.self) { Text($0).tag($0) }
                }
                if let r {
                    HStack { Text("Last used"); Spacer(); Text(r.str("last_no").isEmpty ? "none yet" : r.str("last_no")).mono().foregroundStyle(.secondary) }
                    HStack {
                        Text("Next")
                        Spacer()
                        Text(r.str("next_no")).mono().fw(.semibold)
                    }
                    HStack {
                        TextField("Start the next one at (number)", text: Binding(get: { next[x.key] ?? "" }, set: { next[x.key] = $0 }))
                        Button("Set") { Task { await setNext(x.key) } }.disabled((next[x.key] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            } header: { Text(x.title) }
        }
    }

    private func load() async {
        await app.guarded { rows = try await API.obj("GET", "/numbering").list("series") }
    }

    private func setNext(_ s: String) async {
        let v = (next[s] ?? "").trimmingCharacters(in: .whitespaces)
        await app.guarded {
            let r = try await API.objRaw("PUT", "/numbering", body: ["series": s, "next": v])
            next[s] = ""
            app.notify("The next one will be \(r.str("next_no")).")
            await load()
        }
    }

    private func useMarg() async {
        await app.saveSettings(["num_fy": "0", "num_INV_prefix": "A", "num_INV_digits": "6", "num_PUR_prefix": "P", "num_PUR_digits": "6",
                                "num_DN_prefix": "DNB", "num_DN_digits": "5"])
        await load()
        if let r = rows.first(where: { $0.str("series") == "INV" }) { app.notify("Marg numbering on: the next sale bill is \(r.str("next_no")).") }
    }
}
