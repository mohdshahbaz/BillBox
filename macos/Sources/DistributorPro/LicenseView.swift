import SwiftUI

/// Settings › Licence: the trial or the licence of this device, Buy (on the website), and the licence key.
/// (Same file on iPhone and Mac; the rules are in the engine: services/license.js and License.swift.)
@MainActor struct LicenseSettings: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.openURL) private var openURL
    @State private var s = JSON()
    @State private var key = ""
    @State private var busy = false

    private var state: String { s.str("state") }

    var body: some View {
        SettingsForm {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: state == "licensed" || state == "unlimited" ? "checkmark.seal.fill" : state == "trial" ? "hourglass" : "lock.fill")
                        .font(.title2).foregroundStyle(state == "expired" ? Theme.negative : Theme.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(headline).font(.headline)
                        Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
                if s.str("edition") == "admin" {
                    Label("Admin (test) edition: test licence keys only.", systemImage: "wrench.and.screwdriver")
                        .font(.caption).foregroundStyle(Theme.warning)
                }
            } header: { Text("This device") }

            if state != "unlimited" {
                if state != "licensed" {
                    Section {
                        DriveButton("Buy a licence…", "cart", prominent: true) { if let u = URL(string: s.str("buy_url")) { openURL(u) } }
                        Text("Yearly ₹1,499 · Lifetime ₹3,999 by UPI or bank transfer. Send the reference on the buy page; your licence key is ready there once the payment is confirmed (usually within a few hours). Enter it below.")
                            .font(.caption).foregroundStyle(.secondary)
                    } header: { Text("Buy") }
                }
                Section {
                    if state == "licensed" {
                        LabeledRow("Plan", s.str("plan") == "lifetime" ? "Lifetime" : "Yearly")
                        LabeledRow("Valid till", s.str("expires").isEmpty ? "No end (lifetime)" : Fmt.dmy(s.str("expires")))
                        if !s.str("email").isEmpty { LabeledRow("Licensed to", s.str("email")) }
                        LabeledRow("Checked online by", Fmt.dmy(s.str("renew_by")))
                        DriveButton(busy ? "Checking…" : "Check the licence now", "arrow.clockwise", disabled: busy) { Task { await run("/license/renew", [:]) } }
                        DriveButton("Remove the licence from this device", "xmark.seal", destructive: true, disabled: busy) { Task { await run("/license/deactivate", [:]) } }
                    } else {
                        TextField("Licence key (BB1.…)", text: $key).font(.caption.monospaced()).autocorrectionDisabled()
                        DriveButton(busy ? "Checking…" : "Use this licence key", "key.fill", prominent: true,
                                    disabled: busy || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { Task { await run("/license/activate", ["key": key]) } }
                    }
                } header: { Text("Licence") } footer: {
                    Text("Device \(s.str("device")). One licence works on 2 devices (Mac, Windows, Linux, iPhone or Android). BillBox checks it online every few weeks and keeps working offline in between. To move it, remove it here first.")
                }
                if s.str("edition") == "admin" {
                    Section {
                        DriveButton("Start the trial again", "gobackward", destructive: true, disabled: busy) { Task { await run("/license/reset-trial", [:]) } }
                    } header: { Text("Testing") } footer: { Text("Admin edition only: forgets the licence and starts a new 15-day trial, to test buying again.") }
                }
            }
        }
        .navigationTitle("Licence")
        .task { await load() }
    }

    private var headline: String {
        switch state {
        case "licensed": return s.str("plan") == "lifetime" ? "Licensed for life" : "Licensed"
        case "trial": return "Free trial: \(s.int("trial_days_left")) day\(s.int("trial_days_left") == 1 ? "" : "s") left"
        case "expired": return "The trial has ended"
        default: return "No licence needed"
        }
    }

    private var detail: String {
        switch state {
        case "licensed": return s.str("expires").isEmpty ? "Everything in BillBox, on this device, with no end date." : "Everything in BillBox until \(Fmt.dmy(s.str("expires")))."
        case "trial": return "Everything works during the \(s.int("trial_days"))-day trial. After it, your books stay safe and can be seen, printed and backed up; adding or changing anything needs a licence."
        case "expired": return (s.str("reason").isEmpty ? "" : s.str("reason") + ". ") + "Your books are safe: they can still be seen, printed, exported and backed up. Buy a licence or enter your key to add and change things again."
        default: return "This copy of BillBox is not limited."
        }
    }

    private func load() async { if let r = try? await API.obj("GET", "/license") { s = r } }

    private func run(_ path: String, _ body: [String: Any?]) async {
        busy = true; defer { busy = false }
        await app.guarded {
            s = try await API.obj("POST", path, body: body)
            if s.str("state") == "licensed" { key = "" }
            if !s.str("renew_error").isEmpty { app.notify(s.str("renew_error"), error: true) }
            else { app.notify(s.str("state") == "licensed" ? "Licence checked: BillBox is licensed on this device." : "Done.") }
        }
    }
}

/// A label and its value on one row.
struct LabeledRow: View {
    let label: String, value: String
    init(_ label: String, _ value: String) { self.label = label; self.value = value }
    var body: some View {
        HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).multilineTextAlignment(.trailing) }
    }
}
