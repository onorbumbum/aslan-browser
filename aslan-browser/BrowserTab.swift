//
//  BrowserTab.swift
//  aslan-browser
//

import AppKit
import WebKit

struct NavigationResult {
    let url: String
    let title: String
}

@MainActor
class BrowserTab: NSObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {

    let tabId: String
    let webView: WKWebView
    let window: NSWindow
    var sessionId: String?
    weak var learnRecorder: LearnRecorder?
    private var urlField: NSTextField?
    private var goButton: NSButton?
    private var backButton: NSButton?
    private var canGoBackObservation: NSKeyValueObservation?
    private var statusBar: NSTextField?
    private var statusBarHeightConstraint: NSLayoutConstraint?
    private var recLabel: NSTextField?
    private var addNoteButton: NSButton?
    private var urlBarToGoConstraint: NSLayoutConstraint?
    private var urlBarToRecConstraint: NSLayoutConstraint?

    private var navigationContinuation: CheckedContinuation<NavigationResult, Error>?
    private var messageHandler: ScriptMessageHandler?
    private var urlObservation: NSKeyValueObservation?
    private var titleObservation: NSKeyValueObservation?

    /// Active popup windows (child WKWebViews opened by window.open / target="_blank")
    private var popupWindows: [NSPanel] = []
    /// Navigation delegates for popup webviews (must be retained)
    private var popupNavDelegates: [PopupNavigationDelegate] = []

    /// If set, the next file-input open panel returns these URLs without showing UI.
    private var queuedOpenPanelURLs: [URL]?

    // Event callback: (method, params) — set by TabManager
    var onEvent: ((_ method: String, _ params: [String: Any]) -> Void)?

    // Window close callback — set by TabManager to handle close button
    var onWindowClose: ((_ tabId: String) -> Void)?

    // Loading UI state
    private(set) var isLoading: Bool = false
    private var loadingURL: String?

    // Readiness tracking
    private var didFinishNavigation = false
    private var domStable = false
    private var networkIdle = true  // starts idle (no pending requests)
    private var readyStateComplete = false
    private var idleContinuations: [Int: CheckedContinuation<Void, Error>] = [:]
    private var nextIdleContinuationId = 0

