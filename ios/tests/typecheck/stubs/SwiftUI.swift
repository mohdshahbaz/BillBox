// Type-check stub (Linux only): the iOS 16 SwiftUI (+ Combine) surface BillBox uses.
// Only APIs available on iOS 16 are declared, and builders take at most 10 children (as in the Xcode 14 SDK),
// so code that compiles against this stub also compiles with Xcode 14.2 for iOS 16 (barring signature slips).
@_exported import Foundation
@_exported import UIKit
@_exported import Combine
@_exported import UniformTypeIdentifiers

// MARK: Core
public protocol View {
    associatedtype Body: View
    @ViewBuilder @MainActor var body: Self.Body { get }
}
extension Never: View { public typealias Body = Never; public var body: Never { fatalError() } }
public protocol _Leaf: View where Body == Never {}
extension _Leaf { public var body: Never { fatalError() } }
public protocol DynamicProperty {}

public struct _MV: _Leaf {}
public struct EmptyView: _Leaf { public init() {} }
public struct AnyView: _Leaf { public init<V: View>(_ v: V) {}; public init<V: View>(erasing v: V) {} }
public struct TupleView<T>: _Leaf { public init(_ v: T) {} }
public struct _ConditionalContent<T, F>: _Leaf {}
extension Optional: View where Wrapped: View { public typealias Body = Never; public var body: Never { fatalError() } }

@resultBuilder public struct ViewBuilder {
    public static func buildExpression<C: View>(_ c: C) -> C { c }
    public static func buildBlock() -> EmptyView { EmptyView() }
    public static func buildBlock<C: View>(_ c: C) -> C { c }
    public static func buildBlock<C0: View, C1: View>(_ c0: C0, _ c1: C1) -> TupleView<(C0, C1)> { fatalError() }
    public static func buildBlock<C0: View, C1: View, C2: View>(_ c0: C0, _ c1: C1, _ c2: C2) -> TupleView<(C0, C1, C2)> { fatalError() }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3) -> TupleView<(C0, C1, C2, C3)> { fatalError() }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4) -> TupleView<(C0, C1, C2, C3, C4)> { fatalError() }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5) -> TupleView<(C0, C1, C2, C3, C4, C5)> { fatalError() }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View, C6: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6) -> TupleView<(C0, C1, C2, C3, C4, C5, C6)> { fatalError() }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View, C6: View, C7: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7) -> TupleView<(C0, C1, C2, C3, C4, C5, C6, C7)> { fatalError() }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View, C6: View, C7: View, C8: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8) -> TupleView<(C0, C1, C2, C3, C4, C5, C6, C7, C8)> { fatalError() }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View, C6: View, C7: View, C8: View, C9: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8, _ c9: C9) -> TupleView<(C0, C1, C2, C3, C4, C5, C6, C7, C8, C9)> { fatalError() }
    public static func buildIf<C: View>(_ c: C?) -> C? { c }
    public static func buildEither<T: View, F: View>(first: T) -> _ConditionalContent<T, F> { fatalError() }
    public static func buildEither<T: View, F: View>(second: F) -> _ConditionalContent<T, F> { fatalError() }
    public static func buildLimitedAvailability<C: View>(_ c: C) -> AnyView { AnyView(c) }
}

