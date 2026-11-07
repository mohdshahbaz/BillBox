import SwiftUI

/// Settings › Sync: live sync of a company's books between this Mac, Android phones and Windows/Linux PCs through the
/// BillBox Firebase database (backend services/sync.js). The app calls GET /sync/tick every few seconds (AppModel).
@MainActor struct SyncSettings: View {
    @EnvironmentObject private var app: AppModel
    @State private var s = JSON()
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var remote: [JSON] = []
    @State private var loadedRemote = false

    private var signedIn: Bool { s.bool("signed_in") }
    private var companyName: String { app.company?.str("name") ?? "this company" }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: s.bool("on") ? "arrow.triangle.2.circlepath.icloud.fill" : signedIn ? "icloud" : "icloud.slash")
                        .font(.title2).foregroundStyle(s.bool("on") ? Color.green : Color.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(!signedIn ? "Not signed in" : s.bool("on") ? "\(companyName) is synced live" : "Signed in as \(s.str("email"))")
                            .font(.callout.weight(.medium))
                        if signedIn {
                            Text(s.bool("on") ? "Changes made on any device show on the others within a few seconds." : "Turn on sync for \(companyName) to share it with your other devices.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if !s.str("last_sync").isEmpty { Text("Last sync: \(Fmt.ist(s.str("last_sync")))\(s.int("pending") > 0 ? " · \(s.int("pending")) changes waiting" : "")").font(.caption).foregroundStyle(.secondary) }
                        if !s.str("last_error").isEmpty { Text(s.str("last_error")).font(.caption).foregroundStyle(.red) }
                    }
                }
                if !signedIn {
                    TextField("E-mail", text: $email).autocorrectionDisabled()
                    SecureField("Password (6 or more characters)", text: $password)
                    DriveButton(busy ? "Signing in…" : "Sign in", "person.crop.circle.badge.checkmark", prominent: true, disabled: busy || email.isEmpty || password.isEmpty) { Task { await signIn(create: false) } }
                    DriveButton("Create a sync account", "person.crop.circle.badge.plus", disabled: busy || email.isEmpty || password.count < 6) { Task { await signIn(create: true) } }
                } else {
                    if s.bool("on") {
                        DriveButton(busy ? "Syncing…" : "Sync now", "arrow.clockwise.icloud", prominent: true, disabled: busy) { Task { await run("POST", "/sync/now") } }
                        DriveButton("Stop syncing \(companyName) on this Mac", "icloud.slash", destructive: true, disabled: busy) { Task { await run("POST", "/sync/off") } }
                    } else {
                        DriveButton(busy ? "Sending the books…" : "Turn on sync for \(companyName)", "icloud.and.arrow.up", prominent: true, disabled: busy) { Task { await run("POST", "/sync/on") } }
                    }
                    DriveButton("Sign out of sync", "rectangle.portrait.and.arrow.right", disabled: busy) { Task { await run("POST", "/sync/signout") } }
                }
            } header: { Text("Live sync") } footer: {
                Text("Every device keeps its own copy of the books and works without internet; changes go across when it is online. Sign in with the same account on each device. Stock sold on two devices at once counts both sales; two bills made at the same moment keep different numbers.")
            }

            if signedIn {
                Section {
                    ForEach(remote) { b in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(b.str("name")).font(.callout.weight(.medium))
                                if !b.str("fy").isEmpty { Text("Year \(b.str("fy"))").font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            if b.bool("on_this_device") { Text("On this Mac").font(.caption).foregroundStyle(.secondary) }
                            else { Button("Bring here") { Task { await join(b.str("key")) } }.disabled(busy) }
                        }
                    }
                    if loadedRemote && remote.isEmpty { Text("No company is synced in this account yet.").foregroundStyle(.secondary) }
                    DriveButton(loadedRemote ? "Look again" : "Show the companies in this account", "list.bullet", disabled: busy) { Task { await loadRemote() } }
                } header: { Text("Companies in your sync account") } footer: {
                    Text("Bring here makes a new company on this Mac that fills itself from your other devices.")
                }
            }

            Section {
                Text("1. Firebase console › Authentication › Sign-in method › turn on Email/Password.\n2. Realtime Database › Rules › paste these rules and Publish:").font(.callout)
                Text(s.str("rules")).font(.caption.monospaced()).textSelection(.enabled)
                Button("Copy rules") { Files.copy(s.str("rules")); app.notify("Rules copied.") }
            } header: { Text("One-time Firebase setup") }
        }
        .groupedForm()
        .task(id: app.companyId) { await load() }
    }

    private func load() async {
        if let r = try? await API.obj("GET", "/sync") { s = r }
        if signedIn && !loadedRemote { await loadRemote() }
    }

    private func signIn(create: Bool) async {
        busy = true; defer { busy = false }
        await app.guarded {
            s = try await API.obj("POST", "/sync/signin", body: ["email": email, "password": password, "create": create])
            password = ""
            app.notify(create ? "Sync account made. Now turn on sync for a company, or bring one here from your other device." : "Signed in to sync.")
            await loadRemote()
        }
    }

    private func run(_ method: String, _ path: String) async {
        busy = true; defer { busy = false }
        await app.guarded {
            s = try await API.obj(method, path)
            if !s.str("last_error").isEmpty { app.notify(s.str("last_error"), error: true) }
            if path == "/sync/signout" { remote = []; loadedRemote = false } else { await loadRemote() }
        }
    }

    private func loadRemote() async {
        guard signedIn else { return }
        do { remote = try await API.obj("GET", "/sync/remote").list("books"); loadedRemote = true }
        catch { s.raw["last_error"] = error.localizedDescription }
    }

    private func join(_ key: String) async {
        busy = true; defer { busy = false }
        await app.guarded {
            let r = try await API.obj("POST", "/sync/join", body: ["key": key])
            try await app.reloadCompanies()
            app.notify("The company is on this Mac now. Switch to it from the top of the sidebar.")
            s = r
            await loadRemote()
        }
    }
}
