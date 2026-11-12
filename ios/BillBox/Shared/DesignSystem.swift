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
                .animation(.spring(response: 0.42, dampingFraction: 0.86))
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
        self.buttonBorderShape(.roundedRectangle(radius: 12))
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
        let tint: Color = toast.isError ? .red : .green
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(tint.opacity(0.25), lineWidth: 1))
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
