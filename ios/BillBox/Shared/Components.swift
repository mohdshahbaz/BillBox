import SwiftUI
import PDFKit

// MARK: - Sheets

/// A form in a sheet: Cancel / Save in the navigation bar (Esc and Return with a keyboard), error line under the form.
@MainActor struct FormSheet<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let saveLabel: String
    let canSave: Bool
    let onSave: () async throws -> Void
    let content: Content
    @State private var busy = false
    @State private var errorText: String?

    init(title: String, saveLabel: String = "Save", width: CGFloat = 520, canSave: Bool = true,
         onSave: @escaping () async throws -> Void, @ViewBuilder content: () -> Content) {
        self.title = title
        self.saveLabel = saveLabel
        self.canSave = canSave
        self.onSave = onSave
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            Form {
                content
                if let errorText {
                    Section { Text(errorText).font(.callout).foregroundStyle(.red) }
                }
            }
            .groupedForm()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveLabel) { Task { await save() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(busy || !canSave)
                }
            }
            .overlay { if busy { ProgressView() } }
        }
    }

    private func save() async {
        busy = true
        errorText = nil
        do {
            try await onSave()
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
        busy = false
    }
}

/// Read-only sheet with Close, and optional actions in the bottom bar.
@MainActor struct InfoSheet<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let content: Content
    let trailing: AnyView

    init(title: String, width: CGFloat = 860, height: CGFloat = 520, trailing: AnyView = AnyView(EmptyView()), @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            content
                .padding(.horizontal, 12).padding(.top, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Theme.page)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.keyboardShortcut(.cancelAction) }
                    ToolbarItemGroup(placement: .bottomBar) { trailing }
                }
        }
    }
}

// MARK: - Inputs

struct Choice: Identifiable, Hashable {
    let id: Int
    let label: String
    var detail: String = ""
}

/// A button that opens a searchable list: for parties and items, where a plain menu would be hundreds of rows long.
@MainActor struct SearchPicker: View {
    let title: String
    var placeholder = "Select…"
    let choices: [Choice]
    @Binding var selection: Int
    var onPick: ((Int) -> Void)?
    @State private var open = false

    private var label: String { choices.first(where: { $0.id == selection })?.label ?? placeholder }

