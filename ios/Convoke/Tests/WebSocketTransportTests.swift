#if os(macOS)
import CryptoKit
import Network
import XCTest
@testable import ConvokeCore

@MainActor
final class WebSocketTransportTests: XCTestCase {
    func testRemoteCloseWithoutReceiveDiscardsRecording() async throws {
        let server = LocalWebSocketServer(mode: .close)
        let url = try await server.start()
        defer { server.stop() }
        let transport = WebSocketTransport(heartbeatInterval: 50_000_000, heartbeatTimeout: 200_000_000)
        let speech = TransportTestSpeech()
        let timer = TransportTestTimer()
        let name = "ConvokeTransportTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let controller = SessionController(defaults: defaults, transport: transport,
                                           recognition: speech, timer: timer, player: TransportTestPlayer())
        controller.serverURL = url.absoluteString
        await controller.connect()
        XCTAssertEqual(controller.state, .ready)
        await controller.startCapture()
        XCTAssertEqual(controller.state, .recording)
        let disconnected = expectation(description: "Remote close stops capture without receive")
        transport.onDisconnect = { controller.disconnect(); disconnected.fulfill() }
        await fulfillment(of: [disconnected], timeout: 3)
        XCTAssertEqual(controller.state, .disconnected)
        XCTAssertEqual(speech.cancels, 1)
        XCTAssertTrue(timer.cancelled)
        await controller.submitCapture()
        XCTAssertEqual(speech.finishes, 0)
    }

    func testRawFramesArePreservedAndPendingReceiveIsCancelledOnDisconnect() async throws {
        let server = LocalWebSocketServer(mode: .message)
        let url = try await server.start()
        defer { server.stop() }
        let transport = WebSocketTransport()
        defer { transport.disconnect() }
        try await transport.connect(to: url)
        try await Task.sleep(nanoseconds: 100_000_000)
        let message = try await transport.receive()
        guard case .string(let text) = message else { return XCTFail("Expected unchanged text frame") }
        XCTAssertEqual(text, "held frame")
        let receiving = Task { try await transport.receive() }
        await Task.yield()
        transport.disconnect()
        do {
            _ = try await receiving.value
            XCTFail("Disconnect must end the pending receive")
        } catch {
            // Depending on scheduling, disconnect can precede the receive call.
            XCTAssertTrue(error is CancellationError || error is URLError)
        }
        try await transport.connect(to: url)
        let next = try await transport.receive()
        guard case .string(let nextText) = next else { return XCTFail("Expected new connection's text") }
        XCTAssertEqual(nextText, "held frame")
    }

    func testUnreadRawFrameLimitDisconnectsInsteadOfGrowingWithoutBound() async throws {
        let server = LocalWebSocketServer(mode: .flood)
        let url = try await server.start()
        defer { server.stop() }
        let transport = WebSocketTransport()
        defer { transport.disconnect() }
        let disconnected = expectation(description: "Unread frame queue is bounded")
        transport.onDisconnect = { disconnected.fulfill() }
        try await transport.connect(to: url)
        await fulfillment(of: [disconnected], timeout: 3)
    }

    func testMissingPongTimesOutWithoutReceive() async throws {
        let server = LocalWebSocketServer(mode: .silent)
        let url = try await server.start()
        defer { server.stop() }
        let transport = WebSocketTransport(heartbeatInterval: 20_000_000, heartbeatTimeout: 80_000_000)
        defer { transport.disconnect() }
        let disconnected = expectation(description: "Unresponsive peer is disconnected")
        transport.onDisconnect = { disconnected.fulfill() }
        try await transport.connect(to: url)
        await fulfillment(of: [disconnected], timeout: 3)
    }

    func testOldHeartbeatCannotDisconnectReconnectedSocket() async throws {
        let silent = LocalWebSocketServer(mode: .silent)
        let healthy = LocalWebSocketServer(mode: .pong)
        let oldURL = try await silent.start()
        let newURL = try await healthy.start()
        defer { silent.stop(); healthy.stop() }
        let transport = WebSocketTransport(heartbeatInterval: 1_000_000_000, heartbeatTimeout: 500_000_000)
        defer { transport.disconnect() }
        let noDisconnect = expectation(description: "Cancelled and stale heartbeat callbacks are ignored")
        noDisconnect.isInverted = true
        transport.onDisconnect = { noDisconnect.fulfill() }
        try await transport.connect(to: oldURL)
        // Wait until the old connection has a ping in flight, then replace it.
        try await Task.sleep(nanoseconds: 1_200_000_000)
        transport.disconnect()
        try await transport.connect(to: newURL)
        await fulfillment(of: [noDisconnect], timeout: 3.5)
    }

    func testExplicitDisconnectCancelsHeartbeatDeadline() async throws {
        let server = LocalWebSocketServer(mode: .silent)
        let url = try await server.start()
        defer { server.stop() }
        let transport = WebSocketTransport(heartbeatInterval: 20_000_000, heartbeatTimeout: 150_000_000)
        let noDisconnect = expectation(description: "Local disconnect does not notify again")
        noDisconnect.isInverted = true
        transport.onDisconnect = { noDisconnect.fulfill() }
        try await transport.connect(to: url)
        try await Task.sleep(nanoseconds: 80_000_000)
        transport.disconnect()
        await fulfillment(of: [noDisconnect], timeout: 0.3)
    }
}

