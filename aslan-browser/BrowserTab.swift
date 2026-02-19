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
class BrowserTab: NSObject, WKNavigationDelegate, NSWindowDelegate {

    let tabId: String
    let webView: WKWebView
    let window: NSWindow
    var sessionId: String?
    private var urlField: NSTextField?
    private var goButton: NSButton?
    private var statusBar: NSTextField?
    private var statusBarHeightConstraint: NSLayoutConstraint?

    private var navigationContinuation: CheckedContinuation<NavigationResult, Error>?
    private var messageHandler: ScriptMessageHandler?
    private var urlObservation: NSKeyValueObservation?
    private var titleObservation: NSKeyValueObservation?

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
        config.userContentController.addUserScript(ScriptBridge.makeUserScript())

        let frame = NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))

        let wv = WKWebView(frame: frame, configuration: config)
        self.webView = wv

        let win = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = tabId

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
        statusBar.isHidden = true
        self.statusBar = statusBar

        let statusBarHeight = statusBar.heightAnchor.constraint(equalToConstant: 0)
        self.statusBarHeightConstraint = statusBarHeight

        // Go/Stop button next to URL bar
        let goBtn = NSButton(title: "→", target: nil, action: nil)
        goBtn.bezelStyle = .texturedRounded
        goBtn.font = NSFont.systemFont(ofSize: 14)
        goBtn.translatesAutoresizingMaskIntoConstraints = false
        self.goButton = goBtn

        container.addSubview(urlBar)
        container.addSubview(goBtn)
        container.addSubview(wv)
        container.addSubview(statusBar)

        NSLayoutConstraint.activate([
            urlBar.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            urlBar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            urlBar.trailingAnchor.constraint(equalTo: goBtn.leadingAnchor, constant: -4),
            urlBar.heightAnchor.constraint(equalToConstant: 28),

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

        // Wire up Go button after super.init()
        goBtn.target = self
        goBtn.action = #selector(goButtonAction(_:))

        win.delegate = self
        self.webView.navigationDelegate = self

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
        onEvent = nil
        onWindowClose = nil
        navigationContinuation = nil
        let continuations = idleContinuations
        idleContinuations.removeAll()
        for (_, c) in continuations {
            c.resume(throwing: BrowserError.tabNotFound(tabId))
        }
        webView.stopLoading()
        webView.navigationDelegate = nil
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

    func screenshot(quality: Int = 70, width: Int = 1440) async throws -> String {
        let config = WKSnapshotConfiguration()
        config.snapshotWidth = NSNumber(value: width)

        let image = try await webView.takeSnapshot(configuration: config)

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw BrowserError.screenshotFailed("Failed to create CGImage")
        }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let compressionFactor = Double(quality) / 100.0

        // Encode JPEG off main thread
        let base64 = try await Task.detached {
            guard let jpegData = bitmap.representation(
                using: .jpeg,
                properties: [.compressionFactor: compressionFactor]
            ) else {
                throw BrowserError.screenshotFailed("Failed to encode JPEG")
            }
            return jpegData.base64EncodedString()
        }.value

        return base64
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