    var body: some View {
        Button { open = true } label: {
            HStack(spacing: 6) {
                Text(label).lineLimit(1).truncationMode(.tail)
                    .foregroundStyle(choices.contains(where: { $0.id == selection }) ? Color.primary : Color.secondary)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("\(title): \(label)")
        .sheet(isPresented: $open) {
            SearchPickerList(title: title, choices: choices) { c in
                selection = c.id
                open = false
                onPick?(c.id)
            }
        }
    }
}

@MainActor private struct SearchPickerList: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let choices: [Choice]
    let pick: (Choice) -> Void
    @State private var query = ""

    private var filtered: [Choice] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        if words.isEmpty { return choices }
        return choices.filter { c in
            let hay = (c.label + " " + c.detail).lowercased()
            return words.allSatisfy { hay.contains($0) }
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { c in
                Button { pick(c) } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(c.label).foregroundColor(.primary)
                        if !c.detail.isEmpty { Text(c.detail).font(.caption).foregroundStyle(.secondary) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search \(title.lowercased())")
            .onSubmit(of: .search) { if let f = filtered.first { pick(f) } }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Date shown as DD-MM-YYYY; tap for a calendar. Stores YYYY-MM-DD.
@MainActor struct DateField: View {
    var title: String? = nil
    @Binding var iso: String
    var optional = false
    @State private var open = false

    var body: some View {
        HStack(spacing: 6) {
            Button { open = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                    Text(iso.isEmpty ? (title ?? "Choose date") : (title.map { "\($0)  " } ?? "") + Fmt.dmy(iso)).lineLimit(1).monospacedDigit()
                }
            }
            .accessibilityLabel((title ?? "Date") + ": " + (iso.isEmpty ? "not set" : Fmt.dmy(iso)))
            .popover(isPresented: $open) {
                VStack(spacing: 8) {
                    DatePicker("", selection: Binding(get: { Fmt.date(iso) }, set: { iso = Fmt.iso($0) }), displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .environment(\.locale, Locale(identifier: "en_IN"))
                    Button("Done") { open = false }.buttonStyle(.borderedProminent)
                }
                .padding(12)
                .frame(minWidth: 300)
                .presentationDetents([.medium, .large])
            }
            if optional && !iso.isEmpty {
                Button { iso = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear date")
            }
        }
    }
}

// MARK: - Display

@MainActor struct StatCard: View {
    let title: String
    let value: String
    var note: String = ""
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text(value).font(.system(.title, design: .rounded).weight(.semibold)).monospacedDigit().foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.5)
            if !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(10)
        .accessibilityElement(children: .combine)
    }
}

/// Select mode for a table: "Select" turns row taps into selection; then "N of M selected · Select all · Clear" and the bulk action.
@MainActor struct SelectionBar<ID: Hashable>: View {
    let ids: [ID]
    @Binding var selection: Set<ID>
    @Binding var selecting: Bool
    var actionLabel = "Delete selected…"
    var busy = false
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(selecting ? "Done" : "Select") { selecting.toggle(); if !selecting { selection = [] } }
            if selecting {
                Text("\(selection.count) of \(ids.count) selected").foregroundStyle(.secondary).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                Button(selection.count == ids.count ? "Clear" : "Select all") {
                    selection = selection.count == ids.count ? [] : Set(ids)
                }
                Spacer()
                Button(role: .destructive) { action() } label: { Label(actionLabel, systemImage: "trash").labelStyle(.iconOnly) }
                    .disabled(busy || selection.isEmpty)
                    .accessibilityLabel(actionLabel)
            } else {
                Spacer()
            }
        }
        .font(.callout)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Theme.card)
    }
}

/// Runs `delete` for every id (one at a time, so stock/ledger updates stay consistent) and reports one summary.
func bulkDelete<ID>(_ ids: [ID], notify: (String) -> Void, delete: (ID) async -> BulkOutcome) async {
    var ok = 0, archived = 0; var failed: [String] = []
    for id in ids {
        switch await delete(id) {
        case .deleted: ok += 1
        case .archived: archived += 1
        case .failed(let label, let reason): failed.append(reason.isEmpty ? label : "\(label): \(reason)")
        }
    }
    var parts: [String] = []
    if ok > 0 { parts.append("\(ok) deleted") }
    if archived > 0 { parts.append("\(archived) archived (had history)") }
    if !parts.isEmpty { notify(parts.joined(separator: ", ") + ".") }
    if !failed.isEmpty { notify("Could not delete \(failed.count): " + failed.prefix(5).joined(separator: "; ") + (failed.count > 5 ? "…" : "")) }
}

enum BulkOutcome { case deleted, archived, failed(label: String, reason: String) }

@MainActor struct Banner: View {
    let text: String
    var symbol = "info.circle.fill"
    var tint: Color = .orange

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
        .padding(10)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

@MainActor struct ToastOverlay: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        VStack {
            Spacer()
            if let t = app.toast {
                HStack(spacing: 8) {
                    Image(systemName: t.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(t.isError ? .red : .green)
                    Text(t.text).font(.callout).lineLimit(4).textSelection(.enabled)
                    Button { app.toast = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Dismiss")
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line))
                .shadow(radius: 8, y: 3)
                .padding(.horizontal, 16)
                .padding(.bottom, 64)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: app.toast)
        .allowsHitTesting(app.toast != nil)
    }
}

/// "₹1,234.00 Dr" (they owe you), "₹1,234.00 Cr" (you owe them) or "Settled".
func balanceText(_ v: Double) -> String {
    v.magnitude < 0.005 ? "Settled" : "\(Fmt.money(v.magnitude)) \(v > 0 ? "Dr" : "Cr")"
}

struct PDFPreview: UIViewRepresentable {
    let document: PDFDocument?
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.backgroundColor = .secondarySystemBackground
        return v
    }
    func updateUIView(_ v: PDFView, context: Context) { v.document = document }
}
