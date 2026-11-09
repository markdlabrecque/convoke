import Foundation
import Vapor

struct ChatMessage: Sendable, Equatable {
    enum Role: String, Sendable { case system, user, assistant }
    var role: Role
    var content: String
}

/// Produces the agent's reply to a conversation. `history` ends with the new user message.
protocol Agent: Sendable {
    func reply(to history: [ChatMessage]) async throws -> String
}

/// Errors carry status codes and reasons only, never message text, so they are safe to log.
enum AgentError: Error, CustomStringConvertible {
    case config(String)
    case http(status: UInt)
    case badResponse(String)

    var description: String {
        switch self {
        case .config(let reason): return "agent configuration: \(reason)"
        case .http(let status): return "agent endpoint returned HTTP \(status)"
        case .badResponse(let reason): return "agent endpoint sent an unusable response: \(reason)"
        }
    }
}

struct AgentConfig: Sendable {
    static let systemPrompt = """
        You are a voice assistant. Your reply is spoken aloud. Answer briefly, in plain \
        conversational sentences. Do not use markdown, lists, code blocks, or emoji.
        """

    let baseURL: String
    let model: String
    let apiKey: String?

    /// Reads `CONVOKE_AGENT_BASE_URL` (up to and including `/v1`), `CONVOKE_AGENT_MODEL`
    /// and the optional `CONVOKE_AGENT_API_KEY`.
    init(environment: [String: String]) throws {
        func value(_ name: String) -> String? {
            let trimmed = environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }
        guard let base = value("CONVOKE_AGENT_BASE_URL"), let model = value("CONVOKE_AGENT_MODEL") else {
            throw AgentError.config(
                "set CONVOKE_AGENT_BASE_URL (for example http://localhost:11434/v1) and CONVOKE_AGENT_MODEL; CONVOKE_AGENT_API_KEY is optional"
            )
        }
        guard let url = URL(string: base), ["http", "https"].contains(url.scheme), url.host != nil else {
            throw AgentError.config("CONVOKE_AGENT_BASE_URL must be an http or https URL")
        }
        self.baseURL = base.hasSuffix("/") ? String(base.dropLast()) : base
        self.model = model
        self.apiKey = value("CONVOKE_AGENT_API_KEY")
    }
}

/// OpenAI-compatible `POST {base}/chat/completions` (Ollama, llama.cpp, and others). Not streaming.
struct OpenAIChatAgent: Agent {
    let client: any Client
    let config: AgentConfig

    private struct Request: Content {
        struct Message: Content { var role: String; var content: String }
        var model: String
        var messages: [Message]
        var stream: Bool
    }

    private struct Response: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { var content: String? }
            var message: Message
        }
        var choices: [Choice]
    }

    func reply(to history: [ChatMessage]) async throws -> String {
        let messages = [ChatMessage(role: .system, content: AgentConfig.systemPrompt)] + history
        let body = Request(
            model: config.model,
            messages: messages.map { .init(role: $0.role.rawValue, content: $0.content) },
            stream: false
        )
        var headers = HTTPHeaders()
        if let key = config.apiKey { headers.bearerAuthorization = BearerAuthorization(token: key) }
        let response = try await client.post(URI(string: config.baseURL + "/chat/completions"), headers: headers) {
            try $0.content.encode(body, as: .json)
        }
        guard response.status == .ok else { throw AgentError.http(status: response.status.code) }
        let decoded: Response
        do { decoded = try response.content.decode(Response.self) }
        catch { throw AgentError.badResponse("not a chat completion") }
        let text = decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { throw AgentError.badResponse("empty reply") }
        return text
    }
}
