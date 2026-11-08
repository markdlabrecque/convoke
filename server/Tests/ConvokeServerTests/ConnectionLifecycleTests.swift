import Darwin
import XCTest
import Vapor
import NIOCore
import NIOEmbedded
import NIOWebSocket
import WebSocketKit
@testable import ConvokeServer

final class ConnectionLifecycleTests: XCTestCase {
    func testConversationReleasedAfterNormalAndErrorClosure() throws {
        for invalidInput in [false, true] {
            let channel = EmbeddedChannel()
            try channel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 8080)).wait()
            let weakConversation = WeakConversation()
            let configured = WebSocket.server(on: channel) { socket in
                let conversation = Conversation(socket: socket, timeout: .seconds(10)) { _ in Data([0, 0]) }
                weakConversation.value = conversation
            }
            channel.embeddedEventLoop.run()
            try configured.wait()
            XCTAssertNotNil(weakConversation.value, "Connection retains its conversation while open")
            if invalidInput {
                try channel.writeInbound(WebSocketFrame(fin: true, opcode: .text, data: channel.allocator.buffer(string: "{")))
            }
            try channel.close().wait()
            channel.embeddedEventLoop.run()
            XCTAssertNil(weakConversation.value, "Closed connections must release the conversation")
            _ = try channel.finish(acceptAlreadyClosed: true)
        }
    }

    func testCloseDeadlineDoesNotWaitForBlockedWrite() throws {
        let channel = EmbeddedChannel()
        let stalled = StalledWrites()
        try channel.pipeline.syncOperations.addHandlers(stalled, ConnectionFrames(closeTimeout: .milliseconds(50)))
        try channel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 8080)).wait()
        var closed = false
        channel.closeFuture.whenComplete { _ in closed = true }
        let pending = channel.writeAndFlush(WebSocketFrame(fin: true, opcode: .connectionClose, data: channel.allocator.buffer(capacity: 0)))
        pending.whenFailure { _ in } // The forced close must fail the pending write.
        let lateMessage = channel.writeAndFlush(WebSocketFrame(fin: true, opcode: .text, data: channel.allocator.buffer(string: "late")))
        var rejectedLateMessage = false
        lateMessage.whenFailure { _ in rejectedLateMessage = true }
        XCTAssertTrue(rejectedLateMessage, "No application writes are allowed after close starts")
        channel.embeddedEventLoop.advanceTime(by: .milliseconds(49))
        XCTAssertFalse(closed)
        XCTAssertEqual(stalled.promises.count, 1)
        channel.embeddedEventLoop.advanceTime(by: .milliseconds(1))
        XCTAssertTrue(closed, "Close deadline must not depend on the write promise")
        // Clean up even on regression rather than waiting forever on the write.
        if !closed { try channel.close().wait() }
        XCTAssertThrowsError(try pending.wait())
        _ = try channel.finish(acceptAlreadyClosed: true)
    }

    func testNonAcknowledgingPeerIsDisconnectedAfterErrorAndTimeout() async throws {
        for timeout in [false, true] {
            try await withRawServer(turnTimeout: .milliseconds(50)) { peer in
                try peer.send(text: timeout ? "{\"type\":\"user.text\",\"text\":\"test\"}" : "{")
                if timeout {
                    let text = try peer.receiveFrame()
                    XCTAssertEqual(text.opcode, 1)
                }
                let close = try peer.receiveFrame()
                XCTAssertEqual(close.opcode, 8)
                XCTAssertEqual(close.payload, Data([3, 240])) // 1008
                // Deliberately do not acknowledge. No pong or further frames
                // should arrive, and TCP must close within the receive deadline.
                try peer.send(text: "still here", opcode: 9)
                XCTAssertEqual(try peer.read(upTo: 1).count, 0)
            }
        }
    }

    func testMaskAndReservedBitsAreRejectedBeforeAggregation() async throws {
        // Cover invalid metadata on both initial and continuation fragments.
        for fragmented in [false, true] {
            for invalidContinuation in fragmented ? [false, true] : [false] {
                for fault in 0..<4 {
                    try await withRawServer { peer in
                        if invalidContinuation {
                            try peer.send(text: "{", fin: false)
                        }
                        try peer.send(
                            text: invalidContinuation ? "}" : "{\"type\":\"user.text\",\"text\":\"test\"}",
                            opcode: invalidContinuation ? 0 : 1,
                            fin: !fragmented,
                            masked: fault != 0,
                            reserved: fault == 0 ? 0 : UInt8(0x80 >> fault)
                        )
                        let close = try peer.receiveFrame()
                        XCTAssertEqual(close.opcode, 8, "Invalid wire metadata must not produce agent.text")
                        XCTAssertEqual(close.payload, Data([3, 234])) // 1002
                        XCTAssertEqual(try peer.read(upTo: 1).count, 0)
                    }
                }
            }
        }
    }

    private func withRawServer(
        turnTimeout: TimeAmount = .seconds(10), body: (RawPeer) throws -> Void
    ) async throws {
        let app = try await Application.make(.testing)
        do {
            try configure(app, turnTimeout: turnTimeout, synthesize: { _ in
                try await Task.sleep(nanoseconds: 30_000_000_000)
                return Data([0, 0])
            })
            try await app.server.start(address: .hostname("127.0.0.1", port: 0))
            let port = try XCTUnwrap(app.http.server.shared.localAddress?.port)
            let peer = try RawPeer(port: port)
            try body(peer)
            peer.close()
            await app.server.shutdown()
            try await app.asyncShutdown()
        } catch {
            await app.server.shutdown()
            try? await app.asyncShutdown()
            throw error
        }
    }
}

