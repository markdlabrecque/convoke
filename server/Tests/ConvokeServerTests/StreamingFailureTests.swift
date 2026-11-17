import AsyncHTTPClient
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import NIOCore
import NIOHTTP1
import NIOPosix
import Vapor
import XCTest
@testable import ConvokeServer

final class StreamingFailureTests: XCTestCase {
    /// Unlike an AsyncStream termination assertion, this observes the actual HTTP
    /// connection closing at the upstream peer while its response is unfinished.
    @MainActor func testCancellationDuringSlowWriteClosesRealUpstreamRequest() async throws {
        try await withHTTPFixture(truncated: false) { synthesizer, loop, closed in
            let writing = self.expectation(description: "consumer entered stalled write")
            let gate = loop.makePromise(of: Void.self)
            // Production obtains an existential from makeSpeechSynthesizer. Scoped
            // cleanup must dynamically dispatch to Kokoro's implementation too.
            let source: any SpeechSynthesizer = synthesizer
            let task = Task { @MainActor in
                try await source.consume("fixture") { _ in
                    try await CancellableWrite.run(on: loop) {
                        writing.fulfill()
                        return gate.futureResult
                    }
                }
            }
            await self.fulfillment(of: [writing], timeout: 3)
            task.cancel()
            do { try await task.value; XCTFail("Cancellation succeeded") }
            catch is CancellationError {}
            await self.fulfillment(of: [closed], timeout: 3)
            // A late socket completion must not resume the cancelled consumer twice.
            gate.succeed(())
        }
    }

    @MainActor func testFailedWriteClosesRealUpstreamRequest() async throws {
        try await withHTTPFixture(truncated: false) { synthesizer, loop, closed in
            do {
                try await synthesizer.consume("fixture") { _ in
                    try await CancellableWrite.run(on: loop) { loop.makeFailedFuture(FixtureFailure()) }
                }
                XCTFail("Failed write succeeded")
            } catch is FixtureFailure {}
            await self.fulfillment(of: [closed], timeout: 3)
        }
    }

    @MainActor func testTruncatedHTTPBodyFailsAfterPartialPCM() async throws {
        try await withHTTPFixture(truncated: true) { synthesizer, _, closed in
            var bytes = 0
            do {
                try await synthesizer.consume("fixture") { bytes += $0.count }
                XCTFail("Truncated framing succeeded")
            } catch {
                XCTAssertEqual(bytes, 2)
            }
            await self.fulfillment(of: [closed], timeout: 3)
        }
    }

