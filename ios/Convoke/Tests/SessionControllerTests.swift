import XCTest
@testable import ConvokeCore

@MainActor
final class SessionControllerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var defaultsName: String!
    private var transport: FakeTransport!
    private var speech: FakeSpeech!
    private var timer: FakeTimer!
    private var player: FakePlayer!
    private var session: SessionController!
    private var logs: [String] = []

    private func makeSession() {
        defaultsName = "ConvokeTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsName)!
        transport = FakeTransport()
        speech = FakeSpeech()
        timer = FakeTimer()
        player = FakePlayer()
        session = SessionController(defaults: defaults, transport: transport, recognition: speech,
                                    timer: timer, player: player, log: { [weak self] in self?.logs.append($0) })
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
                                         recognition: FakeSpeech(), timer: FakeTimer(), player: FakePlayer())
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

    func testCaptureOnlyInReadyAndPlaybackHooksGateTurns() async {
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
        session.responsePlaybackStarted()
        XCTAssertEqual(session.state, .playing)
        await session.startCapture()
        XCTAssertEqual(speech.starts, 1)
        session.responseCompleted()
        await session.startCapture()
        XCTAssertEqual(speech.starts, 2)
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
        session.responseCompleted()
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
    func start(onFailure: @escaping () -> Void) async throws {
        starts += 1
        self.onFailure = onFailure
        if let startError { throw startError }
        if holdStart { await withCheckedContinuation { pendingStart = $0 } }
    }
    func finish() async throws -> String {
        if let finishError { throw finishError }
        if holdFinish { return await withCheckedContinuation { pendingFinish = $0 } }
        return text
    }
    func cancel() { cancels += 1 }
}

@MainActor
private final class FakeTimer: CaptureTimer {
    var seconds: TimeInterval?
    var action: (() -> Void)?
    func schedule(after seconds: TimeInterval, action: @escaping () -> Void) {
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
    func stop() { stops += 1 }
}
