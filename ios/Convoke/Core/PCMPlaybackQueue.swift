import Foundation

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
