import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
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

    func testAudioIsEmittedPerChunkAndDoneOnlyOnMatchingCount() throws {
        var response = ResponseAccumulator()
        XCTAssertEqual(try response.consume(text()), .text)
        XCTAssertEqual(try response.consume(audio()), .audio(Data(repeating: 128, count: 2)))
        XCTAssertEqual(try response.consume(audio(4, sequence: 1)), .audio(Data(repeating: 128, count: 4)))
        XCTAssertEqual(try response.consume(done(2)), .done)
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

    func testStrictAudioKeysTypesAndPostDoneFrames() throws {
        for object: [String: Any] in [
            ["type": "agent.audio", "sequence": 0, "data": "AAA=", "extra": false],
            ["type": "agent.audio", "sequence": 0],
            ["type": "agent.audio", "data": "AAA="],
            ["type": "agent.audio", "sequence": "0", "data": "AAA="],
            ["type": "agent.audio", "sequence": 0, "data": 7],
            ["type": "agent.done", "chunks": "1"],
            ["type": "agent.done", "chunks": 0.5],
            ["type": "agent.done", "chunks": NSNull()]
        ] {
            var response = ResponseAccumulator()
            _ = try response.consume(text())
            if object["type"] as? String == "agent.done" { _ = try response.consume(audio()) }
            XCTAssertThrowsError(try response.consume(frame(object)))
        }
        for message in [try text(), try audio(sequence: 1), try done(1)] {
            var response = ResponseAccumulator()
            _ = try response.consume(text())
            _ = try response.consume(audio())
            _ = try response.consume(done(1))
            XCTAssertThrowsError(try response.consume(message), "Every frame after EOF is invalid")
        }
    }

    func testIncrementalEventsRetainOnlyScalarStateAtExactJSONBoundary() throws {
        var response = ResponseAccumulator()
        let textFrame = #"{"type":"agent.text","text":"x"}"#
        _ = try response.consume(.string(textFrame + String(repeating: " ", count: 32_768 - textFrame.utf8.count)))
        for sequence in 0..<3 {
            XCTAssertEqual(try response.consume(audio(16_384, sequence: sequence)),
                           .audio(Data(repeating: 128, count: 16_384)))
            // A structural regression guard: the validator must not add an audio
            // buffer or event collection after handing this chunk to the player.
            for field in Mirror(reflecting: response).children {
                XCTAssertTrue(field.value is Bool || field.value is Int, "Response stores counters/flags only")
            }
        }
        XCTAssertEqual(try response.consume(done(3)), .done)
        var overflow = ResponseAccumulator()
        XCTAssertThrowsError(try overflow.consume(.string(textFrame + String(repeating: " ", count: 32_769 - textFrame.utf8.count))))
    }

    func testExactChunkAndBufferLimitsAndOverflow() throws {
        var response = ResponseAccumulator()
        _ = try response.consume(text())
        for sequence in 0..<512 {
            XCTAssertEqual(try response.consume(audio(16384, sequence: sequence)), .audio(Data(repeating: 128, count: 16384)))
        }
        var overflowing = response
        XCTAssertThrowsError(try overflowing.consume(audio(2, sequence: 512)))
        XCTAssertEqual(try response.consume(done(512)), .done)
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

    private func audioFrame(_ sequence: Int, _ data: String = "AID/fw==") -> URLSessionWebSocketTask.Message {
        .string(#"{"type":"agent.audio","sequence":\#(sequence),"data":"\#(data)"}"#)
    }

    func testPlaybackStartsOnFirstChunkBeforeDoneAndQueuesLaterChunks() async {
        await setup()
        await session.startConversation()
        await session.submitCapture()
        transport.push(.string(#"{"type":"agent.text","text":"You said: hello"}"#))
        transport.push(audioFrame(0))
        await waitFor(.playing)
        XCTAssertEqual(player.begins, 1)
        XCTAssertEqual(player.buffers, [Data([0, 128, 255, 127])])
        XCTAssertEqual(player.ends, 0, "The reply is not complete yet")
        transport.push(audioFrame(1, "AAA="))
        while player.buffers.count < 2 { await Task.yield() }
        XCTAssertEqual(player.begins, 1, "Later chunks queue on the same stream")
        XCTAssertEqual(player.buffers.last, Data([0, 0]))
        XCTAssertEqual(session.state, .playing)
        XCTAssertEqual(speech.starts, 1, "Microphone stays off while the reply streams")
        transport.push(.string(#"{"type":"agent.done","chunks":2}"#))
        while player.pending == nil { await Task.yield() }
        XCTAssertEqual(session.state, .playing, "Still playing until the last chunk has played")
        XCTAssertEqual(speech.starts, 1)
        player.finish()
        await waitFor(.recording)
        XCTAssertEqual(speech.starts, 2)
        XCTAssertTrue(logs.isEmpty)
        session.disconnect()
    }

    func testEndConversationWhileReplyStillStreamingClosesConnection() async {
        await setup()
        await session.startConversation()
        await session.submitCapture()
        transport.push(.string(#"{"type":"agent.text","text":"x"}"#))
        transport.push(audioFrame(0))
        await waitFor(.playing)
        session.endConversation()
        XCTAssertEqual(session.state, .disconnected, "The server is still sending; the protocol cannot cancel it")
        XCTAssertGreaterThan(player.stops, 0)
        XCTAssertEqual(speech.starts, 1)
    }

    func testInvalidChunkMidStreamStopsPlaybackAndDisconnects() async {
        await setup()
        await submit()
        transport.push(.string(#"{"type":"agent.text","text":"x"}"#))
        transport.push(audioFrame(0))
        await waitFor(.playing)
        transport.push(audioFrame(5))  // sequence gap
        await waitFor(.disconnected)
        XCTAssertGreaterThan(player.stops, 0)
        XCTAssertEqual(player.buffers.count, 1, "The invalid chunk is never played")
        XCTAssertEqual(logs, ["WebSocket receive or response validation failed"])
    }

    func testDoneWithoutAudioIsInvalid() async {
        await setup()
        await submit()
        transport.push(.string(#"{"type":"agent.text","text":"x"}"#))
        transport.push(.string(#"{"type":"agent.done","chunks":0}"#))
        await waitFor(.disconnected)
        XCTAssertEqual(player.begins, 0)
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
        XCTAssertGreaterThan(player.stops, 0)
        player.buffers.removeAll()
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
        XCTAssertEqual(transport.disconnects, 0)
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

    private func beginReply() async {
        await session.startConversation()
        await session.submitCapture()
        transport.push(.string(#"{"type":"agent.text","text":"x"}"#))
        transport.push(audioFrame(0))
        let deadline = Date().addingTimeInterval(2)
        while player.buffers.isEmpty && Date() < deadline { await Task.yield() }
        XCTAssertEqual(player.buffers.count, 1)
    }

    func testIndependentlyGatedEOFAndPlaybackAcrossSequentialHandsFreeTurns() async {
        for eofFirst in [false, true] {
            await setup()
            await session.startConversation()
            for turn in 1...3 {
                await session.submitCapture()
                let buffered = expectation(description: "audio delivered before EOF")
                let reading = expectation(description: "receiver waiting while playback is held")
                player.onEnqueue = { [self] in
                    player.onEnqueue = nil
                    buffered.fulfill()
                    transport.onWaiting = { [self] in
                        transport.onWaiting = nil
                        reading.fulfill()
                    }
                }
                transport.push(.string(#"{"type":"agent.text","text":"x"}"#))
                transport.push(audioFrame(0))
                await fulfillment(of: [buffered, reading], timeout: 2)
                XCTAssertEqual(session.state, .playing)
                XCTAssertEqual(speech.starts, turn)
                XCTAssertEqual(player.begins, turn)
                let resumed = expectation(description: "listen exactly once after both gates")
                speech.onStart = { resumed.fulfill() }
                if !eofFirst {
                    player.finish() // Queue runs dry, but the source EOF gate is closed.
                    XCTAssertEqual(session.state, .playing)
                    XCTAssertEqual(speech.starts, turn)
                }
                let ending = expectation(description: "validated source EOF")
                player.onEnd = { ending.fulfill() }
                transport.push(.string(#"{"type":"agent.done","chunks":1}"#))
                await fulfillment(of: [ending], timeout: 2)
                if eofFirst {
                    XCTAssertEqual(speech.starts, turn, "Network completion cannot start the microphone")
                    XCTAssertEqual(session.state, .playing)
                    player.finish()
                }
                await fulfillment(of: [resumed], timeout: 2)
                speech.onStart = nil
                player.onEnd = nil
                XCTAssertEqual(session.state, .recording)
                XCTAssertEqual(speech.starts, turn + 1)
                XCTAssertEqual(player.ends, turn)
            }
            XCTAssertEqual(transport.sent.count, 3)
            session.disconnect()
        }
    }

    func testInitiallyBufferedAudioIsNotPlayingAndEndDisconnects() async {
        await setup()
        player.holdStart = true
        await beginReply()
        XCTAssertEqual(session.state, .waiting)
        XCTAssertEqual(speech.starts, 1)
        session.endConversation()
        XCTAssertEqual(session.state, .disconnected)
        XCTAssertFalse(session.isConversationActive)
    }

    func testShortReplyStartsAtEOFAndWaitsForActualDrain() async {
        await setup()
        player.holdStart = true
        await beginReply()
        XCTAssertEqual(session.state, .waiting)
        transport.push(.string(#"{"type":"agent.done","chunks":1}"#))
        await waitFor(.playing)
        XCTAssertEqual(speech.starts, 1)
        player.finish()
        await waitFor(.recording)
        XCTAssertEqual(speech.starts, 2)
        session.disconnect()
    }

    func testDrainBeforeEOFIsUnderrunAndResumesExactlyOnceAtEOF() async {
        await setup()
        await beginReply()
        player.finish()
        // A read barrier proves the receiver is waiting for EOF while the queue is empty.
        while transport.pending == nil { await Task.yield() }
        XCTAssertEqual(session.state, .playing)
        XCTAssertEqual(speech.starts, 1)
        transport.push(.string(#"{"type":"agent.done","chunks":1}"#))
        await waitFor(.recording)
        XCTAssertEqual(speech.starts, 2)
        XCTAssertEqual(player.ends, 1)
        session.disconnect()
    }

    func testUnderrunAcceptsMoreAudioWithoutStartingCaptureOrAnotherPlayer() async {
        await setup()
        await beginReply()
        player.finish()
        transport.push(audioFrame(1))
        while player.buffers.count < 2 { await Task.yield() }
        XCTAssertEqual(speech.starts, 1)
        XCTAssertEqual(player.begins, 1)
        transport.push(.string(#"{"type":"agent.done","chunks":2}"#))
        while player.pending == nil { await Task.yield() }
        XCTAssertEqual(speech.starts, 1)
        player.finish()
        await waitFor(.recording)
        XCTAssertEqual(speech.starts, 2)
        session.disconnect()
    }

    func testInterruptionBeforeEOFDisconnectsImmediatelyWithoutNextFrame() async {
        await setup()
        await beginReply()
        let failed = player.onFailure
        failed?()
        XCTAssertEqual(session.state, .disconnected)
        XCTAssertEqual(session.errorMessage, "Audio playback failed.")
        XCTAssertFalse(session.isConversationActive)
        XCTAssertGreaterThan(player.stops, 0)
        XCTAssertEqual(speech.starts, 1)
        failed?()
        XCTAssertEqual(logs, ["Audio playback failed"], "Failure is scoped to the invalidated reply")
    }

    func testLateCallbacksAfterEndCannotCorruptNewReplyOnSameConnection() async {
        await setup()
        await beginReply()
        transport.push(.string(#"{"type":"agent.done","chunks":1}"#))
        while player.pending == nil { await Task.yield() }
        let oldStarted = player.onStarted
        let oldFailure = player.onFailure
        let oldCompletion = player.pending
        player.pending = nil // Deliberately retain a callback that ignores cancellation.
        session.endConversation()
        XCTAssertEqual(session.state, .ready)
        await session.startConversation()
        await session.submitCapture()
        oldStarted?()
        oldFailure?()
        oldCompletion?.resume()
        while transport.pending == nil { await Task.yield() }
        XCTAssertEqual(session.state, .waiting)
        XCTAssertNil(session.errorMessage)
        XCTAssertEqual(speech.starts, 2)
        response()
        await waitFor(.playing)
        while player.pending == nil { await Task.yield() }
        player.finish()
        await waitFor(.recording)
        XCTAssertEqual(speech.starts, 3)
        session.disconnect()
    }

    func testEndAfterValidatedEOFBeforeFinalizerRunsDoesNotCallStoppedPlayer() async {
        await setup()
        await beginReply()
        let ended = expectation(description: "End before queued EOF finalizer")
        transport.onReceive = { [self] in
            transport.onReceive = nil
            session.endConversation()
            ended.fulfill()
        }
        transport.push(.string(#"{"type":"agent.done","chunks":1}"#))
        await fulfillment(of: [ended], timeout: 2)
        XCTAssertEqual(session.state, .ready)
        await session.startConversation()
        await session.submitCapture()
        response()
        await waitFor(.playing)
        while player.pending == nil { await Task.yield() }
        XCTAssertEqual(player.ends, 1, "Only the new reply may call endStream")
        player.finish()
        await waitFor(.recording)
        XCTAssertEqual(speech.starts, 3)
        session.disconnect()
    }

    func testInterruptionAfterEOFStopsPendingPlaybackAndCannotRestartCapture() async {
        await setup()
        await beginReply()
        transport.push(.string(#"{"type":"agent.done","chunks":1}"#))
        while player.pending == nil { await Task.yield() }
        player.onFailure?()
        await waitFor(.disconnected)
        XCTAssertFalse(session.isConversationActive)
        XCTAssertEqual(session.errorMessage, "Audio playback failed.")
        XCTAssertEqual(speech.starts, 1)
        XCTAssertNil(player.pending)
    }

    func testOldReceiveCannotStartAudioOnReconnectedConversation() async {
        await setup()
        await beginReply()
        while transport.pending == nil { await Task.yield() }
        let oldRead = transport.pending
        transport.pending = nil
        session.disconnect()
        await session.connect()
        await session.startConversation()
        await session.submitCapture()
        oldRead?.resume(returning: audioFrame(1))
        while transport.pending == nil { await Task.yield() }
        XCTAssertEqual(session.state, .waiting)
        XCTAssertEqual(player.begins, 1)
        response()
        await waitFor(.playing)
        while player.pending == nil { await Task.yield() }
        XCTAssertEqual(player.begins, 2)
        session.disconnect()
    }

    func testBackgroundDisconnectInvalidatesPlayerAndConnectionCallbacks() async {
        await setup()
        await beginReply()
        let oldStarted = player.onStarted
        let oldFailure = player.onFailure
        let oldDisconnect = transport.onDisconnect
        session.disconnect() // ContentView's background action.
        XCTAssertFalse(session.isConversationActive)
        XCTAssertGreaterThan(player.stops, 0)
        await session.connect()
        await session.startConversation()
        oldStarted?()
        oldFailure?()
        oldDisconnect?()
        XCTAssertEqual(session.state, .recording)
        XCTAssertEqual(speech.starts, 2)
        XCTAssertNil(session.errorMessage)
        session.disconnect()
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
    var disconnects = 0
    var onReceive: (() -> Void)?
    var onWaiting: (() -> Void)?
    func connect(to url: URL) async throws { connects += 1 }
    func send(text: String) async throws { sent.append(text) }
    func receive() async throws -> URLSessionWebSocketTask.Message {
        onReceive?()
        if !queue.isEmpty { return queue.removeFirst() }
        return try await withCheckedThrowingContinuation {
            pending = $0
            onWaiting?()
        }
    }
    func push(_ message: URLSessionWebSocketTask.Message) {
        if let pending {
            self.pending = nil
            pending.resume(returning: message)
        } else { queue.append(message) }
    }
    func disconnect() {
        disconnects += 1
        queue.removeAll()
        let pending = pending
        self.pending = nil
        pending?.resume(throwing: CancellationError())
    }
}

@MainActor
private final class ResponsePlayer: ConversationPlayer {
    var pending: CheckedContinuation<Void, Error>?
    /// Every chunk enqueued, in order.
    var buffers: [Data] = []
    var begins = 0
    var ends = 0
    var stops = 0
    var fail = false
    var holdStart = false
    var drained = false
    var onStarted: (() -> Void)?
    var onFailure: (() -> Void)?
    var onEnqueue: (() -> Void)?
    var onEnd: (() -> Void)?
    func beginStream(onStarted: @escaping () -> Void, onFailure: @escaping () -> Void) throws {
        begins += 1
        drained = false
        self.onStarted = onStarted
        self.onFailure = onFailure
    }
    func enqueue(pcm: Data) throws {
        buffers.append(pcm)
        if fail { throw ResponseError.invalid }
        drained = false
        if !holdStart { onStarted?() }
        onEnqueue?()
    }
    func endStream() async throws {
        ends += 1
        onStarted?()
        onEnd?()
        if drained { return }
        try await withCheckedThrowingContinuation { pending = $0 }
    }
    func finish() {
        drained = true
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
    var onStart: (() -> Void)?
    func start(onSpeech: @escaping () -> Void, onFailure: @escaping () -> Void) async throws {
        starts += 1
        onStart?()
    }
    func finish() async throws -> String { "hello" }
    func cancel() {}
}
