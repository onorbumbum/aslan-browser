//
//  JSONRPCHandler.swift
//  aslan-browser
//

import Foundation
import NIOCore

final class JSONRPCHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private let router: MethodRouter
    private let server: SocketServer

    init(router: MethodRouter, server: SocketServer) {
        self.router = router
        self.server = server
    }

    func channelActive(context: ChannelHandlerContext) {
        server.addClient(context.channel)
        context.fireChannelActive()
    }

    func channelInactive(context: ChannelHandlerContext) {
        server.removeClient(context.channel)
        context.fireChannelInactive()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)
        let bytes = buffer.readableBytesView

        guard !bytes.isEmpty else { return }

        let data = Data(bytes)
        var requestId: Int?

        // Parse the JSON-RPC request
        let request: RPCRequest
        do {
            request = try RPCRequest.parse(from: data)
            requestId = request.id
        } catch RPCParseError.invalidJSON {
            writeError(context: context, id: nil, error: .parseError(String(data: data, encoding: .utf8)))
            return
        } catch RPCParseError.invalidRequest(let detail) {
            writeError(context: context, id: nil, error: .invalidRequest(detail))
            return
        } catch {
            writeError(context: context, id: nil, error: .parseError(error.localizedDescription))
            return
        }

        // Dispatch to router on MainActor
        let router = self.router
        let method = request.method
        let params = request.params
        let id = request.id

        Task { @MainActor in
            do {
                let result = try await router.dispatch(method, params: params)
                let response = RPCResponse(id: id, result: result)
                let responseData = try response.serialize()
                context.eventLoop.execute {
                    self.writeData(context: context, data: responseData)
                }
            } catch let rpcError as RPCError {
                let errorData = try? RPCErrorResponse(id: id, error: rpcError).serialize()
                context.eventLoop.execute {
                    if let errorData {
                        self.writeData(context: context, data: errorData)
                    }
                }
            } catch let browserError as BrowserError {
                let rpcError = browserError.rpcError
                let errorData = try? RPCErrorResponse(id: id, error: rpcError).serialize()
                context.eventLoop.execute {
                    if let errorData {
                        self.writeData(context: context, data: errorData)
                    }
                }
            } catch {
                let rpcError = RPCError.internalError(error.localizedDescription)
                let errorData = try? RPCErrorResponse(id: id, error: rpcError).serialize()
                context.eventLoop.execute {
                    if let errorData {
                        self.writeData(context: context, data: errorData)
                    }
                }
            }
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        NSLog("[aslan-browser] Channel error: \(error)")
        context.close(promise: nil)
    }

    // MARK: - Helpers

    private func writeError(context: ChannelHandlerContext, id: Int?, error: RPCError) {
        guard let data = try? RPCErrorResponse(id: id, error: error).serialize() else { return }
        writeData(context: context, data: data)
    }

    private func writeData(context: ChannelHandlerContext, data: Data) {
        var buffer = context.channel.allocator.buffer(capacity: data.count + 1)
        buffer.writeBytes(data)
        buffer.writeString("\n")
        context.writeAndFlush(wrapOutboundOut(buffer), promise: nil)
    }

}
