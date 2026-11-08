import ConvokeCore
import Foundation

@MainActor
final class WebSocketTransport: NSObject, ConversationTransport, URLSessionWebSocketDelegate {
    var onDisconnect: (() -> Void)?
    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var opening: CheckedContinuation<Void, Error>?
    private var heartbeat: Task<Void, Never>?
    private var heartbeatDeadline: Task<Void, Never>?
    private var reader: Task<Void, Never>?
    private var incoming: [URLSessionWebSocketTask.Message] = []
    private var incomingBytes = 0
    private var receiving: CheckedContinuation<URLSessionWebSocketTask.Message, Error>?
    private let heartbeatInterval: UInt64
    private let heartbeatTimeout: UInt64

    init(heartbeatInterval: UInt64 = 2_000_000_000, heartbeatTimeout: UInt64 = 5_000_000_000) {
        self.heartbeatInterval = heartbeatInterval
        self.heartbeatTimeout = heartbeatTimeout
        super.init()
    }

    func connect(to url: URL) async throws {
        disconnect()
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.session = session
        let socket = session.webSocketTask(with: url)
        socket.maximumMessageSize = 32768
        self.socket = socket
        try await withCheckedThrowingContinuation { continuation in
            opening = continuation
            socket.resume()
        }
    }

    func send(text: String) async throws {
        guard let socket else { throw URLError(.notConnectedToInternet) }
        try await socket.send(.string(text))
    }

    func disconnect() {
        heartbeat?.cancel()
        heartbeat = nil
        heartbeatDeadline?.cancel()
        heartbeatDeadline = nil
        reader?.cancel()
        reader = nil
        incoming.removeAll()
        incomingBytes = 0
        let receiver = receiving
        receiving = nil
        receiver?.resume(throwing: CancellationError())
        let continuation = opening
        opening = nil
        let oldSocket = socket
        socket = nil
        oldSocket?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()
        session = nil
        continuation?.resume(throwing: CancellationError())
    }

    // The companion receive loop can use this without exposing URLSession to the controller.
    // It must enforce the first-slice message ordering, audio and frame limits.
    func receive() async throws -> URLSessionWebSocketTask.Message {
        guard socket != nil else { throw URLError(.notConnectedToInternet) }
        if !incoming.isEmpty {
            let message = incoming.removeFirst()
            incomingBytes -= byteCount(message)
            return message
        }
        guard receiving == nil else { throw URLError(.resourceUnavailable) }
        return try await withCheckedThrowingContinuation { receiving = $0 }
    }

    private func byteCount(_ message: URLSessionWebSocketTask.Message) -> Int {
        switch message {
        case .string(let text): return text.utf8.count
        case .data(let data): return data.count
        @unknown default: return 32768
        }
    }

    // URLSession processes close/pong frames reliably only with a read pending.
    // Preserve raw application frames for the companion task; do not parse them.
    private func readFrames(_ socket: URLSessionWebSocketTask) {
        reader = Task { @MainActor [weak self] in
            do {
                while !Task.isCancelled {
                    let message = try await socket.receive()
                    guard !Task.isCancelled, let self, self.socket === socket else { return }
                    if let receiver = self.receiving {
                        self.receiving = nil
                        receiver.resume(returning: message)
                    } else {
                        let size = self.byteCount(message)
                        // Bound unread raw frames, including base64 overhead for
                        // the contract's 8 MiB PCM limit. No transcripts persist.
                        guard self.incoming.count < 1024,
                              self.incomingBytes + size <= 16 * 1024 * 1024 else {
                            self.closed(socket)
                            return
                        }
                        self.incoming.append(message)
                        self.incomingBytes += size
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                self?.closed(socket)
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                                didOpenWithProtocol protocol: String?) {
        Task { @MainActor in
            guard self.socket === webSocketTask else { return }
            let continuation = self.opening
            self.opening = nil
            self.readFrames(webSocketTask)
            self.monitor(webSocketTask)
            continuation?.resume()
        }
    }

    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                                didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Task { @MainActor in self.closed(webSocketTask) }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                                didCompleteWithError error: Error?) {
        Task { @MainActor in self.closed(task) }
    }

    // Detect a peer that stops responding even if TCP never reports a close.
    private func monitor(_ socket: URLSessionWebSocketTask) {
        let interval = heartbeatInterval
        let timeout = heartbeatTimeout
        heartbeat = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: interval) }
            catch { return }
            guard !Task.isCancelled, self?.socket === socket else { return }
            self?.heartbeatDeadline = Task { @MainActor [weak self] in
                do { try await Task.sleep(nanoseconds: timeout) }
                catch { return }
                self?.closed(socket)
            }
            // URLSession need not invoke this handler when the socket is
            // cancelled. Do not suspend a continuation waiting for it.
            socket.sendPing { [weak self] error in
                Task { @MainActor in
                    guard let self, self.socket === socket else { return }
                    if error != nil {
                        self.closed(socket)
                    } else {
                        self.heartbeatDeadline?.cancel()
                        self.heartbeatDeadline = nil
                        self.monitor(socket)
                    }
                }
            }
        }
    }

    private func closed(_ task: URLSessionTask) {
        guard socket === task else { return }
        disconnect()
        onDisconnect?()
    }
}
