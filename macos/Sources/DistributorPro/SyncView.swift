import SwiftUI

/// Settings › Sync: live sync of a company's books between iPhone, Mac, Android phones and Windows/Linux PCs through the
/// BillBox Firebase database (backend services/sync.js; iPhone: BillBoxCore Sync.swift). The app calls GET /sync/tick
/// every few seconds (AppModel). Same file on iPhone and Mac.
@MainActor struct SyncSettings: View {
    @EnvironmentObject private var app: AppModel
    @State private var s = JSON()
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var remote: [JSON] = []
    @State private var loadedRemote = false
    @State private var canMerge = false
    @State private var mergeKey: String?

    #if os(macOS)
    private let device = "Mac"
    #else
    private let device = "iPhone"
    #endif
    private var signedIn: Bool { s.bool("signed_in") }
    private var companyName: String { app.company?.str("name") ?? "this company" }

    var body: some View {
        SettingsForm {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: s.bool("on") ? "arrow.triangle.2.circlepath.icloud.fill" : signedIn ? "icloud" : "icloud.slash")
                        .font(.title2).foregroundStyle(s.bool("on") ? Theme.positive : Color.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(!signedIn ? "Not signed in" : s.bool("on") ? "\(companyName) is synced live" : "Signed in as \(s.str("email"))")
                            .font(.callout.weight(.medium))
                        if signedIn {
                            Text(s.bool("on") ? "Changes made on any device show on the others within a few seconds." : "Turn on sync for \(companyName) to share it with your other devices.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if !s.str("last_sync").isEmpty { Text("Last sync: \(Fmt.ist(s.str("last_sync")))\(s.int("pending") > 0 ? " · \(s.int("pending")) changes waiting" : "")").font(.caption).foregroundStyle(.secondary) }
                        if !s.str("last_error").isEmpty { Text(s.str("last_error")).font(.caption).foregroundStyle(Theme.negative) }
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
                        DriveButton("Stop syncing \(companyName) on this \(device)", "icloud.slash", destructive: true, disabled: busy) { Task { await run("POST", "/sync/off") } }
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
                                // which copy is open here, and which devices use each copy
                                let who = (b.raw["used_by"] as? [String] ?? []).joined(separator: ", ")
                                Text([b.bool("open") ? "Open now" : nil, who.isEmpty ? nil : "Used by: \(who)"].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(b.bool("open") ? Color.accentColor : .secondary)
                            }
                            Spacer()
                            // the same company as the open one, synced into a book of its own: merge the two
                            if b.bool("same_name") && canMerge { Button("Merge") { mergeKey = b.str("key") }.buttonStyle(.borderedProminent).disabled(busy) }
                            if b.bool("on_this_device") { Text("On this \(device)").font(.caption).foregroundStyle(.secondary) }
                            else { Button("Bring here") { Task { await join(b.str("key")) } }.disabled(busy) }
                        }
                    }
                    if loadedRemote && remote.isEmpty { Text("No company is synced in this account yet.").foregroundStyle(.secondary) }
                    DriveButton(loadedRemote ? "Look again" : "Show the companies in this account", "list.bullet", disabled: busy) { Task { await loadRemote() } }
                } header: { Text("Companies in your sync account") } footer: {
                    Text(remote.contains { $0.bool("same_name") } && canMerge
                         ? "\(companyName) is in the account twice: each device turned on sync for its own copy, so they do not see each other's bills. Merge brings that copy's bills, parties and stock changes into the open one (Open now), and the devices using that copy move to the open one by themselves. A backup is made first."
                         : "Bring here makes a new company on this \(device) that fills itself from your other devices.")
                }
            }

            Section {
                Text("1. Firebase console › Authentication › Sign-in method › turn on Email/Password.\n2. Realtime Database › Rules › paste these rules and Publish:").font(.callout)
                Text(s.str("rules")).font(.caption.monospaced()).textSelection(.enabled)
                Button("Copy rules") { Files.copy(s.str("rules")); app.notify("Rules copied.") }
            } header: { Text("One-time Firebase setup") }
        }
        .confirmationDialog("Bring that copy of \(companyName) into the open one?", isPresented: Binding(get: { mergeKey != nil }, set: { if !$0 { mergeKey = nil } }), titleVisibility: .visible) {
            Button("Merge") { if let k = mergeKey { Task { await merge(k) } } }
            Button("Cancel", role: .cancel) { mergeKey = nil }
        } message: {
            Text("Its bills, parties and stock changes go into the open copy, which every device then shares; the devices on that copy move over by themselves. A backup is made first.")
        }
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
        do { let r = try await API.obj("GET", "/sync/remote"); remote = r.list("books"); canMerge = r.bool("can_merge"); loadedRemote = true }
        catch { s.raw["last_error"] = error.localizedDescription }
    }

    private func merge(_ key: String) async {
        busy = true; defer { busy = false }
        mergeKey = nil
        await app.guarded {
            let r = try await API.obj("POST", "/sync/merge", body: ["key": key])
            try await app.reloadCompanies()
            await app.switchCompany(r.int("company_id"))
            app.notify("Merged: \(r.int("merged")) changes came into the open copy.")
            s = r
            await loadRemote()
        }
    }

    private func join(_ key: String) async {
        busy = true; defer { busy = false }
        await app.guarded {
            let r = try await API.obj("POST", "/sync/join", body: ["key": key])
            try await app.reloadCompanies()
            app.notify("The company is on this \(device) now. Switch to it from the company menu.")
            s = r
            await loadRemote()
        }
    }
}
