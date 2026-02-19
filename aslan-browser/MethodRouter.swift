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
        default:
            throw RPCError.methodNotFound(method)
        }
    }

    // MARK: - Method Handlers

    private func handleNavigate(_ params: [String: Any]?) async throws -> [String: Any] {
        guard let url = params?["url"] as? String else {
            throw RPCError.invalidParams("Missing required param: url")
        }

        let result = try await tab.navigate(to: url)
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
}
