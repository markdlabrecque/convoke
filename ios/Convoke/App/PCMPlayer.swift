import AVFoundation
import ConvokeCore

@MainActor
final class PCMPlayer: ConversationPlayer {
    private var engine: AVAudioEngine?
    private var node: AVAudioPlayerNode?
    private var completion: CheckedContinuation<Void, Error>?
    private var observations: [NSObjectProtocol] = []
    private var playbackID = UUID()

    func play(pcm: Data) async throws {
        stop()
        let buffer = try Self.makeBuffer(pcm: pcm)
        let format = buffer.format
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
        observations.append(NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard self?.playbackID == id else { return }
                self?.stop()
            }
        })
        #if os(iOS)
        observations.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard self?.playbackID == id else { return }
                self?.stop()
            }
        })
        #endif
        do {
            try engine.start()
            try await withCheckedThrowingContinuation { continuation in
                completion = continuation
                node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.playbackID == id else { return }
                        let completed = self.completion
                        self.completion = nil
                        self.stop()
                        completed?.resume()
                    }
                }
                node.play()
            }
        } catch {
            if playbackID == id { stop() }
            throw error
        }
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

    func stop() {
        playbackID = UUID()
        for observation in observations { NotificationCenter.default.removeObserver(observation) }
        observations.removeAll()
        node?.stop()
        engine?.stop()
        node = nil
        engine = nil
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        let pending = completion
        completion = nil
        pending?.resume(throwing: CancellationError())
    }
}
