import SwiftUI
import UIKit
import Darwin

/// If BillBox ever closes unexpectedly, the next launch shows what happened (with Copy and Share), so the reason can be sent
/// instead of guessed. Catches Objective-C exceptions, crash signals and the last lines BillBox printed (a Swift fatal error
/// prints its reason there). Nothing leaves the phone unless you share it.
enum CrashCatcher {
    private static var folder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("CrashCatcher", isDirectory: true)
    }
    static var reportURL: URL { folder.appendingPathComponent("last-crash.txt") }
    private static var logURL: URL { folder.appendingPathComponent("session.log") }
    private static var previousLogURL: URL { folder.appendingPathComponent("previous-session.log") }
    private static var markerURL: URL { folder.appendingPathComponent("running") }

    /// Paths prepared before a crash: a signal handler must not allocate.
    private static var reportPath: [CChar] = []

    static func install() {
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)

        // The previous run never reached a normal end (the marker is still there) and left no report: iOS killed it
        // (out of memory, or the main thread was stuck too long). Keep its printed lines as the report.
        if fm.fileExists(atPath: markerURL.path) && !fm.fileExists(atPath: reportURL.path), let tail = tailOf(logURL), !tail.isEmpty {
            try? ("BillBox stopped without a crash signal (iOS ended it).\n\nLast lines it printed:\n" + tail).write(to: reportURL, atomically: true, encoding: .utf8)
        }
        try? fm.removeItem(at: previousLogURL)
        try? fm.moveItem(at: logURL, to: previousLogURL)
        _ = fm.createFile(atPath: markerURL.path, contents: Data())

        // While Xcode is attached its console shows everything; otherwise keep what BillBox prints in a file.
        if !debuggerAttached() {
            freopen(logURL.path, "a+", stderr)
            setvbuf(stderr, nil, _IONBF, 0)
        }
        reportPath = Array(reportURL.path.utf8CString)

        NSSetUncaughtExceptionHandler { e in
            let text = "Uncaught exception: \(e.name.rawValue)\nReason: \(e.reason ?? "")\n\n" + e.callStackSymbols.joined(separator: "\n")
            CrashCatcher.write(text)
        }
        for sig in [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGFPE] {
            signal(sig) { s in
                // best effort: symbols of this thread, then let the system's crash report happen as usual
                let text = "Crash signal \(s) (\(CrashCatcher.signalName(s)))\n\n" + Thread.callStackSymbols.joined(separator: "\n")
                CrashCatcher.write(text)
                signal(s, SIG_DFL)
                raise(s)
            }
        }
    }

    /// The app reached the background normally: not a crash.
    static func markClean() { try? FileManager.default.removeItem(at: markerURL) }
    static func markRunning() { _ = FileManager.default.createFile(atPath: markerURL.path, contents: Data()) }

    static func signalName(_ s: Int32) -> String {
        switch s {
        case SIGABRT: return "abort"
        case SIGSEGV: return "bad memory access"
        case SIGBUS: return "bus error"
        case SIGILL: return "illegal instruction"
        case SIGTRAP: return "Swift runtime error"
        case SIGFPE: return "arithmetic error"
        default: return "signal"
        }
    }

    fileprivate static func write(_ body: String) {
        let info = Bundle.main.infoDictionary
        let header = "BillBox \(info?["CFBundleShortVersionString"] ?? "") (\(info?["CFBundleVersion"] ?? "")) · \(UIDevice.current.model) · iOS \(UIDevice.current.systemVersion)\n\(Date())\n\n"
        fflush(stderr)
        let printed = tailOf(logURL).map { "\n\nLast lines BillBox printed:\n" + $0 } ?? ""
        let text = header + body + printed
        text.withCString { p in
            reportPath.withUnsafeBufferPointer { path in
                guard let base = path.baseAddress else { return }
                let fd = open(base, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
                if fd >= 0 { _ = Darwin.write(fd, p, strlen(p)); close(fd) }
            }
        }
    }

    static func pendingReport() -> String? {
        try? String(contentsOf: reportURL, encoding: .utf8)
    }

    static func clearReport() { try? FileManager.default.removeItem(at: reportURL) }

    private static func tailOf(_ url: URL, lines: Int = 60) -> String? {
        guard let s = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return s.split(separator: "\n", omittingEmptySubsequences: false).suffix(lines).joined(separator: "\n")
    }

    private static func debuggerAttached() -> Bool {
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return false }
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }
}

/// Shown once after an unexpected close.
@MainActor struct CrashReportSheet: View {
    let report: String
    let done: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("BillBox closed unexpectedly the last time it was used. Your books are safe: every bill is saved the moment you save it. Please send this report so the cause can be fixed.")
                        .font(.callout)
                    Text(report).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 8))
                }
                .padding(16)
            }
            .navigationTitle("Last close")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { done() } }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { Files.copy(report) } label: { Label("Copy", systemImage: "doc.on.doc") }
                    Spacer()
                    Button {
                        if let u = Files.temp("BillBox-crash-report.txt", Data(report.utf8)) { Files.share(u) }
                    } label: { Label("Share…", systemImage: "square.and.arrow.up") }
                }
            }
        }
    }
}
