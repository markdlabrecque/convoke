import XCTest
@testable import ConvokeCore

@MainActor
final class AppleSpeechCaptureTests: XCTestCase {
    func testPrematureFinalDiscardsTurnAndLeavesRecordingImmediately() async {
        let name = "ConvokeSpeechTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let speech = CallbackSpeech()
        let transport = SpeechTestTransport()
        let timer = SpeechTestTimer()
        let controller = SessionController(defaults: defaults, transport: transport,
                                           recognition: speech, timer: timer, player: SpeechTestPlayer())
        controller.serverURL = "ws://localhost:8080/conversation"
        await controller.connect()
        await controller.startCapture()
        XCTAssertEqual(controller.state, .recording)
        let timeout = timer.action
        // Exercise the actual adapter's callback handling, without permissions,
        // a recognition service, audio engine startup, or a microphone.
        speech.adapter.processRecognitionResult(final: "premature text", failed: false) {
            speech.onFailure?()
        }
        XCTAssertEqual(controller.state, .ready)
        XCTAssertFalse(controller.isFinalizing)
        XCTAssertNil(timer.action)
        XCTAssertEqual(speech.cancels, 1)
        await controller.submitCapture()
        timeout?()
        await Task.yield()
        XCTAssertTrue(transport.sent.isEmpty)
        // The interrupted turn is not reused by a later capture.
        await controller.startCapture()
        XCTAssertEqual(controller.state, .recording)
        controller.disconnect()
    }

    func testFinalAfterSubmissionResolvesOnceAndIgnoresTrailingError() async throws {
        let adapter = AppleSpeechCapture()
        defer { adapter.cancel() }
        let finishing = Task { try await adapter.waitForFinalResult() }
        while !adapter.isFinishing { await Task.yield() }
        var failures = 0
        adapter.processRecognitionResult(final: "complete turn", failed: false) { failures += 1 }
        adapter.processRecognitionResult(final: nil, failed: true) { failures += 1 }
        let text = try await finishing.value
        XCTAssertEqual(text, "complete turn")
        XCTAssertEqual(failures, 0)
    }

    func testCancelResolvesPendingFinalizationAndResetsOrdering() async {
        let adapter = AppleSpeechCapture()
        let finishing = Task { try await adapter.waitForFinalResult() }
        while !adapter.isFinishing { await Task.yield() }
        adapter.cancel()
        do {
            _ = try await finishing.value
            XCTFail("Cancelled finalization must not produce text")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertFalse(adapter.isFinishing)
        var failures = 0
        adapter.processRecognitionResult(final: "early in next capture", failed: false) { failures += 1 }
        XCTAssertEqual(failures, 1)
    }

    func testCancelledFinalDeadlineCannotResolveNextCapture() async throws {
        let adapter = AppleSpeechCapture(finalResultTimeout: 500_000_000)
        defer { adapter.cancel() }
        let oldFinish = Task { try await adapter.waitForFinalResult() }
        while !adapter.isFinishing { await Task.yield() }
        try await Task.sleep(nanoseconds: 250_000_000)
        adapter.cancel()
        _ = await oldFinish.result
        let newFinish = Task { try await adapter.waitForFinalResult() }
        while !adapter.isFinishing { await Task.yield() }
        // Cross the old deadline, but stay before the new one.
        try await Task.sleep(nanoseconds: 300_000_000)
        adapter.processRecognitionResult(final: "new turn", failed: false) { XCTFail("Unexpected failure") }
        let text = try await newFinish.value
        XCTAssertEqual(text, "new turn")
    }

    func testFinalizationDeadlineReturnsFailureNotPartialText() async {
        let adapter = AppleSpeechCapture(finalResultTimeout: 10_000_000)
        defer { adapter.cancel() }
        do {
            _ = try await adapter.waitForFinalResult()
            XCTFail("Missing final must fail")
        } catch {
            XCTAssertFalse(error is CancellationError)
        }
    }

    func testNonterminalResultDoesNotEndCapture() {
        let adapter = AppleSpeechCapture()
        var failures = 0
        adapter.processRecognitionResult(final: nil, failed: false) { failures += 1 }
        XCTAssertEqual(failures, 0)
        adapter.processRecognitionResult(final: nil, failed: true) { failures += 1 }
        XCTAssertEqual(failures, 1)
        adapter.cancel()
    }
}

@MainActor
private final class CallbackSpeech: SpeechCapture {
    let adapter = AppleSpeechCapture()
    var onFailure: (() -> Void)?
    var cancels = 0
    func start(onFailure: @escaping () -> Void) async throws { self.onFailure = onFailure }
    func finish() async throws -> String { try await adapter.finish() }
    func cancel() { cancels += 1; adapter.cancel() }
}

@MainActor
private final class SpeechTestTransport: ConversationTransport {
    var onDisconnect: (() -> Void)?
    var sent: [String] = []
    func connect(to url: URL) async throws {}
    func receive() async throws -> URLSessionWebSocketTask.Message {
        try await Task.sleep(nanoseconds: UInt64.max)
        throw CancellationError()
    }
    func send(text: String) async throws { sent.append(text) }
    func disconnect() {}
}

@MainActor
private final class SpeechTestTimer: CaptureTimer {
    var action: (() -> Void)?
    func schedule(after seconds: TimeInterval, action: @escaping () -> Void) { self.action = action }
    func cancel() { action = nil }
}

@MainActor
private final class SpeechTestPlayer: ConversationPlayer {
    func play(pcm: Data) async throws {}
    func stop() {}
}