    init(tabId: String, width: Int = 1440, height: Int = 900, isHidden: Bool = false) {
        self.tabId = tabId

        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.userContentController.addUserScript(ScriptBridge.makeUserScript())

        let frame = NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))

        let wv = WKWebView(frame: frame, configuration: config)
        // Bare WKWebView omits Safari's version, which can trigger basic site UIs.
        // Match the installed Safari version rather than claiming to run Chromium.
        let safariVersion = Bundle(path: "/Applications/Safari.app")?
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "17.0"
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(safariVersion) Safari/605.1.15"
        self.webView = wv

        let win = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = tabId
        // Agent-created windows stay standalone; TabManager opts a window into
        // native tabbing only for user-initiated File ▸ New Tab.
        win.tabbingMode = .disallowed

        // Container with URL bar + webView
        let container = NSView(frame: frame)
        // container keeps translatesAutoresizingMaskIntoConstraints = true (default)
        // because NSWindow manages contentView sizing
        win.contentView = container

        let urlBar = NSTextField()
        urlBar.placeholderString = "Enter URL..."
        urlBar.font = NSFont.systemFont(ofSize: 13)
        urlBar.bezelStyle = .roundedBezel
        urlBar.translatesAutoresizingMaskIntoConstraints = false
        // A long URL must never push the window wider than its frame.
        urlBar.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        urlBar.lineBreakMode = .byTruncatingTail

        wv.translatesAutoresizingMaskIntoConstraints = false

        // Status bar — thin text field at bottom
        let statusBar = NSTextField(labelWithString: "")
        statusBar.font = NSFont.systemFont(ofSize: 11)
        statusBar.textColor = .secondaryLabelColor
        statusBar.backgroundColor = .windowBackgroundColor
        statusBar.drawsBackground = true
        statusBar.isEditable = false
        statusBar.isBezeled = false
        statusBar.lineBreakMode = .byTruncatingMiddle
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        statusBar.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusBar.isHidden = true
        self.statusBar = statusBar

        let statusBarHeight = statusBar.heightAnchor.constraint(equalToConstant: 0)
        self.statusBarHeightConstraint = statusBarHeight

        // Back button left of the URL bar
        let backBtn = NSButton(frame: .zero)
        backBtn.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back")
        backBtn.bezelStyle = .texturedRounded
        backBtn.toolTip = "Back (⌘[)"
        backBtn.isEnabled = false
        backBtn.translatesAutoresizingMaskIntoConstraints = false
        self.backButton = backBtn

        // Go/Stop button next to URL bar
        let goBtn = NSButton(title: "→", target: nil, action: nil)
        goBtn.bezelStyle = .texturedRounded
        goBtn.font = NSFont.systemFont(ofSize: 14)
        goBtn.translatesAutoresizingMaskIntoConstraints = false
        self.goButton = goBtn

        // Recording UI — hidden by default
        let recLabel = NSTextField(labelWithString: "● REC")
        recLabel.font = NSFont.boldSystemFont(ofSize: 11)
        recLabel.textColor = .systemRed
        recLabel.isEditable = false
        recLabel.isBezeled = false
        recLabel.drawsBackground = false
        recLabel.translatesAutoresizingMaskIntoConstraints = false
        recLabel.isHidden = true
        self.recLabel = recLabel

        let noteBtn = NSButton(frame: .zero)
        noteBtn.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Add Note")
        noteBtn.bezelStyle = .texturedRounded
        noteBtn.isBordered = true
        noteBtn.translatesAutoresizingMaskIntoConstraints = false
        noteBtn.isHidden = true
        self.addNoteButton = noteBtn

        container.addSubview(backBtn)
        container.addSubview(urlBar)
        container.addSubview(recLabel)
        container.addSubview(noteBtn)
        container.addSubview(goBtn)
        container.addSubview(wv)
        container.addSubview(statusBar)

        // Two URL bar trailing constraints — swap based on recording state
        let urlToGo = urlBar.trailingAnchor.constraint(equalTo: goBtn.leadingAnchor, constant: -4)
        let urlToRec = urlBar.trailingAnchor.constraint(equalTo: recLabel.leadingAnchor, constant: -4)
        urlToGo.isActive = true
        urlToRec.isActive = false
        self.urlBarToGoConstraint = urlToGo
        self.urlBarToRecConstraint = urlToRec

        NSLayoutConstraint.activate([
            urlBar.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            backBtn.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            backBtn.centerYAnchor.constraint(equalTo: urlBar.centerYAnchor),
            backBtn.widthAnchor.constraint(equalToConstant: 36),
            backBtn.heightAnchor.constraint(equalToConstant: 28),

            urlBar.leadingAnchor.constraint(equalTo: backBtn.trailingAnchor, constant: 4),
            urlBar.heightAnchor.constraint(equalToConstant: 28),

            recLabel.centerYAnchor.constraint(equalTo: goBtn.centerYAnchor),
            recLabel.trailingAnchor.constraint(equalTo: noteBtn.leadingAnchor, constant: -4),

            noteBtn.centerYAnchor.constraint(equalTo: goBtn.centerYAnchor),
            noteBtn.trailingAnchor.constraint(equalTo: goBtn.leadingAnchor, constant: -4),
            noteBtn.widthAnchor.constraint(equalToConstant: 28),
            noteBtn.heightAnchor.constraint(equalToConstant: 28),

            goBtn.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            goBtn.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            goBtn.widthAnchor.constraint(equalToConstant: 36),
            goBtn.heightAnchor.constraint(equalToConstant: 28),

            wv.topAnchor.constraint(equalTo: urlBar.bottomAnchor, constant: 4),
            wv.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            wv.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

            statusBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            statusBarHeight,
        ])

        if isHidden {
            win.orderOut(nil)
        } else {
            win.makeKeyAndOrderFront(nil)
        }

        self.window = win

        super.init()

        // Wire up URL bar target/action after super.init()
        urlBar.target = self
        urlBar.action = #selector(urlFieldAction(_:))
        self.urlField = urlBar

        // Wire up Back button after super.init()
        backBtn.target = self
        backBtn.action = #selector(backButtonAction(_:))

        // Wire up Go button after super.init()
        goBtn.target = self
        goBtn.action = #selector(goButtonAction(_:))

        // Wire up Add Note button after super.init()
        noteBtn.target = self
        noteBtn.action = #selector(addNoteAction(_:))

        win.delegate = self
        self.webView.navigationDelegate = self
        self.webView.uiDelegate = self

        let handler = ScriptMessageHandler { [weak self] body in
            Task { @MainActor in
                self?.handleScriptMessage(body)
            }
        }
        self.messageHandler = handler
        config.userContentController.add(handler, name: "agent")

        // KVO: update address bar & window title whenever URL or title changes
        urlObservation = webView.observe(\.url, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.updateURLField()
                self?.updateWindowTitle()
            }
        }
        canGoBackObservation = webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] wv, _ in
            let canGoBack = wv.canGoBack
            Task { @MainActor in
                self?.backButton?.isEnabled = canGoBack
            }
        }
        titleObservation = webView.observe(\.title, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.updateWindowTitle()
            }
        }
    }

    // MARK: - Script Message Handling

    private func handleScriptMessage(_ body: Any) {
        guard let dict = body as? [String: Any],
              let type = dict["type"] as? String else {
            NSLog("[aslan-browser] Unrecognized script message: \(body)")
            return
        }

        switch type {
        case "domStable":
            domStable = true
            checkIdleAndResume()
        case "networkIdle":
            networkIdle = true
            checkIdleAndResume()
        case "networkBusy":
            networkIdle = false
        case "console":
            let level = dict["level"] as? String ?? "log"
            let message = dict["message"] as? String ?? ""
            onEvent?("event.console", ["tabId": tabId, "level": level, "message": message])
        case "error":
            let message = dict["message"] as? String ?? ""
            let source = dict["source"] as? String ?? ""
            let line = dict["line"] as? Int ?? 0
            onEvent?("event.error", ["tabId": tabId, "message": message, "source": source, "line": line])
        case "learn.action":
            guard let recorder = learnRecorder, recorder.state == .recording else { break }
            var actionData = dict
            actionData.removeValue(forKey: "type") // Remove the message type "learn.action"
            // Rename "actionType" to "type" in the action data
            if let actionType = actionData.removeValue(forKey: "actionType") {
                actionData["type"] = actionType
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms for page to react
                let base64 = try? await self.screenshot(quality: 60, width: 1440)
                let _ = recorder.addAction(actionData, screenshotData: base64, tabId: self.tabId)
            }

        default:
            NSLog("[aslan-browser] Unknown script message type: \(type)")
        }
    }

    // MARK: - Readiness

    private func resetReadinessState() {
        didFinishNavigation = false
        domStable = false
        networkIdle = true
        readyStateComplete = false
    }

    private var isIdle: Bool {
        didFinishNavigation && domStable && networkIdle && readyStateComplete
    }

    private func checkIdleAndResume() {
        guard isIdle else { return }
        let continuations = idleContinuations
        idleContinuations.removeAll()
        for (_, c) in continuations {
            c.resume()
        }
    }

    func waitForIdle(timeout: Int = 30000) async throws {
        // Check readyState synchronously first
        await refreshReadyState()

        if isIdle { return }

        let id = nextIdleContinuationId
        nextIdleContinuationId += 1

        // Wait with timeout
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.idleContinuations[id] = continuation

            // Timeout task
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(timeout) * 1_000_000)
                // If still waiting, remove and fail
                if self.idleContinuations.removeValue(forKey: id) != nil {
                    continuation.resume(throwing: BrowserError.timeout("waitForIdle timed out after \(timeout)ms"))
                }
            }
        }
    }

    private func refreshReadyState() async {
        do {
            let state = try await webView.callAsyncJavaScript(
                "return document.readyState",
                arguments: [:],
                contentWorld: .page
            ) as? String
            readyStateComplete = (state == "complete")
            checkIdleAndResume()
        } catch {
            // If we can't eval JS, treat as not complete
        }
    }

    // MARK: - Window Title & URL Bar

    func updateWindowTitle() {
        let url = webView.url?.absoluteString ?? ""
        let title = webView.title ?? ""
        let display = title.isEmpty ? url : title
        window.title = display.isEmpty ? tabId : "\(tabId) — \(display)"
        updateURLField()
    }

    private func updateURLField() {
        urlField?.stringValue = webView.url?.absoluteString ?? ""
    }

    @objc private func backButtonAction(_ sender: Any?) {
        goBackFromUI()
    }

    /// User-initiated back (toolbar button / ⌘[). Unlike `goBack()` it doesn't wait for the load.
    func goBackFromUI() {
        if webView.canGoBack { webView.goBack() }
    }

    @objc private func goButtonAction(_ sender: NSButton) {
        if isLoading {
            webView.stopLoading()
            isLoading = false
            updateLoadingUI()
        } else {
            guard let urlField = urlField else { return }
            urlFieldAction(urlField)
        }
    }

    @objc private func urlFieldAction(_ sender: NSTextField) {
        var urlString = sender.stringValue.trimmingCharacters(in: .whitespaces)
        if urlString.isEmpty { return }

        // Add https:// if no scheme provided
        if !urlString.contains("://") {
            urlString = "https://" + urlString
        }

        Task { @MainActor in
            do {
                let result = try await self.navigate(to: urlString)
                sender.stringValue = result.url
            } catch {
                NSLog("[aslan-browser] URL bar navigation failed: \(error)")
            }
        }
    }

    // MARK: - NSWindowDelegate

    nonisolated func windowShouldClose(_ sender: NSWindow) -> Bool {
        Task { @MainActor in
            self.onWindowClose?(self.tabId)
        }
        return false  // TabManager handles actual close via closeTab()
    }

    // MARK: - Cleanup

    func cleanup() {
        urlObservation?.invalidate()
        urlObservation = nil
        titleObservation?.invalidate()
        titleObservation = nil
        canGoBackObservation?.invalidate()
        canGoBackObservation = nil
        onEvent = nil
        onWindowClose = nil
        navigationContinuation = nil
        let continuations = idleContinuations
        idleContinuations.removeAll()
        for (_, c) in continuations {
            c.resume(throwing: BrowserError.tabNotFound(tabId))
        }
        // Close any open popup windows
        for panel in popupWindows {
            panel.orderOut(nil)
        }
        popupWindows.removeAll()
        popupNavDelegates.removeAll()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        webView.removeFromSuperview()
    }

    // MARK: - Navigate

    enum WaitUntil: String {
        case none
        case load
        case idle
    }

    func navigate(to urlString: String, waitUntil: WaitUntil = .load, timeout: Int = 30000) async throws -> NavigationResult {
        guard let url = URL(string: urlString) else {
            throw BrowserError.invalidURL(urlString)
        }
        resetReadinessState()

        self.isLoading = true
        self.loadingURL = urlString
        self.updateLoadingUI()

        switch waitUntil {
        case .none:
            webView.load(URLRequest(url: url))
            return NavigationResult(url: urlString, title: "")

        case .load:
            let result = try await withCheckedThrowingContinuation { continuation in
                self.navigationContinuation = continuation
                self.webView.load(URLRequest(url: url))
            }
            return result

        case .idle:
            let result = try await withCheckedThrowingContinuation { continuation in
                self.navigationContinuation = continuation
                self.webView.load(URLRequest(url: url))
            }
            try await waitForIdle(timeout: timeout)
            // Re-fetch title after idle since it may have changed
            let title = try await evaluate("return document.title") as? String ?? result.title
            return NavigationResult(url: result.url, title: title)
        }
    }

    // MARK: - Navigation History

    func goBack() async throws -> NavigationResult {
        guard webView.canGoBack else {
            let url = webView.url?.absoluteString ?? ""
            let title = webView.title ?? ""
            return NavigationResult(url: url, title: title)
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.navigationContinuation = continuation
            self.webView.goBack()
        }
    }

    func goForward() async throws -> NavigationResult {
        guard webView.canGoForward else {
            let url = webView.url?.absoluteString ?? ""
            let title = webView.title ?? ""
            return NavigationResult(url: url, title: title)
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.navigationContinuation = continuation
            self.webView.goForward()
        }
    }

    func reload() async throws -> NavigationResult {
        return try await withCheckedThrowingContinuation { continuation in
            self.navigationContinuation = continuation
            self.webView.reload()
        }
    }

    // MARK: - Wait for Selector

    func waitForSelector(_ selector: String, timeout: Int = 5000) async throws {
        do {
            _ = try await webView.callAsyncJavaScript(
                "return await window.__agent.waitForSelector(selector, timeout)",
                arguments: ["selector": selector, "timeout": timeout],
                contentWorld: .page
            )
        } catch {
            throw BrowserError.timeout("waitForSelector(\(selector)) timed out after \(timeout)ms")
        }
    }

    // MARK: - Accessibility Tree

    func getAccessibilityTree() async throws -> [[String: Any]] {
        let result = try await webView.callAsyncJavaScript(
            "return window.__agent.extractA11yTree()",
            arguments: [:],
            contentWorld: .page
        )

        guard let nodes = result as? [[String: Any]] else {
            return []
        }

        return nodes
    }

    // MARK: - Interaction

    /// Resolves a target to a CSS selector: @eN refs → [data-agent-ref="@eN"], otherwise used as-is.
    private func resolveSelector(_ target: String) -> String {
        if target.hasPrefix("@") {
            return "[data-agent-ref=\"\(target)\"]"
        }
        return target
    }

    func click(target: String) async throws {
        let selector = resolveSelector(target)
        let script = """
            var el = document.querySelector(selector);
            if (!el) throw new Error("Element not found: " + selector);
            el.focus();
            el.click();
            return true;
            """
        do {
            _ = try await webView.callAsyncJavaScript(
                script,
                arguments: ["selector": selector],
                contentWorld: .page
            )
        } catch {
            throw BrowserError.javaScriptError("click failed: \(error.localizedDescription)")
        }
    }

    func uploadFileViaOpenPanel(target: String, paths: [String]) async throws -> [String: Any] {
        let urls = paths.map { URL(fileURLWithPath: $0) }
        queuedOpenPanelURLs = urls
        do {
            try await click(target: target)
            try await Task.sleep(nanoseconds: 500_000_000)
            return ["uploaded": urls.map { $0.path }]
        } catch {
            queuedOpenPanelURLs = nil
            throw error
        }
    }

    func fill(target: String, value: String) async throws {
        let selector = resolveSelector(target)
        let script = """
            var el = document.querySelector(selector);
            if (!el) throw new Error("Element not found: " + selector);
            el.focus();
            el.value = value;
            el.dispatchEvent(new Event("input", { bubbles: true }));
            el.dispatchEvent(new Event("change", { bubbles: true }));
            return true;
            """
        do {
            _ = try await webView.callAsyncJavaScript(
                script,
                arguments: ["selector": selector, "value": value],
                contentWorld: .page
            )
        } catch {
            throw BrowserError.javaScriptError("fill failed: \(error.localizedDescription)")
        }
    }

    func select(target: String, value: String) async throws {
        let selector = resolveSelector(target)
        let script = """
            var el = document.querySelector(selector);
            if (!el) throw new Error("Element not found: " + selector);
            el.value = value;
            el.dispatchEvent(new Event("change", { bubbles: true }));
            return true;
            """
        do {
            _ = try await webView.callAsyncJavaScript(
                script,
                arguments: ["selector": selector, "value": value],
                contentWorld: .page
            )
        } catch {
            throw BrowserError.javaScriptError("select failed: \(error.localizedDescription)")
        }
    }

    func keypress(key: String, modifiers: [String: Bool]? = nil) async throws {
        let script = """
            var opts = {
                key: key,
                code: key.length === 1 ? "Key" + key.toUpperCase() : key,
                bubbles: true,
                cancelable: true
            };
            if (mods.ctrlKey) opts.ctrlKey = true;
            if (mods.shiftKey) opts.shiftKey = true;
            if (mods.altKey) opts.altKey = true;
            if (mods.metaKey) opts.metaKey = true;

            var target = document.activeElement || document.body;
            target.dispatchEvent(new KeyboardEvent("keydown", opts));
            target.dispatchEvent(new KeyboardEvent("keyup", opts));
            return true;
            """
        let mods: [String: Bool] = modifiers ?? [:]
        do {
            _ = try await webView.callAsyncJavaScript(
                script,
                arguments: ["key": key, "mods": mods],
                contentWorld: .page
            )
        } catch {
            throw BrowserError.javaScriptError("keypress failed: \(error.localizedDescription)")
        }
    }

    func scroll(x: Double, y: Double, target: String? = nil) async throws {
        if let target {
            let selector = resolveSelector(target)
            let script = """
                var el = document.querySelector(selector);
                if (!el) throw new Error("Element not found: " + selector);
                el.scrollIntoView({ behavior: "instant", block: "center" });
                return true;
                """
            do {
                _ = try await webView.callAsyncJavaScript(
                    script,
                    arguments: ["selector": selector],
                    contentWorld: .page
                )
            } catch {
                throw BrowserError.javaScriptError("scroll failed: \(error.localizedDescription)")
            }
        } else {
            let script = """
                window.scrollTo(x, y);
                return true;
                """
            do {
                _ = try await webView.callAsyncJavaScript(
                    script,
                    arguments: ["x": x, "y": y],
                    contentWorld: .page
                )
            } catch {
                throw BrowserError.javaScriptError("scroll failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Cookies

    func getCookies(url: String? = nil) async -> [[String: Any]] {
        let store = webView.configuration.websiteDataStore.httpCookieStore
        let allCookies = await store.allCookies()

        let filtered: [HTTPCookie]
        if let urlStr = url, let parsedURL = URL(string: urlStr) {
            filtered = allCookies.filter { cookie in
                let host = parsedURL.host ?? ""
                let cookieDomain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
                return host == cookieDomain || host.hasSuffix(".\(cookieDomain)")
            }
        } else {
            filtered = allCookies
        }

        return filtered.map { cookie in
            var dict: [String: Any] = [
                "name": cookie.name,
                "value": cookie.value,
                "domain": cookie.domain,
                "path": cookie.path
            ]
            if let expires = cookie.expiresDate {
                dict["expires"] = expires.timeIntervalSince1970
            }
            return dict
        }
    }

    func setCookie(name: String, value: String, domain: String, path: String = "/", expires: Double? = nil) async throws {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path
        ]
        if let expires {
            properties[.expires] = Date(timeIntervalSince1970: expires)
        }

        guard let cookie = HTTPCookie(properties: properties) else {
            throw BrowserError.javaScriptError("Invalid cookie properties")
        }

        let store = webView.configuration.websiteDataStore.httpCookieStore
        await store.setCookie(cookie)
    }

    // MARK: - Evaluate

    func evaluate(_ script: String, args: [String: Any]? = nil) async throws -> Any? {
        do {
            return try await webView.callAsyncJavaScript(
                script,
                arguments: args ?? [:],
                contentWorld: .page
            )
        } catch {
            throw BrowserError.javaScriptError(error.localizedDescription)
        }
    }

    // MARK: - Screenshot

    /// Tallest full-page capture; WKWebView snapshots fail past GPU texture limits.
    static let maxFullPageHeight = 16384

    /// Without viewport params the snapshot scales the current view to `width` (legacy
    /// behavior). With `viewportWidth`/`viewportHeight` the view is resized to that
    /// CSS-pixel viewport first and captured 1:1. `fullPage` scrolls the document in
    /// viewport-sized slices and stitches them, so `vh` units, lazy images and
    /// scroll-reveal sections behave as they do for a real visitor. The original size
    /// is restored afterwards.
    func screenshot(quality: Int = 70, width: Int = 1440) async throws -> String {
        try await captureScreenshot(quality: quality, width: width).base64
    }

    func captureScreenshot(
        quality: Int = 70,
        width: Int = 1440,
        format: String = "jpeg",
        viewportWidth: Int? = nil,
        viewportHeight: Int? = nil,
        fullPage: Bool = false
    ) async throws -> (base64: String, width: Int, height: Int) {
        let resizing = viewportWidth != nil || viewportHeight != nil || fullPage

        let originalContentSize = window.contentView?.frame.size
        defer {
            if resizing, let size = originalContentSize {
                window.setContentSize(size)
                window.contentView?.layoutSubtreeIfNeeded()
            }
        }

        var cgImage: CGImage
        if fullPage {
            let w = viewportWidth ?? Int(webView.frame.width)
            cgImage = try await captureFullPage(width: w, viewportHeight: Self.fullPageViewportHeight(forWidth: w))
        } else if resizing {
            let w = viewportWidth ?? Int(webView.frame.width)
            let h = viewportHeight ?? Int(webView.frame.height)
            setViewportSize(width: w, height: h)
            try await Task.sleep(nanoseconds: 150_000_000)
            _ = try await evaluate(Self.finishAnimationsJS)
            _ = try await evaluate(Self.decodeVisibleImagesJS)
            try await Task.sleep(nanoseconds: 100_000_000)
            // Snapshots come back at backing-store (Retina) resolution; a requested
            // viewport means CSS pixels, so output W x H pixels like Playwright.
            cgImage = try await snapshotImage(width: w, downscaleToCSSPixels: true)
        } else {
            cgImage = try await snapshotImage(width: width, downscaleToCSSPixels: false)
        }

        let pixelSize = (width: cgImage.width, height: cgImage.height)
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let isPNG = format == "png"
        let compressionFactor = Double(quality) / 100.0

        // Encode off main thread
        let base64 = try await Task.detached {
            guard let data = isPNG
                ? bitmap.representation(using: .png, properties: [:])
                : bitmap.representation(using: .jpeg, properties: [.compressionFactor: compressionFactor])
            else {
                throw BrowserError.screenshotFailed("Failed to encode \(isPNG ? "PNG" : "JPEG")")
            }
            return data.base64EncodedString()
        }.value

        return (base64, pixelSize.width, pixelSize.height)
    }

    /// Slice height for full-page capture; sets what `vh` resolves to on the page.
    private static func fullPageViewportHeight(forWidth width: Int) -> Int {
        width < 768 ? 844 : 1080
    }

    private func snapshotImage(width: Int, downscaleToCSSPixels: Bool) async throws -> CGImage {
        let config = WKSnapshotConfiguration()
        config.snapshotWidth = NSNumber(value: width)
        let image = try await webView.takeSnapshot(configuration: config)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw BrowserError.screenshotFailed("Failed to create CGImage")
        }
        let scale = window.backingScaleFactor
        guard downscaleToCSSPixels, scale > 1 else { return cgImage }
        return try Self.resample(
            cgImage,
            toWidth: Int((CGFloat(cgImage.width) / scale).rounded()),
            height: Int((CGFloat(cgImage.height) / scale).rounded())
        )
    }

    private static let documentHeightJS =
        "return Math.max(document.documentElement.scrollHeight, document.body ? document.body.scrollHeight : 0)"

    /// Hide fixed elements (and sticky ones near the top, i.e. headers) so they appear only
    /// in the first slice instead of repeating in every one.
    private static let hideFixedJS = """
        if (!window.__aslanHidden) {
          window.__aslanHidden = [];
          for (const e of document.querySelectorAll('*')) {
            const p = getComputedStyle(e).position;
            const stuckHeader = p === 'sticky' && e.getBoundingClientRect().top < innerHeight * 0.25;
            if (p !== 'fixed' && !stuckHeader) continue;
            // Fixed elements are out of flow, so display:none cannot shift layout and also
            // beats children that force visibility:visible. Sticky ones stay in flow.
            const prop = p === 'fixed' ? 'display' : 'visibility';
            const value = p === 'fixed' ? 'none' : 'hidden';
            window.__aslanHidden.push([e, prop, e.style.getPropertyValue(prop), e.style.getPropertyPriority(prop)]);
            e.style.setProperty(prop, value, 'important');
          }
        }
        return window.__aslanHidden.length
        """

    /// Resolve once every image currently in the viewport is decoded, so the snapshot does
    /// not catch large lazy images before they paint. Bounded so a stuck image cannot hang.
    private static let decodeVisibleImagesJS = """
        const imgs = [...document.images].filter(i => {
          const r = i.getBoundingClientRect();
          return r.width > 0 && r.bottom > 0 && r.top < innerHeight;
        });
        const decodes = Promise.all(imgs.map(i => i.decode().catch(() => {})));
        const timeout = new Promise(resolve => setTimeout(resolve, 4000));
        await Promise.race([decodes, timeout]);
        return imgs.length
        """

    /// Hidden windows do not advance CSS animations or transitions, so fade-ins (e.g.
    /// `img { opacity: 0; animation: fadeIn }`) would be captured at their start state.
    /// Jump finite ones to their end; infinite animations throw and are left alone.
    private static let finishAnimationsJS = """
        let finished = 0;
        for (const a of document.getAnimations()) {
          try { a.finish(); finished++ } catch (e) {}
        }
        return finished
        """

    private static let restoreFixedJS = """
        if (window.__aslanHidden) {
          for (const [e, prop, v, pr] of window.__aslanHidden) {
            if (v) e.style.setProperty(prop, v, pr); else e.style.removeProperty(prop);
          }
          delete window.__aslanHidden;
        }
        return true
        """

    private func intResult(_ script: String, args: [String: Any]? = nil) async throws -> Int {
        (try await evaluate(script, args: args) as? NSNumber)?.intValue ?? 0
    }

    private func scrollPage(to y: Int) async throws -> Int {
        try await intResult(
            "window.scrollTo({ top: y, left: 0, behavior: 'instant' }); return Math.round(window.scrollY)",
            args: ["y": y]
        )
    }

    /// Scroll through the page once so lazy images and scroll-reveal sections trigger, then
    /// wait (bounded) for images to finish loading. Returns the settled document height.
    private func warmUpPage(viewportHeight vh: Int) async throws -> Int {
        var docHeight = try await intResult(Self.documentHeightJS)
        var y = 0
        while y < min(docHeight, Self.maxFullPageHeight) {
            _ = try await scrollPage(to: y)
            try await Task.sleep(nanoseconds: 120_000_000)
            docHeight = try await intResult(Self.documentHeightJS)  // lazy content can grow the page
            y += max(vh * 3 / 4, 1)
        }
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            // Only images with a rendered box: hidden lazy gallery items never load.
            let pending = try await intResult(
                "return [...document.images].filter(i => !i.complete && i.getClientRects().length > 0).length"
            )
            if pending == 0 { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        return try await intResult(Self.documentHeightJS)
    }

    private func captureFullPage(width w: Int, viewportHeight vh: Int) async throws -> CGImage {
        setViewportSize(width: w, height: vh)
        try await Task.sleep(nanoseconds: 150_000_000)

        let startY = try await intResult("return Math.round(window.scrollY)")
        do {
            let docHeight = try await warmUpPage(viewportHeight: vh)
            let totalHeight = min(max(docHeight, vh), Self.maxFullPageHeight)
            _ = try await scrollPage(to: 0)
            try await Task.sleep(nanoseconds: 200_000_000)

            guard let context = CGContext(
                data: nil, width: w, height: totalHeight, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                throw BrowserError.screenshotFailed("Failed to allocate \(w)x\(totalHeight) canvas")
            }
            context.interpolationQuality = .high

            var y = 0
            while y < totalHeight {
                // The last slice is pulled back so it ends flush with the page bottom.
                let scrolled = try await scrollPage(to: min(y, max(totalHeight - vh, 0)))
                _ = try await evaluate(Self.finishAnimationsJS)
                _ = try await evaluate(Self.decodeVisibleImagesJS)
                try await Task.sleep(nanoseconds: 150_000_000)
                let slice = try await snapshotImage(width: w, downscaleToCSSPixels: false)
                // CGContext origin is bottom-left; slices are placed by their top edge.
                context.draw(slice, in: CGRect(x: 0, y: totalHeight - scrolled - vh, width: w, height: vh))
                if y == 0 { _ = try await evaluate(Self.hideFixedJS) }
                y += vh
            }

            _ = try? await evaluate(Self.restoreFixedJS)
            _ = try? await scrollPage(to: startY)
            guard let image = context.makeImage() else {
                throw BrowserError.screenshotFailed("Failed to compose full-page image")
            }
            return image
        } catch {
            _ = try? await evaluate(Self.restoreFixedJS)
            _ = try? await scrollPage(to: startY)
            throw error
        }
    }

    private static func resample(_ image: CGImage, toWidth width: Int, height: Int) throws -> CGImage {
        guard width > 0, height > 0,
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else {
            throw BrowserError.screenshotFailed("Failed to create resampling context")
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let result = context.makeImage() else {
            throw BrowserError.screenshotFailed("Failed to resample image")
        }
        return result
    }

    /// Resize the window so the web view itself is exactly width x height points.
    private func setViewportSize(width: Int, height: Int) {
        guard let content = window.contentView else { return }
        content.layoutSubtreeIfNeeded()
        // URL bar and status bar share the content view with the web view.
        let chrome = content.bounds.height - webView.frame.height
        window.setContentSize(NSSize(width: CGFloat(width), height: CGFloat(height) + chrome))
        content.layoutSubtreeIfNeeded()
    }

    // MARK: - Focus URL Bar

    func focusURLBar() {
        window.makeKeyAndOrderFront(nil)
        urlField?.selectText(nil)
    }

    // MARK: - Learn Mode

    func startLearnMode() {
        webView.evaluateJavaScript(ScriptBridge.learnModeJS, completionHandler: nil)
    }

    func stopLearnMode() {
        webView.evaluateJavaScript(ScriptBridge.learnModeCleanupJS, completionHandler: nil)
    }

    func setRecordingUI(active: Bool) {
        recLabel?.isHidden = !active
        addNoteButton?.isHidden = !active

        if active {
            urlBarToGoConstraint?.isActive = false
            urlBarToRecConstraint?.isActive = true
        } else {
            urlBarToRecConstraint?.isActive = false
            urlBarToGoConstraint?.isActive = true
        }
    }

    @objc private func addNoteAction(_ sender: NSButton) {
        guard let recorder = learnRecorder, recorder.state == .recording else { return }

        let alert = NSAlert()
        alert.messageText = "Add Annotation"
        alert.informativeText = "Describe what you just did or note something important for this step."
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 260, height: 80))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 260, height: 80))
        textView.isEditable = true
        textView.isRichText = false
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        alert.accessoryView = scrollView

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                let _ = recorder.addAnnotation(text: text)
            }
        }
    }

    // MARK: - WKUIDelegate (Popups, Alerts)

    /// Handle window.open() and target="_blank" — create popup in NSPanel
    nonisolated func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        let url = navigationAction.request.url?.absoluteString ?? "nil"
        popupLog("createWebViewWith called — url: \(url)")

        // Use the provided configuration (shares process pool + data store with parent)
        let popupWebView = WKWebView(frame: .zero, configuration: configuration)
        popupWebView.customUserAgent = webView.customUserAgent
        // Keep translatesAutoresizingMaskIntoConstraints = true (default)
        // so NSWindow manages sizing via autoresizing mask

        let width = windowFeatures.width?.doubleValue ?? 600
        let height = windowFeatures.height?.doubleValue ?? 700
        let panelRect = NSRect(x: 0, y: 0, width: width, height: height)

        let panel = NSPanel(
            contentRect: panelRect,
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Sign In"
        panel.contentView = popupWebView
        panel.center()
        panel.makeKeyAndOrderFront(nil)

        // Set delegates on popup webView
        popupWebView.uiDelegate = self
        let navDelegate = PopupNavigationDelegate()
        popupWebView.navigationDelegate = navDelegate

        // Track popup and retain the nav delegate (must happen synchronously
        // since navigationDelegate is weak and navDelegate is a local var)
        // This nonisolated method is always called on the main thread by WebKit.
        MainActor.assumeIsolated {
            self.popupWindows.append(panel)
            self.popupNavDelegates.append(navDelegate)
        }

        // Do NOT call popupWebView.load() — WebKit auto-loads the request
        // when we return the webView. Double-loading breaks redirect chains.
        popupLog("Popup panel created (\(Int(width))x\(Int(height)))")

        return popupWebView
    }

    /// Handle window.close() from popup
    nonisolated func webViewDidClose(_ webView: WKWebView) {
        Task { @MainActor in
            // Find and close the panel containing this webView
            if let index = self.popupWindows.firstIndex(where: { $0.contentView === webView }) {
                let panel = self.popupWindows.remove(at: index)
                panel.orderOut(nil)
                // Remove corresponding nav delegate
                if index < self.popupNavDelegates.count {
                    self.popupNavDelegates.remove(at: index)
                }
                NSLog("[aslan-browser] Popup closed")
            }
        }
    }

    /// JavaScript alert()
    nonisolated func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            let alert = NSAlert()
            alert.messageText = message
            alert.addButton(withTitle: "OK")
            alert.runModal()
            completionHandler()
        }
    }

    /// JavaScript confirm()
    nonisolated func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        Task { @MainActor in
            let alert = NSAlert()
            alert.messageText = message
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            let response = alert.runModal()
            completionHandler(response == .alertFirstButtonReturn)
        }
    }

    /// JavaScript prompt()
    nonisolated func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        Task { @MainActor in
            let alert = NSAlert()
            alert.messageText = prompt
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
            input.stringValue = defaultText ?? ""
            alert.accessoryView = input
            let response = alert.runModal()
            completionHandler(response == .alertFirstButtonReturn ? input.stringValue : nil)
        }
    }

    /// File upload — present native NSOpenPanel when user clicks <input type="file">
    nonisolated func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping ([URL]?) -> Void
    ) {
        Task { @MainActor in
            if let urls = self.queuedOpenPanelURLs {
                self.queuedOpenPanelURLs = nil
                completionHandler(urls)
                return
            }

            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = parameters.allowsMultipleSelection
            panel.canChooseDirectories = parameters.allowsDirectories
            panel.canChooseFiles = true

            let response = panel.runModal()
            if response == .OK {
                completionHandler(panel.urls)
            } else {
                completionHandler(nil)
            }
        }
    }

    // MARK: - Loading UI

    private func updateLoadingUI() {
        if isLoading {
            statusBar?.stringValue = "Loading \(loadingURL ?? "")…"
            statusBar?.isHidden = false
            statusBarHeightConstraint?.constant = 20
            goButton?.title = "✕"
            urlField?.textColor = .tertiaryLabelColor
        } else {
            statusBar?.stringValue = ""
            statusBar?.isHidden = true
            statusBarHeightConstraint?.constant = 0
            goButton?.title = "→"
            urlField?.textColor = .textColor
        }
    }

    // MARK: - WKNavigationDelegate

    nonisolated func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        Task { @MainActor in
            self.isLoading = true
            self.loadingURL = webView.url?.absoluteString
            self.updateLoadingUI()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.isLoading = false
            self.updateLoadingUI()

            self.didFinishNavigation = true
            self.readyStateComplete = true // didFinish implies readyState complete
            self.checkIdleAndResume()

            let url = webView.url?.absoluteString ?? ""
            let title = webView.title ?? ""
            let result = NavigationResult(url: url, title: title)
            self.navigationContinuation?.resume(returning: result)
            self.navigationContinuation = nil

            self.updateWindowTitle()

            self.onEvent?("event.navigation", ["tabId": self.tabId, "url": url])

            // Learn mode: log navigation and re-inject listeners
            if let recorder = self.learnRecorder, recorder.state == .recording {
                let navAction: [String: Any] = [
                    "type": "navigation",
                    "url": url,
                    "pageTitle": title
                ]
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 500_000_000) // 500ms for page to settle
                    let base64 = try? await self.screenshot(quality: 60, width: 1440)
                    let _ = recorder.addAction(navAction, screenshotData: base64, tabId: self.tabId)
                }
                // Re-inject learn listeners (navigation clears JS state)
                self.startLearnMode()
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.isLoading = false
            self.updateLoadingUI()

            self.navigationContinuation?.resume(throwing: BrowserError.navigationFailed(error.localizedDescription))
            self.navigationContinuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.isLoading = false
            self.updateLoadingUI()

            self.navigationContinuation?.resume(throwing: BrowserError.navigationFailed(error.localizedDescription))
            self.navigationContinuation = nil
        }
    }
}

