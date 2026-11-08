import AVFoundation
import Foundation

@MainActor
final class MacSpeechSynthesizer: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private let accumulator = SpeechAudioAccumulator()
    private var continuation: CheckedContinuation<Data, Error>?

    func synthesize(_ text: String) async throws -> Data {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                synthesizer.delegate = self
                // Leaving voice unset uses the system's default voice.
                let utterance = AVSpeechUtterance(string: text)
                let accumulator = self.accumulator
                synthesizer.write(utterance) { buffer in
                    // Consume before returning: AVFoundation owns the buffer.
                    // Only the final, capped PCM data crosses to the main actor.
                    do {
                        if let audio = try accumulator.consume(buffer) {
                            Task { @MainActor in self.finish(.success(audio)) }
                        }
                    } catch {
                        Task { @MainActor in self.finish(.failure(error)) }
                    }
                }
            }
        } onCancel: {
            Task { @MainActor in self.finish(.failure(CancellationError())) }
        }
    }

    private func finish(_ result: Result<Data, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        accumulator.cancel()
        synthesizer.stopSpeaking(at: .immediate)
        continuation.resume(with: result)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finish(.failure(ConversationError.synthesisFailed)) }
    }
}

// AVFoundation invokes the writer on its own queue. Serialize conversion and
// cancellation, and enforce the cap before appending, not after synthesis ends.
final class SpeechAudioAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private var audio = Data()
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: true
    )!

    func consume(_ buffer: AVAudioBuffer) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return nil }
        do {
            guard let pcm = buffer as? AVAudioPCMBuffer else { throw ConversationError.synthesisFailed }
            if pcm.frameLength == 0 {
                try flushConverter()
                try ConversationProtocol.validateAudio(audio)
                finished = true
                let result = audio
                audio = Data()
                converter = nil
                return result
            }
            if converter == nil {
                sourceFormat = pcm.format
                converter = AVAudioConverter(from: pcm.format, to: targetFormat)
            }
            guard let converter, pcm.format == sourceFormat else { throw ConversationError.synthesisFailed }
            var supplied = false
            while true {
                let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: 4096)!
                var error: NSError?
                let status = converter.convert(to: output, error: &error) { _, inputStatus in
                    if supplied {
                        inputStatus.pointee = .noDataNow
                        return nil
                    }
                    supplied = true
                    inputStatus.pointee = .haveData
                    return pcm
                }
                guard error == nil, status != .error else { throw ConversationError.synthesisFailed }
                try append(output)
                if status == .inputRanDry || status == .endOfStream { break }
                guard output.frameLength > 0 else { throw ConversationError.synthesisFailed }
            }
            return nil
        } catch {
            finished = true
            audio = Data()
            converter = nil
            throw error
        }
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        finished = true
        audio = Data()
        converter = nil
    }

    private func flushConverter() throws {
        guard let converter else { throw ConversationError.synthesisFailed }
        while true {
            let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: 4096)!
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, inputStatus in
                inputStatus.pointee = .endOfStream
                return nil
            }
            guard error == nil, status != .error else { throw ConversationError.synthesisFailed }
            try append(output)
            if status == .endOfStream { return }
            guard output.frameLength > 0 else { throw ConversationError.synthesisFailed }
        }
    }

    private func append(_ buffer: AVAudioPCMBuffer) throws {
        let bytes = Int(buffer.frameLength) * 2
        guard bytes <= ConversationProtocol.maxAudioBytes - audio.count else { throw ConversationError.audioLimit }
        if bytes > 0 {
            guard let samples = buffer.int16ChannelData?[0] else { throw ConversationError.synthesisFailed }
            // Supported macOS architectures are little-endian.
            audio.append(contentsOf: UnsafeRawBufferPointer(start: samples, count: bytes))
        }
    }
}
