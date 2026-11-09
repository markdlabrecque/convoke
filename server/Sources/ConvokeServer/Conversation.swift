import Foundation
import Vapor
import NIOCore

enum ConversationError: Error {
    case invalidMessage, invalidAudio, audioLimit, synthesisFailed, noSynthesizer
}

enum ConversationProtocol {
    static let maxFrameBytes = 32_768
    static let maxTextBytes = 4_096
    static let maxChunkBytes = 16_384
    static let maxAudioBytes = 8 * 1_024 * 1_024

    /// Validates a `user.text` frame and returns its trimmed text.
    static func userText(from frame: String) throws -> String {
        guard frame.utf8.count <= maxFrameBytes,
              let object = try JSONSerialization.jsonObject(with: Data(frame.utf8)) as? [String: Any],
              Set(object.keys) == ["type", "text"],
              object["type"] as? String == "user.text",
              let text = object["text"] as? String else {
            throw ConversationError.invalidMessage
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= maxTextBytes else {
            throw ConversationError.invalidMessage
        }
        return trimmed
    }

    static func json(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard data.count <= maxFrameBytes else { throw ConversationError.invalidMessage }
        return String(decoding: data, as: UTF8.self)
    }

    static func validateAudio(_ data: Data) throws {
        guard data.count <= maxAudioBytes else { throw ConversationError.audioLimit }
        guard !data.isEmpty, data.count.isMultiple(of: 2) else { throw ConversationError.invalidAudio }
    }
}

// All connection state and writes run on the socket's event loop. Synthesis runs
// on the main actor because AVSpeechSynthesizer requires a running main run loop.
final class Conversation: @unchecked Sendable {
    typealias Synthesize = @MainActor (String) async throws -> Data
    private enum State { case idle, active, closed }
    private var state = State.idle
    private let socket: WebSocket
    private let synthesize: Synthesize
    private let agent: any Agent
    private let logger: Logger
    private let timeout: TimeAmount
    // Per-connection history, touched only on the socket's event loop. Never persisted.
    private var history: [ChatMessage] = []
    private static let maxHistoryMessages = 40

    /// Drops the oldest whole user/assistant pairs so the history still starts with a user message.
    static func trimmed(_ history: [ChatMessage]) -> [ChatMessage] {
        var result = history
        while result.count > maxHistoryMessages { result.removeFirst(2) }
        return result
    }

    private var agentTurn: Task<Void, Never>?
    private var synthesis: Task<Void, Never>?
    private var deadline: Scheduled<Void>?

    init(
        socket: WebSocket, timeout: TimeAmount, agent: any Agent,
        logger: Logger = Logger(label: "convoke.conversation"),
        synthesize: @escaping Synthesize
    ) {
        self.socket = socket
        self.logger = logger
        self.timeout = timeout
        self.agent = agent
        self.synthesize = synthesize
        socket.onText { [weak self] _, text in self?.receive(text) }
        socket.onBinary { [weak self] _, _ in self?.close() }
        // Retain the conversation until the channel closes, not through the
        // socket's permanent message callbacks.
        socket.onClose.whenComplete { _ in self.disconnected() }
    }

    func receive(_ frame: String) {
        socket.eventLoop.preconditionInEventLoop()
        guard state == .idle else { close(); return }
        do {
            let userText = try ConversationProtocol.userText(from: frame)
            state = .active
            deadline = socket.eventLoop.scheduleTask(in: timeout) { self.close() }
            history.append(ChatMessage(role: .user, content: userText))
            history = Self.trimmed(history)
            let snapshot = history
            logger.info("Turn started", metadata: ["userBytes": "\(userText.utf8.count)", "historyMessages": "\(snapshot.count)"])
            agentTurn = Task { [agent] in
                do {
                    let reply = try await agent.reply(to: snapshot)
                    try Task.checkCancellation()
                    self.socket.eventLoop.execute { self.deliver(reply) }
                } catch {
                    self.socket.eventLoop.execute { self.agentFailed(error) }
                }
            }
        } catch { close() }
    }

    private func deliver(_ reply: String) {
        guard state == .active else { return }
        agentTurn = nil
        do {
            let text = try ConversationProtocol.json(["type": "agent.text", "text": reply])
            history.append(ChatMessage(role: .assistant, content: reply))
            logger.info("Agent replied", metadata: ["replyBytes": "\(reply.utf8.count)"])
            send(text).whenComplete { result in
                guard self.state == .active else { return }
                switch result {
                case .failure: self.close()
                case .success: self.startSynthesis(reply)
                }
            }
        } catch {
            logger.error("Agent reply cannot be sent", metadata: ["replyBytes": "\(reply.utf8.count)", "error": "\(type(of: error))"])
            fail()
        }
    }

