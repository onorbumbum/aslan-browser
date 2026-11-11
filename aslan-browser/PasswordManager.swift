//
//  PasswordManager.swift
//  aslan-browser
//
//  User-initiated login autofill backed by the Bitwarden CLI (`bw`).
//  The vault session key lives only in memory; it is never written to disk,
//  passed in argv, or exposed over the agent JSON-RPC socket.
//

import AppKit
import WebKit

struct SavedLogin {
    let name: String
    let username: String
    let password: String
}

enum PasswordManagerError: LocalizedError {
    case cliNotFound
    case cliFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .cliNotFound:
            return "Bitwarden CLI (bw) or Node.js was not found. Install it with `npm i -g @bitwarden/cli` and log in with `bw login`."
        case .cliFailed(let message):
            return message
        case .cancelled:
            return "Cancelled"
        }
    }
}

@MainActor
final class PasswordManager {

    static let shared = PasswordManager()

    private var sessionKey: String?
    private var unlockTask: Task<String, Error>?

    var isUnlocked: Bool { sessionKey != nil }

    func lock() {
        sessionKey = nil
        unlockTask?.cancel()
        unlockTask = nil
    }

    // MARK: - Public entry point

    /// Look up logins for the tab's current page and fill one (asking which if several).
    func fill(in tab: BrowserTab, anchor: NSView?) async {
        NSLog("[aslan-browser] Fill Password requested for \(tab.tabId) (unlocked: \(isUnlocked))")
        guard let url = tab.webView.url, let scheme = url.scheme, scheme.hasPrefix("http") else {
            NSSound.beep()
            return
        }

        do {
            var logins: [SavedLogin]
            do {
                let session = try await ensureUnlocked(window: tab.window)
                logins = try await self.logins(for: url, session: session)
            } catch PasswordManagerError.cliFailed(let message) where message.localizedCaseInsensitiveContains("locked") {
                // Session expired out from under us — unlock again once.
                lock()
                let session = try await ensureUnlocked(window: tab.window)
                logins = try await self.logins(for: url, session: session)
            }

            guard !logins.isEmpty else {
                showMessage("No saved login for \(url.host ?? url.absoluteString)",
                            info: "Add one in Bitwarden, then choose Fill Password again. (Lock Passwords forces a fresh sync.)",
                            window: tab.window)
                return
            }

            let chosen: SavedLogin?
            if logins.count == 1 {
                chosen = logins[0]
            } else {
                chosen = chooseLogin(from: logins, anchor: anchor ?? tab.webView)
            }
            guard let login = chosen else { return }

            let result = try await Self.fillPage(tab.webView, login: login)
            if result == "none" {
                showMessage("No login field found on this page",
                            info: "Click into the username or password field and try again.",
                            window: tab.window)
            }
        } catch PasswordManagerError.cancelled {
            return
        } catch {
            NSLog("[aslan-browser] Fill Password failed: \(error.localizedDescription)")
            showMessage("Couldn't fill password", info: error.localizedDescription, window: tab.window)
        }
    }

    // MARK: - Unlock

    private func ensureUnlocked(window: NSWindow) async throws -> String {
        if let sessionKey { return sessionKey }
        if let unlockTask { return try await unlockTask.value }

        let task = Task<String, Error> { @MainActor in
            defer { self.unlockTask = nil }
            var errorText: String?
            while true {
                guard let password = await self.promptForMasterPassword(window: window, error: errorText) else {
                    throw PasswordManagerError.cancelled
                }
                let result = try await Self.runCLI(["unlock", "--raw", "--passwordenv", "ASLAN_BW_PASSWORD"],
                                                   extraEnv: ["ASLAN_BW_PASSWORD": password])
                let key = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                if result.status == 0, !key.isEmpty {
                    self.sessionKey = key
                    // Pull the latest vault; a failed sync still leaves the cached vault usable.
                    let sync = try? await Self.runCLI(["sync"], session: key)
                    if let sync, sync.status != 0 {
                        NSLog("[aslan-browser] bw sync failed: \(sync.stderr)")
                    }
                    return key
                }
                let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                if message.localizedCaseInsensitiveContains("not logged in") {
                    throw PasswordManagerError.cliFailed("Bitwarden CLI is not logged in. Run `bw login` in Terminal first.")
                }
                errorText = message.isEmpty ? "Unlock failed." : message
            }
        }
        unlockTask = task
        return try await task.value
    }

