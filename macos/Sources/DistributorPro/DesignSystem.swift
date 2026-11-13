import SwiftUI

// Design tokens and shared state views from docs/DESIGN_SYSTEM.md — the same numbers as the iPhone's `DS`
// (ios/BillBox/Shared/DesignSystem.swift), Android's `DS` and Flutter's `DS`. Everything here is macOS 12 (Monterey) safe.

enum DS {
    /// The 4 pt grid (§4).
    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let s: CGFloat = 12
        static let m: CGFloat = 16
        static let l: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }
    /// Paddings (§4).
    enum Pad {
        static let screen: CGFloat = 20
        static let card: CGFloat = 14
        static let cardGap: CGFloat = 12
        static let cell: CGFloat = 8
        static let tableSide: CGFloat = 10
    }
    /// Corner radii (§4).
    enum Radius {
        static let card: CGFloat = 14
        static let hero: CGFloat = 22
        static let control: CGFloat = 12
        static let toast: CGFloat = 20
    }
    /// Minimum widths that keep dates, money and pills from being cut off (§4).
    enum Width {
        static let date: CGFloat = 96
        static let money: CGFloat = 90
        static let summaryCell: CGFloat = 120
    }
    /// Smallest click target (§1).
    static let hitTarget: CGFloat = 44
    /// Tint strength for pills and badge backgrounds (§2).
    static let tint: Double = 0.13
    /// Motion (§6): nothing longer than 0.45 s, never on money figures while typing.
    enum Motion {
        static let quick = Animation.easeOut(duration: 0.2)
        static let standard = Animation.spring(response: 0.35, dampingFraction: 0.86)
    }
}

/// Typography tokens (§3), built on text styles so the Text size setting still scales them.
extension Font {
    static var dsTitle: Font { .title2.weight(.semibold) }
    static var dsHeadline: Font { .headline }
    static var dsBody: Font { .body }
    static var dsCallout: Font { .callout }
    static var dsCaption: Font { .caption }
    /// KPI and summary figures, equal-width digits.
    static var dsMoney: Font { .system(.title2, design: .rounded).weight(.semibold).monospacedDigit() }
    /// Table header text: caption, semibold (shown upper case).
    static var dsHeader: Font { .caption.weight(.semibold) }
}

/// Semantic colour roles (§2), the same in every theme: light / dark pairs with at least 4.5:1 contrast on the card.
extension Theme {
    static var text: Color { .primary }
    static var textSecondary: Color { .secondary }
    /// Profit, paid, success.
    static let positive = AppTheme.dyn(0x15803D, 0x4ADE80)
    /// Due, loss, errors.
    static let negative = AppTheme.dyn(0xDC2626, 0xF87171)
    /// Not printed, expiring, low stock.
    static let warning = AppTheme.dyn(0xC2410C, 0xFB923C)
    /// Bills to print, notices.
    static let info = AppTheme.dyn(0x2563EB, 0x60A5FA)
}

/// A small coloured label for a state in a table: Sale, Purchase, Not yet, Retailer …
struct StatusPill: View {
    let text: String
    var tint: Color = Theme.accent

    var body: some View {
        if text.isEmpty {
            Text(" ").font(.caption)
        } else {
            Text(text).font(.dsCaption.weight(.semibold)).foregroundStyle(tint).lineLimit(1).fixedSize()
                .padding(.horizontal, DS.Space.xs).padding(.vertical, 2)
                .background(tint.opacity(DS.tint), in: Capsule())
        }
    }
}

/// Totals under a table: label over figure, in a row that wraps on a narrow window.
struct SummaryCard: View {
    struct Item { let label: String; let value: String; var strong = false; var tint: Color? = nil }
    let items: [Item]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: DS.Width.summaryCell), spacing: DS.Space.s, alignment: .leading)], alignment: .leading, spacing: DS.Space.xs) {
            ForEach(items.indices, id: \.self) { i in
                let it = items[i]
                VStack(alignment: .leading, spacing: 1) {
                    Text(it.label).font(.dsCaption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    Text(it.value).font((it.strong ? Font.callout.weight(.bold) : Font.callout.weight(.medium)).monospacedDigit())
                        .foregroundStyle(it.tint ?? Color.primary).lineLimit(1).minimumScaleFactor(0.7)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, DS.Pad.card).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(DS.Radius.card)
    }
}

/// Grey placeholder rows while a table loads, so the screen keeps its shape. Still with Reduce Motion.
struct SkeletonRows: View {
    var rows = 8
    var rowHeight: CGFloat = 30
    @State private var dim = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<rows, id: \.self) { i in
                HStack(spacing: DS.Space.s) {
                    bar(width: 28)
                    bar(width: 86)
                    bar(width: CGFloat(110 + (i * 37) % 90))
                    Spacer(minLength: DS.Space.xs)
                    bar(width: 64)
                }
                .frame(height: rowHeight)
                .padding(.horizontal, DS.Space.s)
            }
        }
        .padding(.vertical, DS.Space.xs)
        .card(DS.Radius.card)
        .padding(DS.Pad.tableSide)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .opacity(dim ? 0.55 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }

    private func bar(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.primary.opacity(0.08))
            .frame(width: width, height: 11)
    }
}

/// Something went wrong loading a screen: what happened and a way to try again.
struct ErrorState: View {
    let message: String
    var title = "Couldn't load this"
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: DS.Space.xs) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 34)).foregroundStyle(Theme.negative)
            Text(title).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
            Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: 420).textSelection(.enabled)
            if let retry {
                Button("Try again", action: retry).buttonStyle(.borderedProminent).padding(.top, DS.Space.xxs)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DS.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