    private func agentFailed(_ error: Error) {
        guard state == .active else { return }
        agentTurn = nil
        if error is CancellationError { return close() }
        // Error descriptions carry status codes and types only, never message text.
        logger.error("Agent request failed", metadata: ["reason": "\(error)"])
        fail()
    }

    // Tell the client the server failed (close code 1011), not that it broke a rule.
    private func fail() {
        disconnected()
        socket.close(code: .unexpectedServerError, promise: nil)
    }

    private func startSynthesis(_ reply: String) {
        synthesis = Task { @MainActor [synthesize] in
            do {
                let audio = try await synthesize(reply)
                try Task.checkCancellation()
                self.socket.eventLoop.execute { self.sendAudio(audio) }
            } catch {
                // Reasons carry status codes and types only, never text or audio.
                if error is CancellationError {
                    self.socket.eventLoop.execute { self.close() }
                } else {
                    self.logger.error("Speech synthesis failed", metadata: ["reason": "\(error)"])
                    self.socket.eventLoop.execute { self.fail() }
                }
            }
        }
    }

    private func sendAudio(_ audio: Data) {
        guard state == .active else { return }
        synthesis = nil
        do {
            try ConversationProtocol.validateAudio(audio)
            sendChunk(audio, offset: 0, sequence: 0)
        } catch {
            logger.error("Synthesized audio rejected", metadata: ["reason": "\(error)", "audioBytes": "\(audio.count)"])
            fail()
        }
    }

    private func sendChunk(_ audio: Data, offset: Int, sequence: Int) {
        guard state == .active else { return }
        do {
            let complete = offset == audio.count
            let end = min(offset + ConversationProtocol.maxChunkBytes, audio.count)
            let frame = try complete
                ? ConversationProtocol.json(["type": "agent.done", "chunks": sequence])
                : ConversationProtocol.json([
                    "type": "agent.audio", "sequence": sequence,
                    "data": audio.subdata(in: offset..<end).base64EncodedString(),
                ])
            send(frame).whenComplete { result in
                guard self.state == .active else { return }
                switch result {
                case .failure: self.close()
                case .success:
                    if complete {
                        self.deadline?.cancel()
                        self.deadline = nil
                        self.state = .idle
                    } else {
                        // A completed write may invoke its callback inline. Yield
                        // between chunks so a full 8 MiB turn cannot grow the stack.
                        self.socket.eventLoop.execute {
                            self.sendChunk(audio, offset: end, sequence: sequence + 1)
                        }
                    }
                }
            }
        } catch { close() }
    }

    private func send(_ frame: String) -> EventLoopFuture<Void> {
        let promise = socket.eventLoop.makePromise(of: Void.self)
        socket.send(frame, promise: promise)
        return promise.futureResult
    }

    func disconnected() {
        socket.eventLoop.preconditionInEventLoop()
        state = .closed
        deadline?.cancel()
        deadline = nil
        agentTurn?.cancel()
        agentTurn = nil
        synthesis?.cancel()
        synthesis = nil
    }

    func close() {
        disconnected()
        socket.close(code: .policyViolation, promise: nil)
    }
}

func configure(
    _ app: Application,
    turnTimeout: TimeAmount = .seconds(120),
    synthesize: Conversation.Synthesize? = nil,
    agent: (any Agent)? = nil
) throws {
    // Missing agent configuration or a malformed CONVOKE_KOKORO_URL fails here, at startup.
    let agent = try agent ?? OpenAIChatAgent(
        client: app.client, config: AgentConfig(environment: ProcessInfo.processInfo.environment)
    )
    let kokoro = try KokoroConfig(environment: ProcessInfo.processInfo.environment)
    let client = app.client
    let synthesize = synthesize ?? { try await makeSpeechSynthesizer(kokoro: kokoro, client: client).synthesize($0) }
    app.http.server.configuration.hostname = "0.0.0.0"
    if let value = Environment.get("PORT") {
        guard let port = Int(value), (1...65535).contains(port) else {
            throw Abort(.internalServerError, reason: "PORT must be an integer from 1 to 65535")
        }
        app.http.server.configuration.port = port
    } else {
        app.http.server.configuration.port = 8080
    }
    app.get("conversation") { _ -> Response in
        let response = Response(status: .switchingProtocols)
        response.upgrader = ConversationUpgrader { socket in
            _ = Conversation(socket: socket, timeout: turnTimeout, agent: agent, logger: app.logger, synthesize: synthesize)
        }
        return response
    }
}
