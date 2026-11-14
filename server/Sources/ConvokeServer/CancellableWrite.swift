import NIOCore

/// A socket write may remain suspended under backpressure. Cancellation releases the
/// synthesis task immediately, so its HTTP body iterator is destroyed and AHC cancels
/// the real request, rather than waiting for the socket's close-handshake deadline.
final class CancellableWrite: @unchecked Sendable {
    private let loop: any EventLoop
    private let promise: EventLoopPromise<Void>
    private var settled = false // event-loop confined

    private init(on loop: any EventLoop) {
        self.loop = loop
        self.promise = loop.makePromise(of: Void.self)
    }

    private func finish(_ result: Result<Void, Error>) {
        loop.preconditionInEventLoop()
        guard !settled else { return }
        settled = true
        promise.completeWith(result)
    }

    static func run(
        on loop: any EventLoop,
        start: @escaping @Sendable () -> EventLoopFuture<Void>
    ) async throws {
        let waiter = CancellableWrite(on: loop)
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            loop.execute {
                guard !waiter.settled else { return }
                start().whenComplete { waiter.finish($0) }
            }
            try await waiter.promise.futureResult.get()
        } onCancel: {
            loop.execute { waiter.finish(.failure(CancellationError())) }
        }
    }
}