private final class WeakConversation: @unchecked Sendable {
    weak var value: Conversation?
}

private final class StalledWrites: ChannelOutboundHandler, ChannelInboundHandler {
    typealias OutboundIn = WebSocketFrame
    typealias InboundIn = WebSocketFrame
    var promises: [EventLoopPromise<Void>] = []

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        if let promise { promises.append(promise) }
    }

    func channelInactive(context: ChannelHandlerContext) {
        let pending = promises
        promises.removeAll()
        pending.forEach { $0.fail(ChannelError.ioOnClosedChannel) }
        context.fireChannelInactive()
    }
}

// A raw TCP peer intentionally has no automatic WebSocket close acknowledgment.
// All reads have a socket-level timeout so regressions fail rather than hang.
private final class RawPeer {
    private var descriptor: Int32 = -1

    init(port: Int) throws {
        descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        do {
            var timeout = timeval(tv_sec: 3, tv_usec: 0)
            guard setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout))) == 0 else {
                throw POSIXError(.EIO)
            }
            var noSigPipe: Int32 = 1
            _ = setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout.size(ofValue: noSigPipe)))
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = UInt16(port).bigEndian
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard result == 0 else { throw POSIXError(.ECONNREFUSED) }
            try write(Data(("GET /conversation HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n").utf8))
            var response = Data()
            while !response.suffix(4).elementsEqual([13, 10, 13, 10]) {
                let byte = try read(upTo: 1)
                guard !byte.isEmpty, response.count < 8192 else { throw POSIXError(.EPROTO) }
                response.append(byte)
            }
            guard String(decoding: response, as: UTF8.self).hasPrefix("HTTP/1.1 101") else { throw POSIXError(.EPROTO) }
        } catch { close(); throw error }
    }

    deinit { close() }

    func close() {
        if descriptor >= 0 { Darwin.close(descriptor); descriptor = -1 }
    }

    func send(text: String, opcode: UInt8 = 1, fin: Bool = true, masked: Bool = true, reserved: UInt8 = 0) throws {
        let payload = Data(text.utf8)
        precondition(payload.count < 126)
        var bytes = Data([(fin ? 0x80 : 0) | reserved | opcode, (masked ? 0x80 : 0) | UInt8(payload.count)])
        let mask: [UInt8] = [1, 2, 3, 4]
        if masked { bytes.append(contentsOf: mask) }
        bytes.append(contentsOf: payload.enumerated().map { masked ? $0.element ^ mask[$0.offset % 4] : $0.element })
        try write(bytes)
    }

    func receiveFrame() throws -> (opcode: UInt8, payload: Data) {
        let header = try readExactly(2)
        let size = Int(header[1] & 0x7F)
        guard size < 126 else { throw POSIXError(.EPROTO) }
        return (header[0] & 0x0F, try readExactly(size))
    }

    func read(upTo count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let result = Darwin.recv(descriptor, &bytes, count, 0)
        guard result >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return Data(bytes.prefix(result))
    }

    private func readExactly(_ count: Int) throws -> Data {
        var data = Data()
        while data.count < count {
            let part = try read(upTo: count - data.count)
            guard !part.isEmpty else { throw POSIXError(.ECONNRESET) }
            data.append(part)
        }
        return data
    }

    private func write(_ data: Data) throws {
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.send(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset, 0)
                guard written > 0 else { throw POSIXError(.EIO) }
                offset += written
            }
        }
    }
}
