import SwiftUI

/// Settings › Companies › Delete…: the company name has to be typed to confirm. The books are hidden, not erased: the file
/// stays in the app's data folder and in every backup made before.
@MainActor struct DeleteCompanySheet: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    let company: JSON
    @State private var typed = ""
    @State private var working = false
    @State private var error = ""

    private var name: String { company.str("name") }
    private var matches: Bool { typed.trimmingCharacters(in: .whitespaces).lowercased() == name.trimmingCharacters(in: .whitespaces).lowercased() }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Delete \(name)\(company.str("fy").isEmpty ? "" : " · FY \(company.str("fy"))")?").font(.title3.weight(.semibold))
            Text("Its stock, parties, bills and accounts disappear from BillBox. Backups made before today still have them, so it can be brought back from Settings › Backup if needed.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Type the company name to confirm").font(.caption).foregroundStyle(.secondary)
                TextField(name, text: $typed).textFieldStyle(.roundedBorder).disableAutocorrection(true)
            }
            if !error.isEmpty { Text(error).font(.callout).foregroundStyle(Theme.negative).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(role: .destructive) {
                    Task {
                        working = true; defer { working = false }
                        do {
                            _ = try await API.obj("POST", "/companies/\(company.id)/delete", body: ["confirm": typed])
                            try await app.reloadCompanies(pick: true)
                            app.notify("\(name) deleted")
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                } label: { Text(working ? "Deleting…" : "Delete company") }
                .buttonStyle(.borderedProminent).tint(Theme.negative)
                .disabled(!matches || working)
            }
        }
        .padding(24)
        .frame(minWidth: 380, idealWidth: 440)
    }
}
