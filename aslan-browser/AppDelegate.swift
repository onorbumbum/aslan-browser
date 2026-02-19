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
    private var socketServer: SocketServer?

    private let socketPath = "/tmp/aslan-browser.sock"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[aslan-browser] launched (hidden: \(isHidden))")

        let browserTab = BrowserTab(isHidden: isHidden)
        self.tab = browserTab

        let router = MethodRouter(tab: browserTab)
        let server = SocketServer(socketPath: socketPath, router: router)
        self.socketServer = server

        do {
            try server.start()
        } catch {
            NSLog("[aslan-browser] Failed to start socket server: \(error)")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ application: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        socketServer?.stop()
    }
}
