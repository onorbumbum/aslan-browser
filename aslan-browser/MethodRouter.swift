//
//  MethodRouter.swift
//  aslan-browser
//

import Foundation
import WebKit

@MainActor
class MethodRouter {

    private let tab: BrowserTab

    init(tab: BrowserTab) {
        self.tab = tab
    }

    func dispatch(_ method: String, params: [String: Any]?) async throws -> Any {
        switch method {
        case "navigate":
            return try await handleNavigate(params)
        case "evaluate":
            return try await handleEvaluate(params)
        case "screenshot":
            return try await handleScreenshot(params)
        case "getTitle":
            return try await handleGetTitle()
        case "getURL":
            return try await handleGetURL()
        case "waitForSelector":
            return try await handleWaitForSelector(params)
        case "getAccessibilityTree":
            return try await handleGetAccessibilityTree()
        case "click":
            return try await handleClick(params)
        case "fill":
            return try await handleFill(params)
        case "select":
            return try await handleSelect(params)
        case "keypress":
            return try await handleKeypress(params)
        case "scroll":
            return try await handleScroll(params)
        default:
            throw RPCError.methodNotFound(method)
        }
    }

    // MARK: - Method Handlers

    private func handleNavigate(_ params: [String: Any]?) async throws -> [String: Any] {
        guard let url = params?["url"] as? String else {
            throw RPCError.invalidParams("Missing required param: url")
        }

        let waitUntilStr = params?["waitUntil"] as? String ?? "load"
        let waitUntil = BrowserTab.WaitUntil(rawValue: waitUntilStr) ?? .load
        let timeout = params?["timeout"] as? Int ?? 30000

        let result = try await tab.navigate(to: url, waitUntil: waitUntil, timeout: timeout)
        return ["url": result.url, "title": result.title]
    }

    private func handleEvaluate(_ params: [String: Any]?) async throws -> [String: Any] {
        guard let script = params?["script"] as? String else {
            throw RPCError.invalidParams("Missing required param: script")
        }

        let args = params?["args"] as? [String: Any]
        let result = try await tab.evaluate(script, args: args)

        if let result {
            return ["value": result]
        } else {
            return ["value": NSNull()]
        }
    }

    private func handleScreenshot(_ params: [String: Any]?) async throws -> [String: Any] {
        let quality = params?["quality"] as? Int ?? 70
        let width = params?["width"] as? Int ?? 1440

        let base64 = try await tab.screenshot(quality: quality, width: width)
        return ["data": base64]
    }

    private func handleGetTitle() async throws -> [String: Any] {
        let title = try await tab.evaluate("return document.title") as? String ?? ""
        return ["title": title]
    }

    private func handleGetURL() async throws -> [String: Any] {
        let url = tab.webView.url?.absoluteString ?? ""
        return ["url": url]
    }

    private func handleGetAccessibilityTree() async throws -> [String: Any] {
        let nodes = try await tab.getAccessibilityTree()
        return ["tree": nodes]
    }

    private func handleClick(_ params: [String: Any]?) async throws -> [String: Any] {
        guard let selector = params?["selector"] as? String else {
            throw RPCError.invalidParams("Missing required param: selector")
        }
        try await tab.click(target: selector)
        return ["ok": true]
    }

    private func handleFill(_ params: [String: Any]?) async throws -> [String: Any] {
        guard let selector = params?["selector"] as? String else {
            throw RPCError.invalidParams("Missing required param: selector")
        }
        guard let value = params?["value"] as? String else {
            throw RPCError.invalidParams("Missing required param: value")
        }
        try await tab.fill(target: selector, value: value)
        return ["ok": true]
    }

    private func handleSelect(_ params: [String: Any]?) async throws -> [String: Any] {
        guard let selector = params?["selector"] as? String else {
            throw RPCError.invalidParams("Missing required param: selector")
        }
        guard let value = params?["value"] as? String else {
            throw RPCError.invalidParams("Missing required param: value")
        }
        try await tab.select(target: selector, value: value)
        return ["ok": true]
    }

    private func handleKeypress(_ params: [String: Any]?) async throws -> [String: Any] {
        guard let key = params?["key"] as? String else {
            throw RPCError.invalidParams("Missing required param: key")
        }
        let modifiers = params?["modifiers"] as? [String: Bool]
        try await tab.keypress(key: key, modifiers: modifiers)
        return ["ok": true]
    }

    private func handleScroll(_ params: [String: Any]?) async throws -> [String: Any] {
        let x = params?["x"] as? Double ?? 0
        let y = params?["y"] as? Double ?? 0
        let selector = params?["selector"] as? String
        try await tab.scroll(x: x, y: y, target: selector)
        return ["ok": true]
    }

    private func handleWaitForSelector(_ params: [String: Any]?) async throws -> [String: Any] {
        guard let selector = params?["selector"] as? String else {
            throw RPCError.invalidParams("Missing required param: selector")
        }

        let timeout = params?["timeout"] as? Int ?? 5000

        try await tab.waitForSelector(selector, timeout: timeout)
        return ["found": true]
    }
}
