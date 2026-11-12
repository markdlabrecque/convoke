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
    /// Requests microphone access, prepares the on-device speech model, and
    /// starts capture. `onSpeech` is called whenever the transcript changes
    /// (the controller derives silence from it). `onFailure` is called if
    /// recognition ends before `finish()`. Never log recognized text.
    func start(onSpeech: @escaping () -> Void, onFailure: @escaping () -> Void) async throws
    /// Ends audio input and waits for the recognizer's final result.
    func finish() async throws -> String
    func cancel()
}

/// Visible, content-free reasons that on-device capture could not run.
public enum SpeechCaptureError: Error, Equatable {
    case microphoneDenied, unsupportedOS, unsupportedLocale, modelUnavailable
    case modelPreparationFailed, unavailable, noFinalResult, recognitionFailed

    public var message: String {
        switch self {
        case .microphoneDenied: return "Microphone access is denied. Enable it in Settings."
        case .unsupportedOS: return "On-device speech recognition requires iOS 26 or later."
        case .unsupportedLocale: return "On-device speech recognition does not support this language."
        case .modelUnavailable: return "On-device speech recognition is not available on this device."
        case .modelPreparationFailed:
            return "The speech model could not be prepared. Check your network connection and try again."
        case .unavailable: return "The microphone or speech recognizer is unavailable."
        case .noFinalResult: return "Speech recognition did not finish in time."
        case .recognitionFailed: return "Speech recognition failed."
        }
    }
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
    /// Silence after speech that ends a turn.
    public static let silenceSeconds: TimeInterval = 2.5
    /// Hard limit for one captured turn.
    public static let captureLimitSeconds: TimeInterval = 60
    @Published public var serverURL: String {
        didSet { defaults.set(serverURL, forKey: Self.urlDefaultsKey) }
    }
    @Published public private(set) var state: State = .disconnected
    @Published public private(set) var isFinalizing = false
    /// True from Start conversation until End conversation, a capture failure or disconnect.
    @Published public private(set) var isConversationActive = false
    /// True while permissions and the speech model are being prepared.
    @Published public private(set) var isPreparing = false
    /// Latest user-visible error. Never contains transcript text.
    @Published public private(set) var errorMessage: String?

    private let defaults: UserDefaults
    private let transport: ConversationTransport
    private let recognition: SpeechCapture
    private let timer: CaptureTimer
    private let silenceTimer: CaptureTimer
    private let player: ConversationPlayer
    private let log: (String) -> Void
    private var connectionID = UUID()
    private var captureID: UUID?
    private var receiver: Task<Void, Never>?
    private var playback: Task<Void, Never>?
    private var response = ResponseAccumulator()

    public init(defaults: UserDefaults = .standard, transport: ConversationTransport,
                recognition: SpeechCapture, timer: CaptureTimer, silenceTimer: CaptureTimer,
                player: ConversationPlayer,
                log: @escaping (String) -> Void = { _ in }) {
        self.defaults = defaults
        self.transport = transport
        self.recognition = recognition
        self.timer = timer
        self.silenceTimer = silenceTimer
        self.player = player
        self.log = log
        serverURL = defaults.string(forKey: Self.urlDefaultsKey) ?? Self.exampleURL
        transport.onDisconnect = { [weak self] in self?.disconnect() }
    }

    public var statusText: String {
        switch state {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting"
        case .ready: return isConversationActive ? "Starting to listen" : "Connected"
        case .recording: return isPreparing ? "Preparing speech recognition" : (isFinalizing ? "Finishing" : "Listening")
        case .waiting: return "Waiting for reply"
        case .playing: return "Playing reply"
        }
    }

