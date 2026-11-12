import XCTest
@testable import ConvokeCore

@MainActor
final class SessionControllerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var defaultsName: String!
    private var transport: FakeTransport!
    private var speech: FakeSpeech!
    private var timer: FakeTimer!
    private var silence: FakeTimer!
    private var player: FakePlayer!
    private var session: SessionController!
    private var logs: [String] = []

    private func makeSession() {
        defaultsName = "ConvokeTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsName)!
        transport = FakeTransport()
        speech = FakeSpeech()
        timer = FakeTimer()
        silence = FakeTimer()
        player = FakePlayer()
        session = SessionController(defaults: defaults, transport: transport, recognition: speech,
                                    timer: timer, silenceTimer: silence, player: player, log: { [weak self] in self?.logs.append($0) })
        addTeardownBlock { [defaults, defaultsName] in
            defaults?.removePersistentDomain(forName: defaultsName!)
        }
    }

    private func connect() async {
        session.serverURL = "ws://100.100.100.100:8080/conversation"
        await session.connect()
        XCTAssertEqual(session.state, .ready)
    }

    func testURLPersistsAndDefaultIsExample() async {
        makeSession()
        XCTAssertEqual(session.serverURL, SessionController.exampleURL)
        session.serverURL = "ws://100.1.2.3:8080/conversation"
        let reloaded = SessionController(defaults: defaults, transport: FakeTransport(),
                                         recognition: FakeSpeech(), timer: FakeTimer(),
                                         silenceTimer: FakeTimer(), player: FakePlayer())
        XCTAssertEqual(reloaded.serverURL, session.serverURL)
        XCTAssertEqual(defaults.persistentDomain(forName: defaultsName) as? [String: String],
                       [SessionController.urlDefaultsKey: session.serverURL])
    }

    func testConnectDisconnectAndDuplicateConnect() async {
        makeSession()
        await connect()
        await session.connect()
        XCTAssertEqual(transport.connects, 1)
        XCTAssertEqual(transport.url?.absoluteString, session.serverURL)
        session.disconnect()
        XCTAssertEqual(session.state, .disconnected)
        XCTAssertEqual(transport.disconnects, 1)
        XCTAssertEqual(player.stops, 1)
    }

    func testInvalidURLsNeverConnect() async {
        makeSession()
        for value in [SessionController.exampleURL, "", "https://example.com", "ws:///", "ws://user:secret@host/a", "ws://host/a#fragment"] {
            session.serverURL = value
            await session.connect()
            XCTAssertEqual(session.state, .disconnected, value)
        }
        XCTAssertEqual(transport.connects, 0)
    }

    func testCaptureOnlyInReadyAndWaitingGatesRecording() async {
        makeSession()
        await session.startCapture()
        XCTAssertEqual(speech.starts, 0)
        await connect()
        await session.startCapture()
        await session.startCapture()
        XCTAssertEqual(speech.starts, 1)
        XCTAssertEqual(session.state, .recording)
        await session.submitCapture()
        XCTAssertEqual(session.state, .waiting)
        await session.startCapture()
        XCTAssertEqual(speech.starts, 1)
    }

    func testTrimmedFinalTranscriptIsJSONTextFrame() async throws {
        makeSession()
        await connect()
        speech.text = " \nHello \"world\" 👋\n "
        await session.startCapture()
        await session.submitCapture()
        XCTAssertEqual(session.state, .waiting)
        let frame = try XCTUnwrap(transport.sent.first)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(frame.utf8)) as? [String: String])
        XCTAssertEqual(json, ["type": "user.text", "text": "Hello \"world\" 👋"])
        XCTAssertLessThanOrEqual(frame.utf8.count, 32768)
        XCTAssertTrue(logs.isEmpty)
        XCTAssertEqual(defaults.persistentDomain(forName: defaultsName) as? [String: String],
                       [SessionController.urlDefaultsKey: session.serverURL])
    }

    func testEmptyResultsReturnToReadyWithoutSending() async {
        makeSession()
        await connect()
        for value in ["", " \n\t "] {
            speech.text = value
            await session.startCapture()
            await session.submitCapture()
            XCTAssertEqual(session.state, .ready)
        }
        XCTAssertTrue(transport.sent.isEmpty)
    }

    func testUTF8LimitAndEscapedFrameLimit() async {
        makeSession()
        await connect()
        for value in [String(repeating: "👋", count: 1025), String(repeating: "x", count: 4097)] {
            speech.text = value
            await session.startCapture()
            await session.submitCapture()
            XCTAssertEqual(session.state, .ready)
        }
        XCTAssertTrue(transport.sent.isEmpty)
        speech.text = String(repeating: "\u{01}", count: 4096)
        await session.startCapture()
        await session.submitCapture()
        XCTAssertEqual(session.state, .waiting)
        XCTAssertLessThanOrEqual(transport.sent[0].utf8.count, 32768)
        session.disconnect()
        await connect()
        speech.text = String(repeating: "👋", count: 1024)
        await session.startCapture()
        await session.submitCapture()
        XCTAssertEqual(transport.sent.count, 2)
    }

    func testTimeoutSubmitsOnce() async {
        makeSession()
        await connect()
        await session.startCapture()
        XCTAssertEqual(timer.seconds, 60)
        let sent = expectation(description: "Timeout sends a frame")
        transport.onSend = { sent.fulfill() }
        timer.fire()
        await fulfillment(of: [sent], timeout: 2)
        XCTAssertEqual(transport.sent.count, 1)
        XCTAssertEqual(session.state, .waiting)
        await session.submitCapture()
        XCTAssertEqual(transport.sent.count, 1)
    }

    func testDisconnectDiscardsCaptureAndCancelsTimer() async {
        makeSession()
        await connect()
        await session.startCapture()
        session.disconnect()
        XCTAssertEqual(speech.cancels, 1)
        XCTAssertNil(timer.action)
        XCTAssertEqual(player.stops, 1)
        await session.submitCapture()
        XCTAssertTrue(transport.sent.isEmpty)
        await connect()
        XCTAssertEqual(session.state, .ready)
    }

    func testRemoteDisconnectCleansUp() async {
        makeSession()
        await connect()
        await session.startCapture()
        transport.onDisconnect?()
        XCTAssertEqual(session.state, .disconnected)
        XCTAssertEqual(speech.cancels, 1)
        XCTAssertNil(timer.action)
    }

    func testPermissionAndRecognitionErrorsReturnToReadyWithoutTextLogs() async {
        makeSession()
        await connect()
        speech.startError = TestError.failed
        await session.startCapture()
        XCTAssertEqual(session.state, .ready)
        speech.startError = nil
        await session.startCapture()
        speech.onFailure?()
        XCTAssertEqual(session.state, .ready)
        speech.finishError = TestError.failed
        await session.startCapture()
        await session.submitCapture()
        XCTAssertEqual(session.state, .ready)
        XCTAssertTrue(transport.sent.isEmpty)
        XCTAssertEqual(logs, Array(repeating: "Speech permission or recognition failed", count: 3))
    }

    func testConnectAndSendErrorsDisconnect() async {
        makeSession()
        session.serverURL = "ws://localhost:8080/conversation"
        transport.connectError = TestError.failed
        await session.connect()
        XCTAssertEqual(session.state, .disconnected)
        transport.connectError = nil
        await connect()
        transport.sendError = TestError.failed
        await session.startCapture()
        await session.submitCapture()
        XCTAssertEqual(session.state, .disconnected)
    }

    func testDisconnectDuringConnectIgnoresLateSuccess() async {
        makeSession()
        session.serverURL = "ws://localhost:8080/conversation"
        transport.holdConnect = true
        let connecting = Task { await session.connect() }
        while transport.pendingConnect == nil { await Task.yield() }
        XCTAssertEqual(session.state, .connecting)
        await session.startCapture()
        XCTAssertEqual(speech.starts, 0)
        session.disconnect()
        transport.pendingConnect?.resume()
        transport.pendingConnect = nil
        await connecting.value
        XCTAssertEqual(session.state, .disconnected)
    }

    func testDisconnectDuringPermissionRequestIgnoresLateStart() async {
        makeSession()
        await connect()
        speech.holdStart = true
        let starting = Task { await session.startCapture() }
        while speech.pendingStart == nil { await Task.yield() }
        await session.submitCapture()
        XCTAssertTrue(transport.sent.isEmpty)
        session.disconnect()
        speech.pendingStart?.resume()
        speech.pendingStart = nil
        await starting.value
        XCTAssertEqual(session.state, .disconnected)
        XCTAssertNil(timer.action)
    }

    func testDisconnectDuringFinalizationDoesNotSendLateTranscript() async {
        makeSession()
        await connect()
        await session.startCapture()
        speech.holdFinish = true
        let submitting = Task { await session.submitCapture() }
        while speech.pendingFinish == nil { await Task.yield() }
        await session.submitCapture()
        session.disconnect()
        await connect()
        speech.pendingFinish?.resume(returning: "discard me")
        speech.pendingFinish = nil
        await submitting.value
        XCTAssertEqual(session.state, .ready)
        XCTAssertTrue(transport.sent.isEmpty)
    }

    func testStaleTimerCannotSubmitNewCapture() async {
        makeSession()
        await connect()
        await session.startCapture()
        let oldTimeout = timer.action
        session.disconnect()
        await connect()
        await session.startCapture()
        oldTimeout?()
        // Let the timeout task run before checking the new capture.
        await Task.yield()
        await Task.yield()
        XCTAssertEqual(session.state, .recording)
        XCTAssertTrue(transport.sent.isEmpty)
    }

    func testStaleRecognitionFailureCannotEndNewCapture() async {
        makeSession()
        await connect()
        await session.startCapture()
        let oldFailure = speech.onFailure
        session.disconnect()
        await connect()
        await session.startCapture()
        oldFailure?()
        XCTAssertEqual(session.state, .recording)
    }

    // MARK: Hands-free conversation

    func testStartConversationListensAndSilenceTimerOnlyRunsAfterSpeech() async {
        makeSession()
        await connect()
        await session.startConversation()
        XCTAssertTrue(session.isConversationActive)
        XCTAssertEqual(session.state, .recording)
        XCTAssertEqual(session.statusText, "Listening")
        XCTAssertEqual(timer.seconds, 60)
        // No speech yet: no silence countdown, so nothing can submit.
        XCTAssertNil(silence.action)
        speech.onSpeech?()
        XCTAssertEqual(silence.seconds, 2.5)
        XCTAssertNotNil(silence.action)
        session.disconnect()
    }

    func testSilenceAfterSpeechSubmitsOnceAndRestartsOnMoreSpeech() async {
        makeSession()
        await connect()
        await session.startConversation()
        speech.onSpeech?()
        let first = silence.action
        speech.onSpeech?()
        XCTAssertEqual(silence.schedules, 2, "Each transcript change restarts the countdown")
        _ = first
        let sent = expectation(description: "Silence sends a frame")
        transport.onSend = { sent.fulfill() }
        silence.fire()
        await fulfillment(of: [sent], timeout: 2)
        XCTAssertEqual(transport.sent.count, 1)
        XCTAssertEqual(session.state, .waiting)
        XCTAssertNil(timer.action, "Capture limit is cancelled after submission")
        XCTAssertNil(silence.action)
        XCTAssertEqual(speech.finishes, 1)
    }

    func testSpeechCallbackAfterSubmissionDoesNotRestartSilenceTimer() async {
        makeSession()
        await connect()
        await session.startConversation()
        speech.onSpeech?()
        let late = speech.onSpeech
        await session.submitCapture()
        XCTAssertEqual(session.state, .waiting)
        late?()
        XCTAssertNil(silence.action)
    }

    func testStaleSilenceTimerCannotSubmitNewCapture() async {
        makeSession()
        await connect()
        await session.startConversation()
        speech.onSpeech?()
        let oldSilence = silence.action
        session.disconnect()
        await connect()
        await session.startConversation()
        oldSilence?()
        await Task.yield()
        await Task.yield()
        XCTAssertEqual(session.state, .recording)
        XCTAssertTrue(transport.sent.isEmpty)
        session.disconnect()
    }

    func testCaptureLimitWithoutSpeechKeepsListeningInActiveConversation() async {
        makeSession()
        await connect()
        speech.text = "  "
        await session.startConversation()
        XCTAssertEqual(speech.starts, 1)
        timer.fire()
        while speech.starts < 2 { await Task.yield() }
        XCTAssertEqual(session.state, .recording)
        XCTAssertTrue(session.isConversationActive)
        XCTAssertTrue(transport.sent.isEmpty)
        session.disconnect()
    }

    func testFinalizationFailureEndsConversationWithVisibleError() async {
        makeSession()
        await connect()
        await session.startConversation()
        speech.finishError = SpeechCaptureError.noFinalResult
        speech.onSpeech?()
        await session.submitCapture()
        XCTAssertEqual(session.state, .ready)
        XCTAssertFalse(session.isConversationActive)
        XCTAssertEqual(session.errorMessage, SpeechCaptureError.noFinalResult.message)
        XCTAssertTrue(transport.sent.isEmpty)
        XCTAssertNil(silence.action)
        XCTAssertEqual(speech.starts, 1, "A failing recognizer must not retry in a loop")
    }

    func testStartupErrorsAreVisibleAndEndConversation() async {
        makeSession()
        await connect()
        for error in [SpeechCaptureError.microphoneDenied, .unsupportedLocale, .modelPreparationFailed] {
            speech.startError = error
            await session.startConversation()
            XCTAssertEqual(session.state, .ready)
            XCTAssertFalse(session.isConversationActive)
            XCTAssertFalse(session.isPreparing)
            XCTAssertEqual(session.errorMessage, error.message)
        }
        // A new attempt clears the old error.
        speech.startError = nil
        await session.startConversation()
        XCTAssertNil(session.errorMessage)
        session.disconnect()
    }

    func testPreparationIsVisibleWhileModelIsPrepared() async {
        makeSession()
        await connect()
        speech.holdStart = true
        let starting = Task { await session.startConversation() }
        while speech.pendingStart == nil { await Task.yield() }
        XCTAssertEqual(session.statusText, "Preparing speech recognition")
        XCTAssertTrue(session.isPreparing)
        speech.pendingStart?.resume()
        speech.pendingStart = nil
        await starting.value
        XCTAssertFalse(session.isPreparing)
        XCTAssertEqual(session.statusText, "Listening")
        session.disconnect()
    }

    func testConnectDoesNotStartListening() async {
        makeSession()
        await connect()
        XCTAssertEqual(speech.starts, 0)
        XCTAssertFalse(session.isConversationActive)
        await session.startConversation()
        XCTAssertEqual(speech.starts, 1)
        session.disconnect()
    }

    func testStartConversationRequiresReadyAndIsNotReentrant() async {
        makeSession()
        await session.startConversation()
        XCTAssertEqual(speech.starts, 0)
        XCTAssertFalse(session.isConversationActive)
        await connect()
        await session.startConversation()
        await session.startConversation()
        XCTAssertEqual(speech.starts, 1)
        session.disconnect()
    }

    func testEndConversationWhileListeningCancelsCaptureAndKeepsConnection() async {
        makeSession()
        await connect()
        await session.startConversation()
        speech.onSpeech?()
        session.endConversation()
        XCTAssertFalse(session.isConversationActive)
        XCTAssertEqual(session.state, .ready)
        XCTAssertEqual(speech.cancels, 1)
        XCTAssertNil(timer.action)
        XCTAssertNil(silence.action)
        XCTAssertEqual(transport.disconnects, 0)
        await session.submitCapture()
        XCTAssertTrue(transport.sent.isEmpty)
        // A fresh conversation can start on the same connection.
        await session.startConversation()
        XCTAssertEqual(session.state, .recording)
        session.disconnect()
    }

    func testEndConversationDuringPreparationIgnoresLateStart() async {
        makeSession()
        await connect()
        speech.holdStart = true
        let starting = Task { await session.startConversation() }
        while speech.pendingStart == nil { await Task.yield() }
        session.endConversation()
        XCTAssertEqual(session.state, .ready)
        XCTAssertFalse(session.isPreparing)
        speech.pendingStart?.resume()
        speech.pendingStart = nil
        await starting.value
        XCTAssertEqual(session.state, .ready)
        XCTAssertNil(timer.action)
        session.disconnect()
    }

    func testEndConversationDuringFinalizationDoesNotSendLateTranscript() async {
        makeSession()
        await connect()
        await session.startConversation()
        speech.holdFinish = true
        let submitting = Task { await session.submitCapture() }
        while speech.pendingFinish == nil { await Task.yield() }
        session.endConversation()
        speech.pendingFinish?.resume(returning: "discard me")
        speech.pendingFinish = nil
        await submitting.value
        XCTAssertEqual(session.state, .ready)
        XCTAssertTrue(transport.sent.isEmpty)
        XCTAssertEqual(speech.starts, 1)
        session.disconnect()
    }

    func testEndConversationIsNoOpWhenInactive() async {
        makeSession()
        await connect()
        session.endConversation()
        XCTAssertEqual(speech.cancels, 0)
        XCTAssertEqual(session.state, .ready)
    }

    func testDisconnectEndsConversation() async {
        makeSession()
        await connect()
        await session.startConversation()
        session.disconnect()
        XCTAssertFalse(session.isConversationActive)
        XCTAssertFalse(session.isPreparing)
        XCTAssertNil(silence.action)
    }
}

