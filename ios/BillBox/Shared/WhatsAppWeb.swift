import SwiftUI
import UIKit
import WebKit

/// Sends bills through WhatsApp Web inside the app (decision D1: the Mac's method, foreground only).
/// WhatsApp Web is linked once by scanning its QR code (Settings > WhatsApp > Connect). For each bill the page opens the chat with
/// the customer's number, attaches the PDF and presses Send by itself. iOS lets this run only while BillBox is open on screen;
/// the page sits in a nearly invisible view behind the app. The Mac's last-resort fallbacks (a real mouse click, a real Return key
/// and a real Cmd+V paste) do not exist on iOS, so the page's own buttons are used.
@MainActor
final class WhatsAppWeb: NSObject, ObservableObject, WKNavigationDelegate {
    static let shared = WhatsAppWeb()

    @Published var connected = false
    @Published var status = "Not connected yet"
    @Published var lastResult = ""
    /// True while the page is shown in the Connect sheet (QR code / watching a send).
    @Published var showing = false

    private(set) var web: WKWebView?
    private var loadDone: CheckedContinuation<Void, Never>?
    private var chain: Task<Void, Never>?
    private var watcher: Task<Void, Never>?
    /// The customer whose chat is open right now and the chat's heading at that moment. The next bill to the same number
    /// reuses the open chat instead of loading WhatsApp Web again (the heading changes if someone opens another chat by hand).
    private var openChat: (phone: String, heading: String)?
    /// The way of attaching the PDF that worked last time is tried first (each way that does not work costs seconds).
    private var attachOrder: [String] {
        let all = ["paste", "drop", "input"]
        guard let first = UserDefaults.standard.string(forKey: "wa_attach_first"), all.contains(first) else { return all }
        return [first] + all.filter { $0 != first }
    }

    // MARK: web view

    /// A current desktop Safari: WhatsApp Web refuses to link browsers it thinks are out of date, and serves its desktop page
    /// (with the QR code and "Log in with phone number") only to a desktop browser.
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Safari/605.1.15"

