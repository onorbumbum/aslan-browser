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
class BrowserTab: NSObject, WKNavigationDelegate {

    let webView: WKWebView
    let window: NSWindow

    private var navigationContinuation: CheckedContinuation<NavigationResult, Error>?
    private var messageHandler: ScriptMessageHandler?

    // Readiness tracking
    private var didFinishNavigation = false
    private var domStable = false
    private var networkIdle = true  // starts idle (no pending requests)
    private var readyStateComplete = false
    private var idleContinuations: [Int: CheckedContinuation<Void, Error>] = [:]
    private var nextIdleContinuationId = 0

    init(isHidden: Bool = false) {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.userContentController.addUserScript(ScriptBridge.makeUserScript())

        let frame = NSRect(x: 0, y: 0, width: 1440, height: 900)

        let wv = WKWebView(frame: frame, configuration: config)
        self.webView = wv

        let win = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        win.contentView = wv

        if isHidden {
            win.orderOut(nil)
        } else {
            win.makeKeyAndOrderFront(nil)
        }

        self.window = win

        super.init()
        self.webView.navigationDelegate = self

        let handler = ScriptMessageHandler { [weak self] body in
            Task { @MainActor in
                self?.handleScriptMessage(body)
            }
        }
        self.messageHandler = handler
        config.userContentController.add(handler, name: "agent")
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

    // MARK: - WKNavigationDelegate

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.didFinishNavigation = true
            self.readyStateComplete = true // didFinish implies readyState complete
            self.checkIdleAndResume()

            let url = webView.url?.absoluteString ?? ""
            let title = webView.title ?? ""
            let result = NavigationResult(url: url, title: title)
            self.navigationContinuation?.resume(returning: result)
            self.navigationContinuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.navigationContinuation?.resume(throwing: BrowserError.navigationFailed(error.localizedDescription))
            self.navigationContinuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
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
