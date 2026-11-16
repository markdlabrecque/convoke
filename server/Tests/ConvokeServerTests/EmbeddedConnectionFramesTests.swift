import XCTest
import Vapor
import NIOCore
import NIOEmbedded
import NIOHTTP1
import NIOWebSocket
import WebSocketKit
@testable import ConvokeServer

final class EmbeddedConnectionFramesTests: XCTestCase {
    func testMaskAndReservedBitsAreRejectedBeforeAggregation() async throws {
        try await withApplication { app in
            for fragmented in [false, true] {
                for invalidContinuation in fragmented ? [false, true] : [false] {
                    for fault in 0..<4 {
                        let fixture = try EmbeddedConnection(app: app)
                        defer { fixture.finish() }
                        if invalidContinuation {
                            try fixture.send(payload: Data("{".utf8), fin: false)
                            XCTAssertTrue(fixture.delivered.frames.isEmpty, "Initial fragment must remain in the aggregator")
                        }
                        try fixture.send(
                            payload: Data((invalidContinuation ? "}" : "{\"type\":\"user.text\",\"text\":\"test\"}").utf8),
                            opcode: invalidContinuation ? 0 : 1,
                            fin: !fragmented,
                            masked: fault != 0,
                            reserved: fault == 0 ? 0 : UInt8(0x80 >> fault)
                        )
                        try fixture.assertReply(code: 1002)
                        XCTAssertTrue(fixture.delivered.frames.isEmpty, "Bad metadata cannot reach downstream, even on an unfinished fragment")
                    }
                }
            }
        }
    }

    func testInvalidClosePayloadLengthsAndStatusCodes() async throws {
        // The original source has 12 rows, despite the issue's 13-row count.
        // Add reserved code 1999 to explicitly cover 13 without inventing a baseline row.
        let payloads = [Data([1])] + [UInt16(0), 999, 1004, 1005, 1006, 1015, 1016, 1999, 2000, 2999, 5000, 65535].map(closePayload)
        XCTAssertEqual(payloads.count, 13)
        try await withApplication { app in
            for payload in payloads {
                let fixture = try EmbeddedConnection(app: app)
                defer { fixture.finish() }
                try fixture.send(payload: payload, opcode: 8)
                try fixture.assertReply(code: 1002)
                XCTAssertTrue(fixture.delivered.frames.isEmpty, "Invalid close must not be forwarded: \(Array(payload))")
            }
        }
    }

    func testInvalidCloseReasonUTF8() async throws {
        try await withApplication { app in
            for reason: [UInt8] in [[0xFF], [0xC3], [0xC0, 0xAF], [0xED, 0xA0, 0x80], [0xF4, 0x90, 0x80, 0x80]] {
                let fixture = try EmbeddedConnection(app: app)
                defer { fixture.finish() }
                try fixture.send(payload: Data([3, 232] + reason), opcode: 8)
                try fixture.assertReply(code: 1007)
                XCTAssertTrue(fixture.delivered.frames.isEmpty, "Malformed close reason must not be forwarded")
            }
        }
    }

    func testValidClosePayloads() async throws {
        var payloads = [Data()] + [UInt16(1000), 1001, 1002, 1003, 1007, 1008, 1009, 1010, 1011, 1012, 1013, 1014, 3000, 3999, 4000, 4999].map(closePayload)
        for reason in ["goodbye", "À bientôt 🌍", "\u{FFFD}", String(repeating: "x", count: 123)] {
            payloads.append(Data([3, 232]) + Data(reason.utf8))
        }
        XCTAssertEqual(payloads.count, 21)
        try await withApplication { app in
            for payload in payloads {
                let fixture = try EmbeddedConnection(app: app)
                defer { fixture.finish() }
                try fixture.send(payload: payload, opcode: 8)
                let code = payload.isEmpty ? 1000 : UInt16(payload[0]) << 8 | UInt16(payload[1])
                try fixture.assertReply(code: code)
                XCTAssertEqual(fixture.delivered.frames.count, 1)
                let forwarded = try XCTUnwrap(fixture.delivered.frames.first)
                XCTAssertEqual(forwarded.opcode, .connectionClose)
                XCTAssertEqual(Data(forwarded.unmaskedData.readableBytesView), payload, "Forward the complete code/reason bytes to WebSocketKit; its responder echoes the code only")
            }
        }
    }

