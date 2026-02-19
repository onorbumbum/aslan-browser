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

    init(socketPath: String, router: MethodRouter) {
        self.socketPath = socketPath
        self.router = router
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    func start() throws {
        removeStaleSocket()

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(.backlog, value: 256)
            .childChannelInitializer { [router] channel in
                channel.pipeline.addHandlers([
                    ByteToMessageHandler(LineBasedFrameDecoder()),
                    JSONRPCHandler(router: router)
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
