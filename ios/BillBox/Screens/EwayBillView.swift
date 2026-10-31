import SwiftUI

/// E-way bill for one sale bill. BillBox makes the file the government portal takes (ewaybillgst.gov.in › e-Waybill ›
/// Generate Bulk): Part A from the bill, Part B from the transport details typed here. The portal gives back a 12-digit
/// e-way bill number, which is saved here and printed on the bill.
@MainActor struct EwayBillSheet: View {
    @EnvironmentObject private var app: AppModel
    let billId: Int
    @State private var d: JSON?
    @State private var f: [String: String] = [:]
    @State private var mode = 1
    @State private var oversize = false
    @State private var warnings: [String] = []
    @State private var made = ""
    @State private var problem: String?
    @State private var working = false

    private func v(_ k: String) -> Binding<String> { Binding(get: { f[k] ?? "" }, set: { f[k] = $0 }) }

    var body: some View {
        FormSheet(title: "E-way bill · \(d?.str("invoice_no") ?? "")", saveLabel: "Save e-way bill number", width: 640,
                  canSave: d != nil, onSave: saveNumber) {
            if let d {
                Section {
                    HStack {
                        Text(d.str("party").isEmpty ? "Cash customer" : d.str("party"))
                        Spacer()
                        Text(Fmt.money(d.num("total"))).mono().fw(.semibold)
                    }
                    if !d.bool("needed") {
                        Text("This bill is under ₹50,000, so an e-way bill is usually not needed (some states ask for one for goods moved within the state).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !d.str("ewb_no").isEmpty {
                        Label("E-way bill \(d.str("ewb_no"))" + (d.str("ewb_valid").isEmpty ? "" : " · valid until \(Fmt.dmy(d.str("ewb_valid")))"), systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    }
                }
                Section {
                    LabeledField(title: "Your PIN code", text: v("from_pincode"), prompt: "246701")
                    LabeledField(title: "Party's PIN code", text: v("to_pincode"), prompt: "246725")
                    LabeledField(title: "Distance (km)", text: v("distance"), prompt: "0 = portal works it out")
                    Picker("Mode", selection: $mode) {
                        Text("Road").tag(1); Text("Rail").tag(2); Text("Air").tag(3); Text("Ship").tag(4)
                    }
                    if mode == 1 {
                        LabeledField(title: "Vehicle number", text: v("vehicle_no"), prompt: "UP20AB1234")
                        Toggle("Over-dimensional cargo", isOn: $oversize)
                    } else {
                        LabeledField(title: "RR / airway bill / B/L no.", text: v("trans_doc_no"), prompt: "")
                        Labeled("Document date") { DateField(iso: v("trans_doc_date")) }
                    }
                    LabeledField(title: "Transporter name", text: v("transporter_name"), prompt: "optional")
                    LabeledField(title: "Transporter ID (GSTIN)", text: v("transporter_id"), prompt: "optional")
                } header: { Text("1. Transport") } footer: {
                    Text("PIN codes are read from the two addresses when they contain one. For road transport give the vehicle number, or the transporter ID if the transporter will add the vehicle on the portal.")
                }
                Section {
                    Button { Task { await makeFile() } } label: { Label("Make the e-way bill file", systemImage: "doc.badge.arrow.up") }
                        .buttonStyle(.borderedProminent).disabled(working)
                    if let problem { Text(problem).foregroundStyle(.red).font(.callout) }
                    ForEach(warnings, id: \.self) { w in Text(w).font(.caption).foregroundStyle(.orange) }
                    if !made.isEmpty { Text("Saved \(made).").font(.callout) }
                    Link(destination: URL(string: "https://ewaybillgst.gov.in")!) { Label("Open the e-way bill portal", systemImage: "safari") }
                } header: { Text("2. File for the portal") } footer: {
                    Text("On the portal: log in › e-Waybill › Generate Bulk › choose this file › Upload › Generate. The portal shows the 12-digit e-way bill number.")
                }
                Section {
                    LabeledField(title: "E-way bill number", text: v("ewb_no"), prompt: "12 digits")
                    Labeled("E-way bill date") { DateField(iso: v("ewb_date")) }
                    Labeled("Valid until") { DateField(iso: v("ewb_valid")) }
                } header: { Text("3. Number from the portal") } footer: {
                    Text("It is printed on the bill. Clear the number and save if the e-way bill was cancelled.")
                }
            } else {
                ProgressView()
            }
        }
        .task { await load() }
    }

    private func load() async {
        await app.guarded {
            let r = try await API.obj("GET", "/invoices/\(billId)/ewaybill")
            d = r
            for k in ["from_pincode", "to_pincode", "vehicle_no", "transporter_id", "transporter_name", "trans_doc_no", "trans_doc_date", "ewb_no", "ewb_date", "ewb_valid"] {
                f[k] = r.str(k)
            }
            f["distance"] = r.has("distance") && !r.str("distance").isEmpty ? Fmt.qty(r.num("distance")) : ""
            if f["ewb_date"]?.isEmpty != false { f["ewb_date"] = Fmt.today }
            mode = max(1, min(4, r.int("mode")))
            oversize = r.str("vehicle_type") == "O"
        }
    }

    private func makeFile() async {
        problem = nil
        warnings = []
        working = true
        defer { working = false }
        var body: [String: Any] = ["mode": mode, "vehicle_type": oversize ? "O" : "R"]
        for k in ["from_pincode", "to_pincode", "distance", "vehicle_no", "transporter_id", "transporter_name", "trans_doc_no", "trans_doc_date"] { body[k] = f[k] ?? "" }
        if mode == 1 { body["trans_doc_no"] = ""; body["trans_doc_date"] = "" } else { body["vehicle_no"] = "" }
        do {
            let r = try await API.objRaw("POST", "/invoices/\(billId)/ewaybill", body: body)
            warnings = r.strings("warnings")
            let data = try JSONSerialization.data(withJSONObject: r.obj("ewaybill").raw, options: [.prettyPrinted, .sortedKeys])
            if Files.save(r.str("file_name"), data: data) != nil { made = r.str("file_name") }
        } catch { problem = error.localizedDescription }
    }

    private func saveNumber() async throws {
        let r = try await API.objRaw("PUT", "/invoices/\(billId)/ewaybill", body: ["ewb_no": f["ewb_no"] ?? "", "ewb_date": f["ewb_date"] ?? "", "ewb_valid": f["ewb_valid"] ?? ""])
        app.notify(r.str("ewb_no").isEmpty ? "E-way bill number cleared." : "E-way bill \(r.str("ewb_no")) saved on the bill.")
    }
}

/// Title on the left, text field on the right.
@MainActor struct LabeledField: View {
    let title: String
    @Binding var text: String
    var prompt = ""

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 10)
            TextField("", text: $text, prompt: Text(prompt)).multilineTextAlignment(.trailing).frame(maxWidth: 260)
        }
    }
}