    private func closePayload(_ code: UInt16) -> Data {
        Data([UInt8(code >> 8), UInt8(code & 0xFF)])
    }

    private func withApplication(_ body: (Application) throws -> Void) async throws {
        let app = try await Application.make(.testing)
        do { try body(app) }
        catch { try? await app.asyncShutdown(); throw error }
        try await app.asyncShutdown()
    }
}

// Use the actual upgrader, not a replica of its private StrictTextFrames handler.
// This installs encoder -> decoder -> ConnectionFrames -> aggregator ->
// StrictTextFrames -> WebSocketKit's real close responder. Only the passive
// delivery probe is inserted (after the aggregator, before StrictTextFrames).
// No listener, HTTP server, Conversation, timers on real clocks, or production extraction.
private final class EmbeddedConnection {
    let channel = EmbeddedChannel()
    let delivered = DeliveredFrames()

    init(app: Application) throws {
        try channel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 8080)).wait()
        try channel.pipeline.syncOperations.addHandler(delivered)
        let context = try channel.pipeline.syncOperations.context(handler: delivered)
        let upgrader = ConversationUpgrader { _ in }.applyUpgrade(
            req: Request(application: app, on: channel.eventLoop), res: Response()
        )
        let upgraded = upgrader.upgrade(context: context, upgradeRequest: HTTPRequestHead(version: .http1_1, method: .GET, uri: "/conversation"))
        channel.embeddedEventLoop.run()
        try upgraded.wait()
        // Relocate the probe from the upgrade context to the application side
        // of aggregation. Keep every real handler in its installed order.
        try channel.pipeline.syncOperations.removeHandler(delivered).wait()
        let aggregator = try channel.pipeline.syncOperations.context(handlerType: NIOWebSocketFrameAggregator.self)
        try channel.pipeline.syncOperations.addHandler(delivered, position: .after(aggregator.handler))
    }

    func send(payload: Data, opcode: UInt8 = 1, fin: Bool = true, masked: Bool = true, reserved: UInt8 = 0) throws {
        // All matrix payloads are <=125 bytes. A zero mask preserves the bytes
        // while still exercising the decoder's actual mask metadata.
        precondition(payload.count <= 125)
        var wire = channel.allocator.buffer(capacity: payload.count + 6)
        wire.writeInteger((fin ? UInt8(0x80) : 0) | reserved | opcode)
        wire.writeInteger(UInt8(payload.count) | (masked ? 0x80 : 0))
        if masked { wire.writeBytes([UInt8](repeating: 0, count: 4)) }
        wire.writeBytes(payload)
        try channel.writeInbound(wire)
        channel.embeddedEventLoop.run()
    }

    func assertReply(code: UInt16, file: StaticString = #filePath, line: UInt = #line) throws {
        var bytes: [UInt8] = []
        while let buffer = try channel.readOutbound(as: ByteBuffer.self) {
            bytes.append(contentsOf: buffer.readableBytesView)
        }
        XCTAssertEqual(bytes, [0x88, 2, UInt8(code >> 8), UInt8(code & 0xFF)], "Exactly one unmasked close, no application response", file: file, line: line)
        XCTAssertFalse(channel.isActive, "Close response must terminate the connection", file: file, line: line)
        XCTAssertNil(try channel.readInbound(as: WebSocketFrame.self), file: file, line: line)
    }

    func finish() {
        XCTAssertNoThrow(try channel.finish(acceptAlreadyClosed: true))
    }
}

private final class DeliveredFrames: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = WebSocketFrame
    var frames: [WebSocketFrame] = []

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        frames.append(unwrapInboundIn(data))
        context.fireChannelRead(data)
    }
}
