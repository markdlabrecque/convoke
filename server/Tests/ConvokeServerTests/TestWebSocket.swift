import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if os(Linux)
import NIOPosix
import NIOWebSocket
import WebSocketKit
#endif

/// Real network test client. Ubuntu's libcurl does not support Foundation
/// WebSockets, so Linux uses the existing WebSocketKit dependency instead.
/// Apple tests retain their native URLSession transport. No server behavior is mocked.
final class TestWebSocket: @unchecked Sendable {
    typealias Message = URLSessionWebSocketTask.Message
    typealias CloseCode = URLSessionWebSocketTask.CloseCode
    let originalRequest: URLRequest?

    #if os(Linux)
    private let socket: WebSocket
    private var messages: AsyncThrowingStream<Message, Error>.Iterator

    private init(url: URL, socket: WebSocket, messages: AsyncThrowingStream<Message, Error>.Iterator) {
        self.originalRequest = URLRequest(url: url)
        self.socket = socket
        self.messages = messages
    }

    static func connect(to url: URL) async throws -> TestWebSocket {
        let (stream, feed) = AsyncThrowingStream<Message, Error>.makeStream()
        let socket: WebSocket = try await withCheckedThrowingContinuation { opened in
            WebSocket.connect(to: url.absoluteString, on: MultiThreadedEventLoopGroup.singleton) { socket in
                socket.onText { _, text in feed.yield(.string(text)) }
                socket.onBinary { _, bytes in feed.yield(.data(Data(bytes.readableBytesView))) }
                socket.onClose.whenComplete { result in
                    switch result {
                    case .success: feed.finish(throwing: URLError(.networkConnectionLost))
                    case .failure(let error): feed.finish(throwing: error)
                    }
                }
                opened.resume(returning: socket)
            }.whenFailure { opened.resume(throwing: $0) }
        }
        return TestWebSocket(url: url, socket: socket, messages: stream.makeAsyncIterator())
    }

    var closeCode: CloseCode {
        socket.closeCode.flatMap { CloseCode(rawValue: Int(UInt16(webSocketErrorCode: $0))) } ?? .invalid
    }

    func send(_ message: Message) async throws {
        switch message {
        case .string(let text): try await socket.send(text)
        case .data(let bytes): try await socket.send(raw: bytes, opcode: .binary)
        @unknown default: throw URLError(.unsupportedURL)
        }
    }

    func receive() async throws -> Message {
        guard let message = try await messages.next() else { throw URLError(.networkConnectionLost) }
        return message
    }

    func cancel(with code: CloseCode, reason: Data?) {
        socket.close(code: .init(codeNumber: code.rawValue), promise: nil)
    }

    deinit { socket.close(code: .goingAway, promise: nil) }
    #else
    private let session: URLSession
    private let socket: URLSessionWebSocketTask

    private init(url: URL) {
        originalRequest = URLRequest(url: url)
        session = URLSession(configuration: .ephemeral)
        socket = session.webSocketTask(with: url)
        socket.resume()
    }

    static func connect(to url: URL) async throws -> TestWebSocket { TestWebSocket(url: url) }
    var closeCode: CloseCode { socket.closeCode }
    func send(_ message: Message) async throws { try await socket.send(message) }
    func receive() async throws -> Message { try await socket.receive() }
    func cancel(with code: CloseCode, reason: Data?) { socket.cancel(with: code, reason: reason) }
    deinit { session.invalidateAndCancel() }
    #endif
}
