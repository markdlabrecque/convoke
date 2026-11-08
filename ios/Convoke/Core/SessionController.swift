import Combine
import Foundation

@MainActor
public protocol ConversationTransport: AnyObject {
    var onDisconnect: (() -> Void)? { get set }
    func connect(to url: URL) async throws
    func receive() async throws -> URLSessionWebSocketTask.Message
    func send(text: String) async throws
    func disconnect()
}

@MainActor
public protocol SpeechCapture: AnyObject {
    /// Requests permissions and starts capture. Never log recognized text.
    func start(onFailure: @escaping () -> Void) async throws
    /// Ends audio input and waits for the recognizer's final result.
    func finish() async throws -> String
    func cancel()
}

@MainActor
public protocol CaptureTimer: AnyObject {
    func schedule(after seconds: TimeInterval, action: @escaping () -> Void)
    func cancel()
}

/// Plays in-memory 24 kHz mono signed 16-bit little-endian PCM.
@MainActor
public protocol ConversationPlayer: AnyObject {
    func play(pcm: Data) async throws
    func stop()
}

@MainActor
public final class SessionController: ObservableObject {
    public enum State: String {
        case disconnected, connecting, ready, recording, waiting, playing
    }

    public static let exampleURL = "ws://<Mac Tailscale IP>:8080/conversation"
    public static let urlDefaultsKey = "conversationURL"
    @Published public var serverURL: String {
        didSet { defaults.set(serverURL, forKey: Self.urlDefaultsKey) }
    }
    @Published public private(set) var state: State = .disconnected
    @Published public private(set) var isFinalizing = false

    private let defaults: UserDefaults
    private let transport: ConversationTransport
    private let recognition: SpeechCapture
    private let timer: CaptureTimer
    private let player: ConversationPlayer
    private let log: (String) -> Void
    private var connectionID = UUID()
    private var captureID: UUID?
    private var receiver: Task<Void, Never>?
    private var playback: Task<Void, Never>?
    private var response = ResponseAccumulator()

    public init(defaults: UserDefaults = .standard, transport: ConversationTransport,
                recognition: SpeechCapture, timer: CaptureTimer, player: ConversationPlayer,
                log: @escaping (String) -> Void = { _ in }) {
        self.defaults = defaults
        self.transport = transport
        self.recognition = recognition
        self.timer = timer
        self.player = player
        self.log = log
        serverURL = defaults.string(forKey: Self.urlDefaultsKey) ?? Self.exampleURL
        transport.onDisconnect = { [weak self] in self?.disconnect() }
    }

    public func connect() async {
        guard state == .disconnected else { return }
        let value = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value), ["ws", "wss"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.fragment == nil else {
            log("Invalid WebSocket URL")
            return
        }
        let id = UUID()
        connectionID = id
        state = .connecting
        do {
            try await transport.connect(to: url)
            guard connectionID == id else { return }
            state = .ready
            startReceiving(connection: id)
        } catch {
            guard connectionID == id else { return }
            log("WebSocket connection failed")
            disconnect()
        }
    }

    public func disconnect() {
        connectionID = UUID()
        receiver?.cancel()
        receiver = nil
        playback?.cancel()
        playback = nil
        response = ResponseAccumulator()
        captureID = nil
        isFinalizing = false
        state = .disconnected
        timer.cancel()
        recognition.cancel()
        player.stop()
        transport.disconnect()
    }

    public func startCapture() async {
        guard state == .ready else { return }
        let id = UUID()
        captureID = id
        state = .recording
        // Permissions can suspend. Do not allow submit until startup finishes.
        isFinalizing = true
        do {
            try await recognition.start { [weak self] in
                guard let self, self.captureID == id else { return }
                self.captureFailed()
            }
            guard captureID == id else { return }
            isFinalizing = false
            timer.schedule(after: 60) { [weak self] in
                Task { @MainActor in
                    guard let self, self.captureID == id else { return }
                    await self.submitCapture()
                }
            }
        } catch {
            guard captureID == id else { return }
            captureFailed()
        }
    }

    private func captureFailed() {
        log("Speech permission or recognition failed")
        captureID = nil
        isFinalizing = false
        timer.cancel()
        recognition.cancel()
        state = .ready
    }

    public func submitCapture() async {
        guard state == .recording, !isFinalizing, let id = captureID else { return }
        isFinalizing = true
        timer.cancel()
        let text: String
        do {
            text = try await recognition.finish().trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            guard captureID == id else { return }
            captureFailed()
            return
        }
        guard captureID == id else { return }
        captureID = nil
        isFinalizing = false
        recognition.cancel()
        guard !text.isEmpty else {
            state = .ready
            return
        }
        guard text.utf8.count <= 4096 else {
            log("Recognized text exceeds 4096 UTF-8 bytes")
            state = .ready
            return
        }
        struct UserText: Encodable {
            let type = "user.text"
            let text: String
        }
        let connection = connectionID
        do {
            let data = try JSONEncoder().encode(UserText(text: text))
            guard data.count <= 32768 else {
                log("Outgoing frame exceeds 32768 UTF-8 bytes")
                state = .ready
                return
            }
            state = .waiting
            try await transport.send(text: String(decoding: data, as: UTF8.self))
        } catch {
            guard connectionID == connection else { return }
            log("WebSocket send failed")
            disconnect()
        }
    }

    private func startReceiving(connection: UUID) {
        receiver = Task { @MainActor [weak self, transport] in
            do {
                while !Task.isCancelled {
                    let frame = try await transport.receive()
                    guard let self, self.connectionID == connection, !Task.isCancelled else { return }
                    guard self.state == .waiting else { throw ResponseError.invalid }
                    if let pcm = try self.response.consume(frame) {
                        self.response = ResponseAccumulator()
                        self.state = .playing
                        self.playback = Task { @MainActor [weak self, player = self.player] in
                            guard !Task.isCancelled, self?.connectionID == connection else { return }
                            do {
                                try await player.play(pcm: pcm)
                                guard let self, self.connectionID == connection, !Task.isCancelled else { return }
                                self.playback = nil
                                self.state = .ready
                            } catch {
                                guard let self, self.connectionID == connection, !Task.isCancelled else { return }
                                self.log("Audio playback failed")
                                self.disconnect()
                            }
                        }
                    }
                }
            } catch {
                guard let self, self.connectionID == connection, !Task.isCancelled else { return }
                self.log("WebSocket receive or response validation failed")
                self.disconnect()
            }
        }
    }
}

@MainActor
public final class DeadlineTimer: CaptureTimer {
    private var task: Task<Void, Never>?
    public init() {}
    public func schedule(after seconds: TimeInterval, action: @escaping () -> Void) {
        cancel()
        task = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
            catch { return }
            action()
        }
    }
    public func cancel() {
        task?.cancel()
        task = nil
    }
}
