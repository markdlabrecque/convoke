import AVFoundation
import ConvokeCore

@MainActor
final class PCMPlayer: ConversationPlayer {
    private var engine: AVAudioEngine?
    private var node: AVAudioPlayerNode?
    private var completion: CheckedContinuation<Void, Error>?
    private var observations: [NSObjectProtocol] = []
    private var playbackID = UUID()
    /// Chunks scheduled but not yet played back.
    private var scheduled = 0
    private var ended = false
    private var failure: Error?
    private var streaming = false

    /// Starts the engine so the first enqueued chunk plays at once.
    func beginStream() throws {
        stop()
        let format = try Self.makeBuffer(pcm: Data(count: 2)).format
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)
        #endif
        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        self.engine = engine
        self.node = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        let id = UUID()
        playbackID = id
        streaming = true
        observations.append(NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.interrupted(id) }
        })
        #if os(iOS)
        observations.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.interrupted(id) }
        })
        #endif
        do {
            try engine.start()
            node.play()
        } catch {
            stop()
            throw error
        }
    }

    /// Schedules one chunk behind those already queued. Never waits for playback.
    func enqueue(pcm: Data) throws {
        if let failure { throw failure }
        guard streaming, !ended, let node else { throw ResponseError.invalid }
        let buffer = try Self.makeBuffer(pcm: pcm)
        let id = playbackID
        scheduled += 1
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.chunkPlayed(id) }
        }
    }

    /// Returns after every enqueued chunk has played.
    func endStream() async throws {
        if let failure { throw failure }
        guard streaming, !ended else { throw ResponseError.invalid }
        ended = true
        if scheduled == 0 {
            finishStream()
            return
        }
        try await withCheckedThrowingContinuation { completion = $0 }
    }

    private func chunkPlayed(_ id: UUID) {
        guard playbackID == id, scheduled > 0 else { return }
        scheduled -= 1
        guard ended, scheduled == 0 else { return }
        let completed = completion
        completion = nil
        finishStream()
        completed?.resume()
    }

    // An audio-engine change or session interruption fails the stream: later
    // enqueue and endStream calls throw, and a waiting endStream fails now.
    private func interrupted(_ id: UUID) {
        guard playbackID == id, failure == nil else { return }
        let pending = completion
        completion = nil
        teardown()
        failure = ResponseError.invalid
        pending?.resume(throwing: ResponseError.invalid)
    }

    private func finishStream() {
        teardown()
        streaming = false
    }

    static func makeBuffer(pcm: Data) throws -> AVAudioPCMBuffer {
        guard !pcm.isEmpty, pcm.count.isMultiple(of: 2), pcm.count <= 8 * 1024 * 1024,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24000,
                                         channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(pcm.count / 2)),
              let samples = buffer.floatChannelData?[0] else { throw ResponseError.invalid }
        buffer.frameLength = buffer.frameCapacity
        pcm.withUnsafeBytes { bytes in
            let bytes = bytes.bindMemory(to: UInt8.self)
            for index in 0..<Int(buffer.frameLength) {
                let value = UInt16(bytes[index * 2]) | UInt16(bytes[index * 2 + 1]) << 8
                samples[index] = Float(Int16(bitPattern: value)) / 32768
            }
        }
        return buffer
    }

    /// Discards queued audio. A pending `endStream()` throws `CancellationError`.
    func stop() {
        let pending = completion
        completion = nil
        teardown()
        streaming = false
        failure = nil
        pending?.resume(throwing: CancellationError())
    }

    private func teardown() {
        playbackID = UUID()
        for observation in observations { NotificationCenter.default.removeObserver(observation) }
        observations.removeAll()
        node?.stop()
        engine?.stop()
        node = nil
        engine = nil
        scheduled = 0
        ended = false
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}
