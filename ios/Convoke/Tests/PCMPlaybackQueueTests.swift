import XCTest
@testable import ConvokeCore

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
