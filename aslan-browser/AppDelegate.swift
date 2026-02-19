//
//  AppDelegate.swift
//  aslan-browser
//

import AppKit
import Foundation

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    static func main() {
        // Disable window state restoration to suppress
        // "Unable to find className=(null)" warning
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    var isHidden: Bool {
        CommandLine.arguments.contains("--hidden")
    }

    private var tabManager: TabManager?
    private var socketServer: SocketServer?

    private let socketPath = "/tmp/aslan-browser.sock"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[aslan-browser] launched (hidden: \(isHidden))")

        let tabManager = TabManager(isHidden: isHidden)
        tabManager.createTab() // default tab0
        self.tabManager = tabManager

        let router = MethodRouter(tabManager: tabManager)
        let server = SocketServer(socketPath: socketPath, router: router)
        self.socketServer = server

        tabManager.broadcastEvent = { [weak server] method, params in
            server?.broadcast(method: method, params: params)
        }

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