// MARK: Geometry & basic values
public enum Edge: Int8 { case top, leading, bottom, trailing
    public struct Set: OptionSet { public let rawValue: Int8; public init(rawValue: Int8) { self.rawValue = rawValue }
        public static let top = Set(rawValue: 1), leading = Set(rawValue: 2), bottom = Set(rawValue: 4), trailing = Set(rawValue: 8)
        public static let all = Set(rawValue: 15), horizontal = Set(rawValue: 10), vertical = Set(rawValue: 5)
        public init(_ e: Edge) { self.rawValue = 1 } }
}
public enum HorizontalEdge { case leading, trailing }
public struct EdgeInsets: Equatable { public var top: CGFloat = 0, leading: CGFloat = 0, bottom: CGFloat = 0, trailing: CGFloat = 0
    public init() {}; public init(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {} }
public struct HorizontalAlignment: Equatable { public static let leading = HorizontalAlignment(), center = HorizontalAlignment(), trailing = HorizontalAlignment() }
public struct VerticalAlignment: Equatable { public static let top = VerticalAlignment(), center = VerticalAlignment(), bottom = VerticalAlignment(), firstTextBaseline = VerticalAlignment(), lastTextBaseline = VerticalAlignment() }
public struct Alignment: Equatable {
    public init(horizontal: HorizontalAlignment, vertical: VerticalAlignment) {}
    public var horizontal: HorizontalAlignment { .center }
    public var vertical: VerticalAlignment { .center }
    public static let leading = Alignment(horizontal: .leading, vertical: .center), trailing = Alignment(horizontal: .trailing, vertical: .center)
    public static let center = Alignment(horizontal: .center, vertical: .center), top = Alignment(horizontal: .center, vertical: .top), bottom = Alignment(horizontal: .center, vertical: .bottom)
    public static let topLeading = Alignment(horizontal: .leading, vertical: .top), topTrailing = Alignment(horizontal: .trailing, vertical: .top)
    public static let bottomLeading = Alignment(horizontal: .leading, vertical: .bottom), bottomTrailing = Alignment(horizontal: .trailing, vertical: .bottom)
}
public enum TextAlignment: Hashable { case leading, center, trailing }
public enum Axis: Int8 { case horizontal, vertical
    public struct Set: OptionSet { public let rawValue: Int8; public init(rawValue: Int8) { self.rawValue = rawValue }
        public static let horizontal = Set(rawValue: 1), vertical = Set(rawValue: 2) } }
public struct ProposedViewSize: Equatable { public init(_ s: CGSize) {}; public init(width: CGFloat?, height: CGFloat?) {}
    public static let unspecified = ProposedViewSize(width: nil, height: nil), zero = ProposedViewSize(width: 0, height: 0), infinity = ProposedViewSize(width: .infinity, height: .infinity) }
public struct Angle { public static func degrees(_ d: Double) -> Angle { Angle() }; public static func radians(_ d: Double) -> Angle { Angle() } }
public struct UnitPoint { public static let center = UnitPoint(), leading = UnitPoint(), trailing = UnitPoint(), top = UnitPoint(), bottom = UnitPoint(), topLeading = UnitPoint(), topTrailing = UnitPoint(), bottomLeading = UnitPoint(), bottomTrailing = UnitPoint() }

// MARK: Colours, fonts, styles
public protocol ShapeStyle {}
public struct HierarchicalShapeStyle: ShapeStyle { public static let primary = HierarchicalShapeStyle(), secondary = HierarchicalShapeStyle(), tertiary = HierarchicalShapeStyle(), quaternary = HierarchicalShapeStyle() }
extension ShapeStyle where Self == HierarchicalShapeStyle {
    public static var primary: HierarchicalShapeStyle { .init() }
    public static var secondary: HierarchicalShapeStyle { .init() }
    public static var tertiary: HierarchicalShapeStyle { .init() }
    public static var quaternary: HierarchicalShapeStyle { .init() }
}
public struct TintShapeStyle: ShapeStyle {}
extension ShapeStyle where Self == TintShapeStyle { public static var tint: TintShapeStyle { .init() } }
public struct Material: ShapeStyle { public static let regular = Material(), thin = Material(), thick = Material(), ultraThin = Material(), bar = Material() }
extension ShapeStyle where Self == Material {
    public static var regularMaterial: Material { .init() }
    public static var thinMaterial: Material { .init() }
    public static var ultraThinMaterial: Material { .init() }
    public static var bar: Material { .init() }
}
public struct AnyShapeStyle: ShapeStyle { public init<S: ShapeStyle>(_ s: S) {} }

public struct Color: ShapeStyle, View, Hashable {
    public typealias Body = Never
    public var body: Never { fatalError() }
    public init(_ ui: UIColor) {}
    public init(uiColor: UIColor) {}
    public init(red: Double, green: Double, blue: Double, opacity: Double = 1) {}
    public init(white: Double, opacity: Double = 1) {}
    public init(_ name: String) {}
    public init(hue: Double, saturation: Double, brightness: Double, opacity: Double = 1) {}
    public func opacity(_ o: Double) -> Color { self }
    public static func == (a: Color, b: Color) -> Bool { true }
    public func hash(into h: inout Hasher) {}
    public static let black = Color(white: 0), white = Color(white: 1), gray = Color(white: 0.5), red = Color(white: 0), green = Color(white: 0), blue = Color(white: 0)
    public static let orange = Color(white: 0), yellow = Color(white: 0), pink = Color(white: 0), purple = Color(white: 0), teal = Color(white: 0), mint = Color(white: 0)
    public static let cyan = Color(white: 0), indigo = Color(white: 0), brown = Color(white: 0), clear = Color(white: 0)
    public static let primary = Color(white: 0), secondary = Color(white: 0), accentColor = Color(white: 0)
}
extension ShapeStyle where Self == Color {
    public static var black: Color { .init(white: 0) }
    public static var white: Color { .init(white: 0) }
    public static var gray: Color { .init(white: 0) }
    public static var red: Color { .init(white: 0) }
    public static var green: Color { .init(white: 0) }
    public static var blue: Color { .init(white: 0) }
    public static var orange: Color { .init(white: 0) }
    public static var yellow: Color { .init(white: 0) }
    public static var purple: Color { .init(white: 0) }
    public static var teal: Color { .init(white: 0) }
    public static var mint: Color { .init(white: 0) }
    public static var indigo: Color { .init(white: 0) }
    public static var pink: Color { .init(white: 0) }
    public static var clear: Color { .init(white: 0) }
    public static var accentColor: Color { .init(white: 0) }
}
public struct Gradient { public init(colors: [Color]) {} }
public struct LinearGradient: ShapeStyle, _Leaf { public init(colors: [Color], startPoint: UnitPoint, endPoint: UnitPoint) {} }

public struct Font: Hashable {
    public enum TextStyle: CaseIterable { case largeTitle, title, title2, title3, headline, subheadline, body, callout, footnote, caption, caption2 }
    public struct Weight: Hashable { public static let ultraLight = Weight(), thin = Weight(), light = Weight(), regular = Weight(), medium = Weight(), semibold = Weight(), bold = Weight(), heavy = Weight(), black = Weight() }
    public enum Design: Hashable { case `default`, serif, rounded, monospaced }
    public static let largeTitle = Font(), title = Font(), title2 = Font(), title3 = Font(), headline = Font(), subheadline = Font()
    public static let body = Font(), callout = Font(), footnote = Font(), caption = Font(), caption2 = Font()
    public static func system(size: CGFloat, weight: Weight = .regular, design: Design = .default) -> Font { Font() }
    public static func system(_ style: TextStyle, design: Design = .default) -> Font { Font() }
    public static func system(_ style: TextStyle, design: Design? = nil, weight: Weight? = nil) -> Font { Font() }
    public static func custom(_ name: String, size: CGFloat) -> Font { Font() }
    public func weight(_ w: Weight) -> Font { self }
    public func bold() -> Font { self }
    public func italic() -> Font { self }
    public func monospacedDigit() -> Font { self }
    public func monospaced() -> Font { self }
    public func leading(_ l: Leading) -> Font { self }
    public enum Leading { case standard, tight, loose }
}

public enum ColorScheme: CaseIterable, Hashable { case light, dark }
public enum UserInterfaceSizeClass: Hashable { case compact, regular }
public enum ScenePhase: Hashable { case background, inactive, active }
public enum DynamicTypeSize: Hashable, Comparable, CaseIterable { case xSmall, small, medium, large, xLarge, xxLarge, xxxLarge, accessibility1, accessibility2, accessibility3, accessibility4, accessibility5
    public var isAccessibilitySize: Bool { false } }
public enum LayoutDirection { case leftToRight, rightToLeft }

// MARK: Environment & property wrappers
public struct DismissAction { public func callAsFunction() {} }
public struct OpenURLAction { public func callAsFunction(_ u: URL) {} }
public enum EditMode: Hashable { case inactive, transient, active; public var isEditing: Bool { self != .inactive } }
public struct EnvironmentValues {
    public var dismiss: DismissAction { DismissAction() }
    public var openURL: OpenURLAction { OpenURLAction() }
    public var colorScheme: ColorScheme { get { .light } set {} }
    public var horizontalSizeClass: UserInterfaceSizeClass? { get { nil } set {} }
    public var verticalSizeClass: UserInterfaceSizeClass? { get { nil } set {} }
    public var scenePhase: ScenePhase { get { .active } set {} }
    public var dynamicTypeSize: DynamicTypeSize { get { .large } set {} }
    public var isEnabled: Bool { get { true } set {} }
    public var isSearching: Bool { false }
    public var layoutDirection: LayoutDirection { get { .leftToRight } set {} }
    public var locale: Locale { get { Locale.current } set {} }
    public var timeZone: TimeZone { get { TimeZone.current } set {} }
    public var font: Font? { get { nil } set {} }
    public var editMode: Binding<EditMode>? { get { nil } set {} }
}
@propertyWrapper public struct Environment<Value>: DynamicProperty {
    public init(_ kp: KeyPath<EnvironmentValues, Value>) {}
    public var wrappedValue: Value { fatalError() }
}
@propertyWrapper @dynamicMemberLookup public struct Binding<Value>: DynamicProperty {
    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {}
    public init(projectedValue: Binding<Value>) {}
    public init<V>(_ base: Binding<V>) where Value == V? {}
    public init?(_ base: Binding<Value?>) {}
    public static func constant(_ v: Value) -> Binding<Value> { fatalError() }
    public var wrappedValue: Value { get { fatalError() } nonmutating set {} }
    public var projectedValue: Binding<Value> { self }
    public subscript<T>(dynamicMember kp: WritableKeyPath<Value, T>) -> Binding<T> { fatalError() }
}
extension Binding: Identifiable where Value: Identifiable { public var id: Value.ID { wrappedValue.id } }
@propertyWrapper public struct State<Value>: DynamicProperty {
    public init(wrappedValue: Value) {}
    public init(initialValue: Value) {}
    public init() where Value: ExpressibleByNilLiteral {}
    public var wrappedValue: Value { get { fatalError() } nonmutating set {} }
    public var projectedValue: Binding<Value> { fatalError() }
}
@propertyWrapper @frozen public struct ObservedObject<ObjectType: ObservableObject>: DynamicProperty {
    @dynamicMemberLookup public struct Wrapper {
        public subscript<T>(dynamicMember kp: ReferenceWritableKeyPath<ObjectType, T>) -> Binding<T> { fatalError() }
    }
    public init(wrappedValue: ObjectType) {}
    public init(initialValue: ObjectType) {}
    public var wrappedValue: ObjectType { fatalError() }
    public var projectedValue: Wrapper { fatalError() }
}
@propertyWrapper public struct StateObject<ObjectType: ObservableObject>: DynamicProperty {
    public init(wrappedValue: @autoclosure @escaping () -> ObjectType) {}
    public var wrappedValue: ObjectType { fatalError() }
    public var projectedValue: ObservedObject<ObjectType>.Wrapper { fatalError() }
}
@propertyWrapper public struct EnvironmentObject<ObjectType: ObservableObject>: DynamicProperty {
    public init() {}
    public var wrappedValue: ObjectType { fatalError() }
    public var projectedValue: ObservedObject<ObjectType>.Wrapper { fatalError() }
}
@propertyWrapper public struct AppStorage<Value>: DynamicProperty {
    @available(*, unavailable) public init() {}
    public var wrappedValue: Value { get { fatalError() } nonmutating set {} }
    public var projectedValue: Binding<Value> { fatalError() }
}
extension AppStorage {
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == String {}
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == Bool {}
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == Int {}
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == Double {}
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == Data {}
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value: RawRepresentable, Value.RawValue == String {}
}
@propertyWrapper public struct FocusState<Value: Hashable>: DynamicProperty {
    @propertyWrapper public struct Binding {
        @available(*, unavailable) public init() {}
        public var wrappedValue: Value { get { fatalError() } nonmutating set {} }
        public var projectedValue: FocusState<Value>.Binding { self }
    }
    public init() where Value == Bool {}
    public init<T: Hashable>() where Value == T? {}
    public var wrappedValue: Value { get { fatalError() } nonmutating set {} }
    public var projectedValue: FocusState<Value>.Binding { fatalError() }
}
@propertyWrapper public struct ScaledMetric<Value: BinaryFloatingPoint>: DynamicProperty {
    public init(wrappedValue: Value) {}
    public init(wrappedValue: Value, relativeTo: Font.TextStyle) {}
    public var wrappedValue: Value { fatalError() }
}
@propertyWrapper public struct Namespace: DynamicProperty { public init() {}; public struct ID: Hashable {}; public var wrappedValue: ID { ID() } }

// MARK: Text, images, labels
public struct LocalizedStringKey: ExpressibleByStringInterpolation, Equatable {
    public init(_ s: String) {}
    public init(stringLiteral s: String) {}
}
public struct Text: _Leaf, Equatable {
    public init(_ key: LocalizedStringKey) {}
    public init<S: StringProtocol>(_ s: S) {}
    public init(verbatim: String) {}
    public init(_ i: Image) {}
    public init(_ d: Date, style: DateStyle) {}
    public struct DateStyle { public static let date = DateStyle(), time = DateStyle(), relative = DateStyle() }
    public enum TruncationMode { case head, tail, middle }
    public enum Case { case uppercase, lowercase }
    public static func + (a: Text, b: Text) -> Text { a }
    public func font(_ f: Font?) -> Text { self }
    public func fontWeight(_ w: Font.Weight?) -> Text { self }
    public func bold() -> Text { self }
    public func bold(_ on: Bool) -> Text { self }
    public func italic() -> Text { self }
    public func monospacedDigit() -> Text { self }
    public func foregroundColor(_ c: Color?) -> Text { self }
    public func strikethrough(_ on: Bool = true, color: Color? = nil) -> Text { self }
    public func underline(_ on: Bool = true, color: Color? = nil) -> Text { self }
    public func kerning(_ k: CGFloat) -> Text { self }
    public func baselineOffset(_ o: CGFloat) -> Text { self }
}
public struct Image: _Leaf {
    public init(systemName: String) {}
    public init(_ name: String) {}
    public init(uiImage: UIImage) {}
    public init(decorative: String) {}
    public func resizable() -> Image { self }
    public func renderingMode(_ m: TemplateRenderingMode?) -> Image { self }
    public func interpolation(_ i: Interpolation) -> Image { self }
    public enum TemplateRenderingMode { case template, original }
    public enum Interpolation { case none, low, medium, high }
    public enum Scale { case small, medium, large }
}
public struct Label<Title: View, Icon: View>: _Leaf {
    public init(@ViewBuilder title: () -> Title, @ViewBuilder icon: () -> Icon) {}
}
extension Label where Title == Text, Icon == Image {
    public init(_ title: LocalizedStringKey, systemImage: String) {}
    public init<S: StringProtocol>(_ title: S, systemImage: String) {}
    public init<S: StringProtocol>(_ title: S, image: String) {}
}
public struct LabeledContent<L: View, C: View>: _Leaf {
    public init(@ViewBuilder content: () -> C, @ViewBuilder label: () -> L) {}
}
extension LabeledContent where L == Text {
    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> C) {}
}
extension LabeledContent where L == Text, C == Text {
    public init<S: StringProtocol, V: StringProtocol>(_ title: S, value: V) {}
}

