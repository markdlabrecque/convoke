import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Vapor
import NIOCore
import NIOPosix
import NIOWebSocket
import WebSocketKit
@testable import ConvokeServer

/// Stands in for the model: replies "You said: <last user message>".
struct EchoTestAgent: Agent {
    func reply(to history: [ChatMessage]) async throws -> String { "You said: " + (history.last?.content ?? "") }
}

final class ConversationTests: XCTestCase {
    func testPrefixAndTrimmedUTF8Limit() throws {
        XCTAssertEqual(try reply(" \n hello 🌍 \t"), "hello 🌍")
        XCTAssertNoThrow(try reply(String(repeating: "é", count: 2048)))
        XCTAssertThrowsError(try reply(String(repeating: "é", count: 2049)))
        for text in ["", " \n\t "] { XCTAssertThrowsError(try reply(text)) }
    }

    func testMalformedAndUnexpectedInput() {
        for frame in ["no", "null", "[]", "{}", "{\"type\":\"agent.done\"}",
                      "{\"type\":\"user.text\",\"text\":42}",
                      "{\"type\":\"user.text\",\"text\":\"a\",\"extra\":true}"] {
            XCTAssertThrowsError(try ConversationProtocol.userText(from: frame))
        }
    }

    func testFrameByteBoundary() throws {
        let frame = try userText("a")
        let boundary = frame + String(repeating: " ", count: ConversationProtocol.maxFrameBytes - frame.utf8.count)
        XCTAssertEqual(try ConversationProtocol.userText(from: boundary), "a")
        XCTAssertThrowsError(try ConversationProtocol.userText(from: boundary + " "))
        XCTAssertThrowsError(try ConversationProtocol.json(["text": String(repeating: "x", count: 32768)]))
    }

    func testAudioBoundaries() {
        XCTAssertNoThrow(try ConversationProtocol.validateAudio(Data(repeating: 0, count: ConversationProtocol.maxAudioBytes)))
        for size in [0, 1, 3, ConversationProtocol.maxAudioBytes + 2] {
            XCTAssertThrowsError(try ConversationProtocol.validateAudio(Data(repeating: 0, count: size)))
        }
    }

