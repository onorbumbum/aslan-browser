//
//  TabInfo.swift
//  aslan-browser
//

import Foundation

struct TabInfo {
    let tabId: String
    let url: String
    let title: String

    var dict: [String: Any] {
        ["tabId": tabId, "url": url, "title": title]
    }
}
