import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ConvokeCore

final class StreamingBoundsTests: XCTestCase {
    private func frame(_ object: [String: Any]) throws -> URLSessionWebSocketTask.Message {
        .string(String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self))
    }

    func testExactFrameAndCumulativeCapThenRejectOverflow() throws {
        var response = ResponseAccumulator()
        _ = try response.consume(frame(["type": "agent.text", "text": "fixture"]))
        let pcm = Data(count: 16_384)
        for sequence in 0..<512 {
            XCTAssertEqual(try response.consume(frame([
                "type": "agent.audio", "sequence": sequence, "data": pcm.base64EncodedString()
            ])), .audio(pcm))
        }
        var overflow = response
        XCTAssertThrowsError(try overflow.consume(frame([
            "type": "agent.audio", "sequence": 512, "data": Data(count: 2).base64EncodedString()
        ])))
        XCTAssertEqual(try response.consume(frame(["type": "agent.done", "chunks": 512])), .done)
        for object: [String: Any] in [
            ["type": "agent.done", "chunks": 512],
            ["type": "agent.text", "text": "fixture"],
            ["type": "agent.audio", "sequence": 512, "data": Data(count: 2).base64EncodedString()]
        ] {
            XCTAssertThrowsError(try response.consume(frame(object)))
        }
    }
}