    func testSequentialTurnsAndChunkCounts() async throws {
        let audio = Data((0..<40_002).map { UInt8($0 % 251) })
        try await withServer(synthesize: { text in
            XCTAssertTrue(text.hasPrefix("You said: "))
            return audio
        }) { socket in
                let wire = try await WireClient.connect(socket)
            for word in ["first", "second"] {
                try await wire.send(self.userText(" \(word) \n"))
                let text = try await wire.next()
                XCTAssertEqual(text["type"] as? String, "agent.text")
                XCTAssertEqual(text["text"] as? String, "You said: \(word)")
                var reconstructed = Data()
                for sequence in 0..<3 {
                    let frame = try await wire.next()
                    XCTAssertEqual(frame["type"] as? String, "agent.audio")
                    XCTAssertEqual(frame["sequence"] as? Int, sequence)
                    let chunk = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(frame["data"] as? String)))
                    XCTAssertLessThanOrEqual(chunk.count, 16384)
                    XCTAssertTrue(chunk.count.isMultiple(of: 2))
                    reconstructed.append(chunk)
                }
                XCTAssertEqual(reconstructed, audio)
                let done = try await wire.next()
                XCTAssertEqual(done["type"] as? String, "agent.done")
                XCTAssertEqual(done["chunks"] as? Int, 3)
            }
        }
    }

    func testExactChunkAndAudioCapCompletionCounts() async throws {
        for size in [2, 16_384, ConversationProtocol.maxAudioBytes] {
            try await withServer(synthesize: { _ in Data(repeating: 42, count: size) }) { socket in
                let wire = try await WireClient.connect(socket)
                try await wire.send(self.userText("boundary"))
                _ = try await wire.next()
                let expectedChunks = (size + 16_383) / 16_384
                var receivedBytes = 0
                for sequence in 0..<expectedChunks {
                    let frame = try await wire.next()
                    XCTAssertEqual(frame["type"] as? String, "agent.audio")
                    XCTAssertEqual(frame["sequence"] as? Int, sequence)
                    let data = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(frame["data"] as? String)))
                    XCTAssertEqual(data.count, min(16_384, size - receivedBytes))
                    receivedBytes += data.count
                }
                XCTAssertEqual(receivedBytes, size)
                let done = try await wire.next()
                XCTAssertEqual(done["type"] as? String, "agent.done")
                XCTAssertEqual(done["chunks"] as? Int, expectedChunks)
            }
        }
    }

    func testIncrementalCumulativeBoundaryOnWire() async throws {
        let cap = ConversationProtocol.maxAudioBytes
        for total in [cap - 2, cap, cap + 2] {
            let source = BoundarySource(bytes: total)
            try await withServer(stream: { _ in AsyncThrowingStream(unfolding: { await source.next() }) }) { socket in
                let wire = try await WireClient.connect(socket)
                try await wire.send(self.userText("fixture"))
                let text = try await wire.next()
                XCTAssertEqual(text["type"] as? String, "agent.text")
                var bytes = 0, chunks = 0
                var completed = false
                do {
                    while true {
                        let frame = try await wire.next()
                        if frame["type"] as? String == "agent.done" {
                            XCTAssertEqual(frame["chunks"] as? Int, chunks)
                            completed = true
                            break
                        }
                        XCTAssertEqual(frame["type"] as? String, "agent.audio")
                        XCTAssertEqual(frame["sequence"] as? Int, chunks)
                        let pcm = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(frame["data"] as? String)))
                        XCTAssertFalse(pcm.isEmpty)
                        XCTAssertTrue(pcm.count.isMultiple(of: 2))
                        XCTAssertLessThanOrEqual(pcm.count, 16_384)
                        bytes += pcm.count
                        chunks += 1
                    }
                } catch {
                    if total <= cap { throw error }
                }
                XCTAssertEqual(completed, total <= cap)
                XCTAssertLessThanOrEqual(bytes, cap)
                if completed { XCTAssertEqual(bytes, total) }
                else { XCTAssertEqual(wire.closeCode, .unexpectedServerError) }
            }
        }
    }

    private actor BoundarySource {
        var remaining: Int
        var pulls = 0
        init(bytes: Int) { remaining = bytes }
        func next() -> Data? {
            guard remaining > 0 else { return nil }
            let size = min(remaining, pulls.isMultiple(of: 2) ? 16_383 : 16_385)
            pulls += 1
            remaining -= size
            return Data(repeating: UInt8(pulls % 251), count: size)
        }
    }

    func testAudioIsSentBeforeSynthesisFinishes() async throws {
        let (pieces, feed) = AsyncThrowingStream<Data, Error>.makeStream()
        try await withServer(stream: { _ in pieces }) { socket in
            let wire = try await WireClient.connect(socket)
            try await wire.send(self.userText("hi"))
            let text = try await wire.next()
            XCTAssertEqual(text["type"] as? String, "agent.text")
            feed.yield(Data(repeating: 1, count: 100))
            // Synthesis has not finished, yet the first frame arrives.
            let first = try await wire.next()
            XCTAssertEqual(first["type"] as? String, "agent.audio")
            XCTAssertEqual(first["sequence"] as? Int, 0)
            XCTAssertEqual(Data(base64Encoded: try XCTUnwrap(first["data"] as? String)), Data(repeating: 1, count: 100))
            // A piece may split a 16-bit sample: the odd byte joins the next piece.
            feed.yield(Data([5]))
            feed.yield(Data([6, 7, 8]))
            let second = try await wire.next()
            XCTAssertEqual(second["sequence"] as? Int, 1)
            XCTAssertEqual(Data(base64Encoded: try XCTUnwrap(second["data"] as? String)), Data([5, 6, 7, 8]))
            feed.finish()
            let done = try await wire.next()
            XCTAssertEqual(done["type"] as? String, "agent.done")
            XCTAssertEqual(done["chunks"] as? Int, 2)
            // The connection takes a second turn.
            try await wire.send(self.userText("again"))
            let again = try await wire.next()
            XCTAssertEqual(again["type"] as? String, "agent.text")
        }
    }

    func testStreamFailuresAfterPartialAudioCloseWithoutDone() async throws {
        enum Failure: CaseIterable { case thrown, oddFinalByte, empty, overCap }
        for failure in Failure.allCases {
            try await withServer(stream: { _ in
                AsyncThrowingStream<Data, Error> { continuation in
                    switch failure {
                    case .thrown:
                        continuation.yield(Data([0, 0]))
                        continuation.finish(throwing: SpeechError.http(status: 500))
                    case .oddFinalByte:
                        continuation.yield(Data([1, 2, 3]))
                        continuation.finish()
                    case .empty:
                        continuation.finish()
                    case .overCap:
                        for _ in 0...8 { continuation.yield(Data(repeating: 0, count: 1 << 20)) }
                        continuation.finish()
                    }
                }
            }) { socket in
                let wire = try await WireClient.connect(socket)
                try await wire.send(self.userText("test"))
                var audioFrames = 0
                var sawDone = false
                do {
                    while true {
                        let frame = try await wire.next()
                        if frame["type"] as? String == "agent.done" { sawDone = true }
                        if frame["type"] as? String == "agent.audio" { audioFrames += 1 }
                    }
                } catch {}  // The connection closed.
                XCTAssertFalse(sawDone, "\(failure) must not complete the turn")
                XCTAssertEqual(wire.closeCode, .unexpectedServerError, "Partial source/output failures are 1011")
                XCTAssertLessThanOrEqual(audioFrames, ConversationProtocol.maxAudioBytes / ConversationProtocol.maxChunkBytes)
            }
        }
    }

    func testDisconnectCancelsStreamingSynthesis() async throws {
        let cancelled = expectation(description: "Stream consumer cancelled")
        let started = expectation(description: "Stream started")
        try await withServer(stream: { _ in
            AsyncThrowingStream<Data, Error> { continuation in
                continuation.yield(Data([0, 0]))
                started.fulfill()
                continuation.onTermination = { _ in cancelled.fulfill() }
            }
        }) { socket in
            try await socket.send(.string(self.userText("test")))
            await self.fulfillment(of: [started], timeout: 3)
            socket.cancel(with: .goingAway, reason: nil)
            await self.fulfillment(of: [cancelled], timeout: 3)
        }
    }

    @MainActor func testGatedSocketAndSynthesisOrderingAcrossTwoTurns() async throws {
        let app = try await Application.make(.testing)
        let source = GatedSynthesis()
        let (attempts, feed) = AsyncStream<WriteAttempt>.makeStream()
        var writes = attempts.makeAsyncIterator()
        app.get("conversation") { _ -> Response in
            let response = Response(status: .switchingProtocols)
            response.upgrader = ConversationUpgrader { socket in
                _ = Conversation(socket: socket, timeout: .seconds(10), agent: EchoTestAgent(),
                    synthesize: { _ in fatalError("must use the consumer boundary") },
                    consume: { _, consumer in try await source.produce(on: socket.eventLoop, consumer: consumer) },
                    sendFrame: { frame in
                        let gate = socket.eventLoop.makePromise(of: Void.self)
                        feed.yield(WriteAttempt(frame: frame, gate: gate))
                        return gate.futureResult.flatMap {
                            let sent = socket.eventLoop.makePromise(of: Void.self)
                            socket.send(frame, promise: sent)
                            return sent.futureResult
                        }
                    })
            }
            return response
        }
        do {
            try await app.server.start(address: .hostname("127.0.0.1", port: 0))
            let port = try XCTUnwrap(app.http.server.shared.localAddress?.port)
            defer { feed.finish() }
            let socket = try await TestWebSocket.connect(to: URL(string: "ws://127.0.0.1:\(port)/conversation")!)
            let wire = try await WireClient.connect(socket)
            let watchdog = Task {
                try await Task.sleep(nanoseconds: 20_000_000_000)
                feed.finish()
                await app.server.shutdown()
            }
            defer { watchdog.cancel() }
            for turn in 1...2 {
                try await wire.send(self.userText("fixture"))
                let textAttempt = await writes.next()
                let text = try XCTUnwrap(textAttempt)
                XCTAssertEqual(try text.object()["type"] as? String, "agent.text")
                XCTAssertEqual(source.calls, turn - 1, "Synthesis waits for the text write")
                text.gate.succeed(())
                let receivedText = try await wire.next()
                XCTAssertEqual(receivedText["type"] as? String, "agent.text")

                let firstAttempt = await writes.next()
                let first = try XCTUnwrap(firstAttempt)
                XCTAssertEqual(source.afterFirst, turn - 1, "Source is suspended inside the first socket write")
                XCTAssertEqual(try first.object()["sequence"] as? Int, 0)
                first.gate.succeed(())
                let firstAudio = try await wire.next()
                XCTAssertEqual(Data(base64Encoded: try XCTUnwrap(firstAudio["data"] as? String)), Data(repeating: 1, count: 16_384))

                let secondAttempt = await writes.next()
                let second = try XCTUnwrap(secondAttempt)
                XCTAssertEqual(source.completed, turn - 1, "Forwarded audio precedes source EOF")
                XCTAssertEqual(try second.object()["sequence"] as? Int, 1)
                second.gate.succeed(())
                let secondAudio = try await wire.next()
                XCTAssertEqual(Data(base64Encoded: try XCTUnwrap(secondAudio["data"] as? String)), Data([1, 2]), "Preserve the carried sample")
                await fulfillment(of: [source.atEOF[turn - 1]], timeout: 3)
                XCTAssertEqual(source.completed, turn - 1)
                source.eof[turn - 1].succeed(())
                let doneAttempt = await writes.next()
                let done = try XCTUnwrap(doneAttempt)
                XCTAssertEqual(try done.object()["type"] as? String, "agent.done")
                XCTAssertEqual(try done.object()["chunks"] as? Int, 2)
                XCTAssertEqual(source.completed, turn)
                done.gate.succeed(())
                let receivedDone = try await wire.next()
                XCTAssertEqual(receivedDone["type"] as? String, "agent.done")
            }
        } catch {
            await app.server.shutdown()
            try? await app.asyncShutdown()
            throw error
        }
        await app.server.shutdown()
        try await app.asyncShutdown()
    }

    private struct WriteAttempt {
        let frame: String
        let gate: EventLoopPromise<Void>
        func object() throws -> [String: Any] {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(frame.utf8)) as? [String: Any])
        }
    }

    @MainActor private final class GatedSynthesis {
        var calls = 0, afterFirst = 0, completed = 0
        var eof: [EventLoopPromise<Void>] = []
        let atEOF = (0..<2).map { XCTestExpectation(description: "source waiting at EOF \($0)") }
        func produce(on loop: any EventLoop, consumer: PCMConsumer) async throws {
            let index = calls
            calls += 1
            let gate = loop.makePromise(of: Void.self)
            eof.append(gate)
            try await consumer(Data(repeating: 1, count: 16_385))
            afterFirst += 1
            try await consumer(Data([2]))
            try await CancellableWrite.run(on: loop) {
                self.atEOF[index].fulfill()
                return gate.futureResult
            }
            completed += 1
        }
    }

    func testAudioFramerSplitsCarriesAndEnforcesCap() throws {
        var framer = AudioFramer()
        XCTAssertEqual(try framer.push(Data([1])).count, 0)
        let chunks = try framer.push(Data(repeating: 9, count: 16_384 * 2))  // 1 carried + 32768 = odd
        XCTAssertEqual(chunks.map(\.count), [16_384, 16_384])
        XCTAssertThrowsError(try framer.finish(), "A carried half sample is invalid")
        XCTAssertNoThrow(try framer.push(Data([0])))
        XCTAssertNoThrow(try framer.finish())
        var empty = AudioFramer()
        XCTAssertThrowsError(try empty.finish())
        var capped = AudioFramer()
        for _ in 0..<8 { XCTAssertNoThrow(try capped.push(Data(repeating: 0, count: 1 << 20))) }
        XCTAssertNoThrow(try capped.finish(), "Exactly 8 MiB is valid")
        XCTAssertThrowsError(try capped.push(Data([0])), "Even one byte beyond the cap fails")
        XCTAssertThrowsError(try capped.push(Data([0, 0])))
    }

    func testSampleAndFrameBoundaryMatrixAndCumulativeCarryCap() throws {
        let pcm = Data((0..<32_772).map { UInt8($0 % 251) })
        for split in [0, 1, 2, 16_383, 16_384, 16_385, 32_769, pcm.count] {
            var framer = AudioFramer()
            let first = try framer.push(Data(pcm.prefix(split)))
            XCTAssertEqual(first.reduce(0) { $0 + $1.count }, split - split % 2,
                           "Forward whole samples immediately, not only full frames")
            let rest = try framer.push(Data(pcm.dropFirst(split)))
            let chunks = first + rest
            XCTAssertEqual(Data(chunks.joined()), pcm, "Split \(split) preserves every byte in order")
            for chunk in chunks {
                XCTAssertFalse(chunk.isEmpty)
                XCTAssertTrue(chunk.count.isMultiple(of: 2))
                XCTAssertLessThanOrEqual(chunk.count, 16_384)
            }
            XCTAssertEqual(framer.totalBytes, pcm.count)
            try framer.finish()
        }
        var exact = AudioFramer()
        for _ in 0..<511 { _ = try exact.push(Data(count: 16_384)) }
        _ = try exact.push(Data(count: 16_383))
        XCTAssertThrowsError(try exact.finish(), "An odd total just below the cap is not valid EOF")
        _ = try exact.push(Data([7]))
        XCTAssertEqual(exact.totalBytes, ConversationProtocol.maxAudioBytes)
        try exact.finish()
        XCTAssertThrowsError(try exact.push(Data([8])), "The carried half-sample counts against the cumulative cap")
    }

    func testInvalidFramesCloseConnection() async throws {
        let invalid: [URLSessionWebSocketTask.Message] = [
            .string("{"), .string(try userText(" \n")),
            .string(try userText(String(repeating: "a", count: 4097))),
            .string("{\"type\":\"agent.done\"}"), .data(Data([0, 1])),
            .string(String(repeating: "x", count: 32769)),
        ]
        for frame in invalid {
            try await withServer(synthesize: { _ in
                XCTFail("Invalid input reached synthesis")
                return Data([0, 0])
            }) { socket in
                try await socket.send(frame)
                await self.assertClosed(socket)
            }
        }
    }

    func testMalformedUTF8UnknownOpcodeAndFragmentedOverflowClose() async throws {
        for mode in 0..<3 {
            try await withServer(synthesize: { _ in
                XCTFail("Invalid wire input reached synthesis")
                return Data([0, 0])
            }) { client in
                let closed = self.expectation(description: "Raw socket closed")
                try await WebSocket.connect(
                    to: client.originalRequest!.url!.absoluteString.replacingOccurrences(of: "http://", with: "ws://"),
                    on: MultiThreadedEventLoopGroup.singleton
                ) { socket in
                    socket.onText { _, _ in XCTFail("Invalid input produced a response") }
                    socket.onClose.whenComplete { _ in closed.fulfill() }
                    if mode == 2 {
                        socket.send(raw: Data(repeating: 32, count: 20_000), opcode: .text, fin: false)
                        socket.send(raw: Data(repeating: 32, count: 20_000), opcode: .continuation, fin: false)
                    } else if mode == 1 {
                        socket.send(raw: Data(), opcode: .init(encodedWebSocketOpcode: 3)!)
                    } else {
                        var bytes = Data("{\"type\":\"user.text\",\"text\":\"".utf8)
                        bytes.append(0xFF)
                        bytes.append(contentsOf: "\"}".utf8)
                        socket.send(raw: bytes, opcode: .text)
                    }
                }.get()
                await self.fulfillment(of: [closed], timeout: 3)
            }
        }
    }

    func testFragmentedUTF8MessageIsAccepted() async throws {
        try await withServer(synthesize: { _ in Data([0, 0]) }) { client in
            let completed = self.expectation(description: "Fragmented turn completed")
            try await WebSocket.connect(
                to: client.originalRequest!.url!.absoluteString.replacingOccurrences(of: "http://", with: "ws://"),
                on: MultiThreadedEventLoopGroup.singleton
            ) { socket in
                socket.onText { socket, text in
                    do {
                        let frame = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
                        if frame["type"] as? String == "agent.text" {
                            XCTAssertEqual(frame["text"] as? String, "You said: é")
                        }
                        if frame["type"] as? String == "agent.done" {
                            completed.fulfill()
                            socket.close(code: .normalClosure, promise: nil)
                        }
                    } catch { XCTFail("Invalid server JSON") }
                }
                var first = Data("{\"type\":\"user.text\",\"text\":\"".utf8)
                first.append(0xC3)
                socket.send(raw: first, opcode: .text, fin: false)
                socket.send(raw: Data([0xA9, 0x22, 0x7D]), opcode: .continuation)
            }.get()
            await self.fulfillment(of: [completed], timeout: 3)
        }
    }

    func testHistoryGrowsPerConnectionAndFailureClosesLoudly() async throws {
        final class Recorder: Agent, @unchecked Sendable {
            let lock = NSLock()
            var seen: [[ChatMessage]] = []
            func reply(to history: [ChatMessage]) async throws -> String {
                lock.lock(); seen.append(history); let n = seen.count; lock.unlock()
                if history.last?.content == "boom" { throw AgentError.http(status: 500) }
                return "reply \(n)"
            }
        }
        let recorder = Recorder()
        try await withServer(agent: recorder, synthesize: { _ in Data([0, 0]) }) { socket in
            for word in ["one", "two"] {
                try await socket.send(.string(self.userText(word)))
                _ = try await self.receive(socket)
                while try await self.receive(socket)["type"] as? String != "agent.done" {}
            }
            XCTAssertEqual(recorder.seen[1].map(\.content), ["one", "reply 1", "two"])
            XCTAssertEqual(recorder.seen[1].map(\.role), [.user, .assistant, .user])
            try await socket.send(.string(self.userText("boom")))
            await self.assertClosed(socket)
            XCTAssertEqual(socket.closeCode, .internalServerError)
        }
    }

    func testSynthesisFailuresCloseConnection() async throws {
        let synthesizers: [Conversation.Synthesize] = [
            { _ in throw ConversationError.synthesisFailed },
            { try await UnavailableSpeechSynthesizer().synthesize($0) },
            { _ in Data() }, { _ in Data([1]) },
            { _ in Data(repeating: 0, count: ConversationProtocol.maxAudioBytes + 2) },
        ]
        for synthesize in synthesizers {
            try await withServer(synthesize: synthesize) { socket in
                try await socket.send(.string(self.userText("test")))
                let text = try await self.receive(socket)
                XCTAssertEqual(text["type"] as? String, "agent.text")
                await self.assertClosed(socket)
                XCTAssertEqual(socket.closeCode, .internalServerError, "Server-side speech failure closes with 1011")
            }
        }
    }

    func testOverlappingTurnClosesAndCancelsSynthesis() async throws {
        let cancelled = expectation(description: "Synthesis cancelled")
        try await withServer(synthesize: { _ in
            do {
                try await Task.sleep(nanoseconds: 30_000_000_000)
                return Data([0, 0])
            } catch { cancelled.fulfill(); throw error }
        }) { socket in
            try await socket.send(.string(self.userText("one")))
            _ = try await self.receive(socket)
            try await socket.send(.string(self.userText("two")))
            await self.assertClosed(socket)
        }
        await fulfillment(of: [cancelled], timeout: 3)
    }

    func testTimeoutClosesAndCancelsSynthesis() async throws {
        let cancelled = expectation(description: "Timed out synthesis cancelled")
        try await withServer(timeout: .milliseconds(100), synthesize: { _ in
            do {
                try await Task.sleep(nanoseconds: 30_000_000_000)
                return Data([0, 0])
            } catch { cancelled.fulfill(); throw error }
        }) { socket in
            try await socket.send(.string(self.userText("test")))
            _ = try await self.receive(socket)
            await self.assertClosed(socket)
        }
        await fulfillment(of: [cancelled], timeout: 3)
    }

    func testDisconnectCancelsSynthesis() async throws {
        let started = expectation(description: "Synthesis started")
        let cancelled = expectation(description: "Disconnected synthesis cancelled")
        try await withServer(synthesize: { _ in
            started.fulfill()
            do {
                try await Task.sleep(nanoseconds: 30_000_000_000)
                return Data([0, 0])
            } catch { cancelled.fulfill(); throw error }
        }) { socket in
            try await socket.send(.string(self.userText("test")))
            await self.fulfillment(of: [started], timeout: 3)
            socket.cancel(with: .goingAway, reason: nil)
            await self.fulfillment(of: [cancelled], timeout: 3)
        }
    }

