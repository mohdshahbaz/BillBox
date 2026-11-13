import SwiftUI
import UIKit
import BackgroundTasks

@main
struct BillBoxApp: App {
    @StateObject private var app = AppModel()
    @AppStorage("theme") private var themeId = "clean"
    @AppStorage("appearance") private var appearance = "auto"
    @AppStorage("accentOverride") private var accentOverride = ""
    @AppStorage("pageStyle") private var pageStyle = ""
    @Environment(\.scenePhase) private var phase

    /// The theme colour for what UIKit draws itself (alerts, the Files picker, the share sheet, the keyboard bar), which
    /// SwiftUI's tint does not reach.
    @MainActor private func themeChanged() {
        BillBoxApp.tintWindows()
        app.objectWillChange.send()       // every screen that shows the books redraws with the new colours
    }

    @MainActor static func tintWindows() {
        let c = UIColor(AppTheme.current.accent)
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for w in scene.windows { w.tintColor = c }
        }
    }

    init() {
        CrashCatcher.install()
        BackupScheduler.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environment(\.locale, Locale(identifier: "en_IN"))
                .tint(AppTheme.current.accent)
                .preferredColorScheme(appearance == "light" ? .light : (appearance == "dark" ? .dark : nil))
                .modifier(TextSizeChoice())
                .modifier(FontChoice())
                .appChrome()
                // no .id(theme) here: rebuilding every screen closed the open page (Settings › Appearance) on each change;
                // the screens redraw instead, so the new colours show while the page stays open
                .onAppear { BillBoxApp.tintWindows() }
                .onChange(of: themeId) { _ in themeChanged() }
                .onChange(of: accentOverride) { _ in themeChanged() }
                .onChange(of: pageStyle) { _ in themeChanged() }
        }
        .onChange(of: phase) { p in
            switch p {
            case .active:
                CrashCatcher.markRunning()
                BackupScheduler.startTimer(app)
            case .background:
                CrashCatcher.markClean()
                BackupScheduler.stopTimer()
                BackupScheduler.backupOnLeave(app)
                BackupScheduler.scheduleBackground()
            default: break
            }
        }
    }
}

/// Daily backup (decisions D2, D3):
///  - while BillBox is open: checked every minute and shortly after launch, exactly like the Mac;
///  - "back up when I quit": iOS has no quit, so it runs each time BillBox goes to the background;
///  - when BillBox is closed: a background task is requested for the backup time; iOS decides when (or whether) it runs.
@MainActor
enum BackupScheduler {
    nonisolated static let taskId = "com.local.billbox.backup"
    private static var timer: Timer?

    nonisolated static func register() {
        _ = BGTaskScheduler.shared.register(forTaskWithIdentifier: taskId, using: nil) { task in
            let work = Task {
                let ran = await EngineHost.shared.backupIfDue()
                task.setTaskCompleted(success: true)
                _ = ran
            }
            task.expirationHandler = { work.cancel() }
            Task { @MainActor in scheduleBackground() }
        }
    }

    static func startTimer(_ app: AppModel) {
        timer?.invalidate()
        Task {
            await pause(ms: 5000)   // catch up a missed backup shortly after launch
            if let f = await EngineHost.shared.backupTick() { app.notify("Backup complete: \((f as NSString).lastPathComponent)") }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in
                if let f = await EngineHost.shared.backupTick() { app.notify("Backup complete: \((f as NSString).lastPathComponent)") }
            }
        }
    }

    static func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    static func backupOnLeave(_ app: AppModel) {
        let bg = UIApplication.shared.beginBackgroundTask(withName: "BillBox backup")
        Task {
            if let c = try? await API.obj("GET", "/backup").obj("config"), c.bool("on_exit") || c.str("on_exit") == "1" {
                _ = try? await API.obj("POST", "/backup/run", body: [:])
            }
            UIApplication.shared.endBackgroundTask(bg)
        }
    }

    /// Asks iOS to wake BillBox around the next backup time.
    static func scheduleBackground() {
        Task {
            guard let c = try? await API.obj("GET", "/backup").obj("config"), c.bool("enabled") || c.str("enabled") == "1" else { return }
            let parts = c.str("time").split(separator: ":").compactMap { Int($0) }
            var cal = Calendar.current
            cal.timeZone = TimeZone.current
            var next = cal.date(bySettingHour: parts.first ?? 21, minute: parts.count > 1 ? parts[1] : 0, second: 0, of: Date()) ?? Date()
            if next < Date() { next = cal.date(byAdding: .day, value: 1, to: next) ?? next }
            let req = BGAppRefreshTaskRequest(identifier: taskId)
            req.earliestBeginDate = next
            try? BGTaskScheduler.shared.submit(req)
        }
    }
}

/// Settings › Appearance › Text size: the system size unless one is chosen for BillBox.
struct TextSizeChoice: ViewModifier {
    @AppStorage("textSize") private var size = "default"
    @ViewBuilder func body(content: Content) -> some View {
        switch size {
        case "small": content.dynamicTypeSize(.medium)
        case "large": content.dynamicTypeSize(.xLarge)
        case "xlarge": content.dynamicTypeSize(.xxxLarge)
        default: content
        }
    }
}