    func ensure() -> WKWebView {
        if let web { return web }
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()          // keeps the WhatsApp login between launches
        let awake = WKUserScript(source: Self.stayAwake, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        cfg.userContentController.addUserScript(awake)
        // WhatsApp Web sends phones to a "download the app" page (no QR code, no phone-number login): ask for the desktop
        // site and look like a Mac to its checks (platform, touch points), not only by the browser name
        cfg.defaultWebpagePreferences.preferredContentMode = .desktop
        cfg.userContentController.addUserScript(WKUserScript(source: Self.desktop, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let w = WKWebView(frame: CGRect(x: 0, y: 0, width: 1000, height: 720), configuration: cfg)
        // WhatsApp Web serves its desktop page only to a desktop browser
        w.customUserAgent = Self.userAgent
        w.navigationDelegate = self
        web = w
        park()
        return w
    }

    /// Keeps the page inside the app's window but almost invisible and untouchable, so it keeps running while BillBox is open.
    func park() {
        guard let w = web, !showing else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let window = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) ?? scenes.first?.windows.first else { return }
        w.removeFromSuperview()
        w.transform = .identity
        w.frame = CGRect(x: 0, y: 0, width: 1000, height: 720)
        w.alpha = 0.01
        w.isUserInteractionEnabled = false
        window.insertSubview(w, at: 0)
    }

    /// Moves the page into the Connect sheet.
    func unpark() -> WKWebView {
        let w = ensure()
        w.removeFromSuperview()
        w.alpha = 1
        w.isUserInteractionEnabled = true
        return w
    }

    // MARK: page loading

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { Task { @MainActor in self.finishLoad() } }
    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { Task { @MainActor in self.finishLoad() } }
    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { Task { @MainActor in self.finishLoad() } }

    private func finishLoad() { loadDone?.resume(); loadDone = nil }

    private func load(_ url: String) async {
        let w = ensure()
        openChat = nil
        guard let u = URL(string: url) else { return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            loadDone = c
            w.load(URLRequest(url: u))
            Task { await pause(ms: 30_000); if let d = loadDone { loadDone = nil; d.resume() } }   // never wait forever
        }
    }

    private func run(_ body: String, _ args: [String: Any] = [:]) async -> String {
        guard let w = web else { return "" }
        do {
            let r = try await w.callAsyncJavaScript(body, arguments: args, in: nil, contentWorld: .page)
            return (r as? String) ?? "\(r ?? "")"
        } catch { return "js-error: \(error.localizedDescription)" }
    }

    /// The open chat's heading (the customer's name or number).
    private func chatHeading() async -> String {
        await run("const h = document.querySelector('#main header span[dir=\"auto\"]') || document.querySelector('#main header'); return h ? (h.innerText || '').split('\\n')[0].trim() : '';")
    }

    /// loading | qr | code (a phone-number link code is shown) | chats | composer | invalid
    private func pageState() async -> String {
        await run("""
        const q = (s) => document.querySelector(s);
        if (q('footer div[contenteditable="true"]')) return 'composer';
        const d = q('div[role="dialog"]');
        if (d && /invalid|isn.t on WhatsApp|not on WhatsApp/i.test(d.innerText || '')) return 'invalid';
        if (q('[data-link-code]')) return 'code';
        if (q('canvas[aria-label]') || q('div[data-ref]') || q('[data-testid="qrcode"]')) return 'qr';
        if (q('#pane-side') || q('[data-icon="chats"]')) return 'chats';
        return 'loading';
        """)
    }

    // MARK: connecting

    /// Opens WhatsApp Web in the Connect sheet so the QR code can be scanned. The sheet closes itself once the phone is linked.
    func connect() {
        _ = ensure()
        showing = true
        status = "Opening WhatsApp Web…"
        watcher?.cancel()
        watcher = Task {
            await load("https://web.whatsapp.com/")
            for _ in 0..<300 {
                let s = await pageState()
                if s == "chats" || s == "composer" {
                    connected = true
                    status = "Connected"
                    showing = false
                    return
                }
                status = s == "qr" ? "Scan the QR code with WhatsApp on your other phone (Linked devices > Link a device), or close this and use Link with phone number" : "Loading WhatsApp Web…"
                await pause(ms: 2000)
                if Task.isCancelled { return }
            }
            status = "Not connected. Try again."
        }
    }

    // MARK: linking with a phone number (no QR code)

    /// The 8-letter code WhatsApp gives for "Link with phone number instead", while one is waiting to be typed on the phone.
    @Published var linkCode = ""

    /// The number linked last time, for the next link.
    static var linkNumber: String {
        get { UserDefaults.standard.string(forKey: "wa_link_number") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "wa_link_number") }
    }

    /// Asks WhatsApp Web for a link code for this WhatsApp number, instead of a QR code: the way to link when WhatsApp is on
    /// this same phone (a QR code on its own screen can't be scanned). The code is typed in WhatsApp on the phone:
    /// Settings › Linked devices › Link a device › Link with phone number instead. WhatsApp also shows a notification for it.
    func linkWithPhone(_ raw: String, countryCode: String) async {
        var digits = raw.filter(\.isNumber)
        if digits.hasPrefix("0") { digits.removeFirst() }
        if digits.count == 10 { digits = countryCode.filter(\.isNumber) + digits }
        guard digits.count >= 11 else { status = "Type your WhatsApp number (10 digits, or with the country code)."; return }
        Self.linkNumber = raw
        linkCode = ""
        status = "Asking WhatsApp for a link code…"
        watcher?.cancel()
        _ = ensure()
        // linking runs with the page on screen: WhatsApp can refuse a page that is hidden while it links
        showing = true
        let state = await pageState()
        if state == "chats" || state == "composer" { connected = true; status = "Already connected"; return }
        if state != "qr" && state != "code" { await load("https://web.whatsapp.com/") }
        // wait for the login page
        for _ in 0..<60 {
            let s = await pageState()
            if s == "qr" || s == "code" { break }
            if s == "chats" || s == "composer" { connected = true; status = "Already connected"; return }
            await pause(ms: 500)
        }
        let r = await run(Self.linkScript, ["number": "+" + digits])
        if r.hasPrefix("code:") {
            let c = String(r.dropFirst(5)).uppercased().filter { $0.isLetter || $0.isNumber }
            linkCode = c.count == 8 ? String(c.prefix(4)) + "-" + String(c.suffix(4)) : c
            status = "Code \(linkCode) — on your phone: WhatsApp › Settings › Linked devices › Link a device › Link with phone number instead, and type it"
            watchLink()
        } else {
            status = r.hasPrefix("page:") ? "WhatsApp did not offer the phone-number login. The page shows: \(r.dropFirst(5).trimmingCharacters(in: .whitespaces)). Use Show page to see it." : "WhatsApp did not give a code (\(r)). Use Show page and tap “Log in with phone number” there."
        }
    }

    /// Waits for the phone to accept the link, then hides the page.
    private func watchLink() {
        watcher?.cancel()
        watcher = Task {
            for _ in 0..<180 {
                await pause(ms: 2000)
                if Task.isCancelled { return }
                let s = await pageState()
                if s == "chats" || s == "composer" {
                    connected = true; linkCode = ""; status = "Connected"
                    showing = false
                    return
                }
            }
            if !connected { status = "The code was not used in time. Ask for a new one." }
        }
    }

    /// Clicks "Log in with phone number", types the number, presses Next and reads the code WhatsApp shows.
    private static let linkScript = #"""
    const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
    const words = (e) => ((e.textContent || '') + ' ' + (e.getAttribute && (e.getAttribute('aria-label') || '') || '')).replace(/\s+/g, ' ').trim();
    // the smallest element whose own text asks for the phone-number login (WhatsApp words it a few ways)
    const find = (re) => {
      const all = [...document.querySelectorAll('button, a, [role="button"], [role="link"], span, div')]
        .filter((e) => re.test(words(e)) && words(e).length < 80);
      return all.length ? all[all.length - 1] : null;
    };
    const press = (el) => { const b = el.closest('button, a, [role="button"], [role="link"]') || el; b.click(); };
    const code = () => {
      const c = document.querySelector('[data-link-code]');
      if (c) return (c.getAttribute('data-link-code') || '').replace(/[^A-Za-z0-9]/g, '');
      return '';
    };
    if (code()) return 'code:' + code();
    let link = null;
    for (let i = 0; i < 30 && !link; i++) { link = find(/(log ?in|link|sign ?in)( with| using)? (your )?phone( number)?|phone number instead/i); if (!link) await sleep(500); }
    if (!link) return 'page: ' + (document.title || '') + ' | ' + (document.body ? words(document.body).slice(0, 220) : 'empty');
    press(link);
    let input = null;
    for (let i = 0; i < 20 && !input; i++) {
      await sleep(500);
      input = document.querySelector('input[aria-label*="phone" i], input[type="tel"], form input[type="text"], div[role="dialog"] input, input[type="text"]');
    }
    if (!input) return 'no number box';
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
    input.focus();
    setter.call(input, ''); input.dispatchEvent(new Event('input', { bubbles: true }));
    setter.call(input, number); input.dispatchEvent(new Event('input', { bubbles: true }));
    input.dispatchEvent(new Event('change', { bubbles: true }));
    await sleep(700);
    const next = find(/^next$/i);
    if (!next) return 'no Next button';
    press(next);
    for (let i = 0; i < 40; i++) { await sleep(500); if (code()) return 'code:' + code(); }
    const m = (document.body.textContent || '').match(/\b([A-Z0-9]{4})[- ]?([A-Z0-9]{4})\b/);
    return m ? 'code:' + m[1] + m[2] : 'no code shown';
    """#

    func disconnect() async {
        _ = ensure()
        await load("https://web.whatsapp.com/")
        _ = await run("localStorage.clear(); sessionStorage.clear(); return 'ok'")
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: types)
        await store.removeData(ofTypes: types, for: records)
        connected = false
        status = "Not connected yet"
    }

    /// Shows the live page (for watching a send or checking the link).
    func reveal() { _ = ensure(); showing = true }

    // MARK: sending

    struct SendError: LocalizedError { let message: String; var errorDescription: String? { message } }

    /// Queues one bill. Bills are sent one after another, never at the same time.
    func send(pdf: @escaping @MainActor () -> Data?, fileName: String, phone: String, caption: String) async throws {
        let prev = chain
        let job = Task { @MainActor () -> Error? in
            await prev?.value
            do { try await self.sendNow(makePdf: pdf, fileName: fileName, phone: phone, caption: caption); return nil } catch { return error }
        }
        chain = Task { _ = await job.value; _ = await self.run(Self.js(Self.settleScript)) }
        if let e = await job.value { throw e }
    }

    /// Loads WhatsApp Web ahead of the first bill (on the billing screen), so the first send does not pay for starting it up.
    func warmUp() {
        guard web == nil else { return }
        let prev = chain
        chain = Task {
            await prev?.value
            _ = self.ensure()
            await self.load("https://web.whatsapp.com/")
            for _ in 0..<60 {
                let st = await self.pageState()
                if st == "chats" || st == "composer" { self.connected = true; self.status = "Connected"; return }
                if st == "qr" { return }
                await pause(ms: 500)
            }
        }
    }

    private func sendNow(makePdf: @escaping @MainActor () -> Data?, fileName: String, phone: String, caption: String) async throws {
        _ = ensure()
        status = "Sending…"
        // the bill is drawn while WhatsApp Web opens the chat, instead of before
        let pdfJob = Task { @MainActor in makePdf() }
        let reuse: Bool
        if let o = openChat, o.phone == phone, await pageState() == "composer", await chatHeading() == o.heading { reuse = true } else { reuse = false }
        if !reuse { await load("https://web.whatsapp.com/send?phone=\(phone)") }

        var state = "loading"
        var shownLogin = false
        for i in 0..<600 {
            state = await pageState()
            if state == "composer" { break }
            if state == "invalid" { status = connected ? "Connected" : status; throw SendError(message: "\(phone) is not on WhatsApp.") }
            if state == "qr" && !shownLogin {
                shownLogin = true
                connected = false
                status = "Scan the QR code to link WhatsApp"
                showing = true
            }
            if i >= 130 && state == "loading" { break }
            await pause(ms: 300)
        }
        guard state == "composer" else {
            status = "Not connected"
            throw SendError(message: state == "qr" ? "WhatsApp is not linked. Scan the QR code in Settings > WhatsApp." : "WhatsApp Web did not open the chat in time.")
        }
        if shownLogin { showing = false }
        connected = true
        if !reuse { await pause(ms: 200) }

        guard await ensureComposer(phone: phone) else {
            status = "Connected"
            throw SendError(message: "The WhatsApp chat did not stay open (the page went back to its loading screen). Try again in a moment.")
        }
        guard let pdf = await pdfJob.value else { throw SendError(message: "Could not prepare the bill for WhatsApp.") }
        openChat = (phone, await chatHeading())
        let args: [String: Any] = ["b64": pdf.base64EncodedString(), "name": fileName + ".pdf"]
        let prepared = await run(Self.js(Self.prepareScript), args)
        guard prepared == "ready" else { lastResult = prepared; throw SendError(message: "WhatsApp Web did not accept the bill (\(prepared)).") }

        var tried: [String] = []
        var opened = false
        if await run(Self.js("return previewOpen() ? 'y' : 'n';")) == "y" { await closePreviewIfAny() }
        for (k, method) in attachOrder.enumerated() {
            if k > 0 {
                _ = await ensureComposer(phone: phone)
                _ = await run(Self.js(Self.prepareScript), args)   // again, in case the page reloaded and forgot the file
            }
            _ = await run(Self.js(Self.attachScript), ["method": method])
            let ok = await previewOpen(seconds: method == "input" ? 8 : 5)
            tried.append("\(method):\(ok ? "yes" : "no")")
            if ok { opened = true; UserDefaults.standard.set(method, forKey: "wa_attach_first"); break }
            await closePreviewIfAny()
        }
        guard opened else {
            let diag = await run(Self.js(Self.diagnose))
            lastResult = "no-preview [\(tried.joined(separator: ", "))] \(diag)"
            status = "Connected"
            throw SendError(message: "WhatsApp Web could not attach the bill. Tried \(tried.joined(separator: ", ")). Page: \(diag)")
        }

        var result = await run(Self.js(Self.finishScript), ["caption": caption])
        let sentNote = result.hasPrefix("clicked") ? String(result.dropFirst("clicked".count)) : ""
        if result.hasPrefix("clicked") { result = "clicked" }
        result = await run(Self.js(Self.confirmScript), ["name": fileName + ".pdf"])
        lastResult = "\(result) [\(tried.joined(separator: ", "))] \(sentNote)"
        status = "Connected"
        if result == "sent", !caption.isEmpty, sentNote.contains("no-caption") {
            _ = await run(Self.js(Self.sendTextScript), ["caption": caption])
            lastResult += " text-sent-separately"
        }
        guard result == "sent" else {
            openChat = nil
            let diag = await run(Self.js(Self.diagnose))
            lastResult += " " + diag
            throw SendError(message: "WhatsApp Web attached the bill but could not confirm it was sent (\(result)). Check the chat before sending again.")
        }
    }

    private func ensureComposer(phone: String) async -> Bool {
        var reloaded = false
        for i in 0..<360 {
            let st = await pageState()
            if st == "composer" { return true }
            if st == "invalid" { return false }
            if i == 120 && !reloaded {
                reloaded = true
                await load("https://web.whatsapp.com/send?phone=\(phone)")
            }
            await pause(ms: 250)
        }
        return false
    }

    private func previewOpen(seconds: Int) async -> Bool {
        for _ in 0..<(seconds * 4) {
            if await run(Self.js("return previewOpen() ? 'y' : 'n';")) == "y" { return true }
            await pause(ms: 250)
        }
        return false
    }

    private func closePreviewIfAny() async {
        _ = await run(Self.js("""
        const x = document.querySelector('[data-icon="x"], [data-icon="x-viewer"], [data-icon="close"], [aria-label="Close" i]');
        if (x) x.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
        document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', code: 'Escape', keyCode: 27, bubbles: true }));
        return 'ok';
        """))
        await pause(ms: 400)
    }

    // MARK: scripts that run inside the WhatsApp Web page

    private static func js(_ body: String) -> String { prelude + "\n" + body }

    private static let prepareScript = #"""
    const bin = atob(b64); const arr = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i);
    window.__bbFile = new File([arr], name, { type: 'application/pdf' });
    window.__bbBase = { ed: new Set(editables()), sd: new Set(rawSend()) };
    return 'ready';
    """#

    /// Keeps the page from noticing that its window is parked.
    /// A Mac to WhatsApp Web's device checks.
    private static let desktop = #"""
    try {
      const def = (o, k, v) => { try { Object.defineProperty(o, k, { get: () => v, configurable: true }); } catch (e) {} };
      def(Navigator.prototype, 'platform', 'MacIntel');
      def(Navigator.prototype, 'maxTouchPoints', 0);
      def(Navigator.prototype, 'vendor', 'Apple Computer, Inc.');
      try { delete window.ontouchstart; } catch (e) {}
      def(window, 'ontouchstart', undefined);
    } catch (e) {}
    """#

    private static let stayAwake = #"""
    try {
      Object.defineProperty(document, 'hidden', { get: () => false });
      Object.defineProperty(document, 'visibilityState', { get: () => 'visible' });
      document.hasFocus = () => true;
      window.addEventListener('visibilitychange', (e) => e.stopImmediatePropagation(), true);
      document.addEventListener('visibilitychange', (e) => e.stopImmediatePropagation(), true);
    } catch (e) {}
    """#

    /// Helpers every script starts with. WhatsApp changes its markup now and then, so each lookup tries several selectors.
    private static let prelude = #"""
    const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
    const wait = async (fn, ms) => { const t = Date.now(); while (Date.now() - t < ms) { const v = fn(); if (v) return v; await sleep(250); } return null; };
    const vis = (e) => { const r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0; };
    const press = (e) => { for (const t of ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click']) e.dispatchEvent(new MouseEvent(t, { bubbles: true, cancelable: true, view: window })); };
    const composerEl = () => document.querySelector('footer div[contenteditable="true"]');
    // What was already on the page before the bill was attached (the search box, the chat box, any always-present "Send" label).
    // Only elements that appear AFTER attaching count as the preview, so the left-hand search box is never mistaken for the caption box.
    const base = window.__bbBase || { ed: new Set(), sd: new Set() };
    const editables = () => [...document.querySelectorAll('[contenteditable="true"], [contenteditable=""], div[role="textbox"]')];
    const rawSend = () => {
      const found = [...document.querySelectorAll('[aria-label^="Send" i], [data-icon*="send" i], [data-testid*="send" i]')].filter(vis)
        .map((x) => x.closest('button, [role="button"]') || x);
      const rank = (x) => (/selected/i.test(x.getAttribute('aria-label') || '') ? 0 : (x.closest('footer') ? 2 : 1));
      return [...new Set(found)].sort((a, b) => rank(a) - rank(b));
    };
    const sendCands = () => rawSend().filter((x) => !base.sd.has(x));
    const sendEl = () => sendCands()[0] || null;
    const captionEl = () => editables().filter((e) => !base.ed.has(e) && vis(e)).pop() || null;
    const previewOpen = () => sendEl() || captionEl();
    const outCount = () => document.querySelectorAll('[data-icon^="msg-"], .message-out, [data-id^="true_"]').length;
    """#

    private static let attachScript = #"""
    const file = window.__bbFile;
    if (!file) return 'no-file';
    const composer = composerEl();
    if (!composer) return 'no-composer';
    const dt = new DataTransfer(); dt.items.add(file);
    try {
      if (method === 'paste') {
        composer.focus();
        composer.dispatchEvent(new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true }));
      } else if (method === 'drop') {
        const target = document.querySelector('#main') || composer;
        for (const t of ['dragenter', 'dragover', 'drop']) target.dispatchEvent(new DragEvent(t, { dataTransfer: dt, bubbles: true, cancelable: true }));
      } else if (method === 'input') {
        const plus = document.querySelector('footer [data-icon="plus"], footer [data-icon="plus-rounded"], footer [data-icon="clip"], footer [data-icon="attach-menu-plus"], footer [aria-label*="Attach" i]');
        if (plus) { press(plus.closest('button, [role="button"]') || plus); await sleep(800); }
        const inputs = [...document.querySelectorAll('input[type="file"]')];
        const input = inputs.find((i) => !i.accept || i.accept === '*' || !/image|video/i.test(i.accept)) || inputs[0];
        if (!input) return 'no-input';
        input.files = dt.files;
        input.dispatchEvent(new Event('input', { bubbles: true }));
        input.dispatchEvent(new Event('change', { bubbles: true }));
      }
    } catch (e) { return 'error:' + e; }
    return 'tried';
    """#

    /// Types the caption and presses Send. Success means a new outgoing message appeared (or the preview closed), not just that a click happened.
    private static let finishScript = #"""
    const cap = captionEl();
    let note = '';
    if (caption && cap) {
      cap.focus();
      document.execCommand('insertText', false, caption);
      await sleep(300);
      if (!(cap.innerText || cap.textContent || '').includes(caption.slice(0, 8))) {
        const dt = new DataTransfer(); dt.setData('text/plain', caption);
        cap.dispatchEvent(new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true }));
        await sleep(300);
      }
      note = (cap.innerText || cap.textContent || '').includes(caption.slice(0, 8)) ? '' : ':no-caption';
    } else if (caption) note = ':no-caption-box';
    const before = window.__bbOut = outCount();
    const changed = () => outCount() > before || !previewOpen();
    const cands = sendCands();
    if (!cands.length && !cap) return 'no-send-button';
    for (const b of cands) {
      press(b);
      if (await wait(changed, 3000)) break;
      b.click();
      if (await wait(changed, 2000)) break;
    }
    if (!changed() && cap) {
      cap.focus();
      for (const t of ['keydown', 'keypress', 'keyup']) cap.dispatchEvent(new KeyboardEvent(t, { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true }));
      await wait(changed, 3000);
    }
    return changed() ? 'clicked' + note : 'preview-stayed';
    """#

    /// After the send click (or a real Return key): wait for the upload to leave, then check the bill is in the chat.
    private static let confirmScript = #"""
    const before = window.__bbOut || 0;
    const ok = await wait(() => outCount() > before || !previewOpen(), 10000);
    return ok ? 'sent' : 'preview-stayed';
    """#

    /// Fallback: types the message text into the normal chat box and sends it.
    private static let sendTextScript = #"""
    const c = composerEl();
    if (!c) return 'no-composer';
    c.focus();
    document.execCommand('insertText', false, caption);
    await sleep(400);
    const b = [...document.querySelectorAll('footer [data-icon*="send" i], footer [aria-label^="Send" i]')].map((x) => x.closest('button, [role="button"]') || x)[0];
    if (b) press(b);
    else for (const t of ['keydown', 'keypress', 'keyup']) c.dispatchEvent(new KeyboardEvent(t, { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true }));
    await wait(() => !(c.innerText || '').trim(), 5000);
    return 'text-sent';
    """#

    /// Runs after the caller has been told "sent": waits (up to 45 s) for the upload to finish before the next bill uses the page.
    private static let settleScript = #"""
    await wait(() => !document.querySelector('[data-icon="msg-time"]'), 45000);
    return 'settled';
    """#

    /// Where on the page each possible Send button is (centre, in page points), best candidate first.
    private static let sendRects = #"""
    return sendCands().map((b) => { const r = b.getBoundingClientRect(); return Math.round(r.left + r.width / 2) + ',' + Math.round(r.top + r.height / 2); }).join(';');
    """#

    private static let diagnose = #"""
    const icons = [...new Set([...document.querySelectorAll('[data-icon]')].map((e) => e.getAttribute('data-icon')))].slice(0, 40).join(',');
    const sends = sendCands().map((b) => (b.getAttribute('aria-label') || b.tagName) + (b.disabled || b.getAttribute('aria-disabled') === 'true' ? '(disabled)' : '')).join('|');
    return 'icons=' + icons + ' send=' + sends + ' caption=' + (captionEl() ? 'yes' : 'no') + ' out=' + outCount() + ' inputs=' + document.querySelectorAll('input[type=file]').length + ' size=' + innerWidth + 'x' + innerHeight;
    """#
}

/// The live WhatsApp Web page in a sheet (Connect / Show page).
@MainActor struct WhatsAppPageSheet: View {
    @ObservedObject var web = WhatsAppWeb.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text(web.status).font(.callout).padding(8).frame(maxWidth: .infinity, alignment: .leading)
                WebHost()
            }
            .navigationTitle("WhatsApp Web")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { web.showing = false } } }
        }
    }

    /// Holds the page at a desktop size (1000 points wide) and shrinks it to the sheet: on a phone-width page WhatsApp Web
    /// rearranges itself and hides the QR code and "Log in with phone number".
    final class FitBox: UIView {
        weak var page: WKWebView?
        override func layoutSubviews() {
            super.layoutSubviews()
            guard let w = page, bounds.width > 0 else { return }
            let k = min(1, bounds.width / 1000)
            w.transform = .identity
            w.frame = CGRect(x: 0, y: 0, width: 1000, height: max(600, bounds.height / k))
            w.transform = CGAffineTransform(scaleX: k, y: k)
            w.frame.origin = .zero
        }
    }

    private struct WebHost: UIViewRepresentable {
        func makeUIView(context: Context) -> UIView {
            let box = FitBox()
            box.clipsToBounds = true
            let w = WhatsAppWeb.shared.unpark()
            w.autoresizingMask = []
            box.page = w
            box.addSubview(w)
            return box
        }
        func updateUIView(_ v: UIView, context: Context) {}
        static func dismantleUIView(_ v: UIView, coordinator: ()) {
            Task { @MainActor in WhatsAppWeb.shared.park() }
        }
    }
}
