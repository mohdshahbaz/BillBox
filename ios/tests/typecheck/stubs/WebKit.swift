import Foundation
import UIKit
public enum WKUserScriptInjectionTime: Int { case atDocumentStart, atDocumentEnd }
open class WKUserScript: NSObject { public init(source: String, injectionTime: WKUserScriptInjectionTime, forMainFrameOnly: Bool) {} }
open class WKUserContentController: NSObject { open func addUserScript(_ s: WKUserScript) {}; open func removeAllUserScripts() {} }
open class WKWebsiteDataRecord: NSObject {}
open class WKWebsiteDataStore: NSObject {
    open class func `default`() -> WKWebsiteDataStore { WKWebsiteDataStore() }
    open class func nonPersistent() -> WKWebsiteDataStore { WKWebsiteDataStore() }
    open class func allWebsiteDataTypes() -> Set<String> { [] }
    open func dataRecords(ofTypes: Set<String>) async -> [WKWebsiteDataRecord] { [] }
    open func removeData(ofTypes: Set<String>, for: [WKWebsiteDataRecord]) async {}
    open func removeData(ofTypes: Set<String>, modifiedSince: Date) async {}
}
open class WKWebViewConfiguration: NSObject {
    open var websiteDataStore: WKWebsiteDataStore = .default()
    open var userContentController = WKUserContentController()
    open var defaultWebpagePreferences = WKWebpagePreferences()
}
open class WKWebpagePreferences: NSObject {
    public enum ContentMode: Int { case recommended, mobile, desktop }
    open var preferredContentMode: ContentMode = .recommended
}
open class WKNavigation: NSObject {}
open class WKFrameInfo: NSObject {}
open class WKContentWorld: NSObject { open class var page: WKContentWorld { WKContentWorld() }; open class var defaultClient: WKContentWorld { WKContentWorld() } }
@MainActor public protocol WKNavigationDelegate: NSObjectProtocol {}
extension WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {}
}
open class WKWebView: UIView {
    public init(frame: CGRect, configuration: WKWebViewConfiguration) { super.init(frame: frame) }
    open var customUserAgent: String?
    open weak var navigationDelegate: WKNavigationDelegate?
    open var url: URL? { nil }
    open var isLoading: Bool { false }
    @discardableResult open func load(_ r: URLRequest) -> WKNavigation? { nil }
    @discardableResult open func reload() -> WKNavigation? { nil }
    open func stopLoading() {}
    @discardableResult open func loadFileURL(_ url: URL, allowingReadAccessTo: URL) -> WKNavigation? { nil }
    open func callAsyncJavaScript(_ functionBody: String, arguments: [String: Any] = [:], in frame: WKFrameInfo? = nil, contentWorld: WKContentWorld) async throws -> Any? { nil }
    open func evaluateJavaScript(_ s: String) async throws -> Any { 0 }
}
