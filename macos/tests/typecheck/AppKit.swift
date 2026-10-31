// Type-check stub (Linux only): the AppKit surface the Mac app uses, on top of the iOS SwiftUI / UIKit stubs.
// It only has to make the Mac sources type-check; nothing here runs.
@_exported import Foundation
@_exported import UIKit
@_exported import SwiftUI
@_exported import PDFKit
@_exported import WebKit

public struct Selector { public init(_ s: String) {} }
public typealias NSRect = CGRect
public typealias NSSize = CGSize
public typealias NSPoint = CGPoint
public typealias NSColor = UIColor
public typealias NSFont = UIFont
public typealias NSImage = UIImage

extension UIColor {
    public convenience init(srgbRed r: CGFloat, green g: CGFloat, blue b: CGFloat, alpha a: CGFloat) { self.init(white: 0, alpha: 1) }
    public convenience init(name: String?, dynamicProvider: @escaping (NSAppearance) -> NSColor) { self.init(white: 0, alpha: 1) }
    public static var separatorColor: NSColor { .black }
    public static var windowBackgroundColor: NSColor { .black }
    public static var controlBackgroundColor: NSColor { .black }
    public static var textBackgroundColor: NSColor { .black }
    public static var underPageBackgroundColor: NSColor { .black }
}
extension CGRect { public func fill() {} }
extension UIImage {
    public convenience init(size: NSSize) { self.init() }
    public convenience init(size: NSSize, flipped: Bool, drawingHandler: @escaping (NSRect) -> Bool) { self.init() }
    public var tiffRepresentation: Data? { nil }
    public func addRepresentation(_ r: NSBitmapImageRep) {}
    public func lockFocus() {}
    public func unlockFocus() {}
}
open class NSAppearance {
    public struct Name: Hashable { public init(_ s: String) {}; public static let aqua = Name(""), darkAqua = Name("") }
    public func bestMatch(from: [Name]) -> Name? { nil }
    public var name: Name { .aqua }
}
open class NSResponder: NSObject {
    open func keyDown(with e: NSEvent) {}
    open func keyUp(with e: NSEvent) {}
    open func mouseDown(with e: NSEvent) {}
    open func mouseUp(with e: NSEvent) {}
}
open class NSView: NSResponder {
    public override init() {}
    public init(frame: NSRect) {}
    open var frame: NSRect = .zero
    open var bounds: NSRect = .zero
    open var isFlipped: Bool { false }
    open var window: NSWindow? { nil }
    open var subviews: [NSView] = []
    open var autoresizingMask: AutoresizingMask = []
    public struct AutoresizingMask: OptionSet { public let rawValue: Int; public init(rawValue: Int) { self.rawValue = rawValue }; public static let width = AutoresizingMask(rawValue: 1), height = AutoresizingMask(rawValue: 2) }
    open func addSubview(_ v: NSView) {}
    open func removeFromSuperview() {}
    open func convert(_ p: NSPoint, to v: NSView?) -> NSPoint { p }
    open func layoutSubtreeIfNeeded() {}
    open func cacheDisplay(in r: NSRect, to rep: NSBitmapImageRep) {}
    open func bitmapImageRepForCachingDisplay(in r: NSRect) -> NSBitmapImageRep? { nil }
    open func display() {}
}
public final class NSHostingView<Content: View>: NSView {
    public init(rootView: Content) { super.init() }
    public var rootView: Content { fatalError() }
}
open class NSWindow: NSResponder {
    public struct StyleMask: OptionSet { public let rawValue: Int; public init(rawValue: Int) { self.rawValue = rawValue }
        public static let borderless = StyleMask(rawValue: 0), titled = StyleMask(rawValue: 1), closable = StyleMask(rawValue: 2), miniaturizable = StyleMask(rawValue: 4),
                          resizable = StyleMask(rawValue: 8), utilityWindow = StyleMask(rawValue: 16), nonactivatingPanel = StyleMask(rawValue: 32), fullSizeContentView = StyleMask(rawValue: 64) }
    public enum BackingStoreType { case buffered }
    public struct Level: Hashable { public init(_ v: Int) {}; public static let normal = Level(0), floating = Level(1) }
    public struct CollectionBehavior: OptionSet { public let rawValue: Int; public init(rawValue: Int) { self.rawValue = rawValue }
        public static let canJoinAllSpaces = CollectionBehavior(rawValue: 1), stationary = CollectionBehavior(rawValue: 2), ignoresCycle = CollectionBehavior(rawValue: 4), fullScreenAuxiliary = CollectionBehavior(rawValue: 8) }
    public static let willCloseNotification = Notification.Name("w")
    public init(contentRect: NSRect, styleMask: StyleMask, backing: BackingStoreType, defer flag: Bool) {}
    open var contentView: NSView?
    open var title: String = ""
    open var isReleasedWhenClosed = true
    open var delegate: NSWindowDelegate?
    open var level: Level = .normal
    open var collectionBehavior: CollectionBehavior = []
    open var alphaValue: CGFloat = 1
    open var ignoresMouseEvents = false
    open var hasShadow = true
    open var isOpaque = true
    open var backgroundColor: NSColor = .black
    open var frame: NSRect { .zero }
    open var windowNumber: Int { 0 }
    open var isVisible: Bool { false }
    open var hidesOnDeactivate = false
    open var becomesKeyOnlyIfNeeded = false
    open var isMovableByWindowBackground = false
    open var titlebarAppearsTransparent = false
    open var minSize: NSSize = .zero
    open func center() {}
    open func close() {}
    open func orderOut(_ s: Any?) {}
    open func orderFront(_ s: Any?) {}
    open func orderFrontRegardless() {}
    open func makeKeyAndOrderFront(_ s: Any?) {}
    open func setFrame(_ r: NSRect, display: Bool) {}
    open func setFrameOrigin(_ p: NSPoint) {}
    open func setContentSize(_ s: NSSize) {}
    @discardableResult open func makeFirstResponder(_ r: NSResponder?) -> Bool { true }
    open func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    open var canBecomeKey: Bool { true }
    open var canBecomeMain: Bool { true }
}
open class NSPanel: NSWindow {}
@MainActor public protocol NSWindowDelegate: AnyObject {}
extension NSWindowDelegate { public func windowShouldClose(_ sender: NSWindow) -> Bool { true }; public func windowWillClose(_ n: Notification) {} }
open class NSScreen { public static var main: NSScreen? { nil }; public static var screens: [NSScreen] { [] }; public var frame: NSRect { .zero }; public var visibleFrame: NSRect { .zero }; public var backingScaleFactor: CGFloat { 2 } }

