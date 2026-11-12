import SwiftUI
#if canImport(Pow)
import Pow
#endif

/// Motion and haptics, from Pow (EmergeTools, MIT) and the iOS 17+ SwiftUI APIs.
/// Every helper does nothing on the Linux type-check (it has neither Pow nor those APIs), so call sites stay the same.
extension View {
    /// When `tick` changes (a bill saved): green ticks burst out and the phone taps "success".
    func savedEffect(_ tick: Int) -> some View {
        #if canImport(Pow)
        self.changeEffect(.spray { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }, value: tick)
            .sensoryFeedback(.success, trigger: tick)
        #else
        self
        #endif
    }

    /// When `tick` changes (an item added to the bill): a shine runs across and a light tap.
    func addedEffect(_ tick: Int) -> some View {
        #if canImport(Pow)
        self.changeEffect(.shine, value: tick)
            .sensoryFeedback(.impact(weight: .light), trigger: tick)
        #else
        self
        #endif
    }

    /// When `tick` changes (a save refused): the view shakes and the phone taps "error".
    func errorEffect(_ tick: Int) -> some View {
        #if canImport(Pow)
        self.changeEffect(.shake(rate: .fast), value: tick)
            .sensoryFeedback(.error, trigger: tick)
        #else
        self
        #endif
    }

    /// Digits roll to the new figure instead of jumping (amounts, counts).
    func numberRoll<V: Equatable>(_ value: V) -> some View {
        #if canImport(Pow)
        self.contentTransition(.numericText()).animation(.snappy, value: value)
        #else
        self
        #endif
    }

    /// A tappable card that sinks a little while pressed.
    func pressCard() -> some View {
        #if canImport(Pow)
        self.buttonStyle(PressCardStyle())
        #else
        self.buttonStyle(.plain)
        #endif
    }
}

#if canImport(Pow)
struct PressCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.conditionalEffect(.pushDown, condition: configuration.isPressed)
    }
}
#endif
