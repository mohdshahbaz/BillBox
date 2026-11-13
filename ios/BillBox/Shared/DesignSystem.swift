import SwiftUI
#if XCODE_BUILD
import PopupView
#endif

/// The look shared by every screen: toasts (PopupView, exyte, MIT), the dashboard's header background and the shape of
/// buttons. `XCODE_BUILD` is set by the Xcode project only, so the Linux type-check (iOS 16 surface, no packages) still
/// sees the older plain versions and stays useful for everything else.
extension View {
    /// The message banner from `app.notify`: a floating card at the top that slides in, can be swiped up or tapped away,
    /// and shows above open sheets too.
    @MainActor func appToasts(_ toast: Binding<Toast?>) -> some View {
        #if XCODE_BUILD
        self.popup(item: toast) { t in
            ToastCard(toast: t) { toast.wrappedValue = nil }
        } customize: {
            $0.type(.floater())
                .position(.top)
                .animation(DS.Motion.toast)
                .closeOnTap(true)
                .closeOnTapOutside(false)
                .dragToDismiss(true)
        }
        #else
        self.overlay { ToastOverlay() }
        #endif
    }

    /// App-wide control styling: rounder bordered buttons.
    func appChrome() -> some View {
        #if XCODE_BUILD
        self.buttonBorderShape(.roundedRectangle(radius: DS.Radius.control))
        #else
        self
        #endif
    }
}

/// One toast: a coloured badge, the message (selectable, so an error can be copied) and a close button.
@MainActor struct ToastCard: View {
    let toast: Toast
    let close: () -> Void

    var body: some View {
        let tint: Color = toast.isError ? Theme.negative : Theme.positive
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(tint, in: Circle())
            Text(toast.text)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, 10).padding(.trailing, 8).padding(.vertical, 9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.toast, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.toast, style: .continuous).stroke(tint.opacity(0.25), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
        .padding(.horizontal, 12)
        .frame(maxWidth: 560)
    }
}

/// The dashboard header: a soft mesh of the theme's accent on iOS 18, a plain two-tone gradient elsewhere.
@MainActor struct HeroBackground: View {
    var body: some View {
        let a = Theme.accent
        #if XCODE_BUILD
        MeshGradient(width: 3, height: 3, points: [
            .init(0, 0), .init(0.5, 0), .init(1, 0),
            .init(0, 0.5), .init(0.62, 0.42), .init(1, 0.5),
            .init(0, 1), .init(0.5, 1), .init(1, 1),
        ], colors: [
            a.mix(with: .black, by: 0.12), a, a.mix(with: .white, by: 0.22),
            a, a.mix(with: .white, by: 0.12), a.mix(with: .purple, by: 0.18),
            a.mix(with: .black, by: 0.2), a.mix(with: .black, by: 0.05), a.mix(with: .white, by: 0.08),
        ])
        #else
        LinearGradient(colors: [a, a.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing)
        #endif
    }
}

// MARK: - Design tokens (docs/DESIGN_SYSTEM.md)

/// The shared design tokens. Every value here is named in docs/DESIGN_SYSTEM.md, and the Mac, Android and Flutter apps
/// use the same numbers, so a screen looks the same family on every platform.
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
        static let screen: CGFloat = 16
        static let screenWide: CGFloat = 20
        static let card: CGFloat = 14
        static let cardGap: CGFloat = 12
        static let cell: CGFloat = 8
        /// Space around a table or summary card inside a screen.
        static let tableSide: CGFloat = 10
    }
    /// Corner radii before the user's Corners setting (§4).
    enum Radius {
        static let card: CGFloat = 14
        static let hero: CGFloat = 22
        static let control: CGFloat = 12
        static let toast: CGFloat = 20
    }
    /// Minimum widths that keep dates, money and pills from being cut off (§4).
    enum Width {
        static let date: CGFloat = 122
        static let money: CGFloat = 90
        static let summaryCell: CGFloat = 104
    }
    /// Smallest tap target (§1).
    static let hitTarget: CGFloat = 44
    /// Tint strength for pills and badge backgrounds (§2).
    static let tint: Double = 0.13
    /// Motion (§6): nothing longer than 0.45 s.
    enum Motion {
        static let quick = Animation.easeOut(duration: 0.2)
        static let standard = Animation.spring(response: 0.35, dampingFraction: 0.86)
        static let toast = Animation.spring(response: 0.42, dampingFraction: 0.86)
    }
}

/// Typography tokens (§3). Built on text styles, so Dynamic Type and the chosen typeface still scale them.
extension Font {
    static var dsDisplay: Font { .system(.largeTitle, design: .rounded).weight(.bold) }
    static var dsTitle: Font { .title2.weight(.semibold) }
    static var dsHeadline: Font { .headline }
    static var dsBody: Font { .body }
    static var dsCallout: Font { .callout }
    static var dsCaption: Font { .caption }
    /// KPI and summary figures; add `.monospacedDigit()` where shown.
    static var dsMoney: Font { .system(.title2, design: .rounded).weight(.semibold) }
    /// Table header text: caption, semibold (shown upper case).
    static var dsHeader: Font { .caption.weight(.semibold) }
}

/// Semantic colour roles (§2), the same in every theme. Each is a light / dark pair with at least 4.5:1 contrast on the
/// theme's card colour.
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

// MARK: - Loading and error states (§5)

/// Grey placeholder rows while a table loads, so the screen keeps its shape instead of showing a lone spinner.
/// They pulse gently; with Reduce Motion they stay still.
@MainActor struct SkeletonRows: View {
    var rows = 8
    var rowHeight: CGFloat = 36
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
        .padding(.horizontal, DS.Pad.tableSide).padding(.top, DS.Space.xs)
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
            .frame(width: width, height: 12)
    }
}

/// Something went wrong loading a screen: what happened and a way to try again.
@MainActor struct ErrorState: View {
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
            }
        }
        .padding(DS.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
