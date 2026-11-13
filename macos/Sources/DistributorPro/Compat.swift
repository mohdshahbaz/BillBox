import SwiftUI
import AppKit

// Everything in this file exists so the app runs on macOS 12 (Monterey) and newer.
// Newer SwiftUI features are used when the Mac has them and quietly replaced by a simpler version when it does not.

/// Sleeps without the macOS 13+ `Duration` API.
func pause(ms: Int) async { try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000) }

enum Theme {
    /// Card / panel background and page background follow the chosen theme (Settings > Appearance) and light / dark mode.
    static var card: Color { AppTheme.current.card }
    static var page: Color { AppTheme.current.page }
    /// The theme's accent, for icons drawn in it (`Color.accentColor` can stay the system colour).
    static var accent: Color { AppTheme.current.accent }
    static let line = Color(nsColor: .separatorColor)
}

extension View {
    /// `.fontWeight` arrived in macOS 13.
    @ViewBuilder func fw(_ w: Font.Weight) -> some View {
        if #available(macOS 13.0, *) { self.fontWeight(w) } else { self.font(.body.weight(w)) }
    }

    /// Digits of equal width so money columns line up. `View.monospacedDigit` arrived in macOS 13.
    @ViewBuilder func mono() -> some View {
        if #available(macOS 13.0, *) { self.monospacedDigit() } else { self.font(.body.monospacedDigit()) }
    }

    /// Grouped form look (macOS 13+); on Monterey the standard form is used.
    @ViewBuilder func groupedForm() -> some View {
        if #available(macOS 13.0, *) { self.formStyle(.grouped).scrollContentBackground(.hidden) } else { self }
    }

    /// A Settings tab's form. macOS 13+: the grouped form, which scrolls by itself. macOS 12 (Monterey): a Form does not
    /// scroll and a long tab (Billing & Dashboard) made the tab view lay itself out again and again until the app was
    /// stopped, so it goes inside a scroll view there.
    @ViewBuilder func settingsForm() -> some View {
        if #available(macOS 13.0, *) {
            self.formStyle(.grouped).scrollContentBackground(.hidden)
        } else {
            ScrollView(.vertical) {
                self.padding(.horizontal, 20).padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    func card(_ radius: CGFloat = DS.Radius.card) -> some View { self.modifier(CardBackground(radius: radius)) }
}

/// A Settings tab. macOS 13+: the grouped form. macOS 12 (Monterey): a Form inside a scroll view drew nothing on tabs with
/// pickers and sections (Printing, Billing & Dashboard, Parties & Payments), so there the rows are a plain column with
/// even spacing and margins instead.
struct SettingsForm<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        if #available(macOS 13.0, *) {
            Form { content }.formStyle(.grouped).scrollContentBackground(.hidden)
        } else {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) { content }
                    .pickerStyle(.menu)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.regular)
                    .frame(maxWidth: 640, alignment: .leading)
                    .padding(.horizontal, 24).padding(.vertical, 18)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }
}

/// Replacement for `ContentUnavailableView` (macOS 14+).
struct EmptyState: View {
    let title: String
    var symbol = "tray"
    var message = ""

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 34)).foregroundStyle(.secondary)
            Text(title).font(.title3.weight(.semibold))
            if !message.isEmpty { Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420) }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Replacement for `LabeledContent` (macOS 13+).
struct Labeled<Content: View>: View {
    let title: String
    let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            content
        }
    }
}

/// Simple grouped bar chart (Swift Charts needs macOS 13).
struct BarPair: Identifiable {
    let id: String
    let label: String
    let a: Double
    let b: Double
    var c: Double = 0
}

struct BarChartView: View {
    let data: [BarPair]
    var colors: [Color] = [.teal, Theme.warning, Theme.positive]
    var showThird = false

