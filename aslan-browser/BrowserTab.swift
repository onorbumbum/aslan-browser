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

    init(isHidden: Bool = false) {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true

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
    }

    // MARK: - Navigate

    func navigate(to urlString: String) async throws -> NavigationResult {
        guard let url = URL(string: urlString) else {
            throw BrowserError.invalidURL(urlString)
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.navigationContinuation = continuation
            self.webView.load(URLRequest(url: url))
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
