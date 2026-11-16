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

/// Opt in only on an Apple host with an audio output route. Uses silence, never
/// records audio, and exercises the real adapter rather than the queue helper.
@MainActor
final class PCMPlayerRuntimeTests: XCTestCase {
    private func requireRuntime() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CONVOKE_TEST_AUDIO_ENGINE"] == "1",
                          "Set CONVOKE_TEST_AUDIO_ENGINE=1 to exercise the actual audio engine")
    }

    func testActualEngineDrainsThresholdAndShortEOF() async throws {
        try requireRuntime()
        for bytes in [9_600, 2] {
            let player = PCMPlayer()
            var starts = 0
            var failures = 0
            try player.beginStream(onStarted: { starts += 1 }, onFailure: { failures += 1 })
            defer { player.stop() }
            try player.enqueue(pcm: Data(count: bytes))
            XCTAssertEqual(starts, bytes >= 9_600 ? 1 : 0)
            let completed = expectation(description: "actual dataPlayedBack resolves EOF")
            let drain = Task { @MainActor in
                defer { completed.fulfill() }
                do { try await player.endStream() }
                catch { XCTFail("Actual engine failed to drain: \(type(of: error))") }
            }
            defer { drain.cancel() }
            await fulfillment(of: [completed], timeout: 10)
            XCTAssertEqual(starts, 1, "Short EOF starts the same engine without waiting for 200 ms")
            XCTAssertEqual(failures, 0)
        }
    }

    func testActualEngineStopCancelsPendingDrainAndCanRestart() async throws {
        try requireRuntime()
        let player = PCMPlayer()
        defer { player.stop() }
        var starts = 0
        var failures = 0
        try player.beginStream(onStarted: { starts += 1 }, onFailure: { failures += 1 })
        try player.enqueue(pcm: Data(count: 48_000 * 5))
        let entered = expectation(description: "EOF finalizer entered")
        let settled = expectation(description: "stop cancels actual engine drain")
        let drain = Task { @MainActor in
            defer { settled.fulfill() }
            entered.fulfill()
            do {
                try await player.endStream()
                XCTFail("Stopped stream must not succeed")
            } catch is CancellationError {} catch {
                XCTFail("Expected cancellation, received \(type(of: error))")
            }
        }
        defer { drain.cancel() }
        await fulfillment(of: [entered], timeout: 3)
        player.stop()
        await fulfillment(of: [settled], timeout: 3)
        XCTAssertEqual(starts, 1)
        XCTAssertEqual(failures, 0, "Explicit stop is not a playback failure")
        try player.beginStream(onStarted: { starts += 1 }, onFailure: { failures += 1 })
        try player.enqueue(pcm: Data(count: 2))
        let restarted = expectation(description: "replacement stream drains")
        let replacement = Task { @MainActor in
            defer { restarted.fulfill() }
            do { try await player.endStream() }
            catch { XCTFail("Replacement engine failed: \(type(of: error))") }
        }
        defer { replacement.cancel() }
        await fulfillment(of: [restarted], timeout: 10)
        XCTAssertEqual(starts, 2)
        XCTAssertEqual(failures, 0)
    }

    #if os(iOS)
    func testActualAdapterHandlesInjectedSessionInterruptionBeforeEOF() async throws {
        try requireRuntime()
        let player = PCMPlayer()
        defer { player.stop() }
        var starts = 0
        let failed = expectation(description: "actual notification observer fails the stream")
        try player.beginStream(onStarted: { starts += 1 }, onFailure: { failed.fulfill() })
        try player.enqueue(pcm: Data(count: 48_000 * 5))
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification, object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue]
        )
        await fulfillment(of: [failed], timeout: 3)
        XCTAssertThrowsError(try player.enqueue(pcm: Data(count: 2)))
        do {
            try await player.endStream()
            XCTFail("Interrupted stream must not complete successfully")
        } catch {}
        XCTAssertEqual(starts, 1)
    }
    #endif
}
#endif
