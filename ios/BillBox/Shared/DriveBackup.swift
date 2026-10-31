import SwiftUI

/// Settings › Backup › Google Drive: each backup also goes into "BillBox Backups" in the user's Google Drive.
/// Sign-in is Google's code sign-in: BillBox shows a short code, the user enters it at google.com/device on any phone or
/// computer and allows BillBox; BillBox notices by itself. (Same file on iPhone and Mac.)
@MainActor struct DriveBackupSection: View {
    /// Called with the name of a backup brought back from Drive into this device's backup folder: the screen then asks
    /// Replace or Merge and restores it like any other backup.
    var onRestore: ((String) -> Void)? = nil
    @EnvironmentObject private var app: AppModel
    @Environment(\.openURL) private var openURL
    @State private var status = JSON()
    @State private var clientId = ""
    @State private var secret = ""
    @State private var editingKeys = false
    @State private var code = ""
    @State private var link = "https://www.google.com/device"
    @State private var busy = false
    @State private var polling: Task<Void, Never>?
    @State private var showDrive = false
    @State private var driveList: [JSON] = []
    @State private var listing = false
    @State private var fetching = ""
    /// Changes whenever the keys or the connection change, so the rows are rebuilt (iOS kept the old rows after the
    /// Files picker closed: Connect did not appear until BillBox was opened again).
    private var phase: String { "\(connected)-\(hasKeys)-\(editingKeys)-\(code.isEmpty)" }

    private var connected: Bool { status.bool("connected") }
    private var hasKeys: Bool { !status.str("client_id").isEmpty && status.bool("has_secret") }