// A loopback-only WebSocket peer. It exchanges control frames, not conversation
// messages, and needs no external process, dependency, or development server.
private final class LocalWebSocketServer: @unchecked Sendable {
    enum Mode { case close, silent, pong, message, flood }
    private let mode: Mode
    private let queue = DispatchQueue(label: "ConvokeTests.websocket")
    private var listener: NWListener?
    private var startResolved = false
    private var connections: [NWConnection] = []

    init(mode: Mode) { self.mode = mode }

    func start() async throws -> URL {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                guard let self, !self.startResolved else { return }
                switch state {
                case .ready:
                    self.startResolved = true
                    continuation.resume(returning: URL(string: "ws://127.0.0.1:\(self.listener!.port!.rawValue)/conversation")!)
                case .failed(let error):
                    self.startResolved = true
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                self.connections.append(connection)
                connection.start(queue: self.queue)
                self.handshake(connection, buffered: Data())
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        queue.sync {
            listener?.cancel()
            listener?.stateUpdateHandler = nil
            listener?.newConnectionHandler = nil
            connections.forEach { $0.cancel() }
            connections.removeAll()
        }
    }

    private func handshake(_ connection: NWConnection, buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, ended, error in
            guard let self, error == nil, !ended, let data else { return }
            let bytes = buffered + data
            guard let request = String(data: bytes, encoding: .utf8), request.contains("\r\n\r\n") else {
                self.handshake(connection, buffered: bytes)
                return
            }
            guard let line = request.components(separatedBy: "\r\n").first(where: {
                $0.lowercased().hasPrefix("sec-websocket-key:")
            }) else { return }
            let key = line.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)
            let digest = Insecure.SHA1.hash(data: Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8))
            let accept = Data(digest).base64EncodedString()
            let response = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: \(accept)\r\n\r\n"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in })
            if self.mode == .close {
                self.queue.asyncAfter(deadline: .now() + 0.15) {
                    connection.send(content: Data([0x88, 0x02, 0x03, 0xe8]), completion: .contentProcessed { _ in })
                }
            } else {
                if self.mode == .message {
                    let text = Array("held frame".utf8)
                    connection.send(content: Data([0x81, UInt8(text.count)] + text), completion: .contentProcessed { _ in })
                } else if self.mode == .flood {
                    let frames = Data(Array(repeating: [UInt8(0x81), 0], count: 1025).flatMap { $0 })
                    connection.send(content: frames, completion: .contentProcessed { _ in })
                }
                self.controlFrames(connection, buffered: Data())
            }
        }
    }

    private func controlFrames(_ connection: NWConnection, buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, ended, error in
            guard let self, error == nil, !ended, let data else { return }
            var bytes = [UInt8](buffered + data)
            while bytes.count >= 2 {
                let length = Int(bytes[1] & 0x7f)
                let masked = bytes[1] & 0x80 != 0
                let header = masked ? 6 : 2
                guard length <= 125, bytes.count >= header + length else { break }
                if bytes[0] & 0x0f == 9, self.mode != .silent {
                    var payload = Array(bytes[header..<(header + length)])
                    if masked {
                        for index in payload.indices { payload[index] ^= bytes[2 + index % 4] }
                    }
                    connection.send(content: Data([0x8a, UInt8(length)] + payload), completion: .contentProcessed { _ in })
                }
                bytes.removeFirst(header + length)
            }
            self.controlFrames(connection, buffered: Data(bytes))
        }
    }
}

@MainActor
private final class TransportTestSpeech: SpeechCapture {
    var cancels = 0
    var finishes = 0
    func start(onFailure: @escaping () -> Void) async throws {}
    func finish() async throws -> String { finishes += 1; return "must not send" }
    func cancel() { cancels += 1 }
}

@MainActor
private final class TransportTestTimer: CaptureTimer {
    var cancelled = false
    func schedule(after seconds: TimeInterval, action: @escaping () -> Void) { cancelled = false }
    func cancel() { cancelled = true }
}

@MainActor
private final class TransportTestPlayer: ConversationPlayer {
    func stop() {}
}
#endif
