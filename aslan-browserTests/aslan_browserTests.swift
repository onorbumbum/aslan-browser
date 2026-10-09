//
//  aslan_browserTests.swift
//  aslan-browserTests
//
//  Created by Onor Bumbum on 2/18/26.
//

import AppKit
import WebKit
import Testing
@testable import aslan_browser

struct aslan_browserTests {

    @Test @MainActor func newTabsIdentifyAsSafariBeforeNavigation() throws {
        let tab = BrowserTab(tabId: "user-agent-test", isHidden: true)
        defer { tab.window.close() }
        let agent = try #require(tab.webView.customUserAgent)
        #expect(agent.contains("AppleWebKit/605.1.15"))
        #expect(agent.contains("Version/"))
        #expect(agent.contains("Safari/605.1.15"))
        #expect(!agent.contains("Chrome/"))
    }

}