    var body: some View {
        let top = max(1, data.map { max($0.a, max($0.b, showThird ? $0.c : 0)) }.max() ?? 1)
        VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(data) { d in
                    VStack(spacing: 3) {
                        HStack(alignment: .bottom, spacing: 2) {
                            bar(d.a, top, colors[0])
                            bar(d.b, top, colors[1])
                            if showThird { bar(d.c, top, colors[2]) }
                        }
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        Text(d.label).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity)
                    .help("\(d.label): \(Fmt.money(d.a)) · \(Fmt.money(d.b))" + (showThird ? " · \(Fmt.money(d.c))" : ""))
                }
            }
            Text("Tallest bar = \(Fmt.money(top))").font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func bar(_ v: Double, _ top: Double, _ c: Color) -> some View {
        GeometryReader { g in
            RoundedRectangle(cornerRadius: 2).fill(c)
                .frame(height: max(v > 0 ? 2 : 0, g.size.height * CGFloat(max(0, v) / top)))
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}


/// Arrow-key / Escape handling for the item search box (SwiftUI's own key handling needs macOS 14).
/// While `active`, the handler gets the key code; return true to swallow the key.
struct KeyCatcher: NSViewRepresentable {
    var active: Bool
    var handler: (UInt16) -> Bool

    final class Coordinator {
        var monitor: Any?
        var active = false
        var handler: (UInt16) -> Bool = { _ in false }
        deinit { if let m = monitor { NSEvent.removeMonitor(m) } }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let c = context.coordinator
        c.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak c] event in
            if let c, c.active, c.handler(event.keyCode) { return nil }
            return event
        }
        return NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.active = active
        context.coordinator.handler = handler
    }
}


/// Seven weekday chips; any number can be switched on. The value is a list like "1,3,5" (0 = Sunday).
struct DayPicker: View {
    @Binding var days: String
    private let short = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    private var set: Set<Int> { Set(days.split(separator: ",").compactMap { Int($0) }) }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { i in
                let on = set.contains(i)
                Button {
                    var s = set
                    if on { s.remove(i) } else { s.insert(i) }
                    days = s.sorted().map(String.init).joined(separator: ",")
                } label: {
                    Text(short[i]).font(.callout).frame(minWidth: 34)
                        .padding(.vertical, 4).padding(.horizontal, 3)
                        .background(RoundedRectangle(cornerRadius: 6).fill(on ? Theme.accent : Color.gray.opacity(0.18)))
                        .foregroundColor(on ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// "1,3" -> "Mon, Wed"
func dayList(_ csv: String) -> String {
    csv.split(separator: ",").compactMap { Int($0) }.filter { (0...6).contains($0) }.map { String(dayNames[$0].prefix(3)) }.joined(separator: ", ")
}

/// Panels and cards: background in the theme's colour with the style chosen in Settings › Appearance (soft shadow, outlined
/// or flat) and its corner roundness.
struct CardBackground: ViewModifier {
    @AppStorage("cardStyle") private var style = "soft"
    // read so that panels redraw at once when the theme or its colours change
    @AppStorage("theme") private var themeId = "clean"
    @AppStorage("accentOverride") private var accentOverride = ""
    @AppStorage("corners") private var corners = "normal"
    let radius: CGFloat

    func body(content: Content) -> some View {
        let r = radius * (corners == "square" ? 0.45 : (corners == "round" ? 1.6 : 1))
        // the shadow is drawn from the card's shape only: a shadow on the whole content (every text and icon in it) was
        // worked out again on each frame while scrolling, which made the dashboard and lists stutter on iPhone
        return content
            .background(
                RoundedRectangle(cornerRadius: r, style: .continuous)
                    .fill(Theme.card)
                    .shadow(color: Color.black.opacity(style == "soft" ? 0.08 : 0), radius: style == "soft" ? 7 : 0, x: 0, y: style == "soft" ? 3 : 0)
            )
            .overlay(RoundedRectangle(cornerRadius: r, style: .continuous).stroke(Color.primary.opacity(style == "outline" ? 0.16 : 0.06), lineWidth: style == "outline" ? 1 : 0.5))
    }
}

/// Row height multiplier for tables (Settings › Appearance › Table rows).
enum Density {
    static func factor(_ d: String) -> CGFloat { d == "compact" ? 0.82 : (d == "roomy" ? 1.22 : 1) }
}

/// Runs work a moment after the last call; calls made in between are dropped, so typing in a search box loads once.
@MainActor final class Debouncer {
    private var task: Task<Void, Never>?
    func run(_ ms: Int = 250, _ work: @escaping @MainActor () async -> Void) {
        task?.cancel()
        task = Task { @MainActor in
            await pause(ms: ms)
            if Task.isCancelled { return }
            await work()
        }
    }
}