    public func connect() async {
        guard state == .disconnected else { return }
        errorMessage = nil
        let value = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value), ["ws", "wss"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.fragment == nil else {
            log("Invalid WebSocket URL")
            errorMessage = "Enter a valid ws:// or wss:// URL."
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
            errorMessage = "Could not connect to the server."
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
        isPreparing = false
        isConversationActive = false
        state = .disconnected
        timer.cancel()
        silenceTimer.cancel()
        recognition.cancel()
        player.stop()
        transport.disconnect()
    }

    /// Starts the hands-free conversation. The connection must be Ready.
    public func startConversation() async {
        guard state == .ready, !isConversationActive else { return }
        errorMessage = nil
        isConversationActive = true
        await startCapture()
    }

    /// Ends the conversation. Capture and playback are cancelled. The
    /// connection stays open unless a reply is still being buffered: the
    /// protocol cannot cancel a turn, so that case closes the connection.
    public func endConversation() {
        guard isConversationActive else { return }
        isConversationActive = false
        if state == .waiting {
            disconnect()
            return
        }
        captureID = nil
        isFinalizing = false
        isPreparing = false
        timer.cancel()
        silenceTimer.cancel()
        recognition.cancel()
        playback?.cancel()
        playback = nil
        player.stop()
        if state == .recording || state == .playing { state = .ready }
    }

    /// Begins one listening turn. Used by the conversation loop; not exposed in the UI.
    public func startCapture() async {
        guard state == .ready else { return }
        let id = UUID()
        captureID = id
        state = .recording
        // Permissions and model preparation can suspend. Do not allow submit
        // until startup finishes.
        isFinalizing = true
        isPreparing = true
        do {
            try await recognition.start(onSpeech: { [weak self] in
                guard let self, self.captureID == id else { return }
                self.speechDetected(capture: id)
            }, onFailure: { [weak self] in
                guard let self, self.captureID == id else { return }
                self.captureFailed(nil)
            })
            guard captureID == id else { return }
            isFinalizing = false
            isPreparing = false
            timer.schedule(after: Self.captureLimitSeconds) { [weak self] in
                Task { @MainActor in
                    guard let self, self.captureID == id else { return }
                    await self.submitCapture()
                }
            }
        } catch {
            guard captureID == id else { return }
            captureFailed(error)
        }
    }

    // Each transcript change restarts the silence countdown, so it only runs
    // after speech has been heard.
    private func speechDetected(capture id: UUID) {
        guard state == .recording, !isFinalizing else { return }
        silenceTimer.schedule(after: Self.silenceSeconds) { [weak self] in
            Task { @MainActor in
                guard let self, self.captureID == id else { return }
                await self.submitCapture()
            }
        }
    }

    private func captureFailed(_ error: Error?) {
        log("Speech permission or recognition failed")
        errorMessage = (error as? SpeechCaptureError)?.message ?? SpeechCaptureError.recognitionFailed.message
        // A failing recognizer must not retry in a loop.
        isConversationActive = false
        captureID = nil
        isFinalizing = false
        isPreparing = false
        timer.cancel()
        silenceTimer.cancel()
        recognition.cancel()
        state = .ready
    }

    private func resumeListeningIfActive() async {
        if isConversationActive, state == .ready { await startCapture() }
    }

    public func submitCapture() async {
        guard state == .recording, !isFinalizing, let id = captureID else { return }
        isFinalizing = true
        timer.cancel()
        silenceTimer.cancel()
        let text: String
        do {
            text = try await recognition.finish().trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            guard captureID == id else { return }
            captureFailed(error)
            return
        }
        guard captureID == id else { return }
        captureID = nil
        isFinalizing = false
        recognition.cancel()
        guard !text.isEmpty else {
            // Nothing was said before the limit: keep listening.
            state = .ready
            await resumeListeningIfActive()
            return
        }
        guard text.utf8.count <= 4096 else {
            log("Recognized text exceeds 4096 UTF-8 bytes")
            errorMessage = "That was too long to send. Try a shorter turn."
            state = .ready
            await resumeListeningIfActive()
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
                errorMessage = "That was too long to send. Try a shorter turn."
                state = .ready
                await resumeListeningIfActive()
                return
            }
            state = .waiting
            try await transport.send(text: String(decoding: data, as: UTF8.self))
        } catch {
            guard connectionID == connection else { return }
            log("WebSocket send failed")
            errorMessage = "Sending to the server failed."
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
                                // Automatic listening: resume right after the complete reply.
                                await self.resumeListeningIfActive()
                            } catch {
                                guard let self, self.connectionID == connection, !Task.isCancelled else { return }
                                self.log("Audio playback failed")
                                self.errorMessage = "Audio playback failed."
                                self.disconnect()
                            }
                        }
                    }
                }
            } catch {
                guard let self, self.connectionID == connection, !Task.isCancelled else { return }
                self.log("WebSocket receive or response validation failed")
                self.errorMessage = "The connection to the server failed."
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
