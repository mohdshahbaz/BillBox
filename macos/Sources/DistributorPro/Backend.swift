import Foundation
import AppKit

/// Starts the Node backend from inside the app, so there is no separate terminal to keep open.
/// The folder is chosen once and remembered. Everything the backend stores stays in that folder's data/ directory.
@MainActor
final class Backend {
    static let shared = Backend()
    private var process: Process?
    private let key = "backendFolder"

    var folder: String? {
        get { UserDefaults.standard.string(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Finds a likely backend folder next to the app, so the first launch needs no clicks when run from the project.
    func guessFolder() -> String? {
        if let f = folder, FileManager.default.fileExists(atPath: f + "/src/server.js") { return f }
        let cwd = FileManager.default.currentDirectoryPath
        for rel in ["../backend", "backend", "../../backend"] {
            let p = URL(fileURLWithPath: cwd).appendingPathComponent(rel).standardized.path
            if FileManager.default.fileExists(atPath: p + "/src/server.js") { return p }
        }
        return nil
    }

    func chooseFolder() -> String? {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.message = "Choose the backend folder (the one that contains src/server.js)"
        guard p.runModal() == .OK, let url = p.url else { return nil }
        guard FileManager.default.fileExists(atPath: url.path + "/src/server.js") else { return nil }
        folder = url.path
        return url.path
    }

    /// Inside the built app: the server and its own copy of Node live in the app's Resources folder.
    var isBundled: Bool { bundled != nil }
    private var bundled: (node: String, server: String)? {
        guard let res = Bundle.main.resourcePath else { return nil }
        let node = res + "/runtime/node", server = res + "/backend/src/server.js"
        let fm = FileManager.default
        return fm.isExecutableFile(atPath: node) && fm.fileExists(atPath: server) ? (node, server) : nil
    }

    /// Books are kept here (not inside the app), so replacing the app never touches the data.
    static var dataFolder: String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base.appendingPathComponent("DistributorPro/data").path
    }

    static var logPath: String { (dataFolder as NSString).deletingLastPathComponent + "/server.log" }

    /// Last lines the server printed (why it did not start).
    static func logTail() -> String {
        guard let s = try? String(contentsOfFile: logPath, encoding: .utf8) else { return "" }
        return s.split(separator: "\n").suffix(8).joined(separator: "\n")
    }

    /// Launches the server and waits (up to ~15 s) for it to answer.
    func start() async -> String? {
        guard process?.isRunning != true else { return nil }
        let p = Process()
        var env = ProcessInfo.processInfo.environment
        if let b = bundled {
            try? FileManager.default.createDirectory(atPath: Backend.dataFolder, withIntermediateDirectories: true)
            p.executableURL = URL(fileURLWithPath: b.node)
            p.arguments = ["--disable-warning=ExperimentalWarning", b.server]
            p.currentDirectoryURL = URL(fileURLWithPath: (b.server as NSString).deletingLastPathComponent)
            env["DATA_DIR"] = Backend.dataFolder
            // which BillBox this is (services/license.js): from the app's Info.plist, set when the app is built
            env["BILLBOX_EDITION"] = (Bundle.main.object(forInfoDictionaryKey: "BillBoxEdition") as? String) ?? "public"
        } else {
            // running with `swift run` from the project: use the backend folder and a Node on this Mac
            guard let dir = guessFolder() ?? folder else { return "Choose the backend folder first." }
            p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            p.arguments = ["node", "--disable-warning=ExperimentalWarning", "src/server.js"]
            p.currentDirectoryURL = URL(fileURLWithPath: dir)
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        }
        p.environment = env
        // everything the server prints goes to a log file, so a failed start can be explained
        try? FileManager.default.createDirectory(atPath: (Backend.logPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: Backend.logPath, contents: nil)
        let log = FileHandle(forWritingAtPath: Backend.logPath)
        p.standardOutput = log ?? FileHandle.nullDevice
        p.standardError = log ?? FileHandle.nullDevice
        do { try p.run() } catch { return "Could not start the server (\(p.executableURL?.path ?? "")): \(error.localizedDescription)" }
        process = p
        for _ in 0..<60 {
            await pause(ms: 250)
            if await API.healthy() { return nil }
            if !p.isRunning { return "The server stopped right after starting.\n" + Backend.logTail() }
        }
        return "The server did not answer in time."
    }

    func stop() { process?.terminate() }
}