private enum TestError: Error { case failed }

@MainActor
private final class FakeTransport: ConversationTransport {
    var onDisconnect: (() -> Void)?
    var connects = 0
    var disconnects = 0
    var url: URL?
    var sent: [String] = []
    var onSend: (() -> Void)?
    var connectError: Error?
    var sendError: Error?
    var holdConnect = false
    var pendingConnect: CheckedContinuation<Void, Never>?
    func connect(to url: URL) async throws {
        connects += 1
        self.url = url
        if let connectError { throw connectError }
        if holdConnect { await withCheckedContinuation { pendingConnect = $0 } }
    }
    func receive() async throws -> URLSessionWebSocketTask.Message {
        try await Task.sleep(nanoseconds: UInt64.max)
        throw CancellationError()
    }
    func send(text: String) async throws {
        if let sendError { throw sendError }
        sent.append(text)
        onSend?()
    }
    func disconnect() { disconnects += 1 }
}

@MainActor
private final class FakeSpeech: SpeechCapture {
    var starts = 0
    var cancels = 0
    var text = "hello"
    var startError: Error?
    var finishError: Error?
    var onFailure: (() -> Void)?
    var holdStart = false
    var holdFinish = false
    var pendingStart: CheckedContinuation<Void, Never>?
    var pendingFinish: CheckedContinuation<String, Never>?
    var onSpeech: (() -> Void)?
    func start(onSpeech: @escaping () -> Void, onFailure: @escaping () -> Void) async throws {
        starts += 1
        self.onSpeech = onSpeech
        self.onFailure = onFailure
        if let startError { throw startError }
        if holdStart { await withCheckedContinuation { pendingStart = $0 } }
    }
    var finishes = 0
    func finish() async throws -> String {
        finishes += 1
        if let finishError { throw finishError }
        if holdFinish { return await withCheckedContinuation { pendingFinish = $0 } }
        return text
    }
    func cancel() { cancels += 1 }
}

@MainActor
private final class FakeTimer: CaptureTimer {
    var seconds: TimeInterval?
    var schedules = 0
    var action: (() -> Void)?
    func schedule(after seconds: TimeInterval, action: @escaping () -> Void) {
        schedules += 1
        self.seconds = seconds
        self.action = action
    }
    func cancel() { action = nil }
    func fire() {
        let callback = action
        action = nil
        callback?()
    }
}

@MainActor
private final class FakePlayer: ConversationPlayer {
    var stops = 0
    func play(pcm: Data) async throws {}
    func stop() { stops += 1 }
}
