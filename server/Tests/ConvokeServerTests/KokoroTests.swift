import XCTest
import NIOCore
import NIOHTTP1
import NIOPosix
import AsyncHTTPClient
import Vapor
@testable import ConvokeServer

final class KokoroTests: XCTestCase {
    func testConfigFromEnvironment() throws {
        XCTAssertNil(try KokoroConfig(environment: [:]))
        XCTAssertNil(try KokoroConfig(environment: ["CONVOKE_KOKORO_URL": "  "]))
        XCTAssertThrowsError(try KokoroConfig(environment: ["CONVOKE_KOKORO_URL": "localhost:8880"]))
        let defaults = try XCTUnwrap(KokoroConfig(environment: ["CONVOKE_KOKORO_URL": "http://127.0.0.1:8880/"]))
        XCTAssertEqual(defaults.baseURL, "http://127.0.0.1:8880")
        XCTAssertEqual(defaults.voice, KokoroConfig.defaultVoice)
        let custom = try XCTUnwrap(KokoroConfig(environment: ["CONVOKE_KOKORO_URL": "http://k", "CONVOKE_KOKORO_VOICE": "bf_emma"]))
        XCTAssertEqual(custom.voice, "bf_emma")
    }

    @MainActor func testRequestShapeAndPCMPassThrough() async throws {
        let pcm = Data((0..<4_000).map { UInt8($0 % 253) })  // whole 16-bit samples
        let stub = Stub()
        let audio = try await withStub(stub, status: .ok, body: pcm) { try await $0.synthesize("hello there") }
        XCTAssertEqual(audio, pcm, "Kokoro raw PCM is passed through untouched")
        XCTAssertEqual(stub.path, "/v1/audio/speech")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(stub.body.utf8)) as? [String: Any])
        XCTAssertEqual(object["input"] as? String, "hello there")
        XCTAssertEqual(object["voice"] as? String, KokoroConfig.defaultVoice)
        XCTAssertEqual(object["response_format"] as? String, "pcm")
        XCTAssertEqual(object["stream"] as? Bool, false)
    }

    @MainActor func testErrorsAreThrownNotSwallowed() async throws {
        let cases: [(HTTPStatus, Data, String)] = [
            (.internalServerError, Data([0, 0]), "audio/pcm"), (.ok, Data(), "audio/pcm"), (.ok, Data([1, 2, 3]), "audio/pcm"),
            (.ok, Data([0, 0]), "audio/mpeg"), (.ok, Data([0, 0]), "audio/wav"),
        ]
        for (status, body, type) in cases {
            do {
                _ = try await withStub(Stub(), status: status, body: body, type: type) { try await $0.synthesize("x") }
                XCTFail("Expected an error for \(status) with \(body.count) bytes")
            } catch is SpeechError {}
        }
    }

    @MainActor func testStreamRequestShapeAndPiecesConcatenate() async throws {
        let parts = [Data([1, 2, 3]), Data([4, 5]), Data([6, 7, 8, 9, 10])]  // a sample split across parts
        let stub = Stub()
        let audio = try await withStub(stub, status: .ok, body: Data(), streaming: parts) { synthesizer in
            var all = Data()
            for try await piece in try await synthesizer.stream("hello there") {
                XCTAssertFalse(piece.isEmpty)
                XCTAssertTrue(piece.count.isMultiple(of: 2))
                all.append(piece)
            }
            return all
        }
        XCTAssertEqual(audio, Data(parts.joined()))
        XCTAssertEqual(stub.path, "/v1/audio/speech")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(stub.body.utf8)) as? [String: Any])
        XCTAssertEqual(object["input"] as? String, "hello there")
        XCTAssertEqual(object["response_format"] as? String, "pcm")
        XCTAssertEqual(object["stream"] as? Bool, true)
    }

    @MainActor func testStreamErrorsAreThrownBeforeAnyAudio() async throws {
        let cases: [(HTTPStatus, String)] = [
            (.internalServerError, "audio/pcm"), (.noContent, "audio/pcm"),
            (.ok, "audio/mpeg"), (.ok, "audio/wav"), (.ok, "application/octet-stream"), (.ok, "")
        ]
        for (status, type) in cases {
            do {
                _ = try await withStub(Stub(), status: status, body: Data([0, 0]), type: type) { _ = try await $0.stream("x") }
                XCTFail("Expected an error for \(status) \(type)")
            } catch is SpeechError {}
        }
    }

    func testBodyPullerNormalizesOddSplitsAndIgnoresEmptyPieces() async throws {
        let parts = [Data(), Data([1]), Data(), Data([2, 3, 4]), Data([5]), Data([6]), Data()]
        let puller = BodyPuller(TestBody(parts.map { ByteBuffer(bytes: $0) }))
        var result = [Data]()
        while let part = try await puller.next() { result.append(part) }
        XCTAssertEqual(result, [Data([1, 2, 3, 4]), Data([5, 6])])
    }

    func testBodyPullerRejectsEmptyAndTrailingByteEOF() async throws {
        for parts: [[UInt8]] in [[], [[]], [[1]], [[1, 2], [], [3]]] {
            let puller = BodyPuller(TestBody(parts.map { ByteBuffer(bytes: $0) }))
            do {
                while let _ = try await puller.next() {}
                XCTFail("Invalid EOF accepted")
            } catch is SpeechError {}
        }
    }

    func testPCMIsNotSniffedForContainerMagic() async throws {
        let pcm = Data("RIFFabcd".utf8)
        let puller = BodyPuller(TestBody([ByteBuffer(bytes: pcm)]))
        let result = try await puller.next()
        XCTAssertEqual(result, pcm)
        let eof = try await puller.next()
        XCTAssertNil(eof)
    }

    /// Each write is released by the test, not by a timer or a prebuffered body.
    @MainActor func testHTTPHeadersPiecesAndEOFAreIndependent() async throws {
        for type in ["audio/pcm", "audio/l16", "audio/x-pcm", "audio/pcm; rate=24000"] {
            try await withGatedHTTP { synthesizer, peer in
                let delivered = self.expectation(description: "PCM before EOF")
                let headers = self.expectation(description: "headers received")
                var received = Data()
                var finished = false
                let task = Task { @MainActor in
                    let stream = try await synthesizer.stream("fixture")
                    headers.fulfill()
                    for try await piece in stream {
                        XCTAssertFalse(peer.ended)
                        XCTAssertTrue(piece.count.isMultiple(of: 2))
                        received.append(piece)
                        delivered.fulfill()
                    }
                    finished = true
                }
                defer { task.cancel() }
                await self.fulfillment(of: [peer.requested], timeout: 3)
                XCTAssertFalse(finished)
                XCTAssertTrue(received.isEmpty)
                try await peer.send(.head(HTTPResponseHead(version: .http1_1, status: .ok,
                    headers: ["content-type": type, "transfer-encoding": "chunked"])))
                await self.fulfillment(of: [headers], timeout: 3)
                XCTAssertTrue(received.isEmpty, "Headers alone must not produce PCM")
                try await peer.send(.body(.byteBuffer(ByteBuffer(bytes: [1]))))
                try await peer.send(.body(.byteBuffer(ByteBuffer(bytes: [2, 3, 4]))))
                await self.fulfillment(of: [delivered], timeout: 3)
                XCTAssertEqual(received, Data([1, 2, 3, 4]))
                XCTAssertFalse(finished, "Consumer delivery must precede source EOF release")
                try await peer.end()
                try await task.value
                XCTAssertTrue(finished)
            }
        }
    }

    @MainActor private func withGatedHTTP(
        run: (KokoroSpeechSynthesizer, GatedHTTPPeer) async throws -> Void
    ) async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let peer = GatedHTTPPeer(requested: expectation(description: "request received"))
        let server = try await ServerBootstrap(group: group).childChannelInitializer { channel in
            channel.pipeline.configureHTTPServerPipeline().flatMap { channel.pipeline.addHandler(peer) }
        }.bind(host: "127.0.0.1", port: 0).get()
        let http = HTTPClient(eventLoopGroupProvider: .shared(group))
        let app = try await Application.make(.testing)
        do {
            let port = try XCTUnwrap(server.localAddress?.port)
            let config = try XCTUnwrap(KokoroConfig(environment: ["CONVOKE_KOKORO_URL": "http://127.0.0.1:\(port)"]))
            try await run(KokoroSpeechSynthesizer(client: app.client, config: config, http: http), peer)
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

    private struct TestBody: AsyncSequence {
        typealias Element = ByteBuffer
        let parts: [ByteBuffer]
        init(_ parts: [ByteBuffer]) { self.parts = parts }
        struct AsyncIterator: AsyncIteratorProtocol {
            var iterator: IndexingIterator<[ByteBuffer]>
            mutating func next() async throws -> ByteBuffer? { iterator.next() }
        }
        func makeAsyncIterator() -> AsyncIterator { AsyncIterator(iterator: parts.makeIterator()) }
    }

    /// The peer exposes protocol writes so HTTP read-ahead cannot turn this into
    /// a test of a fully buffered response. No content is logged or saved.
    private final class GatedHTTPPeer: ChannelInboundHandler, @unchecked Sendable {
        typealias InboundIn = HTTPServerRequestPart
        let requested: XCTestExpectation
        private let lock = NSLock()
        private var channel: Channel?
        private var eof = false
        var ended: Bool { lock.withLock { eof } }
        init(requested: XCTestExpectation) { self.requested = requested }
        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            if case .end = unwrapInboundIn(data) {
                lock.withLock { channel = context.channel }
                requested.fulfill()
            }
        }
        func send(_ part: HTTPServerResponsePart) async throws {
            let channel = try XCTUnwrap(lock.withLock { self.channel })
            try await channel.writeAndFlush(part).get()
        }
        func end() async throws {
            lock.withLock { eof = true }
            try await send(.end(nil))
        }
    }

    final class Stub: @unchecked Sendable { var path = "", body = "" }

    @MainActor private func withStub<T>(
        _ stub: Stub, status: HTTPStatus, body: Data, type: String = "audio/pcm", streaming: [Data]? = nil,
        _ run: (KokoroSpeechSynthesizer) async throws -> T
    ) async throws -> T {
        let app = try await Application.make(.testing)
        do {
            app.post("v1", "audio", "speech") { request -> Response in
                stub.path = request.url.path
                stub.body = request.body.string ?? ""
                if let streaming {
                    return Response(status: status, headers: ["content-type": type], body: .init(asyncStream: { writer in
                        for part in streaming { try await writer.write(.buffer(ByteBuffer(bytes: part))) }
                        try await writer.write(.end)
                    }))
                }
                return Response(status: status, headers: ["content-type": type], body: .init(data: body))
            }
            try await app.server.start(address: .hostname("127.0.0.1", port: 0))
            let port = try XCTUnwrap(app.http.server.shared.localAddress?.port)
            let config = try XCTUnwrap(KokoroConfig(environment: ["CONVOKE_KOKORO_URL": "http://127.0.0.1:\(port)"]))
            let result = try await run(KokoroSpeechSynthesizer(client: app.client, config: config, http: app.http.client.shared))
            await app.server.shutdown()
            try await app.asyncShutdown()
            return result
        } catch {
            await app.server.shutdown()
            try? await app.asyncShutdown()
            throw error
        }
    }
}
