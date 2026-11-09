import XCTest
import Vapor
@testable import ConvokeServer

final class KokoroTests: XCTestCase {
    func testConfigFromEnvironment() throws {
        XCTAssertNil(try KokoroConfig(environment: [:]))
        XCTAssertNil(try KokoroConfig(environment: ["CONVOKE_KOKORO_URL": "  "]))
        XCTAssertThrowsError(try KokoroConfig(environment: ["CONVOKE_KOKORO_URL": "localhost:8880"]))
        let defaults = try XCTUnwrap(KokoroConfig(environment: ["CONVOKE_KOKORO_URL": "http://127.0.0.1:8880/"]))
        XCTAssertEqual(defaults.baseURL, "http://127.0.0.1:8880")
        XCTAssertEqual(defaults.voice, KokoroConfig.defaultVoice)
        let custom = try XCTUnwrap(KokoroConfig(environment: ["CONVOKE_KOKORO_URL": "http://k", "CONVOKE_KOKORO_VOICE": "bf_emma"]))
        XCTAssertEqual(custom.voice, "bf_emma")
    }

    @MainActor func testRequestShapeAndPCMPassThrough() async throws {
        let pcm = Data((0..<4_000).map { UInt8($0 % 253) })  // whole 16-bit samples
        let stub = Stub()
        let audio = try await withStub(stub, status: .ok, body: pcm) { try await $0.synthesize("hello there") }
        XCTAssertEqual(audio, pcm, "Kokoro raw PCM is passed through untouched")
        XCTAssertEqual(stub.path, "/v1/audio/speech")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(stub.body.utf8)) as? [String: Any])
        XCTAssertEqual(object["input"] as? String, "hello there")
        XCTAssertEqual(object["voice"] as? String, KokoroConfig.defaultVoice)
        XCTAssertEqual(object["response_format"] as? String, "pcm")
        XCTAssertEqual(object["stream"] as? Bool, false)
    }

    @MainActor func testErrorsAreThrownNotSwallowed() async throws {
        let cases: [(HTTPStatus, Data)] = [
            (.internalServerError, Data([0, 0])), (.ok, Data()), (.ok, Data([1, 2, 3])),
        ]
        for (status, body) in cases {
            do {
                _ = try await withStub(Stub(), status: status, body: body) { try await $0.synthesize("x") }
                XCTFail("Expected an error for \(status) with \(body.count) bytes")
            } catch is SpeechError {}
        }
    }

    final class Stub: @unchecked Sendable { var path = "", body = "" }

    @MainActor private func withStub(
        _ stub: Stub, status: HTTPStatus, body: Data, _ run: (KokoroSpeechSynthesizer) async throws -> Data
    ) async throws -> Data {
        let app = try await Application.make(.testing)
        do {
            app.post("v1", "audio", "speech") { request -> Response in
                stub.path = request.url.path
                stub.body = request.body.string ?? ""
                return Response(status: status, body: .init(data: body))
            }
            try await app.server.start(address: .hostname("127.0.0.1", port: 0))
            let port = try XCTUnwrap(app.http.server.shared.localAddress?.port)
            let config = try XCTUnwrap(KokoroConfig(environment: ["CONVOKE_KOKORO_URL": "http://127.0.0.1:\(port)"]))
            let result = try await run(KokoroSpeechSynthesizer(client: app.client, config: config))
            await app.server.shutdown()
            try await app.asyncShutdown()
            return result
        } catch {
            await app.server.shutdown()
            try? await app.asyncShutdown()
            throw error
        }
    }
}
