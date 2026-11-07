// Type-check stub (Linux only): the parts of UIKit / CoreGraphics / CoreFoundation BillBox uses, iOS 16 signatures.
@_exported import Foundation
#if canImport(FoundationNetworking)
@_exported import FoundationNetworking
#endif

// CoreFoundation / CoreGraphics bits
public typealias CFMutableData = NSMutableData
public final class CGDataConsumer { public init?(data: CFMutableData) {} }
public final class CGImage {}
public final class CGPath {}
public final class CGColor {}
public struct CGAffineTransform { public static let identity = CGAffineTransform(); public init() {}; public init(scaleX: CGFloat, y: CGFloat) {} }
public final class CGContext {
    public init?(consumer: CGDataConsumer, mediaBox: UnsafePointer<CGRect>?, _ auxiliaryInfo: NSDictionary?) {}
    public func beginPDFPage(_ pageInfo: NSDictionary?) {}
    public func endPDFPage() {}
    public func closePDF() {}
    public func saveGState() {}
    public func restoreGState() {}
    public func translateBy(x: CGFloat, y: CGFloat) {}
    public func scaleBy(x: CGFloat, y: CGFloat) {}
    public func fill(_ r: CGRect) {}
    public func rotate(by angle: CGFloat) {}
    public func setFillColor(_ c: CGColor) {}
}
public func UIGraphicsGetCurrentContext() -> CGContext? { nil }

public enum UIUserInterfaceStyle: Int { case unspecified, light, dark }
public enum UIUserInterfaceIdiom: Int { case unspecified, phone, pad, mac }
public class UITraitCollection: NSObject { public var userInterfaceStyle: UIUserInterfaceStyle { .light } }

open class UIColor: NSObject {
    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {}
    public init(white: CGFloat, alpha: CGFloat) {}
    open var cgColor: CGColor { CGColor() }
    public init(dynamicProvider: @escaping (UITraitCollection) -> UIColor) {}
    public convenience init(_ dynamicProvider: @escaping (UITraitCollection) -> UIColor) { self.init(dynamicProvider: dynamicProvider) }
    public func setFill() {}
    public func setStroke() {}
    public func withAlphaComponent(_ a: CGFloat) -> UIColor { self }
    public class var black: UIColor { UIColor(white: 0, alpha: 1) }
    public class var white: UIColor { UIColor(white: 1, alpha: 1) }
    public class var clear: UIColor { UIColor(white: 0, alpha: 0) }
    public class var label: UIColor { black }
    public class var secondaryLabel: UIColor { black }
    public class var separator: UIColor { black }
    public class var systemBlue: UIColor { black }
    public class var systemBackground: UIColor { black }
    public class var secondarySystemBackground: UIColor { black }
    public class var systemGroupedBackground: UIColor { black }
    public class var secondarySystemGroupedBackground: UIColor { black }
    public class var tertiarySystemGroupedBackground: UIColor { black }
    public class var systemGray5: UIColor { black }
    public class var systemGray6: UIColor { black }
}

open class UIFont: NSObject {
    open var pointSize: CGFloat { 12 }
    public class func systemFont(ofSize: CGFloat) -> UIFont { UIFont() }
    public class func boldSystemFont(ofSize: CGFloat) -> UIFont { UIFont() }
    public class func monospacedDigitSystemFont(ofSize: CGFloat, weight: UIFont.Weight) -> UIFont { UIFont() }
    public struct Weight { public static let regular = Weight(); public static let bold = Weight(); public static let semibold = Weight() }
}

public struct NSAttributedStringKeyStub {}
extension NSAttributedString.Key {
    public static let font = NSAttributedString.Key("NSFont")
    public static let foregroundColor = NSAttributedString.Key("NSColor")
}
extension NSString {
    public func draw(in rect: CGRect, withAttributes: [NSAttributedString.Key: Any]?) {}
    public func draw(at point: CGPoint, withAttributes: [NSAttributedString.Key: Any]?) {}
}
extension String {
    public func draw(in rect: CGRect, withAttributes: [NSAttributedString.Key: Any]? = nil) {}
}

open class UIImage: NSObject {
    public var cgImage: CGImage? { nil }
    public var size: CGSize { .zero }
    public func pngData() -> Data? { nil }
    public func jpegData(compressionQuality: CGFloat) -> Data? { nil }
    public init?(data: Data) {}
    public init(cgImage: CGImage) {}
    public override init() {}
    public func draw(in rect: CGRect) {}
}
public class UIGraphicsImageRendererFormat: NSObject { public var scale: CGFloat = 1; public override init() {} }

