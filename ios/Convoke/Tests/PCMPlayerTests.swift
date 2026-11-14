import XCTest
@testable import ConvokeCore
#if canImport(AVFoundation)
import AVFoundation

@MainActor
final class PCMPlayerTests: XCTestCase {
    func testLittleEndianSignedSamplesAndFormat() async throws {
        let pcm = Data([0, 128, 255, 127, 0, 0, 0, 64, 0, 192, 1, 0])
        let buffer = try PCMPlayer.makeBuffer(pcm: pcm)
        XCTAssertEqual(buffer.format.sampleRate, 24000)
        XCTAssertEqual(buffer.format.channelCount, 1)
        XCTAssertEqual(buffer.frameLength, 6)
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        XCTAssertEqual(Array(UnsafeBufferPointer(start: samples, count: 6)),
                       [-1, Float(32767) / 32768, 0, 0.5, -0.5, Float(1) / 32768])
    }

    func testInvalidPCMIsRejectedBeforeStartingAudioHardware() async {
        for pcm in [Data(), Data([0]), Data(repeating: 0, count: 8 * 1024 * 1024 + 2)] {
            XCTAssertThrowsError(try PCMPlayer.makeBuffer(pcm: pcm))
        }
    }
}
#endif

/// Exercises the queue used by PCMPlayer without creating an audio engine.
final class PCMPlayerQueueRegressionTests: XCTestCase {
    func testStartupBoundaryMatrixAndShortFlush() throws {
        for bytes in [2, 9_598, 9_600, 9_602, 16_384] {
            var queue = PCMPlaybackQueue()
            try queue.append(bytes: bytes)
            XCTAssertEqual(queue.started, bytes >= 9_600)
            XCTAssertEqual(queue.queuedBytes, bytes)
            try queue.finish()
            XCTAssertTrue(queue.started, "EOF flushes even one sample")
            XCTAssertFalse(queue.drained, "EOF cannot stand in for a played-back callback")
            queue.played(bytes: bytes)
            XCTAssertTrue(queue.drained)
        }
    }

    func testOrderedBufferAccountingInBothEOFOrders() throws {
        let buffers = [2, 9_596, 2, 16_384, 6]
        for eofFirst in [false, true] {
            var queue = PCMPlaybackQueue()
            var total = 0
            for bytes in buffers {
                try queue.append(bytes: bytes)
                total += bytes
                XCTAssertEqual(queue.queuedBytes, total, "Scheduled but unplayed buffers still count")
                XCTAssertEqual(queue.started, total >= 9_600)
            }
            if eofFirst { try queue.finish() }
            for bytes in buffers {
                queue.played(bytes: bytes)
                total -= bytes
                XCTAssertEqual(queue.queuedBytes, total, "Release exactly the next played buffer")
                XCTAssertEqual(queue.drained, eofFirst && total == 0)
            }
            if !eofFirst {
                XCTAssertFalse(queue.drained, "An empty queue before EOF is only an underrun")
                try queue.finish()
            }
            XCTAssertTrue(queue.drained)
        }
    }

    func testRepeatedUnderrunsDoNotReapplyStartupThresholdOrComplete() throws {
        var queue = PCMPlaybackQueue()
        try queue.append(bytes: 9_600)
        queue.played(bytes: 9_600)
        for _ in 0..<3 {
            XCTAssertTrue(queue.started)
            XCTAssertFalse(queue.drained)
            try queue.append(bytes: 2)
            XCTAssertTrue(queue.started, "A resumed stream does not wait for another 200 ms")
            queue.played(bytes: 2)
        }
        try queue.finish()
        XCTAssertTrue(queue.drained)
    }
}
