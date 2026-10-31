import Foundation

// backend/src/services/ewayBill.js — e-way bill for one sale bill, as the JSON file the government portal
// (ewaybillgst.gov.in › Generate Bulk) takes: NIC's bulk format, version 1.0.0621. Part A from the bill, Part B from the
// transport details typed. The 12-digit number the portal gives is then saved on the bill and printed on it.
enum EwayBill {
    static let MODES = [1: "Road", 2: "Rail", 3: "Air", 4: "Ship"]
    static func isDigit(_ c: Character) -> Bool { c >= "0" && c <= "9" }
    static func isAlnum(_ c: Character) -> Bool { isDigit(c) || (c >= "A" && c <= "Z") }
    static func trim(_ v: Any?) -> String { guard let u = unwrap(v) else { return "" }; return JS.trim(JS.string(u)) }

    /// The last 6-digit number in an address that does not start with 0 (the PIN code), or "".
    static func pinFrom(_ address: Any?) -> String {
        let s = Array(trim(address))
        var found = ""
        var i = 0
        while i < s.count {
            if isDigit(s[i]) {
                var j = i
                while j < s.count && isDigit(s[j]) { j += 1 }
                if j - i == 6 && s[i] != "0" { found = String(s[i..<j]) }
                i = j
            } else { i += 1 }
        }
        return found
    }