    var body: some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: connected ? "checkmark.icloud.fill" : "icloud.slash").foregroundColor(connected ? .green : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(connected ? "Connected: backups also go to Google Drive › BillBox Backups" : code.isEmpty ? "Not connected" : "Waiting for Google…")
                        .font(.callout.weight(.medium))
                    if connected && !status.str("last_upload").isEmpty {
                        Text("Last upload: \(status.str("last_upload")) · \(status.str("last_status") == "ok" ? "done" : status.str("last_status"))")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if connected && status.str("last_status").hasPrefix("failed") {
                        Text(status.str("last_status")).font(.caption).foregroundStyle(.red)
                    }
                }
            }
            Group {
                if !code.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. Open google.com/device on any phone or computer.\n2. Enter this code and allow BillBox:").font(.callout)
                        Text(code).font(.system(size: 30, weight: .bold, design: .monospaced)).frame(maxWidth: .infinity).textSelection(.enabled)
                    }
                    .padding(.vertical, 4)
                    DriveButton("Open google.com/device", "safari", prominent: true) { if let u = URL(string: link) { openURL(u) } }
                    DriveButton("Copy code", "doc.on.doc") { copy(code) }
                    DriveButton("Cancel", "xmark") { stopPolling() }
                } else if connected {
                    DriveButton(busy ? "Uploading…" : "Upload the newest backup now", "icloud.and.arrow.up", prominent: true, disabled: busy) { Task { await upload() } }
                    DriveButton("Restore from Google Drive…", "icloud.and.arrow.down", disabled: busy) { Task { await openDriveList() } }
                    DriveButton("Disconnect Google Drive", "xmark.icloud", destructive: true, disabled: busy) { Task { await disconnect() } }
                } else if hasKeys && !editingKeys {
                    DriveButton(busy ? "Connecting…" : "Connect Google Drive", "link.icloud", prominent: true, disabled: busy) { Task { await connect() } }
                    HStack {
                        Text("Client ID").foregroundStyle(.secondary)
                        Spacer()
                        Text(shortId(status.str("client_id"))).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    DriveButton("Change Google keys…", "key", disabled: busy) { editingKeys = true; clientId = status.str("client_id") }
                } else {
                    DriveButton("Import the downloaded JSON file…", "doc.badge.plus", prominent: true, disabled: busy) { Task { await importJSON() } }
                    TextField("Client ID (…apps.googleusercontent.com)", text: $clientId).autocorrectionDisabled()
                    SecureField("Client secret", text: $secret)
                    DriveButton("Save keys", "checkmark.circle",
                                disabled: busy || clientId.trimmingCharacters(in: .whitespaces).isEmpty || secret.trimmingCharacters(in: .whitespaces).isEmpty) { Task { await saveKeys() } }
                    if hasKeys { DriveButton("Cancel", "xmark") { editingKeys = false } }
                }
            }
            .id(phase)
        } header: {
            Text("Google Drive")
        } footer: {
            Text(connected
                 ? "Every backup (Back up now, the daily backup and the backup on quitting) is also uploaded to your Google Drive, into a folder with the backup's name inside BillBox Backups. The copy on this device stays as well. BillBox can see only the files it made itself in your Drive."
                 : "One-time setup (about 5 minutes, free): in console.cloud.google.com make a project, turn on the Google Drive API, set up the consent screen (External; add your Gmail as a test user), then Credentials › Create credentials › OAuth client ID › type “TVs and Limited Input devices”. Download its JSON and import it here (or paste the Client ID and secret), then Connect. A client made a minute ago can take a few minutes before Google knows it. The same keys work on the Mac, iPhone and Android.")
        }
        .task { await load() }
        .onDisappear { polling?.cancel() }
        .sheet(isPresented: $showDrive) { driveSheet }
    }

    /// Drive › BillBox Backups, newest first; choosing one brings it to this device and restores it.
    private var driveSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Restore from Google Drive").font(.headline)
                Spacer()
                Button("Close") { showDrive = false }.keyboardShortcut(.cancelAction)
            }
            .padding()
            List {
                if listing {
                    HStack { ProgressView(); Text("Asking Google Drive…").foregroundStyle(.secondary) }
                } else if driveList.isEmpty {
                    Text("No backups in Google Drive › BillBox Backups yet.").foregroundStyle(.secondary)
                }
                ForEach(driveList, id: \.rid) { b in
                    Button { Task { await fetch(b) } } label: {
                        HStack {
                            Image(systemName: b.bool("on_device") ? "checkmark.circle" : "icloud.and.arrow.down").foregroundStyle(Theme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(b.str("name")).font(.callout.monospaced())
                                Text(b.bool("on_device") ? "Also on this device" : "Only in Google Drive").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if fetching == b.str("name") { ProgressView() }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!fetching.isEmpty)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 360)
    }

    private func openDriveList() async {
        driveList = []; listing = true; showDrive = true
        defer { listing = false }
        do {
            driveList = try await API.list("/backup/drive/list")
        } catch {
            showDrive = false
            app.notify(error.localizedDescription, error: true)
        }
    }

    private func fetch(_ b: JSON) async {
        fetching = b.str("name"); defer { fetching = "" }
        await app.guarded {
            let r = try await API.obj("POST", "/backup/drive/download", body: ["id": b.str("id"), "name": b.str("name")])
            showDrive = false
            try? await Task.sleep(nanoseconds: 400_000_000)   // let the sheet close before the Replace / Merge question
            if r.int("downloaded") > 0 { app.notify("Brought \(r.str("name")) from Google Drive (\(r.int("downloaded")) files).") }
            onRestore?(r.str("name"))
        }
    }

    private func shortId(_ id: String) -> String {
        let head = id.components(separatedBy: ".apps.googleusercontent.com").first ?? id
        return head.count > 22 ? String(head.prefix(10)) + "…" + String(head.suffix(8)) : head
    }

    /// Settings › Google Drive › Import: the client_secret_….json downloaded from Google Cloud holds both keys.
    private func importJSON() async {
        guard let text = await Files.pickJSON() else { return }
        // the Files picker is still closing: changes made now were lost on iPhone, so wait for it to finish
        try? await Task.sleep(nanoseconds: 450_000_000)
        busy = true; defer { busy = false }
        await app.guarded {
            status = try await API.obj("PUT", "/backup/drive/client", body: ["json": text])
            editingKeys = false; secret = ""; clientId = ""
            app.notify("Google keys imported. Now press Connect Google Drive.")
        }
        await load()
    }

    private func copy(_ text: String) {
        Files.copy(text)
        app.notify("Code copied.")
    }

    private func load() async {
        if let s = try? await API.obj("GET", "/backup/drive") { status = s }
    }

    private func saveKeys() async {
        busy = true; defer { busy = false }
        await app.guarded {
            status = try await API.obj("PUT", "/backup/drive/client", body: ["client_id": clientId, "client_secret": secret])
            editingKeys = false; secret = ""
            app.notify("Google keys saved. Now press Connect Google Drive.")
        }
        await load()
    }

    private func connect() async {
        busy = true; defer { busy = false }
        await app.guarded {
            let r = try await API.obj("POST", "/backup/drive/connect", body: [:])
            code = r.str("user_code")
            link = r.str("verification_url").isEmpty ? link : r.str("verification_url")
            let every = max(5, r.int("interval")), until = Date().addingTimeInterval(Double(max(60, r.int("expires_in"))))
            startPolling(every: every, until: until)
        }
    }

    private func startPolling(every: Int, until: Date) {
        polling?.cancel()
        polling = Task {
            while !Task.isCancelled && Date() < until {
                try? await Task.sleep(nanoseconds: UInt64(every) * 1_000_000_000)
                if Task.isCancelled { return }
                do {
                    let r = try await API.obj("POST", "/backup/drive/poll", body: [:])
                    if r.bool("connected") {
                        code = ""
                        await load()
                        app.notify("Google Drive connected. Backups now also go to Drive › BillBox Backups.")
                        return
                    }
                } catch {
                    if (error as? APIError)?.code == "OFFLINE" { continue }   // try again on the next round
                    code = ""
                    app.notify(error.localizedDescription, error: true)
                    await load()
                    return
                }
            }
            if !Task.isCancelled { code = ""; app.notify("The code ran out. Press Connect Google Drive again.", error: true) }
        }
    }

    private func stopPolling() { polling?.cancel(); polling = nil; code = "" }

    private func upload() async {
        busy = true; defer { busy = false }
        await app.guarded {
            let r = try await API.obj("POST", "/backup/drive/upload", body: [:])
            app.notify("Uploaded \(r.str("folder")) to Google Drive (\(r.int("files")) files).")
        }
        await load()
    }

    private func disconnect() async {
        await app.guarded { status = try await API.obj("POST", "/backup/drive/disconnect", body: [:]) }
        app.notify("Google Drive disconnected. Backups stay on this device; the copies already in Drive are not touched.")
    }
}

/// The one button style of the Google Drive section (iPhone and Mac): full width, same height, icon and title.
struct DriveButton: View {
    let title: String, icon: String
    var prominent = false, destructive = false, disabled = false
    let action: () -> Void
    init(_ title: String, _ icon: String, prominent: Bool = false, destructive: Bool = false, disabled: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.icon = icon; self.prominent = prominent; self.destructive = destructive; self.disabled = disabled; self.action = action
    }
    var body: some View {
        Group {
            if prominent {
                Button(role: destructive ? .destructive : nil, action: action) { label }.buttonStyle(.borderedProminent)
            } else {
                Button(role: destructive ? .destructive : nil, action: action) { label }.buttonStyle(.bordered)
            }
        }
        .controlSize(.large)
        .disabled(disabled)
    }
    private var label: some View {
        Label(title, systemImage: icon).font(.body.weight(prominent ? .semibold : .regular)).frame(maxWidth: .infinity, minHeight: 22)
    }
}