// MARK: Layout containers
public struct VStack<Content: View>: _Leaf { public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {} }
public struct HStack<Content: View>: _Leaf { public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {} }
public struct ZStack<Content: View>: _Leaf { public init(alignment: Alignment = .center, @ViewBuilder content: () -> Content) {} }
public struct LazyVStack<Content: View>: _Leaf { public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, pinnedViews: PinnedScrollableViews = .init(), @ViewBuilder content: () -> Content) {} }
public struct LazyHStack<Content: View>: _Leaf { public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil, pinnedViews: PinnedScrollableViews = .init(), @ViewBuilder content: () -> Content) {} }
public struct PinnedScrollableViews: OptionSet { public let rawValue: UInt32; public init(rawValue: UInt32) { self.rawValue = rawValue }; public init() { rawValue = 0 }
    public static let sectionHeaders = PinnedScrollableViews(rawValue: 1), sectionFooters = PinnedScrollableViews(rawValue: 2) }
public struct GridItem {
    public enum Size { case fixed(CGFloat), flexible(minimum: CGFloat = 10, maximum: CGFloat = .infinity), adaptive(minimum: CGFloat, maximum: CGFloat = .infinity) }
    public init(_ size: Size = .flexible(), spacing: CGFloat? = nil, alignment: Alignment? = nil) {}
}
public struct LazyVGrid<Content: View>: _Leaf { public init(columns: [GridItem], alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, pinnedViews: PinnedScrollableViews = .init(), @ViewBuilder content: () -> Content) {} }
public struct LazyHGrid<Content: View>: _Leaf { public init(rows: [GridItem], alignment: VerticalAlignment = .center, spacing: CGFloat? = nil, pinnedViews: PinnedScrollableViews = .init(), @ViewBuilder content: () -> Content) {} }
public struct Grid<Content: View>: _Leaf { public init(alignment: Alignment = .center, horizontalSpacing: CGFloat? = nil, verticalSpacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {} }
public struct GridRow<Content: View>: _Leaf { public init(alignment: VerticalAlignment? = nil, @ViewBuilder content: () -> Content) {} }
public struct ViewThatFits<Content: View>: _Leaf { public init(in axes: Axis.Set = [.horizontal, .vertical], @ViewBuilder content: () -> Content) {} }
public struct Spacer: _Leaf { public init(minLength: CGFloat? = nil) {} }
public struct Divider: _Leaf { public init() {} }
public struct Group<Content>: _Leaf { }
extension Group where Content: View { public init(@ViewBuilder content: () -> Content) {} }
extension Group where Content: ToolbarContent { public init(@ToolbarContentBuilder content: () -> Content) {} }
public struct GeometryProxy { public var size: CGSize { .zero }; public var safeAreaInsets: EdgeInsets { EdgeInsets() }
    public func frame(in s: CoordinateSpace) -> CGRect { .zero } }
public enum CoordinateSpace { case global, local, named(AnyHashable) }
public struct GeometryReader<Content: View>: _Leaf { public init(@ViewBuilder content: @escaping (GeometryProxy) -> Content) {} }
public struct ScrollView<Content: View>: _Leaf { public init(_ axes: Axis.Set = .vertical, showsIndicators: Bool = true, @ViewBuilder content: () -> Content) {} }
public struct ScrollViewProxy { public func scrollTo<ID: Hashable>(_ id: ID, anchor: UnitPoint? = nil) {} }
public struct ScrollViewReader<Content: View>: _Leaf { public init(@ViewBuilder content: @escaping (ScrollViewProxy) -> Content) {} }

public struct ForEach<Data: RandomAccessCollection, ID: Hashable, Content>: _Leaf {}
extension ForEach where Content: View {
    public init(_ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder content: @escaping (Data.Element) -> Content) {}
}
extension ForEach where Content: View, ID == Data.Element.ID, Data.Element: Identifiable {
    public init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {}
}
extension ForEach where Content: View, Data == Range<Int>, ID == Int {
    public init(_ data: Range<Int>, @ViewBuilder content: @escaping (Int) -> Content) {}
}
extension ForEach where Content: ToolbarContent {
    public init(_ data: Data, id: KeyPath<Data.Element, ID>, @ToolbarContentBuilder content: @escaping (Data.Element) -> Content) {}
}
public protocol DynamicViewContent: View {}
extension ForEach: DynamicViewContent where Content: View {}
extension DynamicViewContent {
    public func onMove(perform: ((IndexSet, Int) -> Void)?) -> _MV { _MV() }
    public func onDelete(perform: ((IndexSet) -> Void)?) -> _MV { _MV() }
}
extension MutableCollection where Self: RangeReplaceableCollection {
    public mutating func move(fromOffsets: IndexSet, toOffset: Int) {}
}
extension RangeReplaceableCollection where Self: MutableCollection {
    public mutating func remove(atOffsets: IndexSet) {}
}

// MARK: Lists & forms
public struct List<SelectionValue: Hashable, Content: View>: _Leaf {}
extension List where SelectionValue == Never {
    public init(@ViewBuilder content: () -> Content) {}
    public init<Data: RandomAccessCollection, RowContent: View>(_ data: Data, @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent) where Content == ForEach<Data, Data.Element.ID, RowContent>, Data.Element: Identifiable {}
}
extension List {
    public init(selection: Binding<Set<SelectionValue>>?, @ViewBuilder content: () -> Content) {}
    public init(selection: Binding<SelectionValue?>?, @ViewBuilder content: () -> Content) {}
}
public struct Form<Content: View>: _Leaf { public init(@ViewBuilder content: () -> Content) {} }
public struct Section<Parent, Content, Footer>: _Leaf {}
extension Section where Parent: View, Content: View, Footer: View {
    public init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Parent, @ViewBuilder footer: () -> Footer) {}
}
extension Section where Parent == EmptyView, Content: View, Footer == EmptyView { public init(@ViewBuilder content: () -> Content) {} }
extension Section where Parent: View, Content: View, Footer == EmptyView { public init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Parent) {} }
extension Section where Parent == EmptyView, Content: View, Footer: View { public init(@ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {} }
extension Section where Parent: View, Content: View, Footer: View {
    public init(header: Parent, footer: Footer, @ViewBuilder content: () -> Content) {}
}
extension Section where Parent: View, Content: View, Footer == EmptyView { public init(header: Parent, @ViewBuilder content: () -> Content) {} }
extension Section where Parent == EmptyView, Content: View, Footer: View { public init(footer: Footer, @ViewBuilder content: () -> Content) {} }
extension Section where Parent == Text, Content: View, Footer == EmptyView {
    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) {}
    public init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {}
}
public struct DisclosureGroup<Label: View, Content: View>: _Leaf {
    public init(@ViewBuilder content: @escaping () -> Content, @ViewBuilder label: () -> Label) {}
    public init(isExpanded: Binding<Bool>, @ViewBuilder content: @escaping () -> Content, @ViewBuilder label: () -> Label) {}
}
extension DisclosureGroup where Label == Text {
    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: @escaping () -> Content) {}
    public init<S: StringProtocol>(_ title: S, isExpanded: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) {}
}