#if canImport(AVFoundation)
    // Explicit opt-in: normal tests need neither installed voices nor audio hardware.
    func testSystemVoiceSmoke() async throws {
        guard ProcessInfo.processInfo.environment["CONVOKE_TEST_SYSTEM_VOICE"] == "1" else {
            throw XCTSkip("Set CONVOKE_TEST_SYSTEM_VOICE=1 to exercise the installed macOS voice")
        }
        try await withServer(synthesize: { try await MacSpeechSynthesizer().synthesize($0) }) { socket in
            for word in ["hello", "again"] {
                try await socket.send(.string(self.userText(word)))
                let text = try await self.receive(socket)
                XCTAssertEqual(text["text"] as? String, "You said: \(word)")
                var audio = Data()
                var count = 0
                while true {
                    let frame = try await self.receive(socket)
                    if frame["type"] as? String == "agent.done" {
                        XCTAssertEqual(frame["chunks"] as? Int, count)
                        break
                    }
                    XCTAssertEqual(frame["type"] as? String, "agent.audio")
                    XCTAssertEqual(frame["sequence"] as? Int, count)
                    let chunk = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(frame["data"] as? String)))
                    XCTAssertLessThanOrEqual(chunk.count, 16384)
                    audio.append(chunk)
                    count += 1
                }
                try ConversationProtocol.validateAudio(audio)
                XCTAssertTrue(audio.contains { $0 != 0 }, "Voice must produce non-silent PCM")
            }
        }
    }
