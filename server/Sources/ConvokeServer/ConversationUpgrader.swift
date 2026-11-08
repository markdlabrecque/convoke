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
                        StrictTextFrames(), position: .after(aggregator.handler)
                    )
                }
            }
        )
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