    @MainActor func testConsumerWriteBackpressuresFurtherSourcePulls() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let loop = group.next()
        let gate = loop.makePromise(of: Void.self)
        let writing = expectation(description: "first write started")
        let source = PullProbe()
        let task = Task { @MainActor in
            try await source.consume("fixture") { _ in
                try await CancellableWrite.run(on: loop) {
                    writing.fulfill()
                    return gate.futureResult
                }
            }
        }
        await fulfillment(of: [writing], timeout: 3)
        XCTAssertEqual(source.pulls, 1, "No second pull while downstream write is gated")
        gate.succeed(())
        try await task.value
        XCTAssertEqual(source.pulls, 2, "Second pull observes EOF")
        try await group.shutdownGracefully()
    }

    func testDeadlineRemainsActiveThroughStalledDoneWrite() async throws {
        let attempted = expectation(description: "done write attempted")
        let app = try await Application.make(.testing)
        let probe = WriteProbe()
        app.get("conversation") { _ -> Response in
            let response = Response(status: .switchingProtocols)
            response.upgrader = ConversationUpgrader { socket in
                let gate = socket.eventLoop.makePromise(of: Void.self)
                socket.onClose.whenComplete { _ in gate.fail(FixtureFailure()) }
                _ = Conversation(socket: socket, timeout: .seconds(1), agent: EchoTestAgent(),
                                 synthesize: SpeechAudio.stream(wrapping: { _ in Data([1, 2]) }),
                                 sendFrame: { frame in
                    probe.record(frame)
                    if frame.contains("agent.done") {
                        attempted.fulfill()
                        return gate.futureResult
                    }
                    let promise = socket.eventLoop.makePromise(of: Void.self)
                    socket.send(frame, promise: promise)
                    return promise.futureResult
                })
            }
            return response
        }
        do {
            try await app.server.start(address: .hostname("127.0.0.1", port: 0))
            let port = try XCTUnwrap(app.http.server.shared.localAddress?.port)
            let socket = try await TestWebSocket.connect(to: URL(string: "ws://127.0.0.1:\(port)/conversation")!)
            defer { socket.cancel(with: .goingAway, reason: nil) }
            try await socket.send(.string("{\"type\":\"user.text\",\"text\":\"fixture\"}"))
            _ = try await socket.receive() // text
            _ = try await socket.receive() // audio
            await fulfillment(of: [attempted], timeout: 3)
            do { _ = try await socket.receive(); XCTFail("Done succeeded despite stalled write") } catch {}
            XCTAssertEqual(probe.count, 3, "No writes after the stalled done and deadline")
        } catch {
            await app.server.shutdown()
            try? await app.asyncShutdown()
            throw error
        }
        await app.server.shutdown()
        try await app.asyncShutdown()
    }

    @MainActor func testCancellationDuringBodyReadClosesRealUpstreamRequest() async throws {
        try await withHTTPFixture(truncated: false) { synthesizer, _, closed in
            let received = self.expectation(description: "received partial PCM")
            let task = Task { @MainActor in
                try await synthesizer.consume("fixture") { _ in received.fulfill() }
            }
            await self.fulfillment(of: [received], timeout: 3)
            task.cancel()
            do { try await task.value; XCTFail("Cancellation succeeded") } catch {}
            await self.fulfillment(of: [closed], timeout: 3)
        }
    }

    @MainActor func testConversationDisconnectAndTimeoutCancelRealRequest() async throws {
        for timeout in [false, true] {
            try await withHTTPFixture(truncated: false) { synthesizer, _, closed in
                let app = try await Application.make(.testing)
                do {
                    try configure(app, turnTimeout: timeout ? .seconds(1) : .seconds(10),
                                  stream: { try await synthesizer.stream($0) }, agent: EchoTestAgent())
                    try await app.server.start(address: .hostname("127.0.0.1", port: 0))
                    let port = try XCTUnwrap(app.http.server.shared.localAddress?.port)
                    let socket = try await TestWebSocket.connect(to: URL(string: "ws://127.0.0.1:\(port)/conversation")!)
                    defer { socket.cancel(with: .goingAway, reason: nil) }
                    try await socket.send(.string("{\"type\":\"user.text\",\"text\":\"fixture\"}"))
                    _ = try await socket.receive()
                    _ = try await socket.receive()
                    if timeout {
                        do { _ = try await socket.receive(); XCTFail("Timed-out turn completed") } catch {}
                    } else {
                        socket.cancel(with: .goingAway, reason: nil)
                    }
                    await self.fulfillment(of: [closed], timeout: 3)
                } catch {
                    await app.server.shutdown()
                    try? await app.asyncShutdown()
                    throw error
                }
                await app.server.shutdown()
                try await app.asyncShutdown()
            }
        }
    }

    private final class WriteProbe: @unchecked Sendable {
        private let lock = NSLock()
        private var frames = 0
        func record(_ frame: String) { lock.withLock { frames += 1 } }
        var count: Int { lock.withLock { frames } }
    }

    private struct FixtureFailure: Error {}

    @MainActor private final class PullProbe: SpeechSynthesizer {
        var pulls = 0
        func synthesize(_ text: String) async throws -> Data { fatalError("not buffered") }
        func stream(_ text: String) async throws -> AsyncThrowingStream<Data, Error> {
            AsyncThrowingStream(unfolding: {
                await MainActor.run {
                    self.pulls += 1
                    return self.pulls == 1 ? Data([1, 2]) : nil
                }
            })
        }
    }

    @MainActor private func withHTTPFixture(
        truncated: Bool,
        run: (KokoroSpeechSynthesizer, any EventLoop, XCTestExpectation) async throws -> Void
    ) async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let closed = expectation(description: "upstream HTTP channel closed")
        let server = try await ServerBootstrap(group: group)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(HTTPFixture(truncated: truncated, closed: closed))
                }
            }.bind(host: "127.0.0.1", port: 0).get()
        let http = HTTPClient(eventLoopGroupProvider: .shared(group))
        let app = try await Application.make(.testing)
        do {
            let port = try XCTUnwrap(server.localAddress?.port)
            let config = try XCTUnwrap(KokoroConfig(environment: ["CONVOKE_KOKORO_URL": "http://127.0.0.1:\(port)"]))
            try await run(KokoroSpeechSynthesizer(client: app.client, config: config, http: http), group.next(), closed)
        } catch {
            try? await http.shutdown()
            try? await server.close().get()
            try? await app.asyncShutdown()
            try? await group.shutdownGracefully()
            throw error
        }
        try await http.shutdown()
        try await server.close().get()
        try await app.asyncShutdown()
        try await group.shutdownGracefully()
    }

    private final class HTTPFixture: ChannelInboundHandler, @unchecked Sendable {
        typealias InboundIn = HTTPServerRequestPart
        typealias OutboundOut = HTTPServerResponsePart
        let truncated: Bool
        let closed: XCTestExpectation
        init(truncated: Bool, closed: XCTestExpectation) {
            self.truncated = truncated
            self.closed = closed
        }
        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            guard case .end = unwrapInboundIn(data) else { return }
            let head = HTTPResponseHead(version: .http1_1, status: .ok,
                                        headers: ["content-type": "audio/pcm", "content-length": "100"])
            context.write(wrapOutboundOut(.head(head)), promise: nil)
            let write = context.writeAndFlush(wrapOutboundOut(.body(.byteBuffer(ByteBuffer(bytes: [1, 2])))))
            if truncated { write.whenComplete { _ in context.close(promise: nil) } }
        }
        func channelInactive(context: ChannelHandlerContext) {
            closed.fulfill()
            context.fireChannelInactive()
        }
    }
}
