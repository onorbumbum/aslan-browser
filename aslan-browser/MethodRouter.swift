//
//  MethodRouter.swift
//  aslan-browser
//

import Foundation
import WebKit

@MainActor
class MethodRouter {

    private let tabManager: TabManager

    init(tabManager: TabManager) {
        self.tabManager = tabManager
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
            return try await handleGetTitle(params)
        case "getURL":
            return try await handleGetURL(params)
        case "waitForSelector":
            return try await handleWaitForSelector(params)
        case "getAccessibilityTree":
            return try await handleGetAccessibilityTree(params)
        case "click":
            return try await handleClick(params)
        case "uploadFile":
            return try await handleUploadFile(params)
        case "fill":
            return try await handleFill(params)
        case "select":
            return try await handleSelect(params)
        case "keypress":
            return try await handleKeypress(params)
        case "scroll":
            return try await handleScroll(params)
        case "goBack":
            return try await handleGoBack(params)
        case "goForward":
            return try await handleGoForward(params)
        case "reload":
            return try await handleReload(params)
        case "getCookies":
            return try await handleGetCookies(params)
        case "setCookie":
            return try await handleSetCookie(params)
        case "tab.create":
            return try await handleTabCreate(params)
        case "tab.close":
            return try handleTabClose(params)
        case "tab.list":
            return handleTabList(params)
        case "session.create":
            return handleSessionCreate(params)
        case "session.use":
            return try handleSessionUse(params)
        case "session.list":
            return handleSessionList(params)
        case "session.destroy":
            return try handleSessionDestroy(params)
        case "batch":
            return try await handleBatch(params)
        case "learn.start":
            return try handleLearnStart(params)
        case "learn.stop":
            return try handleLearnStop(params)
        case "learn.status":
            return handleLearnStatus(params)
        case "learn.note":
            return try handleLearnNote(params)
        default:
            throw RPCError.methodNotFound(method)
        }
    }

    // MARK: - Tab Resolution

    private func resolveTab(_ params: [String: Any]?) throws -> BrowserTab {
        let tabId = params?["tabId"] as? String ?? "tab0"
        return try tabManager.getTab(id: tabId)
    }

    // MARK: - Method Handlers

    private func handleNavigate(_ params: [String: Any]?) async throws -> [String: Any] {
        let tab = try resolveTab(params)

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
        let tab = try resolveTab(params)

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

    private func handleUploadFile(_ params: [String: Any]?) async throws -> [String: Any] {
        let tab = try resolveTab(params)
        guard let selector = params?["selector"] as? String else {
            throw RPCError.invalidParams("Missing required param: selector")
        }
        if let path = params?["path"] as? String {
            return try await tab.uploadFileViaOpenPanel(target: selector, paths: [path])
        }
        if let paths = params?["paths"] as? [String] {
            return try await tab.uploadFileViaOpenPanel(target: selector, paths: paths)
        }
        throw RPCError.invalidParams("Missing required param: path or paths")
    }

    private func handleScreenshot(_ params: [String: Any]?) async throws -> [String: Any] {
        let tab = try resolveTab(params)

        let quality = params?["quality"] as? Int ?? 70
        let width = params?["width"] as? Int ?? 1440
        let format = params?["format"] as? String ?? "jpeg"
        let viewportWidth = params?["viewportWidth"] as? Int
        let viewportHeight = params?["viewportHeight"] as? Int
        let fullPage = params?["fullPage"] as? Bool ?? false

        guard format == "jpeg" || format == "png" else {
            throw RPCError.invalidParams("format must be \"jpeg\" or \"png\"")
        }
        if fullPage && viewportHeight != nil {
            throw RPCError.invalidParams("fullPage and viewportHeight are mutually exclusive")
        }
        if let w = viewportWidth, !(1...7680).contains(w) {
            throw RPCError.invalidParams("viewportWidth must be between 1 and 7680")
        }
        if let h = viewportHeight, !(1...BrowserTab.maxFullPageHeight).contains(h) {
            throw RPCError.invalidParams("viewportHeight must be between 1 and \(BrowserTab.maxFullPageHeight)")
        }

        let shot = try await tab.captureScreenshot(
            quality: quality, width: width, format: format,
            viewportWidth: viewportWidth, viewportHeight: viewportHeight, fullPage: fullPage
        )
        // format/width/height let clients detect an app too old to honor the new params.
        return ["data": shot.base64, "format": format, "width": shot.width, "height": shot.height]
    }

    private func handleGetTitle(_ params: [String: Any]?) async throws -> [String: Any] {
        let tab = try resolveTab(params)
        let title = try await tab.evaluate("return document.title") as? String ?? ""
        return ["title": title]
    }

    private func handleGetURL(_ params: [String: Any]?) async throws -> [String: Any] {
        let tab = try resolveTab(params)
        let url = tab.webView.url?.absoluteString ?? ""
        return ["url": url]
    }

    private func handleGetAccessibilityTree(_ params: [String: Any]?) async throws -> [String: Any] {
        let tab = try resolveTab(params)
        let nodes = try await tab.getAccessibilityTree()
        return ["tree": nodes]
    }

    private func handleClick(_ params: [String: Any]?) async throws -> [String: Any] {
        let tab = try resolveTab(params)

        guard let selector = params?["selector"] as? String else {
            throw RPCError.invalidParams("Missing required param: selector")
        }
        try await tab.click(target: selector)
        return ["ok": true]
    }

    private func handleFill(_ params: [String: Any]?) async throws -> [String: Any] {
        let tab = try resolveTab(params)

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
        let tab = try resolveTab(params)

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
        let tab = try resolveTab(params)

        guard let key = params?["key"] as? String else {
            throw RPCError.invalidParams("Missing required param: key")
        }
        let modifiers = params?["modifiers"] as? [String: Bool]
        try await tab.keypress(key: key, modifiers: modifiers)
        return ["ok": true]
    }

    private func handleScroll(_ params: [String: Any]?) async throws -> [String: Any] {
        let tab = try resolveTab(params)

        let x = params?["x"] as? Double ?? 0
        let y = params?["y"] as? Double ?? 0
        let selector = params?["selector"] as? String
        try await tab.scroll(x: x, y: y, target: selector)
        return ["ok": true]
    }

    private func handleWaitForSelector(_ params: [String: Any]?) async throws -> [String: Any] {
        let tab = try resolveTab(params)

        guard let selector = params?["selector"] as? String else {
            throw RPCError.invalidParams("Missing required param: selector")
        }

        let timeout = params?["timeout"] as? Int ?? 5000

        try await tab.waitForSelector(selector, timeout: timeout)
        return ["found": true]
    }

    // MARK: - Navigation History

    private func handleGoBack(_ params: [String: Any]?) async throws -> [String: Any] {
        let tab = try resolveTab(params)
        let result = try await tab.goBack()
        return ["url": result.url, "title": result.title]
    }

    private func handleGoForward(_ params: [String: Any]?) async throws -> [String: Any] {
        let tab = try resolveTab(params)
        let result = try await tab.goForward()
        return ["url": result.url, "title": result.title]
    }

    private func handleReload(_ params: [String: Any]?) async throws -> [String: Any] {
        let tab = try resolveTab(params)
        let result = try await tab.reload()
        return ["url": result.url, "title": result.title]
    }

    // MARK: - Cookie Methods

    private func handleGetCookies(_ params: [String: Any]?) async throws -> [String: Any] {
        let tab = try resolveTab(params)
        let url = params?["url"] as? String
        let cookies = await tab.getCookies(url: url)
        return ["cookies": cookies]
    }

    private func handleSetCookie(_ params: [String: Any]?) async throws -> [String: Any] {
        let tab = try resolveTab(params)

        guard let name = params?["name"] as? String else {
            throw RPCError.invalidParams("Missing required param: name")
        }
        guard let value = params?["value"] as? String else {
            throw RPCError.invalidParams("Missing required param: value")
        }
        guard let domain = params?["domain"] as? String else {
            throw RPCError.invalidParams("Missing required param: domain")
        }

        let path = params?["path"] as? String ?? "/"
        let expires = params?["expires"] as? Double

        try await tab.setCookie(name: name, value: value, domain: domain, path: path, expires: expires)
        return ["ok": true]
    }

    // MARK: - Tab Methods

    private func handleTabCreate(_ params: [String: Any]?) async throws -> [String: Any] {
        let width = params?["width"] as? Int ?? 1440
        let height = params?["height"] as? Int ?? 900
        let hidden = params?["hidden"] as? Bool
        let sessionId = params?["sessionId"] as? String

        let tabId = tabManager.createTab(width: width, height: height, hidden: hidden, sessionId: sessionId)

        // If url provided, navigate after creation
        if let urlStr = params?["url"] as? String {
            let tab = try tabManager.getTab(id: tabId)
            _ = try await tab.navigate(to: urlStr)
        }

        return ["tabId": tabId]
    }

    private func handleTabClose(_ params: [String: Any]?) throws -> [String: Any] {
        guard let tabId = params?["tabId"] as? String else {
            throw RPCError.invalidParams("Missing required param: tabId")
        }
        try tabManager.closeTab(id: tabId)
        return ["ok": true]
    }

    private func handleTabList(_ params: [String: Any]?) -> [String: Any] {
        let sessionId = params?["sessionId"] as? String
        let tabs = tabManager.listTabs(sessionId: sessionId).map { $0.dict }
        return ["tabs": tabs]
    }

    // MARK: - Session Methods

    private func handleSessionCreate(_ params: [String: Any]?) -> [String: Any] {
        let name = params?["name"] as? String
        let sessionId = tabManager.createSession(name: name)
        return ["sessionId": sessionId, "name": name ?? sessionId]
    }

    private func handleSessionUse(_ params: [String: Any]?) throws -> [String: Any] {
        guard let name = params?["name"] as? String, !name.isEmpty else {
            throw RPCError.invalidParams("Missing required param: name")
        }
        let sessionId = tabManager.getOrCreateSession(name: name)
        return ["sessionId": sessionId, "name": name]
    }

    private func handleSessionList(_ params: [String: Any]?) -> [String: Any] {
        return ["sessions": tabManager.listSessions()]
    }

    private func handleSessionDestroy(_ params: [String: Any]?) throws -> [String: Any] {
        guard let idOrName = (params?["sessionId"] as? String) ?? (params?["name"] as? String) else {
            throw RPCError.invalidParams("Missing required param: sessionId")
        }
        guard let sessionId = tabManager.resolveSessionId(idOrName) else {
            throw BrowserError.sessionNotFound(idOrName)
        }
        let closedTabs = try tabManager.destroySession(id: sessionId)
        return ["ok": true, "sessionId": sessionId, "closedTabs": closedTabs]
    }

    // MARK: - Learn Mode

    private func handleLearnStart(_ params: [String: Any]?) throws -> [String: Any] {
        guard let name = params?["name"] as? String else {
            throw RPCError.invalidParams("Missing required param: name")
        }
        return try tabManager.startLearnMode(name: name)
    }

    private func handleLearnStop(_ params: [String: Any]?) throws -> [String: Any] {
        return try tabManager.stopLearnMode()
    }

    private func handleLearnStatus(_ params: [String: Any]?) -> [String: Any] {
        return tabManager.learnRecorder.status()
    }

    private func handleLearnNote(_ params: [String: Any]?) throws -> [String: Any] {
        guard let text = params?["text"] as? String else {
            throw RPCError.invalidParams("Missing required param: text")
        }
        guard tabManager.learnRecorder.state == .recording else {
            throw BrowserError.learnModeError("Not recording")
        }
        let seq = tabManager.learnRecorder.addAnnotation(text: text)
        return ["ok": true, "seq": seq]
    }

    // MARK: - Batch Operations

    private func handleBatch(_ params: [String: Any]?) async throws -> [String: Any] {
        guard let requests = params?["requests"] as? [[String: Any]] else {
            throw RPCError.invalidParams("Missing required param: requests (array)")
        }

        let responses = await withTaskGroup(of: (Int, [String: Any]).self) { group in
            for (index, req) in requests.enumerated() {
                group.addTask { @MainActor in
                    guard let method = req["method"] as? String else {
                        return (index, ["error": ["code": -32600, "message": "Missing method in batch request"]])
                    }

                    // Reject nested batch
                    if method == "batch" {
                        return (index, ["error": ["code": -32600, "message": "Nested batch not allowed"]])
                    }

                    let subParams = req["params"] as? [String: Any]
                    do {
                        let result = try await self.dispatch(method, params: subParams)
                        return (index, ["result": result])
                    } catch let err as RPCError {
                        return (index, ["error": ["code": err.code, "message": err.message]])
                    } catch let err as BrowserError {
                        let rpcErr = err.rpcError
                        return (index, ["error": ["code": rpcErr.code, "message": rpcErr.message]])
                    } catch {
                        return (index, ["error": ["code": -32603, "message": error.localizedDescription]])
                    }
                }
            }

            var results = [(Int, [String: Any])]()
            for await result in group {
                results.append(result)
            }
            return results.sorted { $0.0 < $1.0 }.map { $0.1 }
        }

        return ["responses": responses]
    }
}