#endif

    // Opt-in: needs a running Kokoro sidecar, e.g. CONVOKE_TEST_KOKORO_URL=http://127.0.0.1:8880.
    // Prints sizes and timings only; audio is neither saved nor logged.
    @MainActor func testKokoroSidecarSmoke() async throws {
        guard let url = ProcessInfo.processInfo.environment["CONVOKE_TEST_KOKORO_URL"] else {
            throw XCTSkip("Set CONVOKE_TEST_KOKORO_URL to exercise a real Kokoro sidecar")
        }
        var environment = ["CONVOKE_KOKORO_URL": url]
        environment["CONVOKE_KOKORO_VOICE"] = ProcessInfo.processInfo.environment["CONVOKE_KOKORO_VOICE"]
        let config = try XCTUnwrap(KokoroConfig(environment: environment))
        let httpApp = try await Application.make(.testing)
        let source = SmokeSource(KokoroSpeechSynthesizer(client: httpApp.client, config: config, http: httpApp.http.client.shared))
        do {
            try await withServer(timeout: .seconds(60), stream: { try await source.stream($0) }) { socket in
                let wire = try await WireClient.connect(socket)
                let start = ContinuousClock.now
                source.start = start
                try await wire.send(self.userText("Testing one two three."))
                let reply = try await wire.next()
                XCTAssertEqual(reply["type"] as? String, "agent.text")
                var firstChunk: Duration?
                var bytes = 0, chunks = 0
                var nonSilent = false
                while true {
                    let frame = try await wire.next()
                    if frame["type"] as? String == "agent.done" {
                        XCTAssertEqual(frame["chunks"] as? Int, chunks)
                        break
                    }
                    XCTAssertEqual(frame["type"] as? String, "agent.audio")
                    XCTAssertEqual(frame["sequence"] as? Int, chunks)
                    if firstChunk == nil { firstChunk = ContinuousClock.now - start }
                    let chunk = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(frame["data"] as? String)))
                    XCTAssertFalse(chunk.isEmpty)
                    XCTAssertTrue(chunk.count.isMultiple(of: 2))
                    XCTAssertLessThanOrEqual(chunk.count, 16384)
                    nonSilent = nonSilent || chunk.contains { $0 != 0 }
                    bytes += chunk.count
                    chunks += 1
                }
                let total = ContinuousClock.now - start
                XCTAssertTrue(nonSilent)
                XCTAssertTrue(bytes.isMultiple(of: 2))
                XCTAssertGreaterThan(chunks, 1, "A sentence is more than one 16 KiB chunk")
                XCTAssertLessThanOrEqual(bytes, ConversationProtocol.maxAudioBytes)
                XCTAssertEqual(source.bytes, bytes)
                let firstPCM = try XCTUnwrap(source.firstPCM)
                let synthesisEOF = try XCTUnwrap(source.eof)
                XCTAssertLessThanOrEqual(firstPCM, synthesisEOF)
                print("KOKORO-SMOKE bytes=\(bytes) audioSeconds=\(Double(bytes) / 48_000) chunks=\(chunks) sourcePieces=\(source.pieces) firstPCM=\(firstPCM) synthesisEOF=\(synthesisEOF) firstWireAudio=\(firstChunk!) wireDone=\(total)")
                // These same-clock measurements describe synthesis and transport only.
                // Neither multiple chunks nor this test proves early physical playback.
            }
        } catch {
            try? await httpApp.asyncShutdown()
            throw error
        }
        try await httpApp.asyncShutdown()
    }

    @MainActor private final class SmokeSource {
        let synthesizer: KokoroSpeechSynthesizer
        var iterator: AsyncThrowingStream<Data, Error>.Iterator?
        var start = ContinuousClock.now
        var firstPCM: Duration?, eof: Duration?
        var bytes = 0, pieces = 0
        init(_ synthesizer: KokoroSpeechSynthesizer) { self.synthesizer = synthesizer }
        func stream(_ text: String) async throws -> AsyncThrowingStream<Data, Error> {
            iterator = try await synthesizer.stream(text).makeAsyncIterator()
            return AsyncThrowingStream(unfolding: { try await self.next() })
        }
        func next() async throws -> Data? {
            guard var iterator else { throw ConversationError.invalidAudio }
            let piece = try await iterator.next()
            self.iterator = iterator
            if let piece {
                if firstPCM == nil { firstPCM = ContinuousClock.now - start }
                pieces += 1
                bytes += piece.count
            } else { eof = ContinuousClock.now - start }
            return piece
        }
    }

    private func userText(_ text: String) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: ["type": "user.text", "text": text]), as: UTF8.self)
    }

    private func reply(_ text: String) throws -> String {
        try ConversationProtocol.userText(from: userText(text))
    }

    private func receive(_ socket: TestWebSocket) async throws -> [String: Any] {
        guard case .string(let text) = try await socket.receive() else {
            throw ConversationError.invalidMessage
        }
        XCTAssertLessThanOrEqual(text.utf8.count, ConversationProtocol.maxFrameBytes)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    private func assertClosed(_ socket: TestWebSocket, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await socket.receive()
            XCTFail("Expected connection closure, not another frame", file: file, line: line)
        } catch {
            XCTAssertNotEqual(socket.closeCode, .invalid, "Server must send a close frame", file: file, line: line)
        }
    }

    private func withServer(
        timeout: TimeAmount = .seconds(10),
        agent: any Agent = EchoTestAgent(),
        synthesize: Conversation.Synthesize? = nil,
        stream: Conversation.SynthesizeStream? = nil,
        body: (TestWebSocket) async throws -> Void
    ) async throws {
        let app = try await Application.make(.testing)
        do {
            try configure(app, turnTimeout: timeout, synthesize: synthesize, stream: stream, agent: agent)
            try await app.server.start(address: .hostname("127.0.0.1", port: 0))
            let port = try XCTUnwrap(app.http.server.shared.localAddress?.port)
            let socket = try await TestWebSocket.connect(to: URL(string: "ws://127.0.0.1:\(port)/conversation")!)
            let watchdog = Task {
                try await Task.sleep(nanoseconds: 20_000_000_000)
                socket.cancel(with: .goingAway, reason: nil)
            }
            defer {
                watchdog.cancel()
                socket.cancel(with: .goingAway, reason: nil)
            }
            try await body(socket)
            socket.cancel(with: .goingAway, reason: nil)
            await app.server.shutdown()
            try await app.asyncShutdown()
        } catch {
            await app.server.shutdown()
            try? await app.asyncShutdown()
            throw error
        }
    }
}

