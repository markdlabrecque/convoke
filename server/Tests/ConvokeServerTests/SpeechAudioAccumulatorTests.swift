import AVFoundation
import XCTest
@testable import ConvokeServer

final class SpeechAudioAccumulatorTests: XCTestCase {
    func testConversionTo24kMonoInt16LittleEndian() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let accumulator = SpeechAudioAccumulator()
        let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000)!
        input.frameLength = input.frameCapacity
        for channel in 0..<2 {
            for index in 0..<Int(input.frameLength) {
                input.floatChannelData![channel][index] = 0.5
            }
        }
        XCTAssertNil(try accumulator.consume(input))
        let end = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)!
        let audio = try XCTUnwrap(accumulator.consume(end))
        XCTAssertEqual(audio.count, 24_000 * 2)
        let middle = audio.count / 2
        let sample = Int16(bitPattern: UInt16(audio[middle]) | UInt16(audio[middle + 1]) << 8)
        XCTAssertEqual(Int(sample), 16384, accuracy: 2)
        XCTAssertNil(try accumulator.consume(end), "Completion is delivered once")
    }

    func testCapDuringAccumulation() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
        let accumulator = SpeechAudioAccumulator()
        let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 24_000)!
        input.frameLength = input.frameCapacity
        input.floatChannelData![0].initialize(repeating: 0.25, count: 24_000)
        var hitLimit = false
        for _ in 0..<176 {
            do {
                let result = try accumulator.consume(input)
                XCTAssertNil(result)
            } catch ConversationError.audioLimit { hitLimit = true; break }
        }
        XCTAssertTrue(hitLimit, "Must stop while buffering, before end-of-stream")
        XCTAssertNil(try accumulator.consume(input), "Failed accumulation cannot restart")
    }

    func testEmptyAudioFailsAndCancellationDiscardsBuffers() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
        let empty = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)!
        XCTAssertThrowsError(try SpeechAudioAccumulator().consume(empty))
        let cancelled = SpeechAudioAccumulator()
        cancelled.cancel()
        XCTAssertNil(try cancelled.consume(empty))
    }

    func testFormatChangeFails() throws {
        let accumulator = SpeechAudioAccumulator()
        for rate in [24_000.0, 48_000.0] {
            let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
            let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 100)!
            input.frameLength = input.frameCapacity
            input.floatChannelData![0].initialize(repeating: 0, count: 100)
            if rate == 24_000 { XCTAssertNil(try accumulator.consume(input)) }
            else { XCTAssertThrowsError(try accumulator.consume(input)) }
        }
    }
}
