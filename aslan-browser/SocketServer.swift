//
//  SocketServer.swift
//  aslan-browser
//

import Foundation
import NIOCore
import NIOPosix

// MARK: - Line Decoder

/// Splits incoming bytes on newline boundaries for NDJSON framing.
final class LineBasedFrameDecoder: ByteToMessageDecoder {
    typealias InboundOut = ByteBuffer

    func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        guard let nlIndex = buffer.readableBytesView.firstIndex(of: UInt8(ascii: "\n")) else {
            return .needMoreData
        }

        let length = nlIndex - buffer.readerIndex
        var lineBuffer = buffer.readSlice(length: length)!
        buffer.moveReaderIndex(forwardBy: 1) // consume the \n

        // Trim trailing \r if present
        if let last = lineBuffer.readableBytesView.last, last == UInt8(ascii: "\r") {
            lineBuffer = lineBuffer.getSlice(at: lineBuffer.readerIndex, length: lineBuffer.readableBytes - 1)!
        }

        context.fireChannelRead(wrapInboundOut(lineBuffer))
        return .continue
    }
}

// MARK: - Socket Server

class SocketServer {

    private let group: MultiThreadedEventLoopGroup
    private var channel: Channel?
    private let socketPath: String
    private let router: MethodRouter

    // Connected client tracking
    private let clientLock = NSLock()
    private var clientChannels: [ObjectIdentifier: Channel] = [:]

    init(socketPath: String, router: MethodRouter) {
        self.socketPath = socketPath
        self.router = router
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    func addClient(_ channel: Channel) {
        clientLock.lock()
        clientChannels[ObjectIdentifier(channel)] = channel
        clientLock.unlock()
        NSLog("[aslan-browser] Client connected (total: \(clientChannels.count))")
    }

    func removeClient(_ channel: Channel) {
        clientLock.lock()
        clientChannels.removeValue(forKey: ObjectIdentifier(channel))
        clientLock.unlock()
        NSLog("[aslan-browser] Client disconnected (total: \(clientChannels.count))")
    }

    func broadcast(method: String, params: [String: Any]) {
        let notification: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: notification) else { return }

        clientLock.lock()
        let channels = Array(clientChannels.values)
        clientLock.unlock()

        for ch in channels {
            var buffer = ch.allocator.buffer(capacity: data.count + 1)
            buffer.writeBytes(data)
            buffer.writeString("\n")
            ch.writeAndFlush(buffer).whenFailure { [weak self] _ in
                self?.removeClient(ch)
            }
        }
    }

    func start() throws {
        removeStaleSocket()

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(.backlog, value: 256)
            .childChannelInitializer { [router, weak self] channel in
                guard let self else { return channel.eventLoop.makeSucceededVoidFuture() }
                return channel.pipeline.addHandlers([
                    ByteToMessageHandler(LineBasedFrameDecoder()),
                    JSONRPCHandler(router: router, server: self)
                ])
            }
            .childChannelOption(.socketOption(.so_reuseaddr), value: 1)

        channel = try bootstrap.bind(unixDomainSocketPath: socketPath).wait()
        NSLog("[aslan-browser] Socket server listening on \(socketPath)")
        print("SOCKET_PATH=\(socketPath)")
    }

    func stop() {
        try? channel?.close().wait()
        try? group.syncShutdownGracefully()
        removeStaleSocket()
        NSLog("[aslan-browser] Socket server stopped")
    }

    private func removeStaleSocket() {
        let fm = FileManager.default
        if fm.fileExists(atPath: socketPath) {
            try? fm.removeItem(atPath: socketPath)
        }
    }
}
