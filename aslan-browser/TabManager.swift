//
//  TabManager.swift
//  aslan-browser
//

import AppKit
import WebKit

@MainActor
class TabManager {

    private var tabs: [String: BrowserTab] = [:]
    private var nextId: Int = 0
    private let isHidden: Bool
    private var closingTabs: [BrowserTab] = [] // Prevent premature dealloc during window close

    /// Callback for broadcasting events to all connected clients
    var broadcastEvent: ((_ method: String, _ params: [String: Any]) -> Void)?

    init(isHidden: Bool) {
        self.isHidden = isHidden
    }

    @discardableResult
    func createTab(width: Int = 1440, height: Int = 900, hidden: Bool? = nil) -> String {
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
        tabs[tabId] = tab
        return tabId
    }

    func closeTab(id: String) throws {
        guard let tab = tabs.removeValue(forKey: id) else {
            throw BrowserError.tabNotFound(id)
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

    func listTabs() -> [TabInfo] {
        tabs.map { (id, tab) in
            TabInfo(
                tabId: id,
                url: tab.webView.url?.absoluteString ?? "",
                title: tab.webView.title ?? ""
            )
        }.sorted { $0.tabId < $1.tabId }
    }
}