open class NSEvent: NSObject {
    open var clickCount: Int { 1 }
    public enum EventType { case keyDown, keyUp, leftMouseDown, leftMouseUp, flagsChanged }
    public struct EventTypeMask: OptionSet { public let rawValue: UInt64; public init(rawValue: UInt64) { self.rawValue = rawValue }; public static let keyDown = EventTypeMask(rawValue: 1), flagsChanged = EventTypeMask(rawValue: 2) }
    public struct ModifierFlags: OptionSet { public let rawValue: UInt; public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let command = ModifierFlags(rawValue: 1), shift = ModifierFlags(rawValue: 2), option = ModifierFlags(rawValue: 4), control = ModifierFlags(rawValue: 8),
                          deviceIndependentFlagsMask = ModifierFlags(rawValue: 0xffff) }
    public static var modifierFlags: ModifierFlags { [] }
    public var modifierFlags: ModifierFlags { [] }
    public var keyCode: UInt16 { 0 }
    public var charactersIgnoringModifiers: String? { nil }
    public var characters: String? { nil }
    public var type: EventType { .keyDown }
    public static func addLocalMonitorForEvents(matching m: EventTypeMask, handler: @escaping (NSEvent) -> NSEvent?) -> Any? { nil }
    public static func removeMonitor(_ m: Any) {}
    public class func mouseEvent(with type: EventType, location: NSPoint, modifierFlags: ModifierFlags, timestamp: TimeInterval, windowNumber: Int, context: Any?, eventNumber: Int, clickCount: Int, pressure: Float) -> NSEvent? { nil }
    public class func keyEvent(with type: EventType, location: NSPoint, modifierFlags: ModifierFlags, timestamp: TimeInterval, windowNumber: Int, context: Any?, characters: String, charactersIgnoringModifiers: String, isARepeat: Bool, keyCode: UInt16) -> NSEvent? { nil }
}
open class NSCursor { public static var resizeLeftRight: NSCursor { NSCursor() }; public static var arrow: NSCursor { NSCursor() }; public func push() {}; public static func pop() {}; public func set() {} }

