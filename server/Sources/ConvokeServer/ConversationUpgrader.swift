import Foundation
import NIOCore
import NIOHTTP1
import NIOWebSocket
import Vapor
import WebSocketKit

// Vapor's standard route only limits individual wire frames. Configure the
// aggregator too so fragmentation cannot bypass the in-memory message limit.
struct ConversationUpgrader: Upgrader {
    let onUpgrade: @Sendable (WebSocket) -> Void

    func applyUpgrade(req: Request, res: Response) -> HTTPServerProtocolUpgrader {
        NIOWebSocketServerUpgrader(
            maxFrameSize: ConversationProtocol.maxFrameBytes,
            automaticErrorHandling: false,
            shouldUpgrade: { channel, _ in channel.eventLoop.makeSucceededFuture([:]) },
            upgradePipelineHandler: { channel, _ in
                var config = WebSocket.Configuration()
                config.maxAccumulatedFrameSize = ConversationProtocol.maxFrameBytes
                config.maxAccumulatedFrameCount = ConversationProtocol.maxFrameBytes
                return WebSocket.server(on: channel, config: config, onUpgrade: onUpgrade).flatMapThrowing {
                    let aggregator = try channel.pipeline.syncOperations.context(handlerType: NIOWebSocketFrameAggregator.self)
                    try channel.pipeline.syncOperations.addHandler(
                        ConnectionFrames(), position: .before(aggregator.handler)
                    )
                    try channel.pipeline.syncOperations.addHandler(
                        StrictTextFrames(), position: .after(aggregator.handler)
                    )
                }
            }
        )
    }
}

// Validate wire metadata before aggregation discards it. Observe every outbound
// close frame, including decoder errors, and bound the handshake independently
// of write completion so an unresponsive or non-reading peer cannot keep it open.
final class ConnectionFrames: ChannelDuplexHandler {
    typealias InboundIn = WebSocketFrame
    typealias OutboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame
    private let closeTimeout: TimeAmount
    private var closing = false
    private var closeDeadline: Scheduled<Void>?

    init(closeTimeout: TimeAmount = .seconds(1)) {
        self.closeTimeout = closeTimeout
    }

    private func beginClosing(context: ChannelHandlerContext) {
        guard !closing else { return }
        closing = true
        let channel = context.channel
        closeDeadline = context.eventLoop.scheduleTask(in: closeTimeout) {
            channel.close(mode: .all, promise: nil)
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        if closing {
            // Permit a close acknowledgment, but no more application messages
            // or ping responses while waiting for it.
            if frame.opcode == .connectionClose { context.fireChannelRead(data) }
            return
        }
        let knownOpcode: Bool
        switch frame.opcode {
        case .text, .binary, .continuation, .connectionClose, .ping, .pong: knownOpcode = true
        default: knownOpcode = false
        }
        guard frame.maskKey != nil, !frame.rsv1, !frame.rsv2, !frame.rsv3, knownOpcode else {
            beginClosing(context: context)
            var payload = context.channel.allocator.buffer(capacity: 2)
            payload.writeInteger(UInt16(1002))
            let channel = context.channel
            context.writeAndFlush(wrapOutboundOut(WebSocketFrame(fin: true, opcode: .connectionClose, data: payload)))
                .whenComplete { _ in channel.close(mode: .all, promise: nil) }
            return
        }
        context.fireChannelRead(data)
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        if unwrapOutboundIn(data).opcode == .connectionClose {
            beginClosing(context: context)
        } else if closing {
            promise?.fail(ChannelError.ioOnClosedChannel)
            return
        }
        context.write(data, promise: promise)
    }

    func channelInactive(context: ChannelHandlerContext) {
        closeDeadline?.cancel()
        closeDeadline = nil
        context.fireChannelInactive()
    }
}

// WebSocketKit decodes text with replacement characters. Reject malformed UTF-8
// before that conversion, while still allowing legitimate U+FFFD in transcripts.
private final class StrictTextFrames: ChannelInboundHandler {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame
    private var rejected = false

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard !rejected else { return }
        let frame = unwrapInboundIn(data)
        let closeCode: UInt16?
        switch frame.opcode {
        case .text:
            closeCode = String(bytes: frame.unmaskedData.readableBytesView, encoding: .utf8) == nil ? 1007 : nil
        case .binary, .connectionClose, .ping, .pong:
            closeCode = nil
        default:
            closeCode = 1002
        }
        if let closeCode {
            rejected = true
            var payload = context.channel.allocator.buffer(capacity: 2)
            payload.writeInteger(closeCode)
            context.writeAndFlush(wrapOutboundOut(WebSocketFrame(fin: true, opcode: .connectionClose, data: payload)))
                .whenComplete { _ in context.close(promise: nil) }
        } else {
            context.fireChannelRead(data)
        }
    }
}
