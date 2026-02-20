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

        setupMainMenu()

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

    // MARK: - Main Menu

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // ── App menu ──
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "About Aslan Browser", action: #selector(showAboutPanel), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Aslan Browser", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu

        // ── Edit menu ──
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu

        // ── View menu ──
        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(NSMenuItem(title: "Focus Address Bar", action: #selector(focusAddressBar), keyEquivalent: "l"))
        viewMenuItem.submenu = viewMenu

        NSApp.mainMenu = mainMenu
        NSLog("[aslan-browser] Main menu set with \(NSApp.mainMenu?.items.count ?? 0) items")
    }

    @objc private func focusAddressBar() {
        // Find the BrowserTab that owns the current key window
        guard let keyWindow = NSApp.keyWindow else { return }
        if let tab = tabManager?.tabForWindow(keyWindow) {
            tab.focusURLBar()
        }
    }

    @objc private func showAboutPanel() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"

        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: "Aslan Browser",
            .applicationVersion: version,
            .version: "Build \(build)",
            .credits: NSAttributedString(
                string: "AI-powered browser for ASLAN\n© 2025 Uzunu",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            )
        ])
    }
}
