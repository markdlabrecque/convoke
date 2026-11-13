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

/// Turns arbitrarily sized PCM pieces into whole-sample frames of at most `maxChunkBytes`, and
/// enforces the per-turn cap as audio arrives rather than after synthesis ends. An HTTP body
/// part can split a 16-bit sample, so a single odd byte is carried to the next piece.
struct AudioFramer {
    private var carry = Data()
    private(set) var totalBytes = 0

    mutating func push(_ piece: Data) throws -> [Data] {
        var data = carry + piece
        carry = Data()
        if !data.count.isMultiple(of: 2) {
            carry = Data([data[data.endIndex - 1]])
            data = Data(data.dropLast())
        }
        guard data.count <= ConversationProtocol.maxAudioBytes - totalBytes else { throw ConversationError.audioLimit }
        totalBytes += data.count
        var chunks: [Data] = []
        var offset = data.startIndex
        while offset < data.endIndex {
            let end = min(offset + ConversationProtocol.maxChunkBytes, data.endIndex)
            chunks.append(data.subdata(in: offset..<end))
            offset = end
        }
        return chunks
    }

    /// The stream ended: it must have produced audio and no half sample.
    func finish() throws {
        guard carry.isEmpty, totalBytes > 0 else { throw ConversationError.invalidAudio }
    }
}

// All connection state and writes run on the socket's event loop. Synthesis runs
// on the main actor because AVSpeechSynthesizer requires a running main run loop.
final class Conversation: @unchecked Sendable {
    typealias Synthesize = @MainActor (String) async throws -> Data
    /// PCM pieces of any size, in order. The sender pulls the next piece only after the
    /// previous frame is written, and cancels the task that pulls when the turn ends.
    typealias SynthesizeStream = @MainActor (String) async throws -> AsyncThrowingStream<Data, Error>
    private enum State { case idle, active, closed }
    private var state = State.idle
    private let socket: WebSocket
    private let synthesize: SynthesizeStream
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
        synthesize: @escaping SynthesizeStream
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
                let pieces = try await synthesize(reply)
                var framer = AudioFramer()
                var sequence = 0
                var iterator = pieces.makeAsyncIterator()
                // Each frame goes out as soon as its audio exists, so the phone can start
                // playing before synthesis ends. The next piece is not pulled until the
                // previous frame has been written.
                while let piece = try await iterator.next() {
                    try Task.checkCancellation()
                    for chunk in try framer.push(piece) {
                        let frame = try ConversationProtocol.json([
                            "type": "agent.audio", "sequence": sequence, "data": chunk.base64EncodedString(),
                        ])
                        try await self.write(frame)
                        sequence += 1
                    }
                }
                try Task.checkCancellation()
                try framer.finish()
                try await self.write(ConversationProtocol.json(["type": "agent.done", "chunks": sequence]), completesTurn: true)
            } catch {
                // Reasons carry status codes and types only, never text or audio.
                let cancelled = error is CancellationError || Task.isCancelled
                let writeFailed = error is WriteFailed
                if !cancelled && !writeFailed {
                    self.logger.error("Speech synthesis failed", metadata: ["reason": "\(error)"])
                }
                self.socket.eventLoop.execute {
                    // Already closed by a disconnect, timeout or overlapping turn: nothing to add.
                    guard self.state == .active else { return }
                    if cancelled || writeFailed { self.close() } else { self.fail() }
                }
            }
        }
    }

    private struct WriteFailed: Error {}

    /// Writes one frame from the synthesis task and returns when the socket has accepted it.
    private func write(_ frame: String, completesTurn: Bool = false) async throws {
        let loop = socket.eventLoop
        do {
            try await loop.flatSubmit { () -> EventLoopFuture<Void> in
                guard self.state == .active else { return loop.makeFailedFuture(CancellationError()) }
                return self.send(frame).map {
                    if completesTurn, self.state == .active { self.finishTurn() }
                }
            }.get()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw WriteFailed()
        }
    }

    private func finishTurn() {
        deadline?.cancel()
        deadline = nil
        synthesis = nil
        state = .idle
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
    stream: Conversation.SynthesizeStream? = nil,
    agent: (any Agent)? = nil
) throws {
    // Missing agent configuration or a malformed CONVOKE_KOKORO_URL fails here, at startup.
    let agent = try agent ?? OpenAIChatAgent(
        client: app.client, config: AgentConfig(environment: ProcessInfo.processInfo.environment)
    )
    let kokoro = try KokoroConfig(environment: ProcessInfo.processInfo.environment)
    let client = app.client
    let http = app.http.client.shared
    let streamAudio: Conversation.SynthesizeStream = stream
        ?? synthesize.map(SpeechAudio.stream(wrapping:))
        ?? { try await makeSpeechSynthesizer(kokoro: kokoro, client: client, http: http).stream($0) }
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
            _ = Conversation(socket: socket, timeout: turnTimeout, agent: agent, logger: app.logger, synthesize: streamAudio)
        }
        return response
    }
}