/// A WebSocketKit client. Unlike URLSessionWebSocketTask on Linux it reads whole large frames,
/// so chunked audio can be checked on every platform.
private final class WireClient {
    private let socket: WebSocket
    private var frames: AsyncStream<[String: Any]>.AsyncIterator

    private init(socket: WebSocket, frames: AsyncStream<[String: Any]>.AsyncIterator) {
        self.socket = socket
        self.frames = frames
    }

    static func connect(_ peer: TestWebSocket) async throws -> WireClient {
        let url = peer.originalRequest!.url!.absoluteString.replacingOccurrences(of: "http://", with: "ws://")
        let (stream, continuation) = AsyncStream<[String: Any]>.makeStream()
        let socket: WebSocket = try await withCheckedThrowingContinuation { opened in
            WebSocket.connect(
                to: url, configuration: .init(maxFrameSize: 1 << 20), on: MultiThreadedEventLoopGroup.singleton
            ) { socket in
                socket.onText { _, text in
                    if let frame = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] {
                        continuation.yield(frame)
                    }
                }
                socket.onClose.whenComplete { _ in continuation.finish() }
                opened.resume(returning: socket)
            }.whenFailure { opened.resume(throwing: $0) }
        }
        return WireClient(socket: socket, frames: stream.makeAsyncIterator())
    }

    var closeCode: WebSocketErrorCode? { socket.closeCode }

    func send(_ text: String) async throws { try await socket.send(text) }

    func next() async throws -> [String: Any] {
        guard let frame = await frames.next() else { throw ConversationError.invalidMessage }
        return frame
    }

    deinit { socket.close(code: .normalClosure, promise: nil) }
}
