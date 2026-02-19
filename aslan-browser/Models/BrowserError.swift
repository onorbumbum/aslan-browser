//
//  BrowserError.swift
//  aslan-browser
//

import Foundation

enum BrowserError: Error {
    case navigationFailed(String)
    case invalidURL(String)
    case javaScriptError(String)
    case screenshotFailed(String)
    case tabNotFound(String)
    case timeout(String)

    var rpcError: RPCError {
        switch self {
        case .navigationFailed(let detail):
            return .navigationError(detail)
        case .invalidURL(let detail):
            return .invalidParams("Invalid URL: \(detail)")
        case .javaScriptError(let detail):
            return .javaScriptError(detail)
        case .screenshotFailed(let detail):
            return .internalError("Screenshot failed: \(detail)")
        case .tabNotFound(let tabId):
            return .tabNotFound(tabId)
        case .timeout(let detail):
            return .timeout(detail)
        }
    }
}