    private func promptForMasterPassword(window: NSWindow, error: String?) async -> String? {
        let alert = NSAlert()
        alert.messageText = "Unlock Bitwarden"
        alert.informativeText = error.map { "\($0)\n\nEnter your Bitwarden master password." }
            ?? "Enter your Bitwarden master password to fill saved logins. Aslan keeps the vault unlocked until you quit or choose Edit ▸ Lock Passwords."
        alert.addButton(withTitle: "Unlock")
        alert.addButton(withTitle: "Cancel")

        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "Master password"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        NSLog("[aslan-browser] Showing Bitwarden unlock prompt")
        window.makeKeyAndOrderFront(nil)
        let response: NSApplication.ModalResponse = await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { continuation.resume(returning: $0) }
        }
        let password = field.stringValue
        field.stringValue = ""
        guard response == .alertFirstButtonReturn, !password.isEmpty else { return nil }
        return password
    }

    // MARK: - Lookup

    private func logins(for url: URL, session: String) async throws -> [SavedLogin] {
        let result = try await Self.runCLI(["list", "items", "--url", url.absoluteString], session: session)
        guard result.status == 0 else {
            throw PasswordManagerError.cliFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard let data = result.stdout.data(using: .utf8),
              let items = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw PasswordManagerError.cliFailed("Unexpected output from bw list items.")
        }
        return items.compactMap { item in
            guard let login = item["login"] as? [String: Any] else { return nil }
            let username = login["username"] as? String ?? ""
            let password = login["password"] as? String ?? ""
            if username.isEmpty && password.isEmpty { return nil }
            return SavedLogin(name: item["name"] as? String ?? "", username: username, password: password)
        }
    }

    private func chooseLogin(from logins: [SavedLogin], anchor: NSView) -> SavedLogin? {
        let menu = NSMenu()
        menu.autoenablesItems = false
        var picked: SavedLogin?
        let handler = MenuActionHandler { index in picked = logins[index] }
        for (index, login) in logins.enumerated() {
            let title = login.username.isEmpty ? login.name : login.username
            let item = NSMenuItem(title: title, action: #selector(MenuActionHandler.select(_:)), keyEquivalent: "")
            item.target = handler
            item.tag = index
            if !login.name.isEmpty, login.name != title {
                item.toolTip = login.name
            }
            menu.addItem(item)
        }
        // popUp blocks until the menu is dismissed, so `picked` is set synchronously.
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.height + 4), in: anchor)
        withExtendedLifetime(handler) {}
        return picked
    }

    private func showMessage(_ message: String, info: String, window: NSWindow) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        alert.beginSheetModal(for: window)
    }

    // MARK: - Page filling

    /// Runs in an isolated content world so page scripts can't hook the fill code.
    private static let fillScript = """
    const isVisible = (el) => {
        if (!el || el.disabled || el.readOnly) return false;
        const style = getComputedStyle(el);
        if (style.visibility === 'hidden' || style.display === 'none') return false;
        const r = el.getBoundingClientRect();
        return r.width > 0 && r.height > 0;
    };
    const setValue = (el, value) => {
        el.focus();
        const proto = Object.getPrototypeOf(el);
        const desc = Object.getOwnPropertyDescriptor(proto, 'value')
            || Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
        desc.set.call(el, value);
        el.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertReplacementText', data: value }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
    };
    const userTypes = ['text', 'email', 'tel', ''];
    const looksLikeUser = (el) => {
        const t = (el.getAttribute('type') || '').toLowerCase();
        if (!userTypes.includes(t)) return false;
        const hint = [el.name, el.id, el.autocomplete, el.placeholder, el.getAttribute('aria-label')]
            .join(' ').toLowerCase();
        if (/search|query|filter/.test(hint)) return false;
        return /user|email|login|account|identifier|phone|name/.test(hint) || t === 'email';
    };
    // Username-only pages (multi-step logins) need a stronger signal than a loose hint.
    const strongUser = (el) => {
        if (!looksLikeUser(el)) return false;
        const ac = (el.autocomplete || '').toLowerCase();
        const t = (el.getAttribute('type') || '').toLowerCase();
        const key = [el.name, el.id].join(' ').toLowerCase();
        return /username|email/.test(ac) || t === 'email' || /user|email|login|identifier/.test(key);
    };

    const inputs = Array.from(document.querySelectorAll('input')).filter(isVisible);
    const active = document.activeElement;
    const passwords = inputs.filter(el => (el.type || '').toLowerCase() === 'password');

    let pass = passwords.includes(active) ? active : passwords[0] || null;
    let user = null;
    if (pass) {
        const scope = pass.form ? Array.from(pass.form.querySelectorAll('input')).filter(isVisible) : inputs;
        const before = scope.slice(0, scope.indexOf(pass)).filter(el => userTypes.includes((el.getAttribute('type') || '').toLowerCase()));
        user = before.reverse().find(looksLikeUser) || before[0] || null;
    } else {
        const candidates = inputs.filter(el => userTypes.includes((el.getAttribute('type') || '').toLowerCase()));
        user = (candidates.includes(active) && looksLikeUser(active) && active) || candidates.find(strongUser) || null;
    }

    if (user && username) setValue(user, username);
    if (pass && password) setValue(pass, password);
    if (pass) pass.focus(); else if (user) user.focus();
    return pass && user ? 'both' : pass ? 'password' : user ? 'username' : 'none';
    """

    static func fillPage(_ webView: WKWebView, login: SavedLogin) async throws -> String {
        let result = try await webView.callAsyncJavaScript(
            fillScript,
            arguments: ["username": login.username, "password": login.password],
            in: nil,
            contentWorld: .defaultClient
        )
        return result as? String ?? "none"
    }

    // MARK: - CLI

    private struct CLIResult {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    /// GUI apps don't inherit the shell PATH, so locate `bw` and `node` explicitly.
    private static func locateCLI() -> (bw: String, path: String)? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let bwCandidates = [
            "\(home)/Library/pnpm/bw",
            "/opt/homebrew/bin/bw",
            "/usr/local/bin/bw",
            "\(home)/.npm-global/bin/bw",
        ]
        guard let bw = bwCandidates.first(where: { fm.isExecutableFile(atPath: $0) }) else { return nil }

        var dirs = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", (bw as NSString).deletingLastPathComponent]
        let nvmRoot = "\(home)/.nvm/versions/node"
        if let versions = try? fm.contentsOfDirectory(atPath: nvmRoot) {
            let sorted = versions.sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            if let newest = sorted.first(where: { fm.isExecutableFile(atPath: "\(nvmRoot)/\($0)/bin/node") }) {
                dirs.insert("\(nvmRoot)/\(newest)/bin", at: 0)
            }
        }
        guard dirs.contains(where: { fm.isExecutableFile(atPath: "\($0)/node") })
                || bw.hasPrefix("/opt/homebrew") || bw.hasPrefix("/usr/local") else { return nil }
        return (bw, dirs.joined(separator: ":"))
    }

    private static func runCLI(_ args: [String], session: String? = nil, extraEnv: [String: String] = [:]) async throws -> CLIResult {
        guard let cli = locateCLI() else { throw PasswordManagerError.cliNotFound }

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = cli.path
        env["BW_NOINTERACTION"] = "true"
        env["NODE_NO_WARNINGS"] = "1"
        if let session { env["BW_SESSION"] = session }
        for (k, v) in extraEnv { env[k] = v }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: cli.bw)
                process.arguments = args
                process.environment = env
                let out = Pipe(), err = Pipe()
                process.standardOutput = out
                process.standardError = err
                process.standardInput = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                // Drain stderr concurrently so a full pipe can't deadlock the child.
                var errData = Data()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    errData = err.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                let outData = out.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                process.waitUntilExit()
                continuation.resume(returning: CLIResult(
                    status: process.terminationStatus,
                    stdout: String(decoding: outData, as: UTF8.self),
                    stderr: String(decoding: errData, as: UTF8.self)
                ))
            }
        }
    }
}

private final class MenuActionHandler: NSObject {
    private let onSelect: (Int) -> Void
    init(onSelect: @escaping (Int) -> Void) { self.onSelect = onSelect }
    @objc func select(_ sender: NSMenuItem) { onSelect(sender.tag) }
}