public class UIGraphicsImageRendererContext: NSObject {
    public var cgContext: CGContext { fatalError() }
    public func fill(_ r: CGRect) {}
}
public class UIGraphicsImageRenderer: NSObject {
    public init(size: CGSize) {}
    public init(size: CGSize, format: UIGraphicsImageRendererFormat) {}
    public func image(actions: (UIGraphicsImageRendererContext) -> Void) -> UIImage { UIImage() }
    public func pngData(actions: (UIGraphicsImageRendererContext) -> Void) -> Data { Data() }
}

open class UIResponder: NSObject {}
open class UIView: UIResponder {
    public override init() {}
    public init(frame: CGRect) {}
    open var frame: CGRect = .zero
    open var bounds: CGRect = .zero
    open var isHidden = false
    open var accessibilityElementsHidden = false
    open var tintColor: UIColor! = nil
    open var alpha: CGFloat = 1
    open var isUserInteractionEnabled = true
    open var backgroundColor: UIColor?
    open var clipsToBounds = false
    open var transform: CGAffineTransform = .identity
    open func layoutSubviews() {}
    open var superview: UIView? { nil }
    open var subviews: [UIView] { [] }
    open var window: UIWindow? { nil }
    open var autoresizingMask: AutoresizingMask = []
    open var translatesAutoresizingMaskIntoConstraints = true
    open func addSubview(_ v: UIView) {}
    open func insertSubview(_ v: UIView, at: Int) {}
    open func removeFromSuperview() {}
    open func layoutIfNeeded() {}
    public struct AutoresizingMask: OptionSet { public let rawValue: UInt; public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let flexibleWidth = AutoresizingMask(rawValue: 1); public static let flexibleHeight = AutoresizingMask(rawValue: 2) }
}
open class UIWindow: UIView {
    open var rootViewController: UIViewController?
    open var isKeyWindow: Bool { false }
}
open class UIViewController: UIResponder {
    open var view: UIView! { UIView() }
    open var presentedViewController: UIViewController? { nil }
    open var popoverPresentationController: UIPopoverPresentationController? { nil }
    open func present(_ vc: UIViewController, animated: Bool, completion: (() -> Void)? = nil) {}
    open func dismiss(animated: Bool, completion: (() -> Void)? = nil) {}
}
public struct UIPopoverArrowDirection: OptionSet { public let rawValue: UInt; public init(rawValue: UInt) { self.rawValue = rawValue }; public static let any = UIPopoverArrowDirection(rawValue: 15) }
open class UIPopoverPresentationController: NSObject {
    open var sourceView: UIView?
    open var sourceRect: CGRect = .zero
    open var permittedArrowDirections: UIPopoverArrowDirection = .any
}
open class UIActivityViewController: UIViewController {
    public init(activityItems: [Any], applicationActivities: [Any]?) {}
}
open class UIScene: UIResponder {
    public enum ActivationState: Int { case unattached, foregroundActive, foregroundInactive, background }
    open var activationState: ActivationState { .foregroundActive }
}
open class UIWindowScene: UIScene {
    open var windows: [UIWindow] { [] }
    open var keyWindow: UIWindow? { nil }
}
public struct UIBackgroundTaskIdentifier: Hashable { public static let invalid = UIBackgroundTaskIdentifier() }
open class UIApplication: UIResponder {
    public class var shared: UIApplication { UIApplication() }
    open var connectedScenes: Set<UIScene> { [] }
    open var applicationState: State { .active }
    public enum State: Int { case active, inactive, background }
    open func beginBackgroundTask(withName: String?, expirationHandler: (() -> Void)? = nil) -> UIBackgroundTaskIdentifier { .invalid }
    open func endBackgroundTask(_ id: UIBackgroundTaskIdentifier) {}
    open func open(_ url: URL, options: [AnyHashable: Any] = [:], completionHandler: ((Bool) -> Void)? = nil) {}
    open func canOpenURL(_ url: URL) -> Bool { true }
    public static let openSettingsURLString = ""
}
open class UIDevice: NSObject {
    public class var current: UIDevice { UIDevice() }
    open var userInterfaceIdiom: UIUserInterfaceIdiom { .phone }
    open var name: String { "" }
    open var model: String { "iPhone" }
    open var systemVersion: String { "16.0" }
}
open class UIPasteboard: NSObject {
    public class var general: UIPasteboard { UIPasteboard() }
    open var string: String?
    open var image: UIImage?
    open var items: [[String: Any]] = []
    open func setData(_ d: Data, forPasteboardType: String) {}
    open func setItems(_ items: [[String: Any]], options: [AnyHashable: Any] = [:]) {}
}
public enum UIAccessibility {
    public struct Notification { public static let announcement = Notification(); public static let screenChanged = Notification() }
    public static func post(notification: Notification, argument: Any?) {}
    public static var isVoiceOverRunning: Bool { false }
}

