import SwiftUI
import PDFKit

/// Sends the customer's copy of a bill on WhatsApp through WhatsApp Web inside the app (foreground only on iOS, decision D1).
@MainActor
enum WhatsApp {
    /// Digits only, with the country code. "98765 43210", "+91 98765-43210" and "098765 43210" all become 919876543210.
    static func number(_ raw: String, countryCode: String) -> String? {
        var d = raw.filter(\.isNumber)
        if d.hasPrefix("00") { d.removeFirst(2) }
        if d.hasPrefix("0") && d.count == 11 { d.removeFirst() }
        if d.count == 10 { d = countryCode + d }
        return d.count >= 11 && d.count <= 15 ? d : nil
    }

    static func partyNumber(_ inv: JSON, countryCode: String) -> String? {
        var candidates = [inv.str("party_phone")]
        candidates += inv.str("party_mobiles").split(whereSeparator: { ",;/".contains($0) }).map(String.init)
        for c in candidates { if let n = number(c, countryCode: countryCode) { return n } }
        return nil
    }

    /// After a bill is saved: send it in the background of the screen (nothing is held up or interrupted).
    static func sendIfEnabled(_ id: Int, app: AppModel) async {
        guard app.settings.str("wa_auto") == "1" else { return }
        Task { await send(id, app: app, quiet: true) }
    }

    static func send(_ id: Int, app: AppModel, quiet: Bool = false) async {
        let inv: JSON
        do { inv = try await API.obj("GET", "/invoices/\(id)") } catch { if !quiet { app.notify(error.localizedDescription, error: true) }; return }
        let who = inv.str("party_name").isEmpty ? "the customer" : inv.str("party_name")
        let cc = app.settings.str("wa_cc").isEmpty ? "91" : app.settings.str("wa_cc")
        guard let phone = partyNumber(inv, countryCode: cc) else {
            if !quiet { app.notify("\(who) has no mobile number on file.", error: true) }
            return
        }
        let layout = PrintLayout.parse(app.settings.str("print_layout"))
        let single: PrintLayout = layout.isFullPage ? .a4FullOriginal : .single
        let company = app.settings
        let template = app.settings.str("wa_message").isEmpty ? defaultMessage : app.settings.str("wa_message")
        let text = template
            .replacingOccurrences(of: "{name}", with: inv.str("party_name"))
            .replacingOccurrences(of: "{invoice}", with: inv.str("invoice_no"))
            .replacingOccurrences(of: "{total}", with: Fmt.money(inv.num("total")))
            .replacingOccurrences(of: "{company}", with: app.companyName)
        do {
            // the bill is drawn while WhatsApp Web opens the customer's chat
            try await WhatsAppWeb.shared.send(pdf: { invoicePDF(inv, company: company, layout: single)?.dataRepresentation() }, fileName: inv.str("invoice_no").replacingOccurrences(of: "/", with: "-"), phone: phone, caption: text)
            app.notify("Sent \(inv.str("invoice_no")) to \(who) on WhatsApp.")
        } catch {
            app.notify("WhatsApp: \(error.localizedDescription)", error: true)
        }
    }

    /// A one-page PDF to try the whole route without a real bill.
    static func sendTest(to raw: String, app: AppModel) async {
        let cc = app.settings.str("wa_cc").isEmpty ? "91" : app.settings.str("wa_cc")
        guard let phone = number(raw, countryCode: cc) else { app.notify("Enter a mobile number to send the test to.", error: true); return }
        let r = UIGraphicsImageRenderer(size: CGSize(width: 420, height: 200))
        let img = r.image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 420, height: 200))
            ("BillBox test\nIf you can read this on WhatsApp, automatic sending works." as NSString)
                .draw(in: CGRect(x: 20, y: 20, width: 380, height: 160), withAttributes: [.font: UIFont.systemFont(ofSize: 16), .foregroundColor: UIColor.black])
        }
        guard let page = PDFPage(image: img) else { return }
        let pdf = PDFDocument()
        pdf.insert(page, at: 0)
        guard let data = pdf.dataRepresentation() else { return }
        app.notify("Sending the test… keep BillBox open until it is sent.")
        do {
            try await WhatsAppWeb.shared.send(pdf: { data }, fileName: "BillBox-test", phone: phone, caption: "BillBox test")
            app.notify("Test sent to \(raw) on WhatsApp.")
        } catch {
            app.notify("WhatsApp: \(error.localizedDescription)", error: true)
        }
    }

    static let defaultMessage = "Hello {name}, thank you for your purchase. Your bill {invoice} for {total} is attached. - {company}"
}

@MainActor struct WhatsAppSettings: View {
    @EnvironmentObject private var app: AppModel
    @ObservedObject private var web = WhatsAppWeb.shared
    @State private var auto = false
    @State private var cc = "91"
    @State private var message = ""
    @State private var testNumber = ""
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: web.connected ? "checkmark.seal.fill" : "link.circle").foregroundColor(web.connected ? .green : .orange)
                    Text(web.status).font(.callout)
                }
                Button(web.connected ? "Reconnect" : "Connect WhatsApp") { web.connect() }
                if web.connected { Button("Disconnect", role: .destructive) { Task { await web.disconnect() } } }
                Button("Show page") { web.reveal() }
            } footer: {
                Text("Show page opens the live WhatsApp page so you can watch it or check the chat. Close it to hide it again.")
            }
            Section {
                Toggle("After saving a bill, send the customer's copy on WhatsApp (in the background)", isOn: Binding(
                    get: { auto },
                    set: { on in auto = on; Task { await save(quiet: true) } }))
                Field("Try it: send a test to this number", text: $testNumber, prompt: Text("10-digit mobile, e.g. your own"))
                    .keyboardType(.phonePad)
                Button("Send test") { Task { await WhatsApp.sendTest(to: testNumber, app: app) } }
                Field("Country code for 10-digit numbers", text: $cc).keyboardType(.numberPad)
                Field("Message sent with the bill", text: $message, prompt: Text(WhatsApp.defaultMessage), axis: .vertical)
            }
            Section {
                Text("Tap Connect WhatsApp once and scan the QR code with the phone that has your WhatsApp (WhatsApp > Linked devices > Link a device). After that, bills are sent through WhatsApp Web inside BillBox. On iPhone and iPad this works only while BillBox is open on screen; if you leave the app during a send, it finishes when you come back. Each bill goes as one Original copy in PDF form to the customer's mobile number; customers without a number are skipped, and numbers that are not on WhatsApp are reported. Use {name}, {invoice}, {total} and {company} in the message. WhatsApp does not officially support automated sending, so keep it to your own customers' bills.")
                    .font(.caption).foregroundStyle(.secondary)
                if !web.lastResult.isEmpty { Text("Last send: \(web.lastResult)").font(.caption2).foregroundStyle(.secondary) }
            }
            Section { Button("Save") { Task { await save(quiet: false) } } }
        }
        .groupedForm()
        .navigationTitle("WhatsApp")
        .onAppear {
            guard !loaded else { return }
            loaded = true
            auto = app.settings.str("wa_auto") == "1"
            cc = app.settings.str("wa_cc").isEmpty ? "91" : app.settings.str("wa_cc")
            message = app.settings.str("wa_message")
        }
    }

    private func save(quiet: Bool) async {
        await app.saveSettings(["wa_auto": auto ? "1" : "0", "wa_cc": cc.filter(\.isNumber), "wa_message": message])
        if !quiet { app.notify("WhatsApp settings saved.") }
    }
}