// MARK: Controls
public struct ButtonRole: Equatable { public static let destructive = ButtonRole(), cancel = ButtonRole() }
public struct Button<Label: View>: _Leaf {
    public init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {}
    public init(role: ButtonRole?, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {}
}
extension Button where Label == Text {
    public init(_ title: LocalizedStringKey, action: @escaping () -> Void) {}
    public init<S: StringProtocol>(_ title: S, action: @escaping () -> Void) {}
    public init<S: StringProtocol>(_ title: S, role: ButtonRole?, action: @escaping () -> Void) {}
}
public struct Link<Label: View>: _Leaf { public init(destination: URL, @ViewBuilder label: () -> Label) {} }
extension Link where Label == Text { public init<S: StringProtocol>(_ title: S, destination: URL) {} }
public struct ShareLink<Label: View>: _Leaf { }
extension ShareLink where Label == SwiftUI.Label<Text, Image> {
    public init(item: URL, subject: Text? = nil, message: Text? = nil) {}
    public init(item: String, subject: Text? = nil, message: Text? = nil) {}
}
extension ShareLink {
    public init(item: URL, subject: Text? = nil, message: Text? = nil, @ViewBuilder label: () -> Label) {}
}
public struct TextField<Label: View>: _Leaf {}
extension TextField where Label == Text {
    public init<S: StringProtocol>(_ title: S, text: Binding<String>) {}
    public init<S: StringProtocol>(_ title: S, text: Binding<String>, prompt: Text?) {}
    public init<S: StringProtocol>(_ title: S, text: Binding<String>, axis: Axis) {}
    public init<S: StringProtocol>(_ title: S, text: Binding<String>, prompt: Text?, axis: Axis) {}
    public init(_ title: LocalizedStringKey, text: Binding<String>) {}
    public init<S: StringProtocol, V>(_ title: S, value: Binding<V>, formatter: Formatter) {}
}
public struct SecureField<Label: View>: _Leaf {}
extension SecureField where Label == Text { public init<S: StringProtocol>(_ title: S, text: Binding<String>) {} }
public struct TextEditor: _Leaf { public init(text: Binding<String>) {} }
public struct Toggle<Label: View>: _Leaf { public init(isOn: Binding<Bool>, @ViewBuilder label: () -> Label) {} }
extension Toggle where Label == Text {
    public init<S: StringProtocol>(_ title: S, isOn: Binding<Bool>) {}
    public init(_ title: LocalizedStringKey, isOn: Binding<Bool>) {}
}
public struct Picker<Label: View, SelectionValue: Hashable, Content: View>: _Leaf {
    public init(selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {}
}
extension Picker where Label == Text {
    public init<S: StringProtocol>(_ title: S, selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content) {}
    public init(_ title: LocalizedStringKey, selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content) {}
}
public struct DatePickerComponents: OptionSet { public let rawValue: UInt; public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let date = DatePickerComponents(rawValue: 1), hourAndMinute = DatePickerComponents(rawValue: 2) }
public struct DatePicker<Label: View>: _Leaf {}
extension DatePicker where Label == Text {
    public init<S: StringProtocol>(_ title: S, selection: Binding<Date>, displayedComponents: DatePickerComponents = [.date]) {}
    public init<S: StringProtocol>(_ title: S, selection: Binding<Date>, in range: ClosedRange<Date>, displayedComponents: DatePickerComponents = [.date]) {}
}
public struct Stepper<Label: View>: _Leaf {}
extension Stepper where Label == Text {
    public init<S: StringProtocol, V: Strideable>(_ title: S, value: Binding<V>, in bounds: ClosedRange<V>, step: V.Stride = 1) {}
}
public struct Slider<Label: View, ValueLabel: View>: _Leaf {}
public struct ProgressView<Label: View, CurrentValueLabel: View>: _Leaf {}
extension ProgressView where Label == EmptyView, CurrentValueLabel == EmptyView {
    public init() {}
    public init<V: BinaryFloatingPoint>(value: V?, total: V = 1.0) {}
}
extension ProgressView where Label == Text, CurrentValueLabel == EmptyView {
    public init<S: StringProtocol>(_ title: S) {}
    public init<S: StringProtocol, V: BinaryFloatingPoint>(_ title: S, value: V?, total: V = 1.0) {}
}
public struct Menu<Label: View, Content: View>: _Leaf {
    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {}
}
extension Menu where Label == Text {
    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) {}
}
public struct ControlGroup<Content: View>: _Leaf { public init(@ViewBuilder content: () -> Content) {} }

// MARK: Shapes & drawing
public struct Path {
    public init() {}
    public init(_ r: CGRect) {}
    public init(roundedRect: CGRect, cornerRadius: CGFloat) {}
    public mutating func move(to p: CGPoint) {}
    public mutating func addLine(to p: CGPoint) {}
    public mutating func addRect(_ r: CGRect) {}
    public mutating func addLines(_ p: [CGPoint]) {}
    public mutating func closeSubpath() {}
}
public struct StrokeStyle { public init(lineWidth: CGFloat = 1, lineCap: CGLineCap = .butt, lineJoin: CGLineJoin = .miter, dash: [CGFloat] = []) {} }
public enum CGLineCap { case butt, round, square }
public enum CGLineJoin { case miter, round, bevel }
public protocol Shape: View where Body == Never {}
extension Shape {
    public var body: Never { fatalError() }
    public func fill<S: ShapeStyle>(_ s: S) -> _MV { _MV() }
    public func fill() -> _MV { _MV() }
    public func stroke<S: ShapeStyle>(_ s: S, lineWidth: CGFloat = 1) -> _MV { _MV() }
    public func stroke<S: ShapeStyle>(_ s: S, style: StrokeStyle) -> _MV { _MV() }
    public func stroke(lineWidth: CGFloat = 1) -> _MV { _MV() }
    public func strokeBorder<S: ShapeStyle>(_ s: S, lineWidth: CGFloat = 1) -> _MV { _MV() }
    public func strokeBorder<S: ShapeStyle>(_ s: S, style: StrokeStyle) -> _MV { _MV() }
}
public enum RoundedCornerStyle { case circular, continuous }
public struct Rectangle: Shape { public init() {} }
public struct RoundedRectangle: Shape { public init(cornerRadius: CGFloat, style: RoundedCornerStyle = .circular) {} }
public struct Circle: Shape { public init() {} }
public struct Capsule: Shape { public init(style: RoundedCornerStyle = .circular) {} }
public struct Ellipse: Shape { public init() {} }
public struct GraphicsContext {
    public struct Shading { public static func color(_ c: Color) -> Shading { Shading() } }
    public func stroke(_ p: Path, with: Shading, lineWidth: CGFloat = 1) {}
    public func stroke(_ p: Path, with: Shading, style: StrokeStyle) {}
    public func fill(_ p: Path, with: Shading) {}
    public func draw(_ t: Text, at: CGPoint, anchor: UnitPoint = .center) {}
}
public struct Canvas<Symbols: View>: _Leaf {}
extension Canvas where Symbols == EmptyView {
    public init(opaque: Bool = false, rendersAsynchronously: Bool = false, renderer: @escaping (inout GraphicsContext, CGSize) -> Void) {}
}

// MARK: Gestures, animation, transitions
public protocol Gesture {}
public struct DragGesture: Gesture {
    public struct Value { public var translation: CGSize { .zero }; public var location: CGPoint { .zero }; public var startLocation: CGPoint { .zero } }
    public init(minimumDistance: CGFloat = 10, coordinateSpace: CoordinateSpace = .local) {}
    public func onChanged(_ a: @escaping (Value) -> Void) -> DragGesture { self }
    public func onEnded(_ a: @escaping (Value) -> Void) -> DragGesture { self }
}
public struct TapGesture: Gesture { public init(count: Int = 1) {}; public func onEnded(_ a: @escaping () -> Void) -> TapGesture { self } }
public struct GestureMask: OptionSet { public let rawValue: Int; public init(rawValue: Int) { self.rawValue = rawValue }; public static let all = GestureMask(rawValue: 3) }
public struct Animation: Equatable {
    public static let `default` = Animation(), linear = Animation(), easeIn = Animation(), easeOut = Animation(), easeInOut = Animation(), spring = Animation()
    public static func easeOut(duration: Double) -> Animation { Animation() }
    public static func easeInOut(duration: Double) -> Animation { Animation() }
    public static func linear(duration: Double) -> Animation { Animation() }
    public static func spring(response: Double = 0.5, dampingFraction: Double = 0.8, blendDuration: Double = 0) -> Animation { Animation() }
}
public func withAnimation<R>(_ a: Animation? = .default, _ body: () throws -> R) rethrows -> R { try body() }
public struct AnyTransition {
    public static let opacity = AnyTransition(), scale = AnyTransition(), identity = AnyTransition(), slide = AnyTransition()
    public static func move(edge: Edge) -> AnyTransition { AnyTransition() }
    public func combined(with t: AnyTransition) -> AnyTransition { self }
    public func animation(_ a: Animation?) -> AnyTransition { self }
}

// MARK: Keyboard
public struct KeyEquivalent: Equatable, ExpressibleByExtendedGraphemeClusterLiteral {
    public init(_ c: Character) {}
    public init(extendedGraphemeClusterLiteral c: Character) {}
    public static let upArrow = KeyEquivalent("u"), downArrow = KeyEquivalent("d"), leftArrow = KeyEquivalent("l"), rightArrow = KeyEquivalent("r")
    public static let escape = KeyEquivalent("e"), delete = KeyEquivalent("x"), deleteForward = KeyEquivalent("y"), `return` = KeyEquivalent("\r"), tab = KeyEquivalent("\t"), space = KeyEquivalent(" ")
    public static let home = KeyEquivalent("h"), end = KeyEquivalent("n"), pageUp = KeyEquivalent("p"), pageDown = KeyEquivalent("q"), clear = KeyEquivalent("c")
}
public struct EventModifiers: OptionSet { public let rawValue: Int; public init(rawValue: Int) { self.rawValue = rawValue }
    public static let command = EventModifiers(rawValue: 1), shift = EventModifiers(rawValue: 2), option = EventModifiers(rawValue: 4), control = EventModifiers(rawValue: 8)
    public static let all = EventModifiers(rawValue: 15) }
public struct KeyboardShortcut { public static let defaultAction = KeyboardShortcut(), cancelAction = KeyboardShortcut()
    public init() {}; public init(_ k: KeyEquivalent, modifiers: EventModifiers = .command) {} }
public enum UIKeyboardType: Int { case `default`, asciiCapable, numbersAndPunctuation, URL, numberPad, phonePad, namePhonePad, emailAddress, decimalPad, twitter, webSearch, asciiCapableNumberPad }
public struct TextInputAutocapitalization { public static let never = TextInputAutocapitalization(), words = TextInputAutocapitalization(), sentences = TextInputAutocapitalization(), characters = TextInputAutocapitalization() }
public struct SubmitLabel { public static let done = SubmitLabel(), go = SubmitLabel(), send = SubmitLabel(), join = SubmitLabel(), route = SubmitLabel(), search = SubmitLabel(), `return` = SubmitLabel(), next = SubmitLabel(), `continue` = SubmitLabel() }
public struct SubmitTriggers: OptionSet { public let rawValue: Int; public init(rawValue: Int) { self.rawValue = rawValue }; public static let text = SubmitTriggers(rawValue: 1), search = SubmitTriggers(rawValue: 2) }
public enum UITextContentTypeStub {}

// MARK: Styles
public protocol PrimitiveButtonStyle {}
public struct BorderedButtonStyle: PrimitiveButtonStyle {}
public struct BorderedProminentButtonStyle: PrimitiveButtonStyle {}
public struct BorderlessButtonStyle: PrimitiveButtonStyle {}
public struct PlainButtonStyle: PrimitiveButtonStyle {}
public struct DefaultButtonStyle: PrimitiveButtonStyle {}
extension PrimitiveButtonStyle where Self == BorderedButtonStyle { public static var bordered: BorderedButtonStyle { .init() } }
extension PrimitiveButtonStyle where Self == BorderedProminentButtonStyle { public static var borderedProminent: BorderedProminentButtonStyle { .init() } }
extension PrimitiveButtonStyle where Self == BorderlessButtonStyle { public static var borderless: BorderlessButtonStyle { .init() } }
extension PrimitiveButtonStyle where Self == PlainButtonStyle { public static var plain: PlainButtonStyle { .init() } }
extension PrimitiveButtonStyle where Self == DefaultButtonStyle { public static var automatic: DefaultButtonStyle { .init() } }
public protocol PickerStyle {}
public struct SegmentedPickerStyle: PickerStyle {}
public struct MenuPickerStyle: PickerStyle {}
public struct WheelPickerStyle: PickerStyle {}
public struct InlinePickerStyle: PickerStyle {}
public struct NavigationLinkPickerStyle: PickerStyle {}
extension PickerStyle where Self == SegmentedPickerStyle { public static var segmented: SegmentedPickerStyle { .init() } }
extension PickerStyle where Self == MenuPickerStyle { public static var menu: MenuPickerStyle { .init() } }
extension PickerStyle where Self == WheelPickerStyle { public static var wheel: WheelPickerStyle { .init() } }
extension PickerStyle where Self == InlinePickerStyle { public static var inline: InlinePickerStyle { .init() } }
extension PickerStyle where Self == NavigationLinkPickerStyle { public static var navigationLink: NavigationLinkPickerStyle { .init() } }
public protocol LabelStyle {}
public struct IconOnlyLabelStyle: LabelStyle {}
public struct TitleOnlyLabelStyle: LabelStyle {}
public struct TitleAndIconLabelStyle: LabelStyle {}
extension LabelStyle where Self == IconOnlyLabelStyle { public static var iconOnly: IconOnlyLabelStyle { .init() } }
extension LabelStyle where Self == TitleOnlyLabelStyle { public static var titleOnly: TitleOnlyLabelStyle { .init() } }
extension LabelStyle where Self == TitleAndIconLabelStyle { public static var titleAndIcon: TitleAndIconLabelStyle { .init() } }
public protocol ListStyle {}
public struct PlainListStyle: ListStyle {}
public struct InsetGroupedListStyle: ListStyle {}
public struct GroupedListStyle: ListStyle {}
public struct InsetListStyle: ListStyle {}
extension ListStyle where Self == PlainListStyle { public static var plain: PlainListStyle { .init() } }
extension ListStyle where Self == InsetGroupedListStyle { public static var insetGrouped: InsetGroupedListStyle { .init() } }
extension ListStyle where Self == GroupedListStyle { public static var grouped: GroupedListStyle { .init() } }
extension ListStyle where Self == InsetListStyle { public static var inset: InsetListStyle { .init() } }
public protocol TextFieldStyle {}
public struct RoundedBorderTextFieldStyle: TextFieldStyle {}
public struct PlainTextFieldStyle: TextFieldStyle {}
extension TextFieldStyle where Self == RoundedBorderTextFieldStyle { public static var roundedBorder: RoundedBorderTextFieldStyle { .init() } }
extension TextFieldStyle where Self == PlainTextFieldStyle { public static var plain: PlainTextFieldStyle { .init() } }
public protocol DatePickerStyle {}
public struct GraphicalDatePickerStyle: DatePickerStyle {}
public struct CompactDatePickerStyle: DatePickerStyle {}
public struct WheelDatePickerStyle: DatePickerStyle {}
extension DatePickerStyle where Self == GraphicalDatePickerStyle { public static var graphical: GraphicalDatePickerStyle { .init() } }
extension DatePickerStyle where Self == CompactDatePickerStyle { public static var compact: CompactDatePickerStyle { .init() } }
extension DatePickerStyle where Self == WheelDatePickerStyle { public static var wheel: WheelDatePickerStyle { .init() } }
public protocol FormStyle {}
public struct GroupedFormStyle: FormStyle {}
public struct ColumnsFormStyle: FormStyle {}
extension FormStyle where Self == GroupedFormStyle { public static var grouped: GroupedFormStyle { .init() } }
extension FormStyle where Self == ColumnsFormStyle { public static var columns: ColumnsFormStyle { .init() } }
public enum ControlSize: CaseIterable { case mini, small, regular, large }
public enum Visibility { case automatic, visible, hidden }
public struct AccessibilityChildBehavior { public static let ignore = AccessibilityChildBehavior(), contain = AccessibilityChildBehavior(), combine = AccessibilityChildBehavior() }
public struct AccessibilityTraits: OptionSet { public let rawValue: Int; public init(rawValue: Int) { self.rawValue = rawValue }
    public static let isButton = AccessibilityTraits(rawValue: 1), isHeader = AccessibilityTraits(rawValue: 2), isSelected = AccessibilityTraits(rawValue: 4), isSummaryElement = AccessibilityTraits(rawValue: 8), updatesFrequently = AccessibilityTraits(rawValue: 16), isStaticText = AccessibilityTraits(rawValue: 32) }
public struct TextSelectability {}
public struct EnabledTextSelectability: TextSelectability_ {}
public protocol TextSelectability_ {}
extension TextSelectability_ where Self == EnabledTextSelectability { public static var enabled: EnabledTextSelectability { .init() } }
public struct DisabledTextSelectability: TextSelectability_ {}
extension TextSelectability_ where Self == DisabledTextSelectability { public static var disabled: DisabledTextSelectability { .init() } }
public struct PresentationDetent: Hashable {
    public static let medium = PresentationDetent(), large = PresentationDetent()
    public static func fraction(_ f: CGFloat) -> PresentationDetent { PresentationDetent() }
    public static func height(_ h: CGFloat) -> PresentationDetent { PresentationDetent() }
}
public struct SearchFieldPlacement {
    public static let automatic = SearchFieldPlacement(), toolbar = SearchFieldPlacement(), sidebar = SearchFieldPlacement()
    public enum NavigationBarDrawerDisplayMode { case automatic, always }
    public static func navigationBarDrawer(displayMode: NavigationBarDrawerDisplayMode) -> SearchFieldPlacement { SearchFieldPlacement() }
    public static let navigationBarDrawer = SearchFieldPlacement()
}
public enum TitleDisplayMode { case automatic, inline, large }
public enum PopoverAttachmentAnchor { case rect(Anchor), point(UnitPoint); public enum Anchor { case bounds } }
public enum ContentShapeKinds { case interaction, contextMenuPreview, dragPreview, hoverEffect, accessibility }
public enum SafeAreaRegions { case all, container, keyboard }

// MARK: Navigation & presentation
public struct NavigationPath { public init() {}; public var count: Int { 0 }; public var isEmpty: Bool { true }
    public mutating func append<V: Hashable>(_ v: V) {}; public mutating func removeLast(_ k: Int = 1) {} }
public struct NavigationStack<Data, Root: View>: _Leaf {}
extension NavigationStack where Data == NavigationPath { public init(@ViewBuilder root: () -> Root) {} ; public init(path: Binding<NavigationPath>, @ViewBuilder root: () -> Root) {} }
extension NavigationStack where Data: MutableCollection, Data: RandomAccessCollection, Data: RangeReplaceableCollection, Data.Element: Hashable {
    public init(path: Binding<Data>, @ViewBuilder root: () -> Root) {}
}
public struct NavigationLink<Label: View, Destination: View>: _Leaf {
    public init(@ViewBuilder destination: () -> Destination, @ViewBuilder label: () -> Label) {}
}
extension NavigationLink where Destination == Never {
    public init<P: Hashable>(value: P?, @ViewBuilder label: () -> Label) {}
}
extension NavigationLink where Label == Text {
    public init<S: StringProtocol>(_ title: S, @ViewBuilder destination: () -> Destination) {}
}
extension NavigationLink where Label == Text, Destination == Never {
    public init<S: StringProtocol, P: Hashable>(_ title: S, value: P?) {}
}
public struct TabView<SelectionValue: Hashable, Content: View>: _Leaf {
    public init(selection: Binding<SelectionValue>?, @ViewBuilder content: () -> Content) {}
}
extension TabView where SelectionValue == Int { public init(@ViewBuilder content: () -> Content) {} }

// MARK: Toolbar
public protocol ToolbarContent {}
public struct TupleToolbarContent<T>: ToolbarContent {}
public struct _ConditionalToolbar<T, F>: ToolbarContent {}
extension Optional: ToolbarContent where Wrapped: ToolbarContent {}
@resultBuilder public struct ToolbarContentBuilder {
    public static func buildExpression<C: ToolbarContent>(_ c: C) -> C { c }
    public static func buildBlock<C: ToolbarContent>(_ c: C) -> C { c }
    public static func buildBlock<C0: ToolbarContent, C1: ToolbarContent>(_ c0: C0, _ c1: C1) -> TupleToolbarContent<(C0, C1)> { fatalError() }
    public static func buildBlock<C0: ToolbarContent, C1: ToolbarContent, C2: ToolbarContent>(_ c0: C0, _ c1: C1, _ c2: C2) -> TupleToolbarContent<(C0, C1, C2)> { fatalError() }
    public static func buildBlock<C0: ToolbarContent, C1: ToolbarContent, C2: ToolbarContent, C3: ToolbarContent>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3) -> TupleToolbarContent<(C0, C1, C2, C3)> { fatalError() }
    public static func buildBlock<C0: ToolbarContent, C1: ToolbarContent, C2: ToolbarContent, C3: ToolbarContent, C4: ToolbarContent>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4) -> TupleToolbarContent<(C0, C1, C2, C3, C4)> { fatalError() }
    public static func buildBlock<C0: ToolbarContent, C1: ToolbarContent, C2: ToolbarContent, C3: ToolbarContent, C4: ToolbarContent, C5: ToolbarContent>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5) -> TupleToolbarContent<(C0, C1, C2, C3, C4, C5)> { fatalError() }
    public static func buildBlock<C0: ToolbarContent, C1: ToolbarContent, C2: ToolbarContent, C3: ToolbarContent, C4: ToolbarContent, C5: ToolbarContent, C6: ToolbarContent>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6) -> TupleToolbarContent<(C0, C1, C2, C3, C4, C5, C6)> { fatalError() }
    public static func buildBlock<C0: ToolbarContent, C1: ToolbarContent, C2: ToolbarContent, C3: ToolbarContent, C4: ToolbarContent, C5: ToolbarContent, C6: ToolbarContent, C7: ToolbarContent>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7) -> TupleToolbarContent<(C0, C1, C2, C3, C4, C5, C6, C7)> { fatalError() }
    public static func buildBlock<C0: ToolbarContent, C1: ToolbarContent, C2: ToolbarContent, C3: ToolbarContent, C4: ToolbarContent, C5: ToolbarContent, C6: ToolbarContent, C7: ToolbarContent, C8: ToolbarContent>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8) -> TupleToolbarContent<(C0, C1, C2, C3, C4, C5, C6, C7, C8)> { fatalError() }
    public static func buildBlock<C0: ToolbarContent, C1: ToolbarContent, C2: ToolbarContent, C3: ToolbarContent, C4: ToolbarContent, C5: ToolbarContent, C6: ToolbarContent, C7: ToolbarContent, C8: ToolbarContent, C9: ToolbarContent>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8, _ c9: C9) -> TupleToolbarContent<(C0, C1, C2, C3, C4, C5, C6, C7, C8, C9)> { fatalError() }
    public static func buildIf<C: ToolbarContent>(_ c: C?) -> C? { c }
    public static func buildEither<T: ToolbarContent, F: ToolbarContent>(first: T) -> _ConditionalToolbar<T, F> { fatalError() }
    public static func buildEither<T: ToolbarContent, F: ToolbarContent>(second: F) -> _ConditionalToolbar<T, F> { fatalError() }
}
public struct ToolbarItemPlacement {
    public static let automatic = ToolbarItemPlacement(), principal = ToolbarItemPlacement(), navigation = ToolbarItemPlacement()
    public static let primaryAction = ToolbarItemPlacement(), secondaryAction = ToolbarItemPlacement(), status = ToolbarItemPlacement()
    public static let confirmationAction = ToolbarItemPlacement(), cancellationAction = ToolbarItemPlacement(), destructiveAction = ToolbarItemPlacement()
    public static let navigationBarLeading = ToolbarItemPlacement(), navigationBarTrailing = ToolbarItemPlacement(), bottomBar = ToolbarItemPlacement(), keyboard = ToolbarItemPlacement()
}
public struct ToolbarItem<ID, Content: View>: ToolbarContent {}
extension ToolbarItem where ID == () {
    public init(placement: ToolbarItemPlacement = .automatic, @ViewBuilder content: () -> Content) {}
}
public struct ToolbarItemGroup<Content: View>: ToolbarContent {
    public init(placement: ToolbarItemPlacement = .automatic, @ViewBuilder content: () -> Content) {}
}
public enum ToolbarPlacement { case automatic, bottomBar, navigationBar, tabBar }

