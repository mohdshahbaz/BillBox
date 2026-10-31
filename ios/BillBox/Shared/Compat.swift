import SwiftUI
import UIKit

/// Sleeps for a number of milliseconds.
func pause(ms: Int) async { try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000) }

enum Theme {
    /// Card / panel background and page background follow the chosen theme (Settings > Appearance) and light / dark mode.
    static var card: Color { AppTheme.current.card }
    static var page: Color { AppTheme.current.page }
    static let line = Color(UIColor.separator)
}

extension View {
    func fw(_ w: Font.Weight) -> some View { self.fontWeight(w) }
    /// Digits of equal width so money columns line up.
    func mono() -> some View { self.monospacedDigit() }
    func groupedForm() -> some View { self.formStyle(.grouped) }
    func card(_ radius: CGFloat = 10) -> some View { self.modifier(CardBackground(radius: radius)) }
}

struct EmptyState: View {
    let title: String
    var symbol = "tray"
    var message = ""

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 34)).foregroundStyle(.secondary)
            Text(title).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
            if !message.isEmpty { Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420) }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A form row: title on the left, control on the right.
struct Labeled<Content: View>: View {
    let title: String
    let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(title)
                Spacer()
                content
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                content
            }
        }
    }
}

/// Grouped bar chart. Tap a group to read its figures (the Mac shows them as a hover tip).
struct BarPair: Identifiable {
    let id: String
    let label: String
    let a: Double
    let b: Double
    var c: Double = 0
}

struct BarChartView: View {
    let data: [BarPair]
    var colors: [Color] = [.teal, .orange, .green]
    var showThird = false
    @State private var picked: String?

    var body: some View {
        let top = max(1, data.map { max($0.a, max($0.b, showThird ? $0.c : 0)) }.max() ?? 1)
        VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(data) { d in
                    VStack(spacing: 3) {
                        HStack(alignment: .bottom, spacing: 1) {
                            bar(d.a, top, colors[0])
                            bar(d.b, top, colors[1])
                            if showThird { bar(d.c, top, colors[2]) }
                        }
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        Text(d.label).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.5)
                    }
                    .frame(maxWidth: .infinity)
                    .background(picked == d.id ? Color.primary.opacity(0.06) : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { picked = picked == d.id ? nil : d.id }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(tip(d))
                }
            }
            HStack {
                if let p = picked, let d = data.first(where: { $0.id == p }) { Text(tip(d)).font(.caption2).lineLimit(2) }
                Spacer()
                Text("Tallest bar = \(Fmt.money(top))").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func tip(_ d: BarPair) -> String { "\(d.label): \(Fmt.money(d.a)) · \(Fmt.money(d.b))" + (showThird ? " · \(Fmt.money(d.c))" : "") }

    private func bar(_ v: Double, _ top: Double, _ c: Color) -> some View {
        GeometryReader { g in
            RoundedRectangle(cornerRadius: 2).fill(c)
                .frame(height: max(v > 0 ? 2 : 0, g.size.height * CGFloat(max(0, v) / top)))
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

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
                    Text(short[i]).font(.caption).lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(RoundedRectangle(cornerRadius: 6).fill(on ? Color.accentColor : Color.gray.opacity(0.18)))
                        .foregroundColor(on ? .white : .primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(dayNames[i] + (on ? ", on" : ", off"))
            }
        }
    }
}

/// "1,3" -> "Mon, Wed"
func dayList(_ csv: String) -> String {
    csv.split(separator: ",").compactMap { Int($0) }.filter { (0...6).contains($0) }.map { String(dayNames[$0].prefix(3)) }.joined(separator: ", ")
}

/// A text field whose title stays visible above it once something is typed (an iOS form shows a field's title only as
/// placeholder text, while the Mac's forms keep the label beside the field).
struct Field: View {
    let title: String
    @Binding var text: String
    var prompt: Text? = nil
    var axis: Axis = .horizontal

    init(_ title: String, text: Binding<String>, prompt: Text? = nil, axis: Axis = .horizontal) {
        self.title = title
        self._text = text
        self.prompt = prompt
        self.axis = axis
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
            TextField(title, text: $text, prompt: prompt, axis: axis)
                .accessibilityLabel(title)
        }
    }
}

/// Panels and cards: background in the theme's colour with the style chosen in Settings › Appearance (soft shadow, outlined
/// or flat) and its corner roundness.
struct CardBackground: ViewModifier {
    @AppStorage("cardStyle") private var style = "soft"
    @AppStorage("corners") private var corners = "normal"
    let radius: CGFloat

    func body(content: Content) -> some View {
        let r = radius * (corners == "square" ? 0.45 : (corners == "round" ? 1.6 : 1))
        return content
            .background(Theme.card, in: RoundedRectangle(cornerRadius: r, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: r, style: .continuous).stroke(Color.primary.opacity(style == "outline" ? 0.16 : 0.06), lineWidth: style == "outline" ? 1 : 0.5))
            .shadow(color: Color.black.opacity(style == "soft" ? 0.08 : 0), radius: style == "soft" ? 7 : 0, x: 0, y: style == "soft" ? 3 : 0)
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
