//
//  TabInfo.swift
//  aslan-browser
//

import Foundation

struct TabInfo {
    let tabId: String
    let url: String
    let title: String
    let sessionId: String?
    let sessionName: String?

    var dict: [String: Any] {
        var result: [String: Any] = ["tabId": tabId, "url": url, "title": title]
        if let sessionId {
            result["sessionId"] = sessionId
        }
        if let sessionName {
            result["sessionName"] = sessionName
        }
        return result
    }
}