// MARK: Rendering
@MainActor public final class ImageRenderer<Content: View>: ObservableObject {
    public init(content: Content) {}
    public var proposedSize: ProposedViewSize = .unspecified
    public var scale: CGFloat = 1
    public var uiImage: UIImage? { nil }
    public var cgImage: CGImage? { nil }
    public func render(rasterizationScale: CGFloat = 1, renderer: (CGSize, (CGContext) -> Void) -> Void) {}
}

// MARK: UIKit bridging
public struct UIViewRepresentableContext<R: UIViewRepresentable> { public var coordinator: R.Coordinator { fatalError() } }
public protocol UIViewRepresentable: View where Body == Never {
    associatedtype UIViewType: UIView
    associatedtype Coordinator = Void
    typealias Context = UIViewRepresentableContext<Self>
    @MainActor func makeUIView(context: Context) -> UIViewType
    @MainActor func updateUIView(_ uiView: UIViewType, context: Context)
    @MainActor static func dismantleUIView(_ uiView: UIViewType, coordinator: Coordinator)
    @MainActor func makeCoordinator() -> Coordinator
}
extension UIViewRepresentable {
    public var body: Never { fatalError() }
    public static func dismantleUIView(_ uiView: UIViewType, coordinator: Coordinator) {}
}
extension UIViewRepresentable where Coordinator == Void { public func makeCoordinator() -> Void {} }

