import Foundation
import UIKit
import WebKit

/// The Mac's PDF reader, running inside the app.
/// The Mac reads supplier bills with pdf-parse (Mozilla pdf.js 1.10.100) and joins each page's text with its pdfExtract.js.
/// BillBox/Resources/PDFReader holds that same pdf.js build and the Mac's code (reader.js, generated from pdfExtract.js);
/// a small hidden web view runs them, so a PDF gives the iPhone exactly the text it gives the Mac.
@MainActor
final class PDFReaderWeb: NSObject, WKNavigationDelegate {
    static let shared = PDFReaderWeb()

    struct Failure: LocalizedError { let message: String; var errorDescription: String? { message } }

    private var web: WKWebView?
    private var loaded = false
    private var waiting: [CheckedContinuation<Void, Error>] = []

    /// One string per page, as the Mac's pagerender returns them (pages pdf.js cannot read are left out, as on the Mac).
    func pages(_ pdf: Data) async throws -> [String] {
        let w = try await ready()
        let r = try await w.callAsyncJavaScript("return await window.readPdf(b64);", arguments: ["b64": pdf.base64EncodedString()],
                                                in: nil, contentWorld: .page)
        guard let list = r as? [Any] else { throw Failure(message: "The PDF reader gave no pages.") }
        return list.map { ($0 as? String) ?? "" }
    }

    /// Loads reader.html once; later calls reuse the page.
    private func ready() async throws -> WKWebView {
        if let web, loaded { return web }
        if web == nil {
            guard let html = Bundle.main.url(forResource: "reader", withExtension: "html", subdirectory: "PDFReader") else {
                throw Failure(message: "The PDF reader is missing from the app.")
            }
            let cfg = WKWebViewConfiguration()
            cfg.websiteDataStore = .nonPersistent()
            let w = WKWebView(frame: CGRect(x: 0, y: 0, width: 8, height: 8), configuration: cfg)
            w.navigationDelegate = self
            w.isUserInteractionEnabled = false
            w.alpha = 0.01
            web = w
            attach(w)
            w.loadFileURL(html, allowingReadAccessTo: html.deletingLastPathComponent())
        }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in waiting.append(c) }
        guard let web else { throw Failure(message: "The PDF reader could not start.") }
        return web
    }

    /// Kept inside the app's window (tiny and invisible), so iOS keeps its scripts running.
    private func attach(_ w: WKWebView) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let window = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) ?? scenes.first?.windows.first else { return }
        window.insertSubview(w, at: 0)
    }

    private func finish(_ error: Error?) {
        let all = waiting
        waiting = []
        if let error {
            loaded = false
            web?.removeFromSuperview()
            web = nil
            all.forEach { $0.resume(throwing: error) }
        } else {
            loaded = true
            all.forEach { $0.resume() }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in self.finish(nil) }
    }
    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.finish(error) }
    }
    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.finish(error) }
    }
    /// iOS may end the page's process to free memory; it is loaded again for the next PDF.
    nonisolated func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Task { @MainActor in
            self.loaded = false
            self.web?.removeFromSuperview()
            self.web = nil
        }
    }
}