open class NSAlert: NSObject {
    public enum Style { case warning, informational, critical }
    open var messageText = ""
    open var informativeText = ""
    open var alertStyle: Style = .warning
    open var accessoryView: NSView?
    @discardableResult open func addButton(withTitle t: String) -> NSButton { NSButton() }
    open func runModal() -> NSApplication.ModalResponse { .OK }
    open var buttons: [NSButton] { [] }
}
open class NSButton: NSView { open var hasDestructiveAction = false; open var keyEquivalent = ""; open var title = "" }
open class NSSavePanel: NSObject {
    open var nameFieldStringValue = ""
    open var allowedContentTypes: [UTType] = []
    open var canCreateDirectories = true
    open var message = ""
    open var prompt = ""
    open var title = ""
    open var directoryURL: URL?
    open var url: URL? { nil }
    open func runModal() -> NSApplication.ModalResponse { .OK }
}
open class NSOpenPanel: NSSavePanel {
    open var canChooseFiles = true
    open var canChooseDirectories = false
    open var allowsMultipleSelection = false
    open var urls: [URL] { [] }
}
open class NSPasteboard {
    public struct PasteboardType: Hashable, RawRepresentable { public let rawValue: String; public init(rawValue: String) { self.rawValue = rawValue }; public init(_ s: String) { rawValue = s }
        public static let string = PasteboardType("s"), fileURL = PasteboardType("f"), pdf = PasteboardType("p"), tiff = PasteboardType("t"), png = PasteboardType("png") }
    public static var general: NSPasteboard { NSPasteboard() }
    @discardableResult public func clearContents() -> Int { 0 }
    @discardableResult public func setString(_ s: String, forType t: PasteboardType) -> Bool { true }
    @discardableResult public func setData(_ d: Data?, forType t: PasteboardType) -> Bool { true }
    @discardableResult public func writeObjects(_ o: [NSPasteboardWriting]) -> Bool { true }
    public func string(forType t: PasteboardType) -> String? { nil }
    public var pasteboardItems: [NSPasteboardItem]? { nil }
    public var types: [PasteboardType]? { nil }
    public var changeCount: Int { 0 }
}
public protocol NSPasteboardWriting {}
open class NSPasteboardItem: NSObject, NSPasteboardWriting {
    public var types: [NSPasteboard.PasteboardType] { [] }
    public func data(forType t: NSPasteboard.PasteboardType) -> Data? { nil }
    @discardableResult public func setData(_ d: Data, forType t: NSPasteboard.PasteboardType) -> Bool { true }
    @discardableResult public func setString(_ s: String, forType t: NSPasteboard.PasteboardType) -> Bool { true }
}
open class NSBitmapImageRep: NSObject {
    public enum FileType { case png, jpeg, tiff }
    public init?(data: Data) {}
    public init?(bitmapDataPlanes: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?, pixelsWide: Int, pixelsHigh: Int, bitsPerSample: Int, samplesPerPixel: Int, hasAlpha: Bool, isPlanar: Bool, colorSpaceName: NSColorSpaceName, bytesPerRow: Int, bitsPerPixel: Int) {}
    public func representation(using t: FileType, properties: [AnyHashable: Any]) -> Data? { nil }
    public var size: NSSize = .zero
    public var cgImage: CGImage? { nil }
}
public let NSCalibratedRGBColorSpace = "rgb"
public let NSDeviceRGBColorSpace = "rgb"
open class NSGraphicsContext { public init?(bitmapImageRep: NSBitmapImageRep) {}; public static var current: NSGraphicsContext?; public var cgContext: CGContext { fatalError() }
    public static func saveGraphicsState() {}; public static func restoreGraphicsState() {} }

open class NSPrinter { public init?(name: String) {}; public static var printerNames: [String] { [] }; public var name: String { "" } }
open class NSPrintInfo: NSObject, NSCopying {
    public enum PaperOrientation { case portrait, landscape }
    public enum PaginationMode { case fit, automatic, clip }
    public static var shared: NSPrintInfo { NSPrintInfo() }
    public func copy(with zone: NSZone? = nil) -> Any { self }
    open var printer: NSPrinter = NSPrinter(name: "")!
    open var paperSize: NSSize = .zero
    open var orientation: PaperOrientation = .portrait
    open var topMargin: CGFloat = 0, bottomMargin: CGFloat = 0, leftMargin: CGFloat = 0, rightMargin: CGFloat = 0
    open var horizontalPagination: PaginationMode = .fit, verticalPagination: PaginationMode = .fit
    open var isHorizontallyCentered = true, isVerticallyCentered = true
    open var jobDisposition: String = ""
    open var dictionary: NSMutableDictionary { NSMutableDictionary() }
}
open class NSPrintOperation: NSObject {
    open var showsPrintPanel = true
    open var showsProgressPanel = true
    open var jobTitle: String?
    @discardableResult open func run() -> Bool { true }
    open func runModal(for w: NSWindow, delegate: Any?, didRun: Selector?, contextInfo: UnsafeMutableRawPointer?) {}
}
public enum PDFPrintScalingMode { case pageScaleNone, pageScaleToFit, pageScaleDownToFit }
extension PDFDocument { public func printOperation(for info: NSPrintInfo, scalingMode: PDFPrintScalingMode, autoRotate: Bool) -> NSPrintOperation? { nil } }

