import XCTest
import Vapor
@testable import ConvokeServer

final class AgentTests: XCTestCase {
    func testConfigFromEnvironment() throws {
        XCTAssertThrowsError(try AgentConfig(environment: [:]))
        XCTAssertThrowsError(try AgentConfig(environment: ["CONVOKE_AGENT_BASE_URL": "http://x/v1"]))
        XCTAssertThrowsError(try AgentConfig(environment: ["CONVOKE_AGENT_BASE_URL": "ftp://x", "CONVOKE_AGENT_MODEL": "m"]))
        let config = try AgentConfig(environment: [
            "CONVOKE_AGENT_BASE_URL": "http://localhost:11434/v1/", "CONVOKE_AGENT_MODEL": "m", "CONVOKE_AGENT_API_KEY": " ",
        ])
        XCTAssertEqual(config.baseURL, "http://localhost:11434/v1")
        XCTAssertNil(config.apiKey)
    }

    func testRequestShapeAndReply() async throws {
        let stub = Stub()
        try await withStub(stub, status: .ok, body: #"{"choices":[{"message":{"content":" Hi there. "}}]}"#) { agent in
            let reply = try await agent.reply(to: [
                ChatMessage(role: .user, content: "a"), ChatMessage(role: .assistant, content: "b"),
                ChatMessage(role: .user, content: "c"),
            ])
            XCTAssertEqual(reply, "Hi there.")
        }
        XCTAssertEqual(stub.path, "/v1/chat/completions")
        XCTAssertEqual(stub.auth, "Bearer secret")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(stub.body.utf8)) as? [String: Any])
        XCTAssertEqual(object["model"] as? String, "test-model")
        XCTAssertEqual(object["stream"] as? Bool, false)
        let messages = try XCTUnwrap(object["messages"] as? [[String: String]])
        XCTAssertEqual(messages.map { $0["role"] }, ["system", "user", "assistant", "user"])
        XCTAssertEqual(messages.dropFirst().map { $0["content"] }, ["a", "b", "c"])
    }

    func testErrorsAreThrownNotSwallowed() async throws {
        for (status, body) in [(HTTPStatus.internalServerError, "{}"), (.ok, #"{"choices":[]}"#), (.ok, "not json"),
                               (.ok, #"{"choices":[{"message":{"content":"  "}}]}"#)] {
            try await withStub(Stub(), status: status, body: body) { agent in
                do {
                    _ = try await agent.reply(to: [ChatMessage(role: .user, content: "x")])
                    XCTFail("Expected an error for \(status)")
                } catch is AgentError {}
            }
        }
    }

    final class Stub: @unchecked Sendable { var path = "", auth = "", body = "" }

    private func withStub(_ stub: Stub, status: HTTPStatus, body: String, _ run: (OpenAIChatAgent) async throws -> Void) async throws {
        let app = try await Application.make(.testing)
        do {
            app.post("v1", "chat", "completions") { request -> Response in
                stub.path = request.url.path
                stub.auth = request.headers.first(name: .authorization) ?? ""
                stub.body = request.body.string ?? ""
                return Response(status: status, headers: ["content-type": "application/json"], body: .init(string: body))
            }
            app.http.server.configuration.hostname = "127.0.0.1"
            try await app.server.start(address: .hostname("127.0.0.1", port: 0))
            let port = try XCTUnwrap(app.http.server.shared.localAddress?.port)
            let config = try AgentConfig(environment: [
                "CONVOKE_AGENT_BASE_URL": "http://127.0.0.1:\(port)/v1", "CONVOKE_AGENT_MODEL": "test-model",
                "CONVOKE_AGENT_API_KEY": "secret",
            ])
            try await run(OpenAIChatAgent(client: app.client, config: config))
            await app.server.shutdown()
            try await app.asyncShutdown()
        } catch {
            await app.server.shutdown()
            try? await app.asyncShutdown()
            throw error
        }
    }
}
