//
//  TabManager.swift
//  aslan-browser
//

import AppKit
import WebKit

@MainActor
class TabManager {

    struct Session {
        let sessionId: String
        let name: String
    }

    private var tabs: [String: BrowserTab] = [:]
    private var nextId: Int = 0
    private let isHidden: Bool
    private var closingTabs: [BrowserTab] = [] // Prevent premature dealloc during window close

    let learnRecorder = LearnRecorder()

    // Session tracking
    private var sessions: [String: Session] = [:]
    private var nextSessionId: Int = 0

    /// Callback for broadcasting events to all connected clients
    var broadcastEvent: ((_ method: String, _ params: [String: Any]) -> Void)?

    init(isHidden: Bool) {
        self.isHidden = isHidden
    }

    // MARK: - Sessions

    func createSession(name: String? = nil) -> String {
        let sessionId = "s\(nextSessionId)"
        nextSessionId += 1
        sessions[sessionId] = Session(sessionId: sessionId, name: name ?? sessionId)
        return sessionId
    }

    func destroySession(id: String) throws -> [String] {
        guard sessions.removeValue(forKey: id) != nil else {
            throw BrowserError.sessionNotFound(id)
        }
        let tabIds = tabs.filter { $0.value.sessionId == id }.map { $0.key }
        for tabId in tabIds {
            try closeTab(id: tabId)
        }
        return tabIds
    }

    // MARK: - Tabs

    @discardableResult
    func createTab(width: Int = 1440, height: Int = 900, hidden: Bool? = nil, sessionId: String? = nil) -> String {
        let tabId = "tab\(nextId)"
        nextId += 1

        let tab = BrowserTab(
            tabId: tabId,
            width: width,
            height: height,
            isHidden: hidden ?? isHidden
        )
        tab.onEvent = { [weak self] method, params in
            self?.broadcastEvent?(method, params)
        }
        tab.onWindowClose = { [weak self] tabId in
            try? self?.closeTab(id: tabId)
        }
        tab.sessionId = sessionId
        tab.learnRecorder = learnRecorder
        tabs[tabId] = tab

        if learnRecorder.state == .recording {
            let _ = learnRecorder.addAction(
                ["type": "tab.created", "url": "", "pageTitle": ""],
                screenshotData: nil,
                tabId: tabId
            )
            tab.startLearnMode()
            tab.setRecordingUI(active: true)
        }

        return tabId
    }

    func closeTab(id: String) throws {
        guard let tab = tabs.removeValue(forKey: id) else {
            throw BrowserError.tabNotFound(id)
        }

        if learnRecorder.state == .recording {
            let url = tab.webView.url?.absoluteString ?? ""
            let title = tab.webView.title ?? ""
            let _ = learnRecorder.addAction(
                ["type": "tab.closed", "url": url, "pageTitle": title],
                screenshotData: nil,
                tabId: id
            )
        }

        tab.cleanup()
        tab.window.animationBehavior = .none
        tab.window.orderOut(nil)

        // Keep tab alive until the next runloop cycle to avoid
        // use-after-free in NSWindowTransformAnimation dealloc
        closingTabs.append(tab)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            self?.closingTabs.removeAll { $0 === tab }
        }
    }

    func getTab(id: String) throws -> BrowserTab {
        guard let tab = tabs[id] else {
            throw BrowserError.tabNotFound(id)
        }
        return tab
    }

    // MARK: - Learn Mode

    func startLearnMode(name: String) throws -> [String: Any] {
        let screenshotDir = try learnRecorder.start(name: name)
        for tab in tabs.values {
            tab.startLearnMode()
            tab.setRecordingUI(active: true)
        }
        return ["ok": true, "name": name, "screenshotDir": screenshotDir]
    }

    func stopLearnMode() throws -> [String: Any] {
        let result = try learnRecorder.stop()
        for tab in tabs.values {
            tab.stopLearnMode()
            tab.setRecordingUI(active: false)
        }
        return result
    }

    func tabForWindow(_ window: NSWindow) -> BrowserTab? {
        return tabs.values.first { $0.window === window }
    }

    func listTabs(sessionId: String? = nil) -> [TabInfo] {
        let filtered = sessionId == nil ? tabs : tabs.filter { $0.value.sessionId == sessionId }
        return filtered.map { (id, tab) in
            TabInfo(
                tabId: id,
                url: tab.webView.url?.absoluteString ?? "",
                title: tab.webView.title ?? ""
            )
        }.sorted { $0.tabId < $1.tabId }
    }
}
