import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Settings › Updates: the newest BillBox release of this edition (engine GET /update). On the Mac it is downloaded,
/// put in place of this app and opened; on the iPhone (an unsigned build, installed with Sideloadly or AltStore) the
/// download page opens. Same file on iPhone and Mac.
enum AppUpdate {
    static var version: String { (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "" }
    static var edition: String { (Bundle.main.object(forInfoDictionaryKey: "BillBoxEdition") as? String) ?? "public" }
    #if os(macOS)
    #if arch(arm64)
    static let platform = "mac-arm64"   // the Apple silicon build updates to the Apple silicon build
    #else
    static let platform = "mac-intel"
    #endif
    #else
    static let platform = "iphone"
    #endif

    static func check() async throws -> JSON {
        try await API.obj("GET", "/update", query: ["version": version, "edition": edition, "platform": platform])
    }

    #if os(macOS)
    /// Downloads the zip, unpacks it and, once this app has quit, puts the new BillBox where this one is and opens it.
    static func install(_ url: URL, progress: @escaping (Double) -> Void) async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("BillBox-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let zip = tmp.appendingPathComponent("BillBox.zip")
        progress(0.05)
        let (file, resp) = try await URLSession.shared.download(from: url)
        if let h = resp as? HTTPURLResponse, h.statusCode != 200 { throw APIError(message: "The download answered \(h.statusCode).", status: h.statusCode, code: nil) }
        try FileManager.default.moveItem(at: file, to: zip)
        progress(0.7)
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, tmp.path])
        let new = tmp.appendingPathComponent("BillBox.app")
        guard FileManager.default.fileExists(atPath: new.path) else { throw APIError(message: "The download has no BillBox.app in it.", status: 0, code: nil) }
        progress(0.9)
        let dest = Bundle.main.bundleURL.path
        let script = tmp.appendingPathComponent("swap.sh")
        // waits for this BillBox to quit, swaps the app (the old one comes back if anything fails) and opens the new one
        try """
        #!/bin/sh
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.5; done
        rm -rf "\(dest).old"
        if mv "\(dest)" "\(dest).old" && /usr/bin/ditto "\(new.path)" "\(dest)"; then rm -rf "\(dest).old"; else rm -rf "\(dest)"; mv "\(dest).old" "\(dest)"; fi
        /usr/bin/xattr -dr com.apple.quarantine "\(dest)" 2>/dev/null
        /usr/bin/open "\(dest)"
        rm -rf "\(tmp.path)"
        """.write(to: script, atomically: true, encoding: .utf8)
        try run("/bin/sh", ["-c", "nohup /bin/sh '\(script.path)' >/dev/null 2>&1 &"])
        progress(1)
        await MainActor.run { NSApp.terminate(nil) }
    }

    private static func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 { throw APIError(message: "Could not unpack the update (\(tool) \(p.terminationStatus)).", status: 0, code: nil) }
    }
    #endif

    static func open(_ s: String) {
        guard let u = URL(string: s) else { return }
        #if os(macOS)
        NSWorkspace.shared.open(u)
        #else
        UIApplication.shared.open(u)
        #endif
    }
}

@MainActor struct UpdateSettings: View {
    @EnvironmentObject private var app: AppModel
    @State private var u: JSON?
    @State private var errorText: String?
    @State private var busy = false
    @State private var progress: Double?

    var body: some View {
        Form {
            Section {
                Text("This \(AppUpdate.platform.hasPrefix("mac") ? "Mac" : "iPhone") has BillBox \(AppUpdate.version)\(AppUpdate.edition == "admin" ? " (admin)" : "")")
                if let errorText { Text(errorText).foregroundStyle(Theme.negative).font(.callout) }
                else if let u {
                    if u.bool("available") {
                        Text("BillBox \(u.str("latest")) is available").font(.headline)
                        if !u.str("notes").isEmpty { Text(String(u.str("notes").prefix(600))).font(.caption).foregroundStyle(.secondary) }
                        if let progress { ProgressView(value: progress) }
                        #if os(macOS)
                        DriveButton(busy ? "Updating…" : "Download and install \(u.str("latest"))", "arrow.down.circle", prominent: true, disabled: busy) { Task { await install(u) } }
                        Text("BillBox closes, the new version takes its place and opens. Your books stay as they are.").font(.caption).foregroundStyle(.secondary)
                        #else
                        DriveButton("Open the download page", "safari", prominent: true) { AppUpdate.open(u.str("page")) }
                        Text("The iPhone build is installed with Sideloadly or AltStore: download the .ipa from the page and install it the same way. Your books stay as they are.")
                            .font(.caption).foregroundStyle(.secondary)
                        #endif
                    } else {
                        Text(u.str("latest").isEmpty ? "No release found." : "BillBox is up to date (newest: \(u.str("latest"))).").foregroundStyle(.secondary)
                    }
                } else {
                    HStack { ProgressView(); Text("Looking for a new version…").foregroundStyle(.secondary) }
                }
                DriveButton("Look again", "arrow.clockwise", disabled: busy) { Task { await load() } }
            } header: { Text("Updates") } footer: { Text("Back up first to be safe (Settings › Backup).") }
        }
        #if os(macOS)
        .settingsForm()
        #else
        .groupedForm()
        #endif
        .task { await load() }
    }

    private func load() async {
        errorText = nil; u = nil
        do { u = try await AppUpdate.check() } catch { errorText = error.localizedDescription }
    }

    #if os(macOS)
    private func install(_ u: JSON) async {
        let f = u.obj("file")
        guard let url = URL(string: f.str("url")), !f.str("url").isEmpty else { AppUpdate.open(u.str("page")); return }
        busy = true; progress = 0
        do { try await AppUpdate.install(url) { p in Task { @MainActor in progress = p } } }
        catch { errorText = error.localizedDescription; busy = false; progress = nil }
    }
    #endif
}