// Printing
open class UIPrintInfo: NSObject {
    public enum OutputType: Int { case general, photo, grayscale, photoGrayscale }
    public enum Orientation: Int { case portrait, landscape }
    public init(dictionary: [AnyHashable: Any]?) {}
    open var outputType: OutputType = .general
    open var jobName = ""
    open var orientation: Orientation = .portrait
}
open class UIPrintPaper: NSObject {
    open var paperSize: CGSize { .zero }
    open var printableRect: CGRect { .zero }
    open class func bestPaper(forPageSize contentSize: CGSize, withPapersFrom paperList: [UIPrintPaper]) -> UIPrintPaper { UIPrintPaper() }
}
public protocol UIPrintInteractionControllerDelegate: NSObjectProtocol {
    func printInteractionController(_ c: UIPrintInteractionController, choosePaper paperList: [UIPrintPaper]) -> UIPrintPaper
}
open class UIPrinter: NSObject {
    public init(url: URL) {}
    open var url: URL { URL(fileURLWithPath: "/") }
    open var displayName: String { "" }
}
open class UIPrintInteractionController: NSObject {
    public class var shared: UIPrintInteractionController { UIPrintInteractionController() }
    public typealias CompletionHandler = (UIPrintInteractionController, Bool, Error?) -> Void
    open var printInfo: UIPrintInfo?
    open var printingItem: Any?
    open var printingItems: [Any]?
    open var printPageRenderer: UIPrintPageRenderer?
    open var showsNumberOfCopies = true
    weak open var delegate: UIPrintInteractionControllerDelegate?
    @discardableResult open func present(animated: Bool, completionHandler: CompletionHandler? = nil) -> Bool { true }
    @discardableResult open func present(from rect: CGRect, in view: UIView, animated: Bool, completionHandler: CompletionHandler? = nil) -> Bool { true }
    @discardableResult open func print(to printer: UIPrinter, completionHandler: CompletionHandler? = nil) -> Bool { true }
    open func dismiss(animated: Bool) {}
}
open class UIPrintPageRenderer: NSObject {
    public override init() {}
    open var numberOfPages: Int { 0 }
    open var paperRect: CGRect { .zero }
    open var printableRect: CGRect { .zero }
    open func drawPage(at pageIndex: Int, in printableRect: CGRect) {}
}
open class UIPrinterPickerController: NSObject {
    public typealias CompletionHandler = (UIPrinterPickerController, Bool, Error?) -> Void
    public init(initiallySelectedPrinter: UIPrinter?) {}
    open var selectedPrinter: UIPrinter? { nil }
    @discardableResult open func present(animated: Bool, completionHandler: CompletionHandler? = nil) -> Bool { true }
    @discardableResult open func present(from rect: CGRect, in view: UIView, animated: Bool, completionHandler: CompletionHandler? = nil) -> Bool { true }
}


// Document picker
@_exported import UniformTypeIdentifiers
public protocol UIDocumentPickerDelegate: NSObjectProtocol {}
extension UIDocumentPickerDelegate {
    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {}
    public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
}
open class UIDocumentPickerViewController: UIViewController {
    public init(forOpeningContentTypes: [UTType], asCopy: Bool = false) {}
    public init(forExporting: [URL], asCopy: Bool = false) {}
    open weak var delegate: UIDocumentPickerDelegate?
    open var allowsMultipleSelection = false
    open var directoryURL: URL?
}

public protocol UINavigationControllerDelegate: NSObjectProtocol {}
public protocol UIImagePickerControllerDelegate: NSObjectProtocol {}
extension UIImagePickerControllerDelegate {
    public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {}
    public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {}
}
open class UIImagePickerController: UIViewController {
    public enum SourceType: Int { case photoLibrary, camera, savedPhotosAlbum }
    public struct InfoKey: Hashable, RawRepresentable { public let rawValue: String; public init(rawValue: String) { self.rawValue = rawValue }
        public static let originalImage = InfoKey(rawValue: "UIImagePickerControllerOriginalImage") }
    open class func isSourceTypeAvailable(_ t: SourceType) -> Bool { false }
    public override init() {}
    open var sourceType: SourceType = .photoLibrary
    open weak var delegate: (UIImagePickerControllerDelegate & UINavigationControllerDelegate)?
}
