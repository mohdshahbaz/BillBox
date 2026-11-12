import SwiftUI
import UIKit

/// One line of a handwritten payment list, as read and matched by the engine, ready to be checked and changed.
struct PaymentLine: Identifiable {
    let id: Int
    var text: String
    var partyId: Int?
    var amount: String
    var reference: String
    var include: Bool
    var problems: [String]
    var bills: String
    var candidates: [JSON]

    init(_ r: JSON) {
        id = r.int("line")
        text = r.str("text")
        partyId = r.optInt("party_id")
        amount = r.num("amount") > 0 ? Fmt.amount(r.num("amount")).replacingOccurrences(of: ",", with: "") : ""
        reference = r.str("reference")
        problems = r.strings("problems")
        include = problems.isEmpty
        candidates = r.list("candidates")
        bills = r.list("bills").map { b in
            b.str("invoice_no").isEmpty ? Fmt.money(b.num("amount")) + " (no bill found)" : "\(b.str("invoice_no")) \(Fmt.money(b.num("amount")))"
        }.joined(separator: ", ")
    }

    var ready: Bool { include && partyId != nil && (Double(amount) ?? 0) > 0 }
}

/// Payments from a photo of a handwritten list. Each line: party name, the bill amounts separated by commas, then the
/// payment (when it differs from the bills' total). The photo is read on this iPhone; every line can be checked and
/// corrected before anything is saved, and all the payments are saved together.
@MainActor struct PaymentPhotoSheet: View {
    @EnvironmentObject private var app: AppModel
    let done: () async -> Void
    @State private var text = ""
    @State private var lines: [PaymentLine] = []
    @State private var parties: [JSON] = []
    @State private var date = ""
    @State private var mode = "CASH"
    @State private var reading = false
    @State private var readError: String?

    private var ready: [PaymentLine] { lines.filter { $0.ready } }
    private var total: Double { ready.reduce(0) { $0 + (Double($1.amount) ?? 0) } }

    var body: some View {
        FormSheet(title: "Payments from a photo", saveLabel: ready.isEmpty ? "Save" : "Save \(ready.count) payment\(ready.count == 1 ? "" : "s")", canSave: !ready.isEmpty, onSave: save) {
            Section {
                HStack(spacing: 12) {
                    if PhotoPicker.hasCamera {
                        PhotoSourceTile(title: "Take photo", detail: "Use the camera", symbol: "camera.fill", prominent: true) { Task { await read(camera: true) } }
                    }
                    PhotoSourceTile(title: "Choose photo", detail: "From your photos", symbol: "photo.on.rectangle") { Task { await read(camera: false) } }
                }
                .disabled(reading)
                .padding(.vertical, 4)
                if reading { HStack(spacing: 8) { ProgressView(); Text("Reading the writing…").font(.callout).foregroundStyle(.secondary) } }
                if let readError { Text(readError).font(.callout).foregroundStyle(Theme.negative) }
            } header: { Text("1. Photo of the list") } footer: {
                Text("Write one party per line: name, the bill amounts separated by commas, then the payment. “Gupta Store 1200, 850 - 2000” records 2,000 against bills of 1,200 and 850; “Gupta Store 1200, 850” records 2,050.")
            }
            Section {
                TextEditor(text: $text).frame(minHeight: 110).font(.body.monospaced()).autocorrectionDisabled().textInputAutocapitalization(.never)
                Button { Task { await parse() } } label: { Label("Read these lines", systemImage: "text.viewfinder") }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: { Text("2. Text read from the photo") } footer: { Text("Fix anything read wrongly here, or type the list yourself.") }
            if !lines.isEmpty {
                Section {
                    ForEach(lines.indices, id: \.self) { i in lineRow($lines[i]) }
                } header: { Text("3. Check each payment") } footer: {
                    Text("\(ready.count) of \(lines.count) ready · total \(Fmt.money(total)). Lines with a problem are left out until you choose the party and amount.")
                }
                Section {
                    Labeled("Date") { DateField(iso: $date) }
                    Picker("Mode", selection: $mode) {
                        Text("Cash").tag("CASH"); Text("UPI").tag("UPI"); Text("Cheque").tag("CHEQUE"); Text("Bank transfer").tag("BANK"); Text("Card").tag("CARD")
                    }
                }
            }
        }
        .task {
            if date.isEmpty { date = app.dateInFY }
            if lines.isEmpty, ["CASH", "UPI", "CHEQUE", "BANK", "CARD"].contains(app.settings.str("pay_default_mode")) { mode = app.settings.str("pay_default_mode") }
            await app.guarded { parties = try await API.list("/parties", query: ["kind": "CUSTOMER"]) }
        }
    }

    @ViewBuilder private func lineRow(_ l: Binding<PaymentLine>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle("", isOn: l.include).labelsHidden()
                Text(l.wrappedValue.text).font(.callout.monospaced()).lineLimit(2).foregroundStyle(.secondary)
            }
            Picker("Party", selection: l.partyId) {
                Text("Choose party…").tag(Int?.none)
                let near = l.wrappedValue.candidates.map { $0.id }
                ForEach(l.wrappedValue.candidates) { c in Text("\(c.str("name"))  · \(Int(c.num("score") * 100))% match").tag(Int?.some(c.id)) }
                ForEach(parties.filter { !near.contains($0.id) }) { p in Text(p.str("name")).tag(Int?.some(p.id)) }
            }
            HStack {
                Text("Amount")
                TextField("0", text: l.amount).keyboardType(.decimalPad).multilineTextAlignment(.trailing).font(.body.monospacedDigit())
            }
            if !l.wrappedValue.bills.isEmpty { Text("Bills: " + l.wrappedValue.bills).font(.caption).foregroundStyle(.secondary) }
            if !l.wrappedValue.problems.isEmpty && !l.wrappedValue.ready {
                Text(l.wrappedValue.problems.joined(separator: " · ")).font(.caption).foregroundStyle(Theme.warning)
            }
        }
        .onChange(of: l.wrappedValue.partyId) { v in if v != nil && (Double(l.wrappedValue.amount) ?? 0) > 0 { l.wrappedValue.include = true } }
    }

    private func read(camera: Bool) async {
        readError = nil
        guard let img = await PhotoPicker.pick(camera: camera) else { return }
        reading = true
        defer { reading = false }
        do {
            guard let cg = PhotoPicker.upright(img) else { throw PDFText.Failure(message: "This photo could not be read.") }
            let read = try await PDFText.textLines(cg)
            if read.isEmpty { readError = "No writing was found in the photo. Take it again in good light, with the page filling the picture."; return }
            text = read.joined(separator: "\n")
            await parse()
        } catch { readError = error.localizedDescription }
    }

    private func parse() async {
        await app.guarded {
            let r = try await API.obj("POST", "/receipts/sheet/parse", body: ["text": text])
            lines = r.list("rows").map(PaymentLine.init)
        }
    }

    private func save() async throws {
        let rows: [[String: Any]] = ready.map { l in
            ["party_id": l.partyId!, "amount": Double(l.amount) ?? 0, "reference": l.reference]
        }
        let r = try await API.objRaw("POST", "/receipts/sheet", body: ["date": date, "mode": mode, "rows": rows])
        app.notify("Saved \(r.int("count")) payment\(r.int("count") == 1 ? "" : "s"), total \(Fmt.money(r.num("total"))).")
        await done()
    }
}

