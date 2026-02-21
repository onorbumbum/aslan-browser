//
//  RPCMessage.swift
//  aslan-browser
//

import Foundation

// MARK: - Request

struct RPCRequest {
    let jsonrpc: String
    let id: Int?
    let method: String
    let params: [String: Any]?

    static func parse(from data: Data) throws -> RPCRequest {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RPCParseError.invalidJSON
        }

        guard let jsonrpc = json["jsonrpc"] as? String, jsonrpc == "2.0" else {
            throw RPCParseError.invalidRequest("Missing or invalid jsonrpc field")
        }

        guard let method = json["method"] as? String else {
            throw RPCParseError.invalidRequest("Missing method field")
        }

        let id = json["id"] as? Int
        let params = json["params"] as? [String: Any]

        return RPCRequest(jsonrpc: jsonrpc, id: id, method: method, params: params)
    }
}

// MARK: - Response

struct RPCResponse {
    let jsonrpc: String = "2.0"
    let id: Int?
    let result: Any?

    func serialize() throws -> Data {
        var dict: [String: Any] = ["jsonrpc": jsonrpc]
        if let id { dict["id"] = id }
        if let result { dict["result"] = result } else { dict["result"] = NSNull() }
        return try JSONSerialization.data(withJSONObject: dict)
    }
}

// MARK: - Error Response

struct RPCErrorResponse {
    let jsonrpc: String = "2.0"
    let id: Int?
    let error: RPCError

    func serialize() throws -> Data {
        var errorDict: [String: Any] = [
            "code": error.code,
            "message": error.message
        ]
        if let data = error.data { errorDict["data"] = data }

        var dict: [String: Any] = [
            "jsonrpc": jsonrpc,
            "error": errorDict
        ]
        if let id { dict["id"] = id }
        return try JSONSerialization.data(withJSONObject: dict)
    }
}

struct RPCError: Error {
    let code: Int
    let message: String
    let data: String?

    // Standard JSON-RPC error codes
    static func parseError(_ detail: String? = nil) -> RPCError {
        RPCError(code: -32700, message: "Parse error", data: detail)
    }

    static func invalidRequest(_ detail: String? = nil) -> RPCError {
        RPCError(code: -32600, message: "Invalid request", data: detail)
    }

    static func methodNotFound(_ method: String) -> RPCError {
        RPCError(code: -32601, message: "Method not found: \(method)", data: nil)
    }

    static func invalidParams(_ detail: String? = nil) -> RPCError {
        RPCError(code: -32602, message: "Invalid params", data: detail)
    }

    static func internalError(_ detail: String? = nil) -> RPCError {
        RPCError(code: -32603, message: "Internal error", data: detail)
    }

    // Application-defined error codes
    static func tabNotFound(_ tabId: String) -> RPCError {
        RPCError(code: -32000, message: "Tab not found: \(tabId)", data: nil)
    }

    static func javaScriptError(_ detail: String) -> RPCError {
        RPCError(code: -32001, message: "JavaScript error", data: detail)
    }

    static func navigationError(_ detail: String) -> RPCError {
        RPCError(code: -32002, message: "Navigation error", data: detail)
    }

    static func timeout(_ detail: String? = nil) -> RPCError {
        RPCError(code: -32003, message: "Timeout", data: detail)
    }

    static func sessionNotFound(_ sessionId: String) -> RPCError {
        RPCError(code: -32004, message: "Session not found: \(sessionId)", data: nil)
    }

    static func learnModeError(_ detail: String) -> RPCError {
        RPCError(code: -32005, message: "Learn mode error", data: detail)
    }
}

// MARK: - Parse Errors

enum RPCParseError: Error {
    case invalidJSON
    case invalidRequest(String)
}
