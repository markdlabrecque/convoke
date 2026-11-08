import AVFoundation
import XCTest

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