// MARK: App & scenes
public protocol Scene { associatedtype Body: Scene; @SceneBuilder @MainActor var body: Self.Body { get } }
extension Never: Scene {}
public struct TupleScene<T>: Scene { public var body: Never { fatalError() } }
@resultBuilder public struct SceneBuilder {
    public static func buildBlock<C: Scene>(_ c: C) -> C { c }
    public static func buildBlock<C0: Scene, C1: Scene>(_ c0: C0, _ c1: C1) -> TupleScene<(C0, C1)> { fatalError() }
    public static func buildBlock<C0: Scene, C1: Scene, C2: Scene>(_ c0: C0, _ c1: C1, _ c2: C2) -> TupleScene<(C0, C1, C2)> { fatalError() }
    public static func buildBlock<C0: Scene, C1: Scene, C2: Scene, C3: Scene>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3) -> TupleScene<(C0, C1, C2, C3)> { fatalError() }
    public static func buildBlock<C0: Scene, C1: Scene, C2: Scene, C3: Scene, C4: Scene>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4) -> TupleScene<(C0, C1, C2, C3, C4)> { fatalError() }
}
public struct WindowGroup<Content: View>: Scene { public init(@ViewBuilder content: () -> Content) {}; public var body: Never { fatalError() } }
@MainActor @preconcurrency public protocol App { associatedtype Body: Scene; @SceneBuilder @MainActor var body: Self.Body { get }; init() }
extension App { public static func main() {} }
extension Scene {
    public func onChange<V: Equatable>(of v: V, perform: @escaping (V) -> Void) -> some Scene { self }
    public func backgroundTask<D, R>(_ t: BackgroundTask<D, R>, action: @escaping @Sendable (D) async -> R) -> some Scene { self }
}
public struct BackgroundTask<Request, Response> { public static func appRefresh(_ id: String) -> BackgroundTask<Void, Void> { fatalError() } }

