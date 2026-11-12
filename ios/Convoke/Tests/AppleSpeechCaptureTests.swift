import XCTest
@testable import ConvokeCore

@MainActor
final class AppleSpeechCaptureTests: XCTestCase {
    func testPrematureCompletionDiscardsTurnAndLeavesRecordingImmediately() async {
        let name = "ConvokeSpeechTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let speech = CallbackSpeech()
        let transport = SpeechTestTransport()
        let timer = SpeechTestTimer()
        let silence = SpeechTestTimer()
        let controller = SessionController(defaults: defaults, transport: transport,
                                           recognition: speech, timer: timer, silenceTimer: silence,
                                           player: SpeechTestPlayer())
        controller.serverURL = "ws://localhost:8080/conversation"
        await controller.connect()
        await controller.startConversation()
        XCTAssertEqual(controller.state, .recording)
        let timeout = timer.action
        // Exercise the actual adapter's completion handling, without permissions,
        // a speech model, audio engine startup, or a microphone.
        speech.adapter.processCompletion(failed: false) { speech.onFailure?() }
        XCTAssertEqual(controller.state, .ready)
        XCTAssertFalse(controller.isFinalizing)
        XCTAssertFalse(controller.isConversationActive)
        XCTAssertNotNil(controller.errorMessage)
        XCTAssertNil(timer.action)
        XCTAssertNil(silence.action)
        XCTAssertEqual(speech.cancels, 1)
        await controller.submitCapture()
        timeout?()
        await Task.yield()
        XCTAssertTrue(transport.sent.isEmpty)
        // The interrupted turn is not reused by a later capture.
        await controller.startConversation()
        XCTAssertEqual(controller.state, .recording)
        controller.disconnect()
    }

    func testFinalAfterSubmissionJoinsFinalizedSegmentsAndIgnoresLaterCompletion() async throws {
        let adapter = AppleSpeechCapture()
        defer { adapter.cancel() }
        adapter.processResult(text: "hello", isFinal: false) {}
        adapter.processResult(text: "hello there", isFinal: true) {}
        adapter.processResult(text: "how are you", isFinal: true) {}
        let finishing = Task { try await adapter.waitForFinalResult() }
        while !adapter.isFinishing { await Task.yield() }
        var failures = 0
        adapter.processCompletion(failed: false) { failures += 1 }
        adapter.processCompletion(failed: true) { failures += 1 }
        let text = try await finishing.value
        XCTAssertEqual(text, "hello there how are you")
        XCTAssertEqual(failures, 0)
    }

    func testVolatileTextIsNeverSubmittedAsPartialTranscript() async {
        let adapter = AppleSpeechCapture()
        defer { adapter.cancel() }
        adapter.processResult(text: "unfinalized words", isFinal: false) {}
        let finishing = Task { try await adapter.waitForFinalResult() }
        while !adapter.isFinishing { await Task.yield() }
        adapter.processCompletion(failed: false) {}
        let text = try? await finishing.value
        XCTAssertEqual(text, "")
    }

    func testRecognitionErrorDuringFinalizationFailsWithoutText() async {
        let adapter = AppleSpeechCapture()
        defer { adapter.cancel() }
        adapter.processResult(text: "kept out", isFinal: true) {}
        let finishing = Task { try await adapter.waitForFinalResult() }
        while !adapter.isFinishing { await Task.yield() }
        adapter.processCompletion(failed: true) { XCTFail("Unexpected failure callback") }
        do {
            _ = try await finishing.value
            XCTFail("A recognizer error must fail the turn")
        } catch {
            XCTAssertEqual(error as? SpeechCaptureError, .recognitionFailed)
        }
    }

    func testSpeechActivityReportsOnlyNewTranscriptText() {
        let adapter = AppleSpeechCapture()
        defer { adapter.cancel() }
        var speech = 0
        adapter.processResult(text: "", isFinal: false) { speech += 1 }
        adapter.processResult(text: "  ", isFinal: false) { speech += 1 }
        XCTAssertEqual(speech, 0, "Empty transcripts are not speech")
        adapter.processResult(text: "hel", isFinal: false) { speech += 1 }
        adapter.processResult(text: "hello", isFinal: false) { speech += 1 }
        XCTAssertEqual(speech, 2)
        adapter.processResult(text: "hello", isFinal: false) { speech += 1 }
        XCTAssertEqual(speech, 2, "Repeated text must not extend the silence countdown")
        adapter.processResult(text: "hello", isFinal: true) { speech += 1 }
        XCTAssertEqual(speech, 2, "A final confirming volatile text is not new speech")
        adapter.processResult(text: "again", isFinal: true) { speech += 1 }
        XCTAssertEqual(speech, 3)
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
        adapter.processCompletion(failed: false) { failures += 1 }
        XCTAssertEqual(failures, 1)
    }

    func testCancelClearsFinalizedSegmentsForNextCapture() async throws {
        let adapter = AppleSpeechCapture()
        defer { adapter.cancel() }
        adapter.processResult(text: "old turn", isFinal: true) {}
        adapter.cancel()
        let finishing = Task { try await adapter.waitForFinalResult() }
        while !adapter.isFinishing { await Task.yield() }
        adapter.processResult(text: "new turn", isFinal: true) {}
        adapter.processCompletion(failed: false) {}
        let text = try await finishing.value
        XCTAssertEqual(text, "new turn")
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
        adapter.processResult(text: "new turn", isFinal: true) {}
        adapter.processCompletion(failed: false) { XCTFail("Unexpected failure") }
        let text = try await newFinish.value
        XCTAssertEqual(text, "new turn")
    }

    func testFinalizationDeadlineReturnsFailureNotPartialText() async {
        let adapter = AppleSpeechCapture(finalResultTimeout: 10_000_000)
        defer { adapter.cancel() }
        adapter.processResult(text: "partial", isFinal: false) {}
        do {
            _ = try await adapter.waitForFinalResult()
            XCTFail("Missing final must fail")
        } catch {
            XCTAssertEqual(error as? SpeechCaptureError, .noFinalResult)
        }
    }

    func testFinishWithoutStartedCaptureFails() async {
        let adapter = AppleSpeechCapture()
        do {
            _ = try await adapter.finish()
            XCTFail("finish() needs a started analyzer")
        } catch {
            XCTAssertEqual(error as? SpeechCaptureError, .unavailable)
        }
    }

    func testCompletionBeforeFinishingReportsFailureOnce() {
        let adapter = AppleSpeechCapture()
        var failures = 0
        adapter.processCompletion(failed: true) { failures += 1 }
        XCTAssertEqual(failures, 1)
        adapter.cancel()
    }
}

@MainActor
private final class CallbackSpeech: SpeechCapture {
    let adapter = AppleSpeechCapture()
    var onFailure: (() -> Void)?
    var cancels = 0
    func start(onSpeech: @escaping () -> Void, onFailure: @escaping () -> Void) async throws {
        self.onFailure = onFailure
    }
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
