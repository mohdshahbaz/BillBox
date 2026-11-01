import SwiftUI
import AppKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when the app is started with `swift run` rather than from a .app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    /// Optional backup on quit: hold the quit for a moment, run the backup, then quit.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor in
            if let c = try? await API.obj("GET", "/backup").obj("config"), c.bool("on_exit") || c.str("on_exit") == "1" {
                _ = try? await API.obj("POST", "/backup/run", body: [:])
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) {
        Backend.shared.stop()
    }
}

@main
struct DistributorProApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var app = AppModel()
    @AppStorage("theme") private var themeId = "clean"
    @AppStorage("appearance") private var appearance = "auto"
    @AppStorage("accentOverride") private var accentOverride = ""
    @AppStorage("pageStyle") private var pageStyle = ""

    var body: some Scene {
        WindowGroup("BillBox") {
            RootView()
                .environmentObject(app)
                .frame(minWidth: 1080, minHeight: 680)
                .environment(\.locale, Locale(identifier: "en_IN"))
                .tint(AppTheme.current.accent)
                .accentColor(AppTheme.current.accent)
                .preferredColorScheme(appearance == "light" ? .light : (appearance == "dark" ? .dark : nil))
                .modifier(FontChoice())
                .modifier(InterfaceSizeChoice())
                .id(themeId + accentOverride + pageStyle)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Go") {
                ForEach(Array(Page.allCases.enumerated()), id: \.element) { i, s in
                    Button(s.title) { app.section = s }
                        .keyboardShortcut(KeyEquivalent(Character(i < 9 ? "\(i + 1)" : "0")), modifiers: .command)
                }
            }
        }
    }
}

/// Settings › Appearance › Interface size: controls and the default text a step smaller or larger.
struct InterfaceSizeChoice: ViewModifier {
    @AppStorage("textSize") private var size = "default"
    @ViewBuilder func body(content: Content) -> some View {
        switch size {
        case "small": content.controlSize(.small).font(.system(size: 12))
        case "large": content.controlSize(.large).font(.system(size: 15))
        default: content
        }
    }
}
