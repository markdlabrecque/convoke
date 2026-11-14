import XCTest
@testable import ConvokeCore

@MainActor
final class PCMPlaybackLifetimeTests: XCTestCase {
    func testStopSettlesPendingWorkOnceAndInvalidatesOldCallbacks() async throws {
        let lifetime = PCMPlaybackLifetime()
        var starts = 0
        var failures = 0
        let old = lifetime.begin(onStarted: { starts += 1 }, onFailure: { failures += 1 })
        let registered = expectation(description: "Waiter enters the main-actor wait")
        let waiting = Task {
            registered.fulfill()
            try await lifetime.wait()
        }
        await fulfillment(of: [registered], timeout: 2)
        lifetime.stop()
        lifetime.stop()
        lifetime.fail(old)
        lifetime.succeed(old)
        lifetime.started(old)
        do { try await waiting.value; XCTFail("Stop must cancel") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(starts, 0)
        XCTAssertEqual(failures, 0)
        let current = lifetime.begin(onStarted: { starts += 1 }, onFailure: { failures += 1 })
        lifetime.started(old)
        lifetime.fail(old)
        lifetime.succeed(old)
        XCTAssertEqual(lifetime.id, current)
        lifetime.started(current)
        lifetime.started(current)
        XCTAssertEqual(starts, 1)
        lifetime.succeed(current)
        try await lifetime.wait()
        XCTAssertEqual(failures, 0)
    }

    func testInterruptionOrConfigurationFailureBeforeWaitIsVisibleExactlyOnce() async {
        let lifetime = PCMPlaybackLifetime()
        var failures = 0
        let id = lifetime.begin(onStarted: {}, onFailure: {
            failures += 1
            XCTAssertNil(lifetime.id, "Invalidation precedes the failure callback")
            lifetime.stop() // Controller teardown is allowed to be reentrant.
        })
        lifetime.fail(id)
        lifetime.fail(id)
        lifetime.succeed(id)
        XCTAssertEqual(failures, 1)
        XCTAssertThrowsError(try lifetime.check())
        do { try await lifetime.wait(); XCTFail("Failure must survive until EOF") }
        catch { XCTAssertEqual(error as? ResponseError, .invalid) }
    }

    func testFailureResolvesWaitingEOFAndLateStopCannotChangeSuccess() async throws {
        let lifetime = PCMPlaybackLifetime()
        var failures = 0
        let id = lifetime.begin(onStarted: {}, onFailure: { failures += 1 })
        let registered = expectation(description: "EOF waiter registered")
        let waiting = Task {
            registered.fulfill()
            try await lifetime.wait()
        }
        await fulfillment(of: [registered], timeout: 2)
        lifetime.fail(id)
        do { try await waiting.value; XCTFail("Expected failure") }
        catch { XCTAssertEqual(error as? ResponseError, .invalid) }
        XCTAssertEqual(failures, 1)
        let next = lifetime.begin(onStarted: {}, onFailure: { failures += 1 })
        lifetime.succeed(next)
        lifetime.stop()
        lifetime.fail(next)
        try await lifetime.wait()
        XCTAssertEqual(failures, 1)
    }
}

final class PCMPlaybackQueueTests: XCTestCase {
    func testStartupAndShortEOFFlush() throws {
        var queue = PCMPlaybackQueue()
        try queue.append(bytes: 9_598)
        XCTAssertFalse(queue.started)
        try queue.append(bytes: 2)
        XCTAssertTrue(queue.started)
        var short = PCMPlaybackQueue()
        try short.append(bytes: 2)
        XCTAssertFalse(short.started)
        try short.finish()
        XCTAssertTrue(short.started)
        XCTAssertFalse(short.drained)
        short.played(bytes: 2)
        XCTAssertTrue(short.drained)
    }

    func testExactCapOverflowAndPlayedStorageRelease() throws {
        var queue = PCMPlaybackQueue()
        try queue.append(bytes: PCMPlaybackQueue.limit)
        XCTAssertEqual(queue.queuedBytes, PCMPlaybackQueue.limit)
        XCTAssertThrowsError(try queue.append(bytes: 2))
        XCTAssertEqual(queue.queuedBytes, PCMPlaybackQueue.limit)
        queue.played(bytes: 16_384)
        try queue.append(bytes: 16_384)
        XCTAssertEqual(queue.queuedBytes, PCMPlaybackQueue.limit)
        queue.played(bytes: PCMPlaybackQueue.limit)
        XCTAssertEqual(queue.queuedBytes, 0)
    }

    func testUnderrunWaitsForLaterAudioAndEOF() throws {
        var queue = PCMPlaybackQueue()
        try queue.append(bytes: 9_600)
        queue.played(bytes: 9_600)
        XCTAssertFalse(queue.drained)
        XCTAssertTrue(queue.started)
        try queue.append(bytes: 2)
        queue.played(bytes: 2)
        XCTAssertFalse(queue.drained)
        try queue.finish()
        XCTAssertTrue(queue.drained)
        XCTAssertThrowsError(try queue.append(bytes: 2))
        XCTAssertThrowsError(try queue.finish())
    }

    func testInvalidSizesDoNotChangeAccounting() {
        var queue = PCMPlaybackQueue()
        for bytes in [0, -2, 1, Int.max] {
            XCTAssertThrowsError(try queue.append(bytes: bytes))
            XCTAssertEqual(queue.queuedBytes, 0)
        }
    }
}
