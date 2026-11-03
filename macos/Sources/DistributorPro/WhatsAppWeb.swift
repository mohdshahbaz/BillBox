import SwiftUI
import AppKit
import WebKit

/// Sends bills through WhatsApp Web, inside the app, in the background.
/// A WhatsApp Web page lives in a web view that is signed in once (scan the QR code with the phone: Settings > WhatsApp > Connect).
/// For each bill the page opens the chat with the customer's number, attaches the PDF and presses Send by itself.
/// The page is kept in a window parked far outside every screen, so it can never show through BillBox and never takes focus.
@MainActor
final class WhatsAppWeb: NSObject, ObservableObject, WKNavigationDelegate, NSWindowDelegate {
    static let shared = WhatsAppWeb()

    @Published var connected = false
    @Published var status = "Not connected yet"
    @Published var lastResult = ""

    private var web: WKWebView?
    private var panel: NSPanel?          // the parked, invisible window the page normally lives in
    private var loginPanel: NSPanel?     // an ordinary window used only while the QR code is scanned
    private var loadDone: CheckedContinuation<Void, Never>?
    private var chain: Task<Void, Never>?
    private var watcher: Task<Void, Never>?
    /// The customer whose chat is open right now and the chat's heading at that moment. The next bill to the same number
    /// reuses the open chat instead of loading WhatsApp Web again (the heading changes if someone opens another chat by hand).
    private var openChat: (phone: String, heading: String)?
    /// Once the chat is open, attaching and sending must finish by this time, so one stuck step can never hold up every bill after it.
    private var abortAt = Date.distantFuture
    private var overtime: Bool { Date() > abortAt }
    /// The way of attaching the PDF that worked last time is tried first (each way that does not work costs seconds).
    private var attachOrder: [String] {
        let all = ["paste", "drop", "input"]
        guard let first = UserDefaults.standard.string(forKey: "wa_attach_first"), all.contains(first) else { return all }
        return [first] + all.filter { $0 != first }
    }

    // MARK: window

    /// A current desktop Safari: WhatsApp Web refuses to link browsers it thinks are out of date, and serves its desktop page
    /// (with the QR code and "Log in with phone number") only to a desktop browser.
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Safari/605.1.15"