open class NSApplication: NSResponder {
    public enum ActivationPolicy { case regular, accessory, prohibited }
    public enum TerminateReply { case terminateNow, terminateCancel, terminateLater }
    public struct ModalResponse: Equatable { public init(_ v: Int) {}; public static let OK = ModalResponse(1), cancel = ModalResponse(0),
        alertFirstButtonReturn = ModalResponse(1000), alertSecondButtonReturn = ModalResponse(1001), alertThirdButtonReturn = ModalResponse(1002) }
    public static var shared: NSApplication { NSApplication() }
    open var currentEvent: NSEvent? { nil }
    @discardableResult open func setActivationPolicy(_ p: ActivationPolicy) -> Bool { true }
    open func activate(ignoringOtherApps: Bool) {}
    open func terminate(_ s: Any?) {}
    open func reply(toApplicationShouldTerminate: Bool) {}
    @discardableResult open func sendAction(_ a: Selector, to: Any?, from: Any?) -> Bool { true }
    open var windows: [NSWindow] { [] }
    open var keyWindow: NSWindow? { nil }
    open var mainWindow: NSWindow? { nil }
    open var isActive: Bool { true }
    open func hide(_ s: Any?) {}
}
public var NSApp: NSApplication! = NSApplication()
@MainActor public protocol NSApplicationDelegate: AnyObject {}
public func NSSelectorFromString(_ s: String) -> Selector { Selector(s) }

// the iOS stubs' PDFView and WKWebView are UIViews; on the Mac they are NSViews
extension UIView {
    public var isFlipped: Bool { false }
    public func mouseDown(with e: NSEvent) {}
    public func mouseUp(with e: NSEvent) {}
    public func keyDown(with e: NSEvent) {}
    public func keyUp(with e: NSEvent) {}
    public func convert(_ p: NSPoint, to v: UIView?) -> NSPoint { p }
}
extension UIWindow {
    public var windowNumber: Int { 0 }
    @discardableResult public func makeFirstResponder(_ r: Any?) -> Bool { true }
}

// SwiftUI on the Mac
public struct NSViewRepresentableContext<R: NSViewRepresentable> { public var coordinator: R.Coordinator { fatalError() } }
public protocol NSViewRepresentable: View where Body == Never {
    associatedtype NSViewType: AnyObject
    associatedtype Coordinator = Void
    typealias Context = NSViewRepresentableContext<Self>
    @MainActor func makeNSView(context: Context) -> NSViewType
    @MainActor func updateNSView(_ nsView: NSViewType, context: Context)
    @MainActor static func dismantleNSView(_ nsView: NSViewType, coordinator: Coordinator)
    @MainActor func makeCoordinator() -> Coordinator
}
extension NSViewRepresentable {
    public var body: Never { fatalError() }
    public static func dismantleNSView(_ nsView: NSViewType, coordinator: Coordinator) {}
}
extension NSViewRepresentable where Coordinator == Void { public func makeCoordinator() -> Void {} }
extension Color { public init(nsColor: NSColor) { self.init(uiColor: nsColor) } }
@propertyWrapper public struct NSApplicationDelegateAdaptor<D: NSApplicationDelegate>: DynamicProperty {
    public init(_ t: D.Type) {}
    public var wrappedValue: D { fatalError() }
}
// ViewModifier now lives in the shared iOS SwiftUI stub

public struct NSColorSpaceName: Hashable { public init(_ s: String) {}; public static let deviceRGB = NSColorSpaceName("NSDeviceRGBColorSpace"), calibratedRGB = NSColorSpaceName("NSCalibratedRGBColorSpace") }
extension UIColor { public static var controlAccentColor: NSColor { .black } }
