import XCTest
@testable import ConvokeCore

final class ResponseDecodingTests: XCTestCase {
    private func frame(_ object: [String: Any]) throws -> URLSessionWebSocketTask.Message {
        .string(String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self))
    }
    private func text() throws -> URLSessionWebSocketTask.Message {
        try frame(["type": "agent.text", "text": "You said: hello"])
    }
    private func audio(_ bytes: Int = 2, sequence: Int = 0) throws -> URLSessionWebSocketTask.Message {
        try frame(["type": "agent.audio", "sequence": sequence,
                   "data": Data(repeating: 128, count: bytes).base64EncodedString()])
    }
    private func done(_ count: Int) throws -> URLSessionWebSocketTask.Message {
        try frame(["type": "agent.done", "chunks": count])
    }

    func testOrderedAudioIsReturnedOnlyOnMatchingDone() throws {
        var response = ResponseAccumulator()
        XCTAssertNil(try response.consume(text()))
        XCTAssertNil(try response.consume(audio()))
        XCTAssertNil(try response.consume(audio(4, sequence: 1)))
        XCTAssertEqual(try response.consume(done(2)), Data(repeating: 128, count: 6))
    }

    func testMalformedFramesAndUnexpectedOrderAreRejected() throws {
        let invalid: [URLSessionWebSocketTask.Message] = [
            .string("{"), .string("[]"), .data(Data()),
            .string(String(repeating: "x", count: 32769)),
            .string("{\"type\":\"agent.text\",\"text\":\"\(String(repeating: "👋", count: 8192))\"}"),
            try frame(["type": "user.text", "text": "hello"]),
            try frame(["type": "agent.text", "text": ""]),
            try frame(["type": "agent.text", "text": "hello", "extra": true]),
            try frame(["type": "agent.text", "text": 7]),
            try audio(), try done(0)
        ]
        for message in invalid {
            var response = ResponseAccumulator()
            XCTAssertThrowsError(try response.consume(message))
        }
        for message in [try text(), try audio(sequence: 1), try audio(sequence: -1),
                        try audio(0), try audio(1), try audio(16386), try done(0),
                        try frame(["type": "agent.audio", "sequence": true, "data": "AAA="]),
                        try frame(["type": "agent.audio", "sequence": 0.5, "data": "AAA="]),
                        try frame(["type": "agent.audio", "sequence": 0, "data": "!AAA="]),
                        try frame(["type": "agent.audio", "sequence": 0, "data": NSNull()])] {
            var response = ResponseAccumulator()
            _ = try response.consume(text())
            XCTAssertThrowsError(try response.consume(message))
        }
    }

    func testDuplicateSequenceAndIncorrectDoneCountsAreRejected() throws {
        for message in [try audio(), try audio(sequence: 2), try done(0), try done(2),
                        try frame(["type": "agent.done", "chunks": true]),
                        try frame(["type": "agent.done", "chunks": 1, "extra": 0])] {
            var response = ResponseAccumulator()
            _ = try response.consume(text())
            _ = try response.consume(audio())
            XCTAssertThrowsError(try response.consume(message))
        }
    }

    func testExactChunkAndBufferLimitsAndOverflow() throws {
        var response = ResponseAccumulator()
        _ = try response.consume(text())
        for sequence in 0..<512 {
            XCTAssertNil(try response.consume(audio(16384, sequence: sequence)))
        }
        var overflowing = response
        XCTAssertThrowsError(try overflowing.consume(audio(2, sequence: 512)))
        XCTAssertEqual(try response.consume(done(512))?.count, 8 * 1024 * 1024)
    }
}

@MainActor
final class ResponseLifecycleTests: XCTestCase {
    private var transport: ResponseTransport!
    private var player: ResponsePlayer!
    private var speech: ResponseSpeech!
    private var session: SessionController!
    private var logs: [String] = []