// MARK: - Popup Debug Logging

/// Write to /tmp/aslan-popup.log since NSLog doesn't show in `log show`
func popupLog(_ message: String) {
    let ts = ISO8601DateFormatter().string(from: Date())
    let line = "[\(ts)] \(message)\n"
    let path = "/tmp/aslan-popup.log"
    if let handle = FileHandle(forWritingAtPath: path) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: path, contents: line.data(using: .utf8))
    }
}

// MARK: - Popup Navigation Delegate

/// Navigation delegate for popup WKWebViews — logs to /tmp/aslan-popup.log
class PopupNavigationDelegate: NSObject, WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = navigationAction.request.url?.absoluteString ?? "nil"
        popupLog("decidePolicyFor: \(url) (type: \(navigationAction.navigationType.rawValue))")
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let url = navigationResponse.response.url?.absoluteString ?? "nil"
        let status = (navigationResponse.response as? HTTPURLResponse)?.statusCode ?? 0
        popupLog("navigationResponse: \(url) (status: \(status))")
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        popupLog("didStartProvisional: \(webView.url?.absoluteString ?? "nil")")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let url = webView.url?.absoluteString ?? "nil"
        popupLog("didFinish: \(url)")

        // Check window.opener and log it for debugging
        webView.evaluateJavaScript("JSON.stringify({opener: !!window.opener, openerOrigin: window.opener ? 'exists' : 'null', href: window.location.href})") { result, error in
            if let result = result as? String {
                popupLog("  window state: \(result)")
            }
            if let error = error {
                popupLog("  JS eval error: \(error.localizedDescription)")
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        popupLog("didFail: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        popupLog("didFailProvisionalNavigation: \(error.localizedDescription)")
    }
}

// MARK: - Script Message Handler

class ScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private let callback: @Sendable (Any) -> Void

    init(callback: @escaping @Sendable (Any) -> Void) {
        self.callback = callback
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        callback(message.body)
    }
}
