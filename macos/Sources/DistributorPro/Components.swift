import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers

// MARK: - Sheets

/// Standard macOS form sheet: grouped form, error line, Cancel / Save with Esc and Return.
@MainActor struct FormSheet<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let saveLabel: String
    let width: CGFloat
    let canSave: Bool
    let onSave: () async throws -> Void
    let content: Content
    @State private var busy = false
    @State private var errorText: String?

    init(title: String, saveLabel: String = "Save", width: CGFloat = 520, canSave: Bool = true,
         onSave: @escaping () async throws -> Void, @ViewBuilder content: () -> Content) {
        self.title = title
        self.saveLabel = saveLabel
        self.width = width
        self.canSave = canSave
        self.onSave = onSave
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 4)
            Form { content }
                .groupedForm()
            if let errorText {
                Text(errorText)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(saveLabel) {
                    Task {
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
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(busy || !canSave)
            }
            .padding(16)
        }
        .frame(width: width)
    }
}

/// Read-only sheet with a Close button.
@MainActor struct InfoSheet<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let width: CGFloat
    let height: CGFloat
    let content: Content
    let trailing: AnyView

    init(title: String, width: CGFloat = 860, height: CGFloat = 520, trailing: AnyView = AnyView(EmptyView()), @ViewBuilder content: () -> Content) {
        self.title = title
        self.width = width
        self.height = height
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3.weight(.semibold))
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack {
                trailing
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: width, height: height)
    }
}

// MARK: - Inputs

struct Choice: Identifiable, Hashable {
    let id: Int
    let label: String
    var detail: String = ""
}

/// A pop-up button with a search box: for parties and items, where a plain menu would be hundreds of rows long.
@MainActor struct SearchPicker: View {
    let title: String
    var placeholder = "Select…"
    let choices: [Choice]
    @Binding var selection: Int
    var onPick: ((Int) -> Void)?
    @State private var open = false
    @State private var query = ""

    private var label: String { choices.first(where: { $0.id == selection })?.label ?? placeholder }
    private var filtered: [Choice] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        if words.isEmpty { return choices }
        return choices.filter { c in
            let hay = (c.label + " " + c.detail).lowercased()
            return words.allSatisfy { hay.contains($0) }
        }
    }

    var body: some View {
        Button {
            query = ""
            open = true
        } label: {
            HStack(spacing: 6) {
                Text(label).lineLimit(1).truncationMode(.tail)
                    .foregroundStyle(choices.contains(where: { $0.id == selection }) ? Color.primary : Color.secondary)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .help(title)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(spacing: 8) {
                TextField("Search \(title.lowercased())", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { if let f = filtered.first { pick(f) } }
                List(filtered) { c in
                    Button { pick(c) } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.label).lineLimit(1)
                            if !c.detail.isEmpty { Text(c.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
            .padding(10)
            .frame(width: 360, height: 340)
        }
    }

    private func pick(_ c: Choice) {
        selection = c.id
        open = false
        onPick?(c.id)
    }
}

/// Date shown as DD-MM-YYYY; click for a calendar. Stores YYYY-MM-DD.
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
                    Text(iso.isEmpty ? (title ?? "Choose date") : (title.map { "\($0)  " } ?? "") + Fmt.dmy(iso))
                }
            }
            .popover(isPresented: $open, arrowEdge: .bottom) {
                DatePicker("", selection: Binding(get: { Fmt.date(iso) }, set: { iso = Fmt.iso($0) }), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "en_IN"))
                    .padding(12)
                    .frame(width: 280)
            }
            if optional && !iso.isEmpty {
                Button { iso = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
    }
}

/// Right-aligned number entry that keeps whatever text was typed.
@MainActor struct NumberField: View {
    let title: String
    @Binding var text: String
    var prompt = ""
    var width: CGFloat? = nil

    var body: some View {
        TextField(title, text: $text, prompt: Text(prompt))
            .multilineTextAlignment(.trailing)
            .mono()
            .frame(width: width)
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
            Text(value).font(.system(size: 26, weight: .semibold, design: .rounded)).mono().foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.6)
            if !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(10)
    }
}

/// A thin strip that appears once at least one row is selected in a DataGrid: "N selected · Select all · Clear"
/// plus a destructive bulk action (usually "Delete selected…"). Used the same way on every table in the app.
@MainActor struct SelectionBar<ID: Hashable>: View {
    let ids: [ID]
    @Binding var selection: Set<ID>
    var actionLabel = "Delete selected…"
    var busy = false
    /// More buttons for the ticked rows (print, mark printed, WhatsApp…), shown before Delete.
    var extra: AnyView? = nil
    let action: () -> Void

    var body: some View {
        if !selection.isEmpty {
            HStack(spacing: 10) {
                Text("\(selection.count) of \(ids.count) selected").foregroundStyle(.secondary)
                Button(selection.count == ids.count ? "Clear" : "Select all") {
                    selection = selection.count == ids.count ? [] : Set(ids)
                }
                Spacer()
                if let extra { extra }
                Button(role: .destructive) { action() } label: { Label(actionLabel, systemImage: "trash") }
                    .disabled(busy)
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .background(Theme.card)
        }
    }
}

/// Runs `delete` for every id in `ids` (sequentially, so stock/ledger updates stay consistent) and reports one
/// summary instead of one alert per row. Returns once everything has been attempted.
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
            Text(text).frame(maxWidth: .infinity, alignment: .leading)
        }
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
                    Text(t.text).lineLimit(4).textSelection(.enabled)
                    Button { app.toast = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().stroke(Theme.line))
                .shadow(radius: 8, y: 3)
                .padding(.bottom, 18)
                .frame(maxWidth: 720)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: app.toast)
        .allowsHitTesting(app.toast != nil)
    }
}

/// Qty/price text that is red when it is a negative amount.
func balanceText(_ v: Double) -> String {
    v.magnitude < 0.005 ? "Settled" : "\(Fmt.money(v.magnitude)) \(v > 0 ? "Dr" : "Cr")"
}

// MARK: - Files and PDF

enum Files {
    @MainActor
    static func save(_ name: String, data: Data) -> URL? {
        let p = NSSavePanel()
        p.nameFieldStringValue = name
        guard p.runModal() == .OK, let url = p.url else { return nil }
        do { try data.write(to: url); return url } catch { return nil }
    }

    @MainActor
    static func open(types: [String]) -> URL? {
        let p = NSOpenPanel()
        p.allowedContentTypes = types.compactMap { UTType(filenameExtension: $0) }
        p.allowsMultipleSelection = false
        return p.runModal() == .OK ? p.url : nil
    }

    /// A JSON file chosen in Finder, as text (nil when cancelled or unreadable).
    @MainActor
    static func pickJSON() async -> String? {
        guard let u = open(types: ["json"]) else { return nil }
        return try? String(contentsOf: u, encoding: .utf8)
    }

    @MainActor
    static func chooseFolder() -> String? {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.canCreateDirectories = true
        return p.runModal() == .OK ? p.url?.path : nil
    }

    @MainActor
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct PDFPreview: NSViewRepresentable {
    let document: PDFDocument?
    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        return v
    }
    func updateNSView(_ v: PDFView, context: Context) { v.document = document }
}

/// Tab-separated text for pasting into Excel / Numbers.
func tsv(_ header: [String], _ rows: [[String]]) -> String {
    ([header] + rows).map { $0.joined(separator: "\t") }.joined(separator: "\n")
}