/// The camera or the photo library, presented by BillBox itself (like the Files picker). nil when cancelled.
enum PhotoPicker {
    static var hasCamera: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    @MainActor
    static func pick(camera: Bool) async -> UIImage? {
        guard let top = Files.topController() else { return nil }
        return await withCheckedContinuation { (c: CheckedContinuation<UIImage?, Never>) in
            let picker = UIImagePickerController()
            picker.sourceType = camera && hasCamera ? .camera : .photoLibrary
            let d = ImagePickerDelegate { img in c.resume(returning: img) }
            picker.delegate = d
            ImagePickerDelegate.current = d
            top.present(picker, animated: true)
        }
    }

    /// The photo the right way up and at most 2,400 points wide (camera photos carry their rotation separately).
    static func upright(_ img: UIImage) -> CGImage? {
        let s = img.size
        guard s.width > 0, s.height > 0 else { return img.cgImage }
        let k = min(1, 2400 / max(s.width, s.height))
        let size = CGSize(width: s.width * k, height: s.height * k)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }.cgImage
    }
}

final class ImagePickerDelegate: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    static var current: ImagePickerDelegate?
    private var done: ((UIImage?) -> Void)?
    init(_ done: @escaping (UIImage?) -> Void) { self.done = done }
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        finish(info[.originalImage] as? UIImage)
    }
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        finish(nil)
    }
    private func finish(_ img: UIImage?) {
        done?(img)
        done = nil
        ImagePickerDelegate.current = nil
    }
}

/// A large source button for the payments-from-photo sheet: icon over a title and a short line, equal widths side by side.
struct PhotoSourceTile: View {
    let title: String
    let detail: String
    let symbol: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 26, weight: .medium))
                    .foregroundStyle(prominent ? Color.white : Theme.accent)
                    .frame(width: 52, height: 52)
                    .background(prominent ? Theme.accent : Theme.accent.opacity(0.14), in: Circle())
                Text(title).font(.callout.weight(.semibold)).foregroundStyle(.primary)
                Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14).padding(.horizontal, 8)
            .background(Theme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.accent.opacity(0.25), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)   // each tile is its own tap target inside the form row
    }
}

/// Parties › Customers: the way into payments from a photo, as a card above the list (Settings › Parties & Payments can hide it).
struct PhotoPaymentsCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "camera.viewfinder").font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(Theme.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Payments from a photo").font(.callout.weight(.semibold)).foregroundStyle(.primary)
                    Text("Photograph the handwritten list: every party's payment is recorded together.").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 8)
                Text("Start").font(.callout.weight(.semibold)).foregroundStyle(Theme.accent)
                    .padding(.horizontal, 12).padding(.vertical, 6).background(Theme.accent.opacity(0.12), in: Capsule())
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Payments from a photo")
        .accessibilityHint("Record many payments from a photo of a handwritten list")
    }
}
