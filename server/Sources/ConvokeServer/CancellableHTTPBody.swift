import AsyncHTTPClient
import NIOCore
import NIOHTTP1

/// Owns the actual AHC request, independently of Swift async-iterator lifetimes.
/// One delegate body part is outstanding at a time: its acknowledgement is released
/// only by the next pull, after the caller has finished its downstream write.
final class CancellableHTTPBody: AsyncSequence, @unchecked Sendable {
    typealias Element = ByteBuffer
    private let delegate: BodyDelegate
    private let task: HTTPClient.Task<Void>

    init(http: HTTPClient, request: HTTPClient.Request) {
        let loop = http.eventLoopGroup.next()
        delegate = BodyDelegate(loop: loop)
        task = http.execute(request: request, delegate: delegate,
                            eventLoop: .delegate(on: loop), deadline: .now() + .seconds(120))
    }

    func waitForHead() async throws {
        try await withTaskCancellationHandler {
            try await delegate.head.futureResult.get()
        } onCancel: {
            self.cancel()
        }
    }

    func cancel() { task.cancel() }
    deinit { task.cancel() }

    struct AsyncIterator: AsyncIteratorProtocol {
        let body: CancellableHTTPBody
        mutating func next() async throws -> ByteBuffer? {
            try await body.next()
        }
    }

    func makeAsyncIterator() -> AsyncIterator { AsyncIterator(body: self) }

    private func next() async throws -> ByteBuffer? {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                delegate.loop.execute { self.delegate.pull(continuation) }
            }
        } onCancel: {
            self.cancel()
        }
    }
}

/// All mutable state is confined to the explicitly selected delegate event loop.
/// AHC documents that didReceiveError may interrupt a backpressured body callback.
private final class BodyDelegate: HTTPClientResponseDelegate, @unchecked Sendable {
    typealias Response = Void
    let loop: any EventLoop
    let head: EventLoopPromise<Void>
    private var receivedHead = false
    private var terminal: Result<Void, Error>?
    private var waiting: CheckedContinuation<ByteBuffer?, Error>?
    private var buffered: ByteBuffer?
    private var acknowledgement: EventLoopPromise<Void>?

    init(loop: any EventLoop) {
        self.loop = loop
        head = loop.makePromise(of: Void.self)
    }

    func didReceiveHead(task: HTTPClient.Task<Void>, _ response: HTTPResponseHead) -> EventLoopFuture<Void> {
        loop.assertInEventLoop()
        let result: Result<Void, Error>
        if response.status != .ok {
            result = .failure(SpeechError.http(status: response.status.code))
        } else {
            let type = response.headers.first(name: "content-type")?.lowercased()
                .split(separator: ";").first.map(String.init) ?? "none"
            result = ["audio/pcm", "audio/l16", "audio/x-pcm"].contains(type)
                ? .success(()) : .failure(SpeechError.badResponse("content type is not raw PCM"))
        }
        receivedHead = true
        head.completeWith(result)
        switch result {
        case .success: return loop.makeSucceededVoidFuture()
        case .failure(let error): return loop.makeFailedFuture(error)
        }
    }

    func didReceiveBodyPart(task: HTTPClient.Task<Void>, _ buffer: ByteBuffer) -> EventLoopFuture<Void> {
        loop.assertInEventLoop()
        precondition(acknowledgement == nil && buffered == nil)
        let promise = loop.makePromise(of: Void.self)
        acknowledgement = promise
        if let waiting {
            self.waiting = nil
            waiting.resume(returning: buffer)
        } else {
            buffered = buffer
        }
        return promise.futureResult
    }

    func pull(_ continuation: CheckedContinuation<ByteBuffer?, Error>) {
        loop.assertInEventLoop()
        precondition(waiting == nil, "Only one PCM consumer is supported")
        // Preserve a body part already received before an HTTP framing error. The
        // consumer observes that partial PCM, then the error on its following pull.
        if let buffered {
            self.buffered = nil
            continuation.resume(returning: buffered)
        } else if let terminal {
            continuation.resume(with: terminal.map { nil })
        } else {
            waiting = continuation
            let previous = acknowledgement
            acknowledgement = nil
            previous?.succeed(())
        }
    }

    func didReceiveError(task: HTTPClient.Task<Void>, _ error: Error) {
        finish(.failure(error))
    }

    func didFinishRequest(task: HTTPClient.Task<Void>) throws {
        finish(.success(()))
    }

    private func finish(_ result: Result<Void, Error>) {
        loop.assertInEventLoop()
        guard terminal == nil else { return }
        terminal = result
        if !receivedHead { head.completeWith(result) }
        let waiting = self.waiting
        self.waiting = nil
        let acknowledgement = self.acknowledgement
        self.acknowledgement = nil
        // Cancellation must also release the delegate's backpressure future.
        acknowledgement?.completeWith(result)
        waiting?.resume(with: result.map { nil })
    }
}