// MARK: Modifiers
public struct ContextMenu<MenuItems: View> { public init(@ViewBuilder menuItems: () -> MenuItems) {} }
public struct _TaskPriority {}
extension View {
    public func frame(width: CGFloat? = nil, height: CGFloat? = nil, alignment: Alignment = .center) -> _MV { _MV() }
    public func frame(minWidth: CGFloat? = nil, idealWidth: CGFloat? = nil, maxWidth: CGFloat? = nil, minHeight: CGFloat? = nil, idealHeight: CGFloat? = nil, maxHeight: CGFloat? = nil, alignment: Alignment = .center) -> _MV { _MV() }
    public func padding(_ edges: Edge.Set = .all, _ length: CGFloat? = nil) -> _MV { _MV() }
    public func padding(_ length: CGFloat) -> _MV { _MV() }
    public func padding(_ insets: EdgeInsets) -> _MV { _MV() }
    public func foregroundStyle<S: ShapeStyle>(_ s: S) -> _MV { _MV() }
    public func foregroundStyle<S1: ShapeStyle, S2: ShapeStyle>(_ a: S1, _ b: S2) -> _MV { _MV() }
    public func foregroundColor(_ c: Color?) -> _MV { _MV() }
    public func font(_ f: Font?) -> _MV { _MV() }
    public func fontWeight(_ w: Font.Weight?) -> _MV { _MV() }
    public func bold(_ on: Bool = true) -> _MV { _MV() }
    public func italic(_ on: Bool = true) -> _MV { _MV() }
    public func monospacedDigit() -> _MV { _MV() }
    public func lineLimit(_ n: Int?) -> _MV { _MV() }
    public func lineLimit(_ r: ClosedRange<Int>) -> _MV { _MV() }
    public func lineLimit(_ r: PartialRangeFrom<Int>) -> _MV { _MV() }
    public func lineLimit(_ n: Int, reservesSpace: Bool) -> _MV { _MV() }
    public func multilineTextAlignment(_ a: TextAlignment) -> _MV { _MV() }
    public func minimumScaleFactor(_ f: CGFloat) -> _MV { _MV() }
    public func truncationMode(_ m: Text.TruncationMode) -> _MV { _MV() }
    public func allowsTightening(_ on: Bool) -> _MV { _MV() }
    public func lineSpacing(_ s: CGFloat) -> _MV { _MV() }
    public func textCase(_ c: Text.Case?) -> _MV { _MV() }
    public func fixedSize() -> _MV { _MV() }
    public func fixedSize(horizontal: Bool, vertical: Bool) -> _MV { _MV() }
    public func layoutPriority(_ p: Double) -> _MV { _MV() }
    @_disfavoredOverload public func background<B: View>(_ b: B, alignment: Alignment = .center) -> _MV { _MV() }
    public func background<B: View>(alignment: Alignment = .center, @ViewBuilder content: () -> B) -> _MV { _MV() }
    public func background<S: ShapeStyle>(_ s: S, ignoresSafeAreaEdges: Edge.Set = .all) -> _MV { _MV() }
    public func background<S: ShapeStyle, T: Shape>(_ s: S, in shape: T, fillStyle: FillStyle = FillStyle()) -> _MV { _MV() }
    public func background(ignoresSafeAreaEdges: Edge.Set = .all) -> _MV { _MV() }
    @_disfavoredOverload public func overlay<O: View>(_ o: O, alignment: Alignment = .center) -> _MV { _MV() }
    public func overlay<O: View>(alignment: Alignment = .center, @ViewBuilder content: () -> O) -> _MV { _MV() }
    public func overlay<S: ShapeStyle, T: Shape>(_ s: S, in shape: T) -> _MV { _MV() }
    public func opacity(_ o: Double) -> _MV { _MV() }
    public func hidden() -> _MV { _MV() }
    public func disabled(_ d: Bool) -> _MV { _MV() }
    public func tag<V: Hashable>(_ v: V) -> _MV { _MV() }
    public func id<ID: Hashable>(_ id: ID) -> _MV { _MV() }
    public func zIndex(_ z: Double) -> _MV { _MV() }
    public func offset(_ s: CGSize) -> _MV { _MV() }
    public func offset(x: CGFloat = 0, y: CGFloat = 0) -> _MV { _MV() }
    public func position(x: CGFloat = 0, y: CGFloat = 0) -> _MV { _MV() }
    public func scaleEffect(_ s: CGFloat, anchor: UnitPoint = .center) -> _MV { _MV() }
    public func rotationEffect(_ a: Angle, anchor: UnitPoint = .center) -> _MV { _MV() }
    public func clipped(antialiased: Bool = false) -> _MV { _MV() }
    public func clipShape<S: Shape>(_ s: S, style: FillStyle = FillStyle()) -> _MV { _MV() }
    public func cornerRadius(_ r: CGFloat, antialiased: Bool = true) -> _MV { _MV() }
    public func mask<M: View>(alignment: Alignment = .center, @ViewBuilder _ mask: () -> M) -> _MV { _MV() }
    public func shadow(color: Color = .black, radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) -> _MV { _MV() }
    public func border<S: ShapeStyle>(_ s: S, width: CGFloat = 1) -> _MV { _MV() }
    public func contentShape<S: Shape>(_ s: S, eoFill: Bool = false) -> _MV { _MV() }
    public func contentShape<S: Shape>(_ kind: ContentShapeKinds, _ s: S, eoFill: Bool = false) -> _MV { _MV() }
    public func allowsHitTesting(_ on: Bool) -> _MV { _MV() }
    public func tint(_ c: Color?) -> _MV { _MV() }
    public func tint<S: ShapeStyle>(_ s: S?) -> _MV { _MV() }
    public func accentColor(_ c: Color?) -> _MV { _MV() }
    public func preferredColorScheme(_ c: ColorScheme?) -> _MV { _MV() }
    public func environment<V>(_ kp: WritableKeyPath<EnvironmentValues, V>, _ v: V) -> _MV { _MV() }
    public func environmentObject<O: ObservableObject>(_ o: O) -> _MV { _MV() }
    public func dynamicTypeSize(_ s: DynamicTypeSize) -> _MV { _MV() }
    public func dynamicTypeSize<T: RangeExpression>(_ r: T) -> _MV where T.Bound == DynamicTypeSize { _MV() }
    public func ignoresSafeArea(_ regions: SafeAreaRegions = .all, edges: Edge.Set = .all) -> _MV { _MV() }
    public func safeAreaInset<V: View>(edge: VerticalEdge, alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> V) -> _MV { _MV() }
    public func animation<V: Equatable>(_ a: Animation?, value: V) -> _MV { _MV() }
    public func transition(_ t: AnyTransition) -> _MV { _MV() }
    public func labelsHidden() -> _MV { _MV() }
    public func controlSize(_ s: ControlSize) -> _MV { _MV() }
    public func buttonStyle<S: PrimitiveButtonStyle>(_ s: S) -> _MV { _MV() }
    public func buttonBorderShape(_ s: ButtonBorderShape) -> _MV { _MV() }
    public func pickerStyle<S: PickerStyle>(_ s: S) -> _MV { _MV() }
    public func labelStyle<S: LabelStyle>(_ s: S) -> _MV { _MV() }
    public func listStyle<S: ListStyle>(_ s: S) -> _MV { _MV() }
    public func textFieldStyle<S: TextFieldStyle>(_ s: S) -> _MV { _MV() }
    public func datePickerStyle<S: DatePickerStyle>(_ s: S) -> _MV { _MV() }
    public func formStyle<S: FormStyle>(_ s: S) -> _MV { _MV() }
    public func menuStyle<S>(_ s: S) -> _MV { _MV() }
    public func listRowInsets(_ i: EdgeInsets?) -> _MV { _MV() }
    public func listRowBackground<V: View>(_ v: V?) -> _MV { _MV() }
    public func listRowSeparator(_ v: Visibility, edges: VerticalEdge.Set = .all) -> _MV { _MV() }
    public func listSectionSeparator(_ v: Visibility, edges: VerticalEdge.Set = .all) -> _MV { _MV() }
    public func scrollContentBackground(_ v: Visibility) -> _MV { _MV() }
    public func scrollDismissesKeyboard(_ m: ScrollDismissesKeyboardMode) -> _MV { _MV() }
    public func scrollDisabled(_ d: Bool) -> _MV { _MV() }
    public func scrollIndicators(_ v: ScrollIndicatorVisibility, axes: Axis.Set = [.vertical, .horizontal]) -> _MV { _MV() }
    public func keyboardType(_ t: UIKeyboardType) -> _MV { _MV() }
    public func textInputAutocapitalization(_ a: TextInputAutocapitalization?) -> _MV { _MV() }
    public func autocorrectionDisabled(_ d: Bool = true) -> _MV { _MV() }
    public func disableAutocorrection(_ d: Bool?) -> _MV { _MV() }
    public func textContentType(_ t: UITextContentType?) -> _MV { _MV() }
    public func submitLabel(_ l: SubmitLabel) -> _MV { _MV() }
    public func onSubmit(of triggers: SubmitTriggers = .text, _ action: @escaping () -> Void) -> _MV { _MV() }
    public func focused(_ b: FocusState<Bool>.Binding) -> _MV { _MV() }
    public func focused<V: Hashable>(_ b: FocusState<V>.Binding, equals v: V) -> _MV { _MV() }
    public func textSelection<S: TextSelectability_>(_ s: S) -> _MV { _MV() }
    public func keyboardShortcut(_ k: KeyEquivalent, modifiers: EventModifiers = .command) -> _MV { _MV() }
    public func keyboardShortcut(_ s: KeyboardShortcut) -> _MV { _MV() }
    public func keyboardShortcut(_ s: KeyboardShortcut?) -> _MV { _MV() }
    public func accessibilityLabel(_ t: Text) -> _MV { _MV() }
    public func accessibilityLabel<S: StringProtocol>(_ s: S) -> _MV { _MV() }
    public func accessibilityHint<S: StringProtocol>(_ s: S) -> _MV { _MV() }
    public func accessibilityHint(_ t: Text) -> _MV { _MV() }
    public func accessibilityValue<S: StringProtocol>(_ s: S) -> _MV { _MV() }
    public func accessibilityHidden(_ h: Bool) -> _MV { _MV() }
    public func accessibilityElement(children: AccessibilityChildBehavior = .ignore) -> _MV { _MV() }
    public func accessibilityAddTraits(_ t: AccessibilityTraits) -> _MV { _MV() }
    public func accessibilityRemoveTraits(_ t: AccessibilityTraits) -> _MV { _MV() }
    public func accessibilityAction(named: Text, _ handler: @escaping () -> Void) -> _MV { _MV() }
    public func accessibilityAction<S: StringProtocol>(named: S, _ handler: @escaping () -> Void) -> _MV { _MV() }
    public func accessibilitySortPriority(_ p: Double) -> _MV { _MV() }
    public func onTapGesture(count: Int = 1, perform: @escaping () -> Void) -> _MV { _MV() }
    public func onLongPressGesture(minimumDuration: Double = 0.5, perform: @escaping () -> Void) -> _MV { _MV() }
    public func gesture<G: Gesture>(_ g: G, including: GestureMask = .all) -> _MV { _MV() }
    public func highPriorityGesture<G: Gesture>(_ g: G, including: GestureMask = .all) -> _MV { _MV() }
    public func simultaneousGesture<G: Gesture>(_ g: G, including: GestureMask = .all) -> _MV { _MV() }
    public func onAppear(perform: (() -> Void)? = nil) -> _MV { _MV() }
    public func onDisappear(perform: (() -> Void)? = nil) -> _MV { _MV() }
    public func onChange<V: Equatable>(of v: V, perform: @escaping (V) -> Void) -> _MV { _MV() }
    public func task(priority: TaskPriority = .userInitiated, @_inheritActorContext _ action: @escaping @Sendable () async -> Void) -> _MV { _MV() }
    public func task<T: Equatable>(id: T, priority: TaskPriority = .userInitiated, @_inheritActorContext _ action: @escaping @Sendable () async -> Void) -> _MV { _MV() }
    public func refreshable(@_inheritActorContext action: @escaping @Sendable () async -> Void) -> _MV { _MV() }
    public func onOpenURL(perform: @escaping (URL) -> Void) -> _MV { _MV() }
    public func contextMenu<M: View>(@ViewBuilder menuItems: () -> M) -> _MV { _MV() }
    public func contextMenu<M: View, P: View>(@ViewBuilder menuItems: () -> M, @ViewBuilder preview: () -> P) -> _MV { _MV() }
    public func swipeActions<C: View>(edge: HorizontalEdge = .trailing, allowsFullSwipe: Bool = true, @ViewBuilder content: () -> C) -> _MV { _MV() }
    public func badge(_ n: Int) -> _MV { _MV() }
    public func help<S: StringProtocol>(_ s: S) -> _MV { _MV() }
    public func navigationTitle<S: StringProtocol>(_ s: S) -> _MV { _MV() }
    public func navigationTitle(_ t: Text) -> _MV { _MV() }
    public func navigationBarTitleDisplayMode(_ m: NavigationBarItem.TitleDisplayMode) -> _MV { _MV() }
    public func navigationBarBackButtonHidden(_ h: Bool = true) -> _MV { _MV() }
    public func navigationDestination<D: Hashable, C: View>(for: D.Type, @ViewBuilder destination: @escaping (D) -> C) -> _MV { _MV() }
    public func navigationDestination<V: View>(isPresented: Binding<Bool>, @ViewBuilder destination: () -> V) -> _MV { _MV() }
    public func toolbar<C: ToolbarContent>(@ToolbarContentBuilder content: () -> C) -> _MV { _MV() }
    public func toolbar<C: View>(@ViewBuilder content: () -> C) -> _MV { _MV() }
    public func toolbar(_ v: Visibility, for: ToolbarPlacement...) -> _MV { _MV() }
    public func toolbarBackground(_ v: Visibility, for: ToolbarPlacement...) -> _MV { _MV() }
    public func tabItem<V: View>(@ViewBuilder _ label: () -> V) -> _MV { _MV() }
    public func searchable(text: Binding<String>, placement: SearchFieldPlacement = .automatic, prompt: Text? = nil) -> _MV { _MV() }
    public func searchable<S: StringProtocol>(text: Binding<String>, placement: SearchFieldPlacement = .automatic, prompt: S) -> _MV { _MV() }
    public func sheet<C: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> C) -> _MV { _MV() }
    public func sheet<I: Identifiable, C: View>(item: Binding<I?>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping (I) -> C) -> _MV { _MV() }
    public func fullScreenCover<C: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> C) -> _MV { _MV() }
    public func fullScreenCover<I: Identifiable, C: View>(item: Binding<I?>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping (I) -> C) -> _MV { _MV() }
    public func popover<C: View>(isPresented: Binding<Bool>, attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds), arrowEdge: Edge = .top, @ViewBuilder content: @escaping () -> C) -> _MV { _MV() }
    public func presentationDetents(_ d: Set<PresentationDetent>) -> _MV { _MV() }
    public func presentationDetents(_ d: Set<PresentationDetent>, selection: Binding<PresentationDetent>) -> _MV { _MV() }
    public func presentationDragIndicator(_ v: Visibility) -> _MV { _MV() }
    public func interactiveDismissDisabled(_ d: Bool = true) -> _MV { _MV() }
    public func alert<S: StringProtocol, A: View>(_ title: S, isPresented: Binding<Bool>, @ViewBuilder actions: () -> A) -> _MV { _MV() }
    public func alert<S: StringProtocol, A: View, M: View>(_ title: S, isPresented: Binding<Bool>, @ViewBuilder actions: () -> A, @ViewBuilder message: () -> M) -> _MV { _MV() }
    public func alert<S: StringProtocol, A: View, M: View, T>(_ title: S, isPresented: Binding<Bool>, presenting: T?, @ViewBuilder actions: (T) -> A, @ViewBuilder message: (T) -> M) -> _MV { _MV() }
    public func confirmationDialog<S: StringProtocol, A: View>(_ title: S, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, @ViewBuilder actions: () -> A) -> _MV { _MV() }
    public func confirmationDialog<S: StringProtocol, A: View, M: View>(_ title: S, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, @ViewBuilder actions: () -> A, @ViewBuilder message: () -> M) -> _MV { _MV() }
    public func confirmationDialog<S: StringProtocol, A: View, M: View, T>(_ title: S, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, presenting: T?, @ViewBuilder actions: (T) -> A, @ViewBuilder message: (T) -> M) -> _MV { _MV() }
    public func fileImporter(isPresented: Binding<Bool>, allowedContentTypes: [UTType], allowsMultipleSelection: Bool = false, onCompletion: @escaping (Result<URL, Error>) -> Void) -> _MV { _MV() }
}
public struct FillStyle { public init(eoFill: Bool = false, antialiased: Bool = true) {} }
public enum VerticalEdge { case top, bottom
    public struct Set: OptionSet { public let rawValue: Int8; public init(rawValue: Int8) { self.rawValue = rawValue }; public static let all = Set(rawValue: 3), top = Set(rawValue: 1), bottom = Set(rawValue: 2) } }
