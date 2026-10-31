import SwiftUI

/// Settings › Backup › Google Drive: each backup also goes into "BillBox Backups" in the user's Google Drive.
/// Sign-in is Google's code sign-in: BillBox shows a short code, the user enters it at google.com/device on any phone or
/// computer and allows BillBox; BillBox notices by itself. (Same file on iPhone and Mac.)
@MainActor struct DriveBackupSection: View {
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
            if !code.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. Open google.com/device on any phone or computer.\n2. Enter this code and allow BillBox:").font(.callout)
                    Text(code).font(.system(size: 30, weight: .bold, design: .monospaced)).frame(maxWidth: .infinity).textSelection(.enabled)
                    HStack {
                        Button { if let u = URL(string: link) { openURL(u) } } label: { Label("Open google.com/device", systemImage: "safari") }
                            .buttonStyle(.borderedProminent)
                        Button { copy(code) } label: { Label("Copy code", systemImage: "doc.on.doc") }.buttonStyle(.bordered)
                    }
                    Button("Cancel", role: .cancel) { stopPolling() }.buttonStyle(.borderless)
                }
                .padding(.vertical, 4)
            }
            if connected {
                Button { Task { await upload() } } label: { Text(busy ? "Uploading…" : "Upload the newest backup now") }.disabled(busy)
                Button("Disconnect Google Drive", role: .destructive) { Task { await disconnect() } }.disabled(busy)
            } else if code.isEmpty {
                if hasKeys && !editingKeys {
                    Button { Task { await connect() } } label: { Label(busy ? "Connecting…" : "Connect Google Drive", systemImage: "link") }
                        .buttonStyle(.borderedProminent).disabled(busy)
                    Button("Change Google keys…") { editingKeys = true; clientId = status.str("client_id") }.buttonStyle(.borderless)
                } else {
                    TextField("Client ID (…apps.googleusercontent.com)", text: $clientId).textFieldStyle(.roundedBorder).autocorrectionDisabled()
                    SecureField("Client secret", text: $secret).textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Save keys") { Task { await saveKeys() } }.buttonStyle(.borderedProminent)
                            .disabled(busy || clientId.trimmingCharacters(in: .whitespaces).isEmpty || secret.trimmingCharacters(in: .whitespaces).isEmpty)
                        if hasKeys { Button("Cancel") { editingKeys = false }.buttonStyle(.bordered) }
                    }
                }
            }
        } header: {
            Text("Google Drive")
        } footer: {
            Text(connected
                 ? "Every backup (Back up now, the daily backup and the backup on quitting) is also uploaded to your Google Drive, into a folder with the backup's name inside BillBox Backups. The copy on this device stays as well. BillBox can see only the files it made itself in your Drive."
                 : "One-time setup (about 5 minutes, free): in console.cloud.google.com make a project, turn on the Google Drive API, set up the consent screen (External; add your Gmail as a test user), then Credentials › Create credentials › OAuth client ID › type “TVs and Limited Input devices”. Paste its Client ID and secret here, then Connect. The same keys work on the Mac, iPhone and Android.")
        }
        .task { await load() }
        .onDisappear { polling?.cancel() }
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