    static func addressParts(_ address: Any?) -> (addr1: String, addr2: String, place: String) {
        let flat = trim(address).replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: ", ")
        let parts = flat.components(separatedBy: ",").map { JS.trim($0) }.filter { !$0.isEmpty }
        var place = ""
        var k = parts.count - 1
        while k >= 0 && place.isEmpty {
            let letters = JS.trim(String(parts[k].filter { !isDigit($0) && $0 != "-" }))
            if letters.jsLength >= 2 { place = letters }
            k -= 1
        }
        let one = parts.joined(separator: ", ")
        return (one.jsSlice(0, 120), one.jsSlice(120, 240), place.jsSlice(0, 50))
    }

    static func dmy(_ iso: String) -> String { iso.jsLength >= 10 ? "\(iso.jsSlice(8, 10))/\(iso.jsSlice(5, 7))/\(iso.jsSlice(0, 4))" : "" }
    static func upperNoSpace(_ v: Any?) -> String { String(trim(v).uppercased().filter { $0 != " " && $0 != "-" && $0 != "." }) }
    static func isPin(_ p: String) -> Bool { p.count == 6 && p.first != "0" && p.allSatisfy(isDigit) }
    static func isIsoDate(_ d: String) -> Bool {
        let a = Array(d)
        return a.count == 10 && a[4] == "-" && a[7] == "-" && (a[0..<4] + a[5..<7] + a[8..<10]).allSatisfy(isDigit)
    }

    /// JSON.stringify of a string.
    static func jsonString(_ s: String) -> String {
        var o = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": o += "\\\""
            case "\\": o += "\\\\"
            case "\n": o += "\\n"
            case "\r": o += "\\r"
            case "\t": o += "\\t"
            case "\u{8}": o += "\\b"
            case "\u{C}": o += "\\f"
            default:
                if u.value < 0x20 { o += String(format: "\\u%04x", u.value) } else { o.unicodeScalars.append(u) }
            }
        }
        return o + "\""
    }

    static func loadBill(_ db: Database, _ id: String) throws -> Row {
        guard let inv = try db.prepare("""
            SELECT i.*, p.name party_name, p.gstin party_gstin, p.address party_address, p.state_code party_state
                FROM invoices i LEFT JOIN parties p ON p.id=i.party_id WHERE i.id=?
            """).get(JS.number(id)) else { throw HttpError(404, "Bill not found") }
        return inv
    }

    static func details(_ db: Database, _ id: String) throws -> Row {
        let inv = try loadBill(db, id)
        let co = try Billing.settings(db)
        var saved: [String: Any] = [:]
        if JS.truthy(inv["ewb_transport"] ?? nil), let d = inv.str("ewb_transport").data(using: .utf8),
           let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { saved = o }
        func sv(_ k: String) -> Any? { JS.truthy(saved[k]) ? saved[k] : nil }
        let coPin = trim(co["company_pincode"] ?? nil)
        return [
            "bill_id": inv.i("id"), "invoice_no": inv["invoice_no"]!, "date": inv["date"]!, "total": inv["total"]!,
            "party": JS.truthy(inv["party_name"] ?? nil) ? inv["party_name"]! : NSNull(),
            "needed": inv.n("total") >= 50000,
            "from_pincode": sv("from_pincode") ?? (coPin.isEmpty ? pinFrom(co["company_address"] ?? nil) : coPin),
            "to_pincode": sv("to_pincode") ?? pinFrom(inv["party_address"] ?? nil),
            "distance": { () -> Any in guard let d = saved["distance"], !(d is NSNull) else { return NSNull() }; return JS.number(d) }(),
            "mode": { let m = JS.number(saved["mode"]); return m.isFinite && m != 0 ? Int(m) : 1 }(), "vehicle_no": sv("vehicle_no") ?? "", "vehicle_type": sv("vehicle_type") ?? "R",
            "transporter_id": sv("transporter_id") ?? "", "transporter_name": sv("transporter_name") ?? "",
            "trans_doc_no": sv("trans_doc_no") ?? "", "trans_doc_date": sv("trans_doc_date") ?? "",
            "ewb_no": JS.truthy(inv["ewb_no"] ?? nil) ? inv["ewb_no"]! : NSNull(),
            "ewb_date": JS.truthy(inv["ewb_date"] ?? nil) ? inv["ewb_date"]! : NSNull(),
            "ewb_valid": JS.truthy(inv["ewb_valid"] ?? nil) ? inv["ewb_valid"]! : NSNull(),
        ]
    }

    static func build(_ db: Database, _ id: String, _ b: Row) throws -> Row {
        let inv = try loadBill(db, id)
        let co = try Billing.settings(db)
        if !JS.truthy(inv["party_id"] ?? nil) { throw HttpError(400, "Choose the customer on this bill first: an e-way bill needs the buyer’s name and address.") }
        let fromGstin = upperNoSpace(co["company_gstin"] ?? nil)
        if fromGstin.jsLength != 15 { throw HttpError(400, "Add your GSTIN in Settings › Companies to make an e-way bill.") }
        var last: [String: Any] = [:]
        if JS.truthy(inv["ewb_transport"] ?? nil), let d = inv.str("ewb_transport").data(using: .utf8),
           let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { last = o }
        var fromPin = trim(b["from_pincode"] ?? nil)
        if fromPin.isEmpty { fromPin = trim(last["from_pincode"]) }
        if fromPin.isEmpty { fromPin = trim(co["company_pincode"] ?? nil) }
        if fromPin.isEmpty { fromPin = pinFrom(co["company_address"] ?? nil) }
        if !isPin(fromPin) { throw HttpError(400, "Your PIN code is needed (6 digits): type it here or add it to your address in Settings › Companies.") }
        var toPin = trim(b["to_pincode"] ?? nil)
        if toPin.isEmpty { toPin = trim(last["to_pincode"]) }
        if toPin.isEmpty { toPin = pinFrom(inv["party_address"] ?? nil) }
        if !isPin(toPin) { throw HttpError(400, "The PIN code of \(inv.str("party_name")) is needed (6 digits): type it here or add it to the party’s address.") }
        let dist = trim(b["distance"] ?? nil).isEmpty ? Double.nan : JS.number(unwrap(b["distance"] ?? nil))
        if !(dist.isFinite && dist == dist.rounded() && dist >= 0 && dist <= 4000) {
            throw HttpError(400, "Distance must be a whole number of km from 0 to 4000 (0 lets the portal work it out from the PIN codes).")
        }
        let modeText = trim(b["mode"] ?? nil).lowercased()
        var mode: Int
        if ["1", "2", "3", "4"].contains(modeText) { mode = Int(modeText)! } else if let k = ["road", "rail", "air", "ship"].firstIndex(of: modeText) { mode = k + 1 } else { mode = modeText.isEmpty ? 1 : 0 }
        if mode == 0 { throw HttpError(400, "Mode must be road, rail, air or ship") }
        let vehicle = upperNoSpace(b["vehicle_no"] ?? nil)
        if !vehicle.isEmpty && (vehicle.count < 6 || vehicle.count > 15 || !vehicle.allSatisfy(isAlnum)) {
            throw HttpError(400, "Vehicle number \"\(trim(b["vehicle_no"] ?? nil))\" does not look right (e.g. UP20AB1234)")
        }
        let transId = upperNoSpace(b["transporter_id"] ?? nil)
        if !transId.isEmpty && (transId.count != 15 || !transId.allSatisfy(isAlnum)) { throw HttpError(400, "Transporter ID is the transporter’s 15-character GSTIN or TRANSIN") }
        let docNo = trim(b["trans_doc_no"] ?? nil).jsSlice(0, 15), docDate = trim(b["trans_doc_date"] ?? nil)
        if !docDate.isEmpty && !isIsoDate(docDate) { throw HttpError(400, "Transport document date must be YYYY-MM-DD") }
        if mode == 1 && vehicle.isEmpty && transId.isEmpty { throw HttpError(400, "Enter the vehicle number, or the transporter ID if the transporter will add the vehicle later.") }
        if mode != 1 && docNo.isEmpty { throw HttpError(400, "For \(MODES[mode]!.lowercased()) transport enter the RR / airway bill / bill of lading number.") }
        let vType = trim(b["vehicle_type"] ?? nil).uppercased() == "O" ? "O" : "R"

        let lines = try db.prepare("""
            SELECT l.item_id, it.name, it.hsn, l.qty, l.free_qty, l.taxable, l.gst_rate, l.cgst, l.sgst, l.igst
                FROM invoice_lines l JOIN items it ON it.id=l.item_id WHERE l.invoice_id=? ORDER BY l.id
            """).all(inv.i("id"))
        var noHsn: [String] = []
        var byItem: [(itemId: Int, name: String, hsn: String, gst: Double, qty: Double, taxable: Double)] = []
        for l in lines {
            let hsn = trim(l["hsn"] ?? nil)
            if hsn.isEmpty || !hsn.allSatisfy(isDigit) { if !noHsn.contains(l.str("name")) { noHsn.append(l.str("name")) }; continue }
            if let k = byItem.firstIndex(where: { $0.itemId == l.i("item_id") && $0.gst == l.n("gst_rate") }) {
                byItem[k].qty += l.n("qty") + l.n("free_qty")
                byItem[k].taxable = r2(byItem[k].taxable + l.n("taxable"))
            } else {
                byItem.append((l.i("item_id"), l.str("name"), hsn, l.n("gst_rate"), l.n("qty") + l.n("free_qty"), r2(0 + l.n("taxable"))))
            }
        }
        if !noHsn.isEmpty {
            throw HttpError(400, "Add the HSN code (Stock › edit item) for: \(noHsn.prefix(5).joined(separator: ", "))\(noHsn.count > 5 ? " and \(noHsn.count - 5) more" : "")")
        }
        let intra = !(inv.n("igst") > 0)
        var main = byItem.first
        for g in byItem where g.taxable > main!.taxable { main = g }
        let from = addressParts(co["company_address"] ?? nil), to = addressParts(inv["party_address"] ?? nil)
        let stateText = trim(co["state_code"] ?? nil)
        let fromState = JS.number(stateText.isEmpty ? fromGstin.jsSlice(0, 2) : stateText)
        let toGstin = upperNoSpace(inv["party_gstin"] ?? nil)
        let ps = trim(inv["party_state"] ?? nil)
        let toStateText = !ps.isEmpty ? ps : (toGstin.jsLength == 15 ? toGstin.jsSlice(0, 2) : "")
        let toState = toStateText.isEmpty ? (intra ? fromState : 0) : JS.number(toStateText)
        let invNo = inv.str("invoice_no")
        let docNoBill = invNo.jsLength > 16 ? invNo.jsSlice(invNo.jsLength - 16) : invNo
        let items: [Row] = byItem.enumerated().map { i, g in
            ["itemNo": i + 1, "productName": g.name.jsSlice(0, 100), "productDesc": g.name.jsSlice(0, 100), "hsnCode": JS.number(g.hsn), "quantity": g.qty, "qtyUnit": "PCS",
             "taxableAmount": g.taxable, "sgstRate": intra ? g.gst / 2 : 0, "cgstRate": intra ? g.gst / 2 : 0, "igstRate": intra ? 0 : g.gst, "cessRate": 0, "cessNonAdvol": 0]
        }
        let bill: Row = [
            "userGstin": fromGstin, "supplyType": "O", "subSupplyType": 1, "subSupplyDesc": "", "docType": "INV", "docNo": docNoBill, "docDate": dmy(inv.str("date")), "transType": 1,
            "fromGstin": fromGstin, "fromTrdName": trim(co["company_name"] ?? nil).jsSlice(0, 100), "fromAddr1": from.addr1, "fromAddr2": from.addr2, "fromPlace": from.place,
            "fromPincode": JS.number(fromPin), "fromStateCode": fromState, "actualFromStateCode": fromState,
            "toGstin": toGstin.jsLength == 15 ? toGstin : "URP", "toTrdName": trim(inv["party_name"] ?? nil).jsSlice(0, 100), "toAddr1": to.addr1, "toAddr2": to.addr2, "toPlace": to.place,
            "toPincode": JS.number(toPin), "toStateCode": toState, "actualToStateCode": toState,
            "totalValue": r2(inv.n("taxable")), "cgstValue": r2(inv.n("cgst")), "sgstValue": r2(inv.n("sgst")), "igstValue": r2(inv.n("igst")), "cessValue": 0, "TotNonAdvolVal": 0,
            "OthValue": r2(inv.n("total") - (inv.n("taxable") + inv.n("cgst") + inv.n("sgst") + inv.n("igst"))), "totInvValue": r2(inv.n("total")),
            "transMode": mode, "transDistance": JS.numberString(dist), "transporterName": trim(b["transporter_name"] ?? nil).jsSlice(0, 100), "transporterId": transId,
            "transDocNo": docNo, "transDocDate": dmy(docDate), "vehicleNo": vehicle, "vehicleType": vType,
            "mainHsnCode": JS.number(main?.hsn ?? "0"), "itemList": items,
        ]
        var warnings: [String] = []
        if inv.n("total") < 50000 { warnings.append("This bill is under ₹50,000: an e-way bill is usually not needed (some states ask for one for goods moved within the state).") }
        if byItem.count > 250 { warnings.append("The portal takes at most 250 items on one e-way bill.") }
        if from.place.isEmpty || to.place.isEmpty {
            warnings.append("The portal needs the place of \(from.place.isEmpty ? "your business (Settings › Companies › address)" : "\(inv.str("party_name")) (the party’s address)"): add it before uploading.")
        }
        if JS.truthy(inv["ewb_no"] ?? nil) { warnings.append("This bill already has e-way bill \(inv.str("ewb_no")). Make a new one only if that one was cancelled.") }
        if !JS.truthy(b["preview"] ?? nil) {
            // the same text as JSON.stringify of the Mac's object, key for key
            let saved = "{\"from_pincode\":\(jsonString(fromPin)),\"to_pincode\":\(jsonString(toPin)),\"distance\":\(JS.numberString(dist)),\"mode\":\(mode),"
                + "\"vehicle_no\":\(jsonString(vehicle)),\"vehicle_type\":\(jsonString(vType)),\"transporter_id\":\(jsonString(transId)),"
                + "\"transporter_name\":\(jsonString(trim(b["transporter_name"] ?? nil))),\"trans_doc_no\":\(jsonString(docNo)),\"trans_doc_date\":\(jsonString(docDate))}"
            try db.prepare("UPDATE invoices SET ewb_transport=? WHERE id=?").run(saved, inv.i("id"))
        }
        let safe = String(invNo.map { isAlnum($0.uppercased().first ?? $0) ? $0 : "-" })
        return ["file_name": "EWB_\(safe).json", "warnings": warnings, "mode_name": MODES[mode]!, "ewaybill": ["version": "1.0.0621", "billLists": [bill]] as Row]
    }

    static func saveNumber(_ db: Database, _ id: String, _ b: Row) throws -> Row {
        let inv = try loadBill(db, id)
        let no = upperNoSpace(b["ewb_no"] ?? nil)
        if no.isEmpty {
            try db.prepare("UPDATE invoices SET ewb_no=NULL, ewb_date=NULL, ewb_valid=NULL WHERE id=?").run(inv.i("id"))
            return ["ok": true, "ewb_no": NSNull()]
        }
        if no.count != 12 || !no.allSatisfy(isDigit) { throw HttpError(400, "The e-way bill number is the 12-digit number the portal gives") }
        let d = trim(b["ewb_date"] ?? nil), v = trim(b["ewb_valid"] ?? nil)
        if (!d.isEmpty && !isIsoDate(d)) || (!v.isEmpty && !isIsoDate(v)) { throw HttpError(400, "Dates must be YYYY-MM-DD") }
        if !d.isEmpty && !v.isEmpty && v < d { throw HttpError(400, "Valid until cannot be before the e-way bill date") }
        let date = d.isEmpty ? inv.str("date") : d
        try db.prepare("UPDATE invoices SET ewb_no=?, ewb_date=?, ewb_valid=? WHERE id=?").run(no, date, v.isEmpty ? nil : v, inv.i("id"))
        return ["ok": true, "ewb_no": no, "ewb_date": date, "ewb_valid": v.isEmpty ? NSNull() : v]
    }
}