public struct ButtonBorderShape { public static let automatic = ButtonBorderShape(), capsule = ButtonBorderShape(), roundedRectangle = ButtonBorderShape()
    public static func roundedRectangle(radius: CGFloat) -> ButtonBorderShape { ButtonBorderShape() } }
public struct ScrollDismissesKeyboardMode { public static let automatic = ScrollDismissesKeyboardMode(), immediately = ScrollDismissesKeyboardMode(), interactively = ScrollDismissesKeyboardMode(), never = ScrollDismissesKeyboardMode() }
public struct ScrollIndicatorVisibility { public static let automatic = ScrollIndicatorVisibility(), visible = ScrollIndicatorVisibility(), hidden = ScrollIndicatorVisibility(), never = ScrollIndicatorVisibility() }
public struct UITextContentType: Hashable { public static let telephoneNumber = UITextContentType(), name = UITextContentType(), emailAddress = UITextContentType() }
public enum NavigationBarItem { public enum TitleDisplayMode { case automatic, inline, large } }

public struct _ViewModifierContent<M>: _Leaf {}
public protocol ViewModifier { associatedtype Body: View; typealias Content = _ViewModifierContent<Self>; @ViewBuilder @MainActor func body(content: Content) -> Body }
extension View { public func modifier<M: ViewModifier>(_ m: M) -> _MV { fatalError() } }
