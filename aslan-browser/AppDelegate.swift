//
//  AppDelegate.swift
//  aslan-browser
//

import AppKit
import Foundation

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    var isHidden: Bool {
        CommandLine.arguments.contains("--hidden")
    }

    private var tab: BrowserTab?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[aslan-browser] launched (hidden: \(isHidden))")

        Task { @MainActor in
            await self.runSmokeTest()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ application: NSApplication) -> Bool {
        return false
    }

    /// Temporary smoke test to verify Phase 1 functionality.
    /// Will be removed or replaced in Phase 2 when the socket server is added.
    @MainActor
    private func runSmokeTest() async {
        let browserTab = BrowserTab(isHidden: isHidden)
        self.tab = browserTab

        do {
            let result = try await browserTab.navigate(to: "https://example.com")
            NSLog("[aslan-browser] Navigated — URL: \(result.url), Title: \(result.title)")

            let titleResult = try await browserTab.evaluate("return document.title")
            NSLog("[aslan-browser] JS eval — title: \(titleResult ?? "nil")")

            // Brief wait to ensure rendering is complete
            try await Task.sleep(nanoseconds: 1_000_000_000)

            let base64 = try await browserTab.screenshot()
            guard let jpegData = Data(base64Encoded: base64) else {
                NSLog("[aslan-browser] Failed to decode base64 screenshot")
                return
            }

            let path = NSTemporaryDirectory() + "aslan-screenshot.jpg"
            try jpegData.write(to: URL(fileURLWithPath: path))
            NSLog("[aslan-browser] Screenshot saved to \(path) (\(jpegData.count) bytes)")
        } catch {
            NSLog("[aslan-browser] Smoke test error: \(error)")
        }
    }
}