    private func setup() async {
        transport = ResponseTransport()
        player = ResponsePlayer()
        speech = ResponseSpeech()
        let name = "ResponseTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        session = SessionController(defaults: defaults, transport: transport, recognition: speech,
                                    timer: DeadlineTimer(), silenceTimer: DeadlineTimer(), player: player,
                                    log: { [weak self] in self?.logs.append($0) })
        session.serverURL = "ws://localhost:8080/conversation"
        await session.connect()
    }

    private func waitFor(_ state: SessionController.State, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(2)
        while session.state != state && Date() < deadline { await Task.yield() }
        XCTAssertEqual(session.state, state, file: file, line: line)
    }

    private func submit() async {
        await session.startCapture()
        await session.submitCapture()
        XCTAssertEqual(session.state, .waiting)
    }

    private func response() {
        transport.push(.string(#"{"type":"agent.text","text":"You said: hello"}"#))
        transport.push(.string(#"{"type":"agent.audio","sequence":0,"data":"AID/fw=="}"#))
        transport.push(.string(#"{"type":"agent.done","chunks":1}"#))
    }

    func testPlaybackCompletionAllowsSecondTurnAndGatesRecording() async {
        await setup()
        for turn in 1...2 {
            await submit()
            await session.startCapture()
            XCTAssertEqual(speech.starts, turn)
            response()
            await waitFor(.playing)
            while player.pending == nil { await Task.yield() }
            XCTAssertEqual(player.buffers.last, Data([0, 128, 255, 127]))
            await session.startCapture()
            XCTAssertEqual(speech.starts, turn)
            player.finish()
            await waitFor(.ready)
        }
        XCTAssertEqual(transport.sent.count, 2)
        XCTAssertTrue(logs.isEmpty)
        session.disconnect()
    }

    func testInvalidInputInReadyRecordingWaitingAndPlayingDisconnects() async {
        for state in [SessionController.State.ready, .recording, .waiting, .playing] {
            await setup()
            switch state {
            case .recording: await session.startCapture()
            case .waiting: await submit()
            case .playing:
                await submit()
                response()
                await waitFor(.playing)
            default: break
            }
            transport.push(.string(#"{"type":"agent.done","chunks":0}"#))
            await waitFor(.disconnected)
            XCTAssertGreaterThan(player.stops, 0)
            XCTAssertNil(transport.pending)
            XCTAssertTrue(logs.allSatisfy { !$0.contains("hello") })
        }
    }

    func testPlaybackErrorDisconnects() async {
        await setup()
        player.fail = true
        await submit()
        response()
        await waitFor(.disconnected)
        XCTAssertEqual(logs, ["Audio playback failed"])
        XCTAssertNil(transport.pending)
    }

    func testDisconnectClearsPartialResponseAndManualReconnectStartsFresh() async {
        await setup()
        await submit()
        transport.push(.string(#"{"type":"agent.text","text":"old"}"#))
        transport.push(.string(#"{"type":"agent.audio","sequence":0,"data":"AAA="}"#))
        while !transport.queue.isEmpty { await Task.yield() }
        transport.onDisconnect?()
        XCTAssertEqual(session.state, .disconnected)
        XCTAssertTrue(transport.queue.isEmpty)
        XCTAssertTrue(player.buffers.isEmpty)
        await session.connect()
        XCTAssertEqual(transport.sent.count, 1)
        await submit()
        response()
        await waitFor(.playing)
        while player.pending == nil { await Task.yield() }
        XCTAssertEqual(player.buffers, [Data([0, 128, 255, 127])])
        session.disconnect()
        await session.connect()
        await Task.yield()
        XCTAssertEqual(session.state, .ready)
        XCTAssertEqual(transport.sent.count, 2)
        session.disconnect()
    }

    func testLatePlaybackCompletionCannotCompleteNewTurn() async {
        await setup()
        await submit()
        response()
        await waitFor(.playing)
        while player.pending == nil { await Task.yield() }
        let old = player.pending
        player.pending = nil
        session.disconnect()
        await session.connect()
        await submit()
        old?.resume()
        await Task.yield()
        XCTAssertEqual(session.state, .waiting)
        session.disconnect()
    }

    func testConversationListensAgainOnlyAfterCompletePlayback() async {
        await setup()
        await session.startConversation()
        XCTAssertEqual(speech.starts, 1)
        await session.submitCapture()
        XCTAssertEqual(session.state, .waiting)
        response()
        await waitFor(.playing)
        while player.pending == nil { await Task.yield() }
        XCTAssertEqual(speech.starts, 1, "No listening while the reply plays")
        player.finish()
        await waitFor(.recording)
        XCTAssertEqual(speech.starts, 2)
        XCTAssertTrue(session.isConversationActive)
        // A second automatic turn.
        await session.submitCapture()
        response()
        await waitFor(.playing)
        while player.pending == nil { await Task.yield() }
        player.finish()
        await waitFor(.recording)
        XCTAssertEqual(speech.starts, 3)
        XCTAssertEqual(transport.sent.count, 2)
        XCTAssertTrue(logs.isEmpty)
        session.disconnect()
    }

    func testEndConversationDuringPlaybackStopsAudioAndDoesNotListen() async {
        await setup()
        await session.startConversation()
        await session.submitCapture()
        response()
        await waitFor(.playing)
        while player.pending == nil { await Task.yield() }
        session.endConversation()
        XCTAssertEqual(session.state, .ready)
        XCTAssertGreaterThan(player.stops, 0)
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(speech.starts, 1)
        XCTAssertEqual(session.state, .ready)
        session.disconnect()
    }

    func testEndConversationWhileWaitingClosesConnectionBecauseTurnCannotBeCancelled() async {
        await setup()
        await session.startConversation()
        await session.submitCapture()
        XCTAssertEqual(session.state, .waiting)
        session.endConversation()
        XCTAssertEqual(session.state, .disconnected)
        XCTAssertFalse(session.isConversationActive)
        XCTAssertEqual(speech.starts, 1)
    }

    func testReceiveFailureDisconnectsWithoutAutomaticReconnect() async {
        await setup()
        while transport.pending == nil { await Task.yield() }
        let pending = transport.pending
        transport.pending = nil
        pending?.resume(throwing: URLError(.networkConnectionLost))
        await waitFor(.disconnected)
        XCTAssertEqual(transport.connects, 1)
        XCTAssertTrue(transport.queue.isEmpty)
    }
}

@MainActor
private final class ResponseTransport: ConversationTransport {
    var onDisconnect: (() -> Void)?
    var pending: CheckedContinuation<URLSessionWebSocketTask.Message, Error>?
    var queue: [URLSessionWebSocketTask.Message] = []
    var sent: [String] = []
    var connects = 0
    func connect(to url: URL) async throws { connects += 1 }
    func send(text: String) async throws { sent.append(text) }
    func receive() async throws -> URLSessionWebSocketTask.Message {
        if !queue.isEmpty { return queue.removeFirst() }
        return try await withCheckedThrowingContinuation { pending = $0 }
    }
    func push(_ message: URLSessionWebSocketTask.Message) {
        if let pending {
            self.pending = nil
            pending.resume(returning: message)
        } else { queue.append(message) }
    }
    func disconnect() {
        queue.removeAll()
        let pending = pending
        self.pending = nil
        pending?.resume(throwing: CancellationError())
    }
}

@MainActor
private final class ResponsePlayer: ConversationPlayer {
    var pending: CheckedContinuation<Void, Error>?
    var buffers: [Data] = []
    var stops = 0
    var fail = false
    func play(pcm: Data) async throws {
        buffers.append(pcm)
        if fail { throw ResponseError.invalid }
        try await withCheckedThrowingContinuation { pending = $0 }
    }
    func finish() {
        let pending = pending
        self.pending = nil
        pending?.resume()
    }
    func stop() {
        stops += 1
        let pending = pending
        self.pending = nil
        pending?.resume(throwing: CancellationError())
    }
}

@MainActor
private final class ResponseSpeech: SpeechCapture {
    var starts = 0
    func start(onSpeech: @escaping () -> Void, onFailure: @escaping () -> Void) async throws { starts += 1 }
    func finish() async throws -> String { "hello" }
    func cancel() {}
}