    private func ensure() -> WKWebView {
        if let web { return web }
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()          // keeps the WhatsApp login between launches
        // WhatsApp Web should believe its tab is in front, so it never slows down or pauses while the window is parked.
        let awake = WKUserScript(source: Self.stayAwake, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        cfg.userContentController.addUserScript(awake)
        let w = WKWebView(frame: NSRect(x: 0, y: 0, width: 1000, height: 720), configuration: cfg)
        w.customUserAgent = Self.userAgent
        w.navigationDelegate = self
        w.autoresizingMask = [.width, .height]
        let p = ParkedPanel(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 720),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.contentView = w
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.isExcludedFromWindowsMenu = true
        p.isOpaque = false
        p.backgroundColor = .clear
        web = w
        panel = p
        hidePanel()
        return w
    }

    /// The window that holds the page while it works in the background.
    private final class ParkedPanel: NSPanel {
        override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
        override var canBecomeKey: Bool { true }
    }

    /// Parks the page: a borderless, 99% transparent window whose body hangs off the left edge of the screen, with only a thin
    /// sliver on screen. Nothing can be seen and it takes no clicks or focus, but because part of it is on screen (and above
    /// other windows) macOS and WebKit treat the page as showing, so WhatsApp Web runs at full speed and its Send button works.
    private func hidePanel() {
        guard let p = panel, let w = web else { return }
        loginPanel?.orderOut(nil)
        if p.contentView !== w { p.contentView = w }
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        p.alphaValue = 0.01
        p.ignoresMouseEvents = true
        p.hasShadow = false
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        p.setFrame(NSRect(x: screen.minX - 980, y: screen.minY, width: 1000, height: 720), display: false)
        p.orderFrontRegardless()
    }

    private func showPanelForLogin() {
        guard let w = web else { return }
        if loginPanel == nil {
            let l = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 720),
                            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            l.title = "Connect WhatsApp"
            l.isReleasedWhenClosed = false
            l.delegate = self
            l.hidesOnDeactivate = false
            l.isExcludedFromWindowsMenu = true
            loginPanel = l
        }
        guard let l = loginPanel else { return }
        panel?.orderOut(nil)
        l.contentView = w
        l.center()
        l.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { hidePanel(); return false }

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

    /// Opens WhatsApp Web in a normal window so the QR code can be scanned. It hides itself once the phone is linked.
    func connect() {
        _ = ensure()
        showPanelForLogin()
        status = "Opening WhatsApp Web…"
        watcher?.cancel()
        watcher = Task {
            await load("https://web.whatsapp.com/")
            for _ in 0..<300 {
                let s = await pageState()
                if s == "chats" || s == "composer" {
                    connected = true
                    status = "Connected"
                    hidePanel()
                    return
                }
                status = s == "qr" ? "Scan the QR code with WhatsApp on your phone (Linked devices > Link a device)" : "Loading WhatsApp Web…"
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
            status = "Type the code on your phone: WhatsApp › Settings › Linked devices › Link a device › Link with phone number instead"
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
                    hidePanel()
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
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            store.fetchDataRecords(ofTypes: types) { records in
                store.removeData(ofTypes: types, for: records) { c.resume() }
            }
        }
        connected = false
        status = "Not connected yet"
    }

    // MARK: sending

    struct SendError: LocalizedError { let message: String; var errorDescription: String? { message } }

    /// Times every step of one send (open chat, stage bill, attach, press Send), so the real cost of each tap and wait on this
    /// device can be read from "Last result" in Settings > WhatsApp instead of guessed. Example: open 1850ms · attach 140ms · send 210ms.
    struct StepTrace {
        private let start = Date()
        private var last = Date()
        private var steps: [(String, Int)] = []
        mutating func mark(_ name: String) {
            let now = Date()
            steps.append((name, Int(now.timeIntervalSince(last) * 1000)))
            last = now
        }
        var summary: String { steps.map { "\($0.0) \($0.1)ms" }.joined(separator: " · ") + " · total \(Int(Date().timeIntervalSince(start) * 1000))ms" }
    }

    /// The previous bill's upload, still finishing in the page. Only a page reload would cut it off, so only a reload waits for it.
    private var settling: Task<Void, Never>?

    /// Waits for the previous bill's upload to leave, but never longer than `maxSeconds` (a phone that is offline would hold every later bill for 45 s).
    private func waitSettled(maxSeconds: Int) async {
        guard let s = settling else { return }
        await withTaskGroup(of: Void.self) { g in
            g.addTask { await s.value }
            g.addTask { await pause(ms: maxSeconds * 1000) }
            _ = await g.next()
            g.cancelAll()
        }
    }

    /// Queues one bill. Bills are sent one after another, never at the same time. Returns when WhatsApp has taken it (or failed).
    func send(pdf: @escaping @MainActor () -> Data?, fileName: String, phone: String, caption: String) async throws {
        let prev = chain
        let job = Task { @MainActor () -> Error? in
            await prev?.value
            do { try await self.sendNow(makePdf: pdf, fileName: fileName, phone: phone, caption: caption); return nil } catch { return error }
        }
        // the caller is told as soon as the bill is on its way; the next bill waits until this one has left the phone
        chain = Task { _ = await job.value }
        settling = Task { _ = await job.value; _ = await self.run(Self.js(Self.settleScript)) }
        let failure = await job.value
        if status == "Sending…" { status = connected ? "Connected" : "Not connected" }   // never stay stuck on "Sending…"
        if let e = failure { throw e }
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
        var trace = StepTrace()
        // the bill is drawn while WhatsApp Web opens the chat, instead of before
        let pdfJob = Task { @MainActor in makePdf() }
        let reuse: Bool
        // one call: is the chat box up, and whose chat is it (was two calls)
        let now = await run(Self.js(Self.chatNowScript))
        if let o = openChat, o.phone == phone, now == "composer|" + o.heading { reuse = true } else { reuse = false }
        trace.mark("check")
        if !reuse {
            // a reload would cut off the previous bill's upload: wait for it to leave first (only here, not for every bill)
            await waitSettled(maxSeconds: 15)
            trace.mark("settle")
            await load("https://web.whatsapp.com/send?phone=\(phone)")
            trace.mark("load")
        }

        // wait for the chat (up to ~3 minutes if the phone has to be linked first)
        var state = "loading"
        var shownLogin = false
        let waitStart = Date()
        while true {
            // the waiting happens inside the page (it looks every 60 ms and answers the moment the chat box is there),
            // instead of this app asking every 300 ms
            state = await run(Self.js(Self.waitComposerScript), ["ms": 2500])
            if state.hasPrefix("js-error") { state = "loading"; await pause(ms: 150) }   // the page was reloading under us
            if state == "composer" { break }
            if state == "invalid" { status = connected ? "Connected" : status; throw SendError(message: "\(phone) is not on WhatsApp.") }
            if state == "qr" && !shownLogin {
                shownLogin = true
                connected = false
                status = "Scan the QR code to link WhatsApp"
                showPanelForLogin()
            }
            let waited = Date().timeIntervalSince(waitStart)
            if state == "loading" && waited > 39 { break }
            if waited > 180 { break }
            if state == "qr" || state == "code" { await pause(ms: 300) }   // waiting for the person to link: do not spin
        }
        guard state == "composer" else {
            status = "Not connected"
            throw SendError(message: state == "qr" ? "WhatsApp is not linked. Scan the QR code in Settings > WhatsApp." : "WhatsApp Web did not open the chat in time.")
        }
        if shownLogin { hidePanel() }
        connected = true
        trace.mark("chat")
        if !reuse { await pause(ms: 100) }   // the chat box has just been mounted: a moment for its paste handler (was 200 ms)

        guard await ensureComposer(phone: phone) else {
            status = "Connected"
            throw SendError(message: "The WhatsApp chat did not stay open (the page went back to its loading screen). Try again in a moment.")
        }
        guard let pdf = await pdfJob.value else { throw SendError(message: "Could not prepare the bill for WhatsApp.") }
        openChat = (phone, await chatHeading())
        let args: [String: Any] = ["b64": pdf.base64EncodedString(), "name": fileName + ".pdf"]
        let prepared = await run(Self.js(Self.prepareScript), args)
        trace.mark("stage")
        guard prepared == "ready" else { lastResult = prepared; throw SendError(message: "WhatsApp Web did not accept the bill (\(prepared)).") }

        // Try each way of attaching the PDF until WhatsApp shows its preview with a Send button.
        abortAt = Date().addingTimeInterval(45)   // attaching and sending must be done by then: a stuck step can never hold up every bill after it
        var tried: [String] = []
        var opened = false
        if await run(Self.js("return previewOpen() ? 'y' : 'n';")) == "y" { await closePreviewIfAny() }   // start from a clean chat
        for (k, method) in attachOrder.enumerated() {
            if k > 0 {
                _ = await ensureComposer(phone: phone)
                _ = await run(Self.js(Self.prepareScript), args)   // again, in case the page reloaded and forgot the file
            }
            _ = await run(Self.js(Self.attachScript), ["method": method])
            let ok = await previewOpen(seconds: method == "input" ? 8 : 5)
            tried.append("\(method):\(ok ? "yes" : "no")")
            if ok { opened = true; UserDefaults.standard.set(method, forKey: "wa_attach_first"); trace.mark("attach-\(method)"); break }
            await closePreviewIfAny()
            if overtime { break }
        }
        if !opened {
            let ok = await nativePaste(pdf: pdf, fileName: fileName)
            tried.append("native:\(ok ? "yes" : "no")")
            opened = ok
        }
        guard opened else {
            let diag = await run(Self.js(Self.diagnose))
            lastResult = "no-preview [\(tried.joined(separator: ", "))] \(diag) \(await saveSnapshot())"
            status = "Connected"
            throw SendError(message: "WhatsApp Web could not attach the bill. Tried \(tried.joined(separator: ", ")). Page: \(diag)")
        }

        var result = await run(Self.js(Self.finishScript), ["caption": caption])
        let sentNote = result.hasPrefix("clicked") ? String(result.dropFirst("clicked".count)) : ""
        if result.hasPrefix("clicked") { result = "clicked" }
        if result == "preview-stayed",
           await run(Self.js("return (outCount() > (window.__bbOut || 0) || !previewOpen()) ? 'y' : 'n';")) == "n" {
            // the page ignored the scripted clicks: click the Send button with a genuine mouse click, then a real Return key
            tried.append("mouse-click")
            await nativeClick()
            if await previewOpen(seconds: 2) {
                tried.append("return-key")
                await pressReturn()
            }
        }
        // "clicked" already means a new outgoing message appeared or the preview closed, the very test the confirm step makes: no second wait
        if result == "clicked" { result = "sent" } else { result = await run(Self.js(Self.confirmScript), ["name": fileName + ".pdf"]) }
        trace.mark("send")
        lastResult = "\(result) [\(tried.joined(separator: ", "))] \(sentNote) ⏱ \(trace.summary)"
        status = "Connected"
        if result == "sent", !caption.isEmpty, sentNote.contains("no-caption") {
            // the preview had no usable caption box: send the message text as an ordinary chat message right after the bill
            _ = await run(Self.js(Self.sendTextScript), ["caption": caption])
            lastResult += " text-sent-separately"
        }
        guard result == "sent" else {
            openChat = nil
            let diag = await run(Self.js(Self.diagnose))
            lastResult += " " + diag + " " + (await saveSnapshot())
            // the bill is attached but the send click was not confirmed: open the WhatsApp page so the green Send icon can be clicked
            if await run(Self.js("return previewOpen() ? 'y' : 'n';")) == "y" {
                reveal()
                throw SendError(message: "The bill is attached in the chat. Click the green Send icon on the WhatsApp page that opened.")
            }
            throw SendError(message: "WhatsApp Web attached the bill but could not confirm it was sent (\(result)). Check the chat before sending again.")
        }
    }

    /// A genuine mouse click on the Send button, delivered to the web view the way a real pointer would be.
    private func nativeClick() async {
        guard let w = web, let p = w.window else { return }
        let spots = await run(Self.js(Self.sendRects))
        for spot in spots.split(separator: ";") {
            let xy = spot.split(separator: ",").compactMap { Double($0) }
            guard xy.count == 2 else { continue }
            let local = NSPoint(x: xy[0], y: w.isFlipped ? xy[1] : Double(w.bounds.height) - xy[1])
            let at = w.convert(local, to: nil)
            for kind in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                if let e = NSEvent.mouseEvent(with: kind, location: at, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: p.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: kind == .leftMouseDown ? 1 : 0) {
                    if kind == .leftMouseDown { w.mouseDown(with: e) } else { w.mouseUp(with: e) }
                }
            }
            await pause(ms: 800)
            if !(await previewOpen(seconds: 1)) { return }
        }
    }

    /// A genuine Return key press delivered to the web view (the same as pressing Return in the caption box).
    private func pressReturn() async {
        guard let w = web, let p = w.window else { return }
        _ = await run(Self.js("const c = captionEl() || composerEl(); if (c) c.focus(); return 'ok';"))
        p.makeFirstResponder(w)
        for down in [true, false] {
            if let e = NSEvent.keyEvent(with: down ? .keyDown : .keyUp, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: p.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
                                        isARepeat: false, keyCode: 36) {
                if down { w.keyDown(with: e) } else { w.keyUp(with: e) }
            }
        }
        await pause(ms: 500)
    }

    /// Saves a picture of what the page looks like to a file next to the app's data, so a failure can be looked at.
    private func saveSnapshot() async -> String {
        guard let w = web else { return "" }
        return await withCheckedContinuation { (c: CheckedContinuation<String, Never>) in
            w.takeSnapshot(with: nil) { image, _ in
                guard let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else { c.resume(returning: ""); return }
                let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DistributorPro", isDirectory: true)
                let url = dir.appendingPathComponent("whatsapp-last-failure.png")
                do { try png.write(to: url); c.resume(returning: "picture=\(url.path)") } catch { c.resume(returning: "") }
            }
        }
    }

    /// WhatsApp Web sometimes reloads itself (an update, or a dropped connection) and shows only its logo for a while.
    /// This waits for the chat box to be back, and reopens the chat link once if the page stays on the logo.
    private func ensureComposer(phone: String) async -> Bool {
        var reloaded = false
        for i in 0..<224 {
            let st = await pageState()
            if st == "composer" { return true }
            if st == "invalid" { return false }
            if i == 64 && !reloaded {
                reloaded = true
                await load("https://web.whatsapp.com/send?phone=\(phone)")
            }
            await pause(ms: 250)
        }
        return false
    }

    /// Shows the live WhatsApp page in an ordinary window (for watching a send or checking the link). Hide puts it back out of sight.
    func reveal() { _ = ensure(); showPanelForLogin() }
    func conceal() { hidePanel() }

    /// Waits until WhatsApp's attachment preview (with its Send button) is on the page.
    private func previewOpen(seconds: Int) async -> Bool {
        // waits inside the page (looks every 40 ms) and answers as soon as the preview with its Send button is there
        await run(Self.js(Self.waitPreviewScript), ["ms": seconds * 1000]) == "y"
    }

    /// Dismisses a half-open preview or menu so the next method starts from a clean chat.
    private func closePreviewIfAny() async {
        _ = await run(Self.js("""
        const x = document.querySelector('[data-icon="x"], [data-icon="x-viewer"], [data-icon="close"], [aria-label="Close" i]');
        if (x) x.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
        document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', code: 'Escape', keyCode: 27, bubbles: true }));
        return 'ok';
        """))
        await pause(ms: 150)
    }

    /// Last resort: a real paste, the same as pressing Cmd+V in the chat with the PDF copied in Finder. The clipboard is put back afterwards.
    private func nativePaste(pdf: Data, fileName: String) async -> Bool {
        guard let w = web, let p = w.window else { return false }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("BillBoxWhatsApp", isDirectory: true)
        let url = dir.appendingPathComponent(fileName + ".pdf")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try pdf.write(to: url)
        } catch { return false }

        let board = NSPasteboard.general
        var saved: [[(NSPasteboard.PasteboardType, Data)]] = []
        for item in board.pasteboardItems ?? [] {
            saved.append(item.types.compactMap { t in item.data(forType: t).map { (t, $0) } })
        }
        board.clearContents()
        board.writeObjects([url as NSURL])

        _ = await run(Self.js("const c = document.querySelector('footer div[contenteditable=\"true\"]'); if (c) c.focus(); return 'ok';"))
        p.makeFirstResponder(w)
        _ = NSApp.sendAction(NSSelectorFromString("paste:"), to: w, from: nil)
        let ok = await previewOpen(seconds: 8)

        board.clearContents()
        for entries in saved {
            let item = NSPasteboardItem()
            for (t, d) in entries { item.setData(d, forType: t) }
            board.writeObjects([item])
        }
        try? FileManager.default.removeItem(at: url)
        return ok
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
    const wait = async (fn, ms) => { const t = Date.now(); while (Date.now() - t < ms) { const v = fn(); if (v) return v; await sleep(50); } return null; };
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

    /// Is the chat box up, and whose chat is it? One answer: "composer|Heading" or "none".
    private static let chatNowScript = #"""
    if (!composerEl()) return 'none';
    const h = document.querySelector('#main header span[dir="auto"]') || document.querySelector('#main header');
    return 'composer|' + (h ? (h.innerText || '').split('\n')[0].trim() : '');
    """#

    /// Waits INSIDE the page for the chat box (or an answer that needs the person: not on WhatsApp, QR code, link code).
    /// Same checks as pageState(); returns loading / chats if `ms` runs out first.
    private static let waitComposerScript = #"""
    const q = (s) => document.querySelector(s);
    const st = () => {
      if (q('footer div[contenteditable="true"]')) return 'composer';
      const d = q('div[role="dialog"]');
      if (d && /invalid|isn.t on WhatsApp|not on WhatsApp/i.test(d.innerText || '')) return 'invalid';
      if (q('[data-link-code]')) return 'code';
      if (q('canvas[aria-label]') || q('div[data-ref]') || q('[data-testid="qrcode"]')) return 'qr';
      if (q('#pane-side') || q('[data-icon="chats"]')) return 'chats';
      return 'loading';
    };
    const t0 = Date.now();
    let s = st();
    while ((s === 'loading' || s === 'chats') && Date.now() - t0 < ms) { await sleep(60); s = st(); }
    return s;
    """#

    /// Waits INSIDE the page for the attachment preview (the Send button or the caption box).
    private static let waitPreviewScript = #"""
    return (await wait(() => previewOpen(), ms)) ? 'y' : 'n';
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
      const has = () => (cap.innerText || cap.textContent || '').includes(caption.slice(0, 8));
      await wait(has, 600);
      if (!has()) {
        const dt = new DataTransfer(); dt.setData('text/plain', caption);
        cap.dispatchEvent(new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true }));
        await wait(has, 600);
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
