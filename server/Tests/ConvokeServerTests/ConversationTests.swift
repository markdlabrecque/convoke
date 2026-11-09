import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Vapor
import NIOCore
import NIOPosix
import WebSocketKit
@testable import ConvokeServer

final class ConversationTests: XCTestCase {
    func testPrefixAndTrimmedUTF8Limit() throws {
        XCTAssertEqual(try reply(" \n hello 🌍 \t"), "You said: hello 🌍")
        XCTAssertNoThrow(try reply(String(repeating: "é", count: 2048)))
        XCTAssertThrowsError(try reply(String(repeating: "é", count: 2049)))
        for text in ["", " \n\t "] { XCTAssertThrowsError(try reply(text)) }
    }

    func testMalformedAndUnexpectedInput() {
        for frame in ["no", "null", "[]", "{}", "{\"type\":\"agent.done\"}",
                      "{\"type\":\"user.text\",\"text\":42}",
                      "{\"type\":\"user.text\",\"text\":\"a\",\"extra\":true}"] {
            XCTAssertThrowsError(try ConversationProtocol.reply(to: frame))
        }
    }

    func testFrameByteBoundary() throws {
        let frame = try userText("a")
        let boundary = frame + String(repeating: " ", count: ConversationProtocol.maxFrameBytes - frame.utf8.count)
        XCTAssertEqual(try ConversationProtocol.reply(to: boundary), "You said: a")
        XCTAssertThrowsError(try ConversationProtocol.reply(to: boundary + " "))
        XCTAssertThrowsError(try ConversationProtocol.json(["text": String(repeating: "x", count: 32768)]))
    }

    func testAudioBoundaries() {
        XCTAssertNoThrow(try ConversationProtocol.validateAudio(Data(repeating: 0, count: ConversationProtocol.maxAudioBytes)))
        for size in [0, 1, 3, ConversationProtocol.maxAudioBytes + 2] {
            XCTAssertThrowsError(try ConversationProtocol.validateAudio(Data(repeating: 0, count: size)))
        }
    }

    func testSequentialTurnsAndChunkCounts() async throws {
        #if os(Linux)
        // swift-corelibs URLSessionWebSocketTask hands back messages cut at ~16 KiB, so
        // multi-chunk audio frames cannot be read by this client on Linux.
        throw XCTSkip("URLSessionWebSocketTask truncates large messages on Linux")
        #endif
        let audio = Data((0..<40_002).map { UInt8($0 % 251) })
        try await withServer(synthesize: { text in
            XCTAssertTrue(text.hasPrefix("You said: "))
            return audio
        }) { socket in
            for word in ["first", "second"] {
                try await socket.send(.string(self.userText(" \(word) \n")))
                let text = try await self.receive(socket)
                XCTAssertEqual(text["type"] as? String, "agent.text")
                XCTAssertEqual(text["text"] as? String, "You said: \(word)")
                var reconstructed = Data()
                for sequence in 0..<3 {
                    let frame = try await self.receive(socket)
                    XCTAssertEqual(frame["type"] as? String, "agent.audio")
                    XCTAssertEqual(frame["sequence"] as? Int, sequence)
                    let chunk = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(frame["data"] as? String)))
                    XCTAssertLessThanOrEqual(chunk.count, 16384)
                    XCTAssertTrue(chunk.count.isMultiple(of: 2))
                    reconstructed.append(chunk)
                }
                XCTAssertEqual(reconstructed, audio)
                let done = try await self.receive(socket)
                XCTAssertEqual(done["type"] as? String, "agent.done")
                XCTAssertEqual(done["chunks"] as? Int, 3)
            }
        }
    }

    func testExactChunkAndAudioCapCompletionCounts() async throws {
        #if os(Linux)
        // swift-corelibs URLSessionWebSocketTask hands back messages cut at ~16 KiB, so
        // multi-chunk audio frames cannot be read by this client on Linux.
        throw XCTSkip("URLSessionWebSocketTask truncates large messages on Linux")
        #endif
        for size in [2, 16_384, ConversationProtocol.maxAudioBytes] {
            try await withServer(synthesize: { _ in Data(repeating: 42, count: size) }) { socket in
                try await socket.send(.string(self.userText("boundary")))
                _ = try await self.receive(socket)
                let expectedChunks = (size + 16_383) / 16_384
                var receivedBytes = 0
                for sequence in 0..<expectedChunks {
                    let frame = try await self.receive(socket)
                    XCTAssertEqual(frame["type"] as? String, "agent.audio")
                    XCTAssertEqual(frame["sequence"] as? Int, sequence)
                    let data = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(frame["data"] as? String)))
                    XCTAssertEqual(data.count, min(16_384, size - receivedBytes))
                    receivedBytes += data.count
                }
                XCTAssertEqual(receivedBytes, size)
                let done = try await self.receive(socket)
                XCTAssertEqual(done["type"] as? String, "agent.done")
                XCTAssertEqual(done["chunks"] as? Int, expectedChunks)
            }
        }
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

    private func userText(_ text: String) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: ["type": "user.text", "text": text]), as: UTF8.self)
    }

    private func reply(_ text: String) throws -> String {
        try ConversationProtocol.reply(to: userText(text))
    }

    private func receive(_ socket: URLSessionWebSocketTask) async throws -> [String: Any] {
        guard case .string(let text) = try await socket.receive() else {
            throw ConversationError.invalidMessage
        }
        XCTAssertLessThanOrEqual(text.utf8.count, ConversationProtocol.maxFrameBytes)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    private func assertClosed(_ socket: URLSessionWebSocketTask, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await socket.receive()
            XCTFail("Expected connection closure, not another frame", file: file, line: line)
        } catch {
            XCTAssertNotEqual(socket.closeCode, .invalid, "Server must send a close frame", file: file, line: line)
        }
    }

    private func withServer(
        timeout: TimeAmount = .seconds(10),
        synthesize: @escaping Conversation.Synthesize,
        body: (URLSessionWebSocketTask) async throws -> Void
    ) async throws {
        let app = try await Application.make(.testing)
        do {
            try configure(app, turnTimeout: timeout, synthesize: synthesize)
            try await app.server.start(address: .hostname("127.0.0.1", port: 0))
            let port = try XCTUnwrap(app.http.server.shared.localAddress?.port)
            let session = URLSession(configuration: .ephemeral)
            let socket = session.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)/conversation")!)
            let watchdog = Task {
                try await Task.sleep(nanoseconds: 20_000_000_000)
                socket.cancel(with: .goingAway, reason: nil)
            }
            defer {
                watchdog.cancel()
                socket.cancel(with: .goingAway, reason: nil)
                session.invalidateAndCancel()
            }
            socket.resume()
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
