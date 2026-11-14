import Foundation

/// Hardware-free stream identity and exactly-once completion. The adapter must
/// settle this before stopping its engine, since stop may deliver old callbacks.
@MainActor
public final class PCMPlaybackLifetime {
    public private(set) var id: UUID?
    private var result: Result<Void, Error>?
    private var waiter: CheckedContinuation<Void, Error>?
    private var onStarted: (() -> Void)?
    private var onFailure: (() -> Void)?

    public init() {}

    @discardableResult
    public func begin(onStarted: @escaping () -> Void, onFailure: @escaping () -> Void) -> UUID {
        stop()
        let id = UUID()
        self.id = id
        result = nil
        self.onStarted = onStarted
        self.onFailure = onFailure
        return id
    }

    public func started(_ id: UUID) {
        guard self.id == id else { return }
        let callback = onStarted
        onStarted = nil
        callback?()
    }

    public func check() throws {
        if case .failure(let error) = result { throw error }
        guard id != nil else { throw ResponseError.invalid }
    }

    public func wait() async throws {
        if let result { return try result.get() }
        guard id != nil, waiter == nil else { throw ResponseError.invalid }
        try await withCheckedThrowingContinuation { waiter = $0 }
    }

    public func succeed(_ id: UUID) { settle(id, result: .success(()), notifyFailure: false) }
    public func fail(_ id: UUID) { settle(id, result: .failure(ResponseError.invalid), notifyFailure: true) }

    public func stop() {
        if let id { settle(id, result: .failure(CancellationError()), notifyFailure: false) }
    }

    private func settle(_ id: UUID, result: Result<Void, Error>, notifyFailure: Bool) {
        guard self.id == id else { return }
        self.id = nil
        self.result = result
        let pending = waiter
        waiter = nil
        let failure = notifyFailure ? onFailure : nil
        onFailure = nil
        onStarted = nil
        pending?.resume(with: result)
        failure?()
    }
}

/// Counts pending and scheduled-but-unplayed audio in original Int16 PCM bytes.
/// Float32 conversion takes twice this storage. AVAudioPlayerNode releases each
/// scheduled buffer after playback; the adapter must call played(bytes:) then.
/// A drained queue before EOF is an underrun, not completion.
public struct PCMPlaybackQueue {
    public static let limit = 8 * 1024 * 1024
    public static let startupBytes = 9_600
    public private(set) var queuedBytes = 0
    public private(set) var started = false
    public private(set) var ended = false
    public var drained: Bool { ended && queuedBytes == 0 }

    public init() {}

    public mutating func append(bytes: Int) throws {
        guard !ended, bytes > 0, bytes.isMultiple(of: 2),
              bytes <= Self.limit - queuedBytes else { throw ResponseError.invalid }
        queuedBytes += bytes
        if queuedBytes >= Self.startupBytes { started = true }
    }

    public mutating func finish() throws {
        guard !ended else { throw ResponseError.invalid }
        ended = true
        if queuedBytes > 0 { started = true }
    }

    public mutating func played(bytes: Int) {
        precondition(bytes > 0 && bytes <= queuedBytes && bytes.isMultiple(of: 2))
        queuedBytes -= bytes
    }
}
