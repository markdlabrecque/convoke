import AVFoundation
import ConvokeCore
import Speech

/// On-device capture with SpeechAnalyzer and SpeechTranscriber (iOS 26+).
/// Audio never leaves the device. Silence and the 60-second limit are decided
/// by `SessionController`; this adapter reports speech activity, then
/// finalizes within a deadline and never substitutes partial text.
@available(iOS 26.0, macOS 26.0, *)
@MainActor
final class AppleSpeechCapture: SpeechCapture {
    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var finalization: Task<Void, Never>?
    private var finalizedSegments: [String] = []
    private var volatileText = ""
    private var finalText: String?
    private(set) var isFinishing = false
    private let finalResultTimeout: UInt64
    private var completion: CheckedContinuation<String, Error>?
    private var finalDeadline: Task<Void, Never>?
    private var operation = UUID()
    private var hasTap = false

    init(finalResultTimeout: UInt64 = 5_000_000_000) {
        self.finalResultTimeout = finalResultTimeout
    }

    func start(onSpeech: @escaping () -> Void, onFailure: @escaping () -> Void) async throws {
        cancel()
        let id = operation
        let microphoneAllowed = await AVCaptureDevice.requestAccess(for: .audio)
        guard operation == id else { throw CancellationError() }
        guard microphoneAllowed else { throw SpeechCaptureError.microphoneDenied }
        guard SpeechTranscriber.isAvailable else { throw SpeechCaptureError.modelUnavailable }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) else {
            throw SpeechCaptureError.unsupportedLocale
        }
        guard operation == id else { throw CancellationError() }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [],
                                            reportingOptions: [.volatileResults], attributeOptions: [])
        // The speech model may need a one-time download. The controller shows
        // "Preparing speech recognition" until this finishes.
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        } catch {
            guard operation == id else { throw CancellationError() }
            throw SpeechCaptureError.modelPreparationFailed
        }
        guard operation == id else { throw CancellationError() }
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw SpeechCaptureError.modelUnavailable
        }
        guard operation == id else { throw CancellationError() }
        do {
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            #endif
            let input = engine.inputNode
            let microphoneFormat = input.outputFormat(forBus: 0)
            guard microphoneFormat.sampleRate > 0, microphoneFormat.channelCount > 0,
                  let converter = AVAudioConverter(from: microphoneFormat, to: analyzerFormat) else {
                throw SpeechCaptureError.unavailable
            }
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            self.analyzer = analyzer
            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            inputContinuation = continuation
            resultsTask = Task { @MainActor [weak self] in
                var failed = false
                do {
                    for try await result in transcriber.results {
                        let text = String(result.text.characters)
                        guard let self, self.operation == id else { return }
                        self.processResult(text: text, isFinal: result.isFinal, onSpeech: onSpeech)
                    }
                } catch {
                    failed = true
                }
                guard let self, self.operation == id else { return }
                self.processCompletion(failed: failed, onFailure: onFailure)
            }
            try await analyzer.start(inputSequence: stream)
            guard operation == id else { throw CancellationError() }
            input.installTap(onBus: 0, bufferSize: 4096, format: microphoneFormat,
                             block: Self.makeTap(converter: converter, format: analyzerFormat,
                                                 continuation: continuation))
            hasTap = true
            engine.prepare()
            try engine.start()
        } catch {
            let cancelled = operation != id
            cancel()
            if cancelled || error is CancellationError { throw CancellationError() }
            throw (error as? SpeechCaptureError) ?? SpeechCaptureError.unavailable
        }
    }

    // The tap runs on the audio thread, so it is built outside main-actor
    // isolation and only touches the converter and the input stream.
    nonisolated private static func makeTap(
        converter: AVAudioConverter, format: AVAudioFormat,
        continuation: AsyncStream<AnalyzerInput>.Continuation
    ) -> (AVAudioPCMBuffer, AVAudioTime) -> Void {
        return { buffer, _ in
            guard let converted = convert(buffer, using: converter, to: format) else { return }
            continuation.yield(AnalyzerInput(buffer: converted))
        }
    }

    nonisolated private static func convert(
        _ buffer: AVAudioPCMBuffer, using converter: AVAudioConverter, to format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil, output.frameLength > 0 else { return nil }
        return output
    }

    // Kept separate from Apple's result stream so ordering can be tested
    // without permissions, speech models, or a microphone.
    func processResult(text: String, isFinal: Bool, onSpeech: () -> Void) {
        let hadVolatile = !volatileText.isEmpty
        let previous = volatileText
        if isFinal {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { finalizedSegments.append(trimmed) }
            volatileText = ""
        } else {
            volatileText = text
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // A final that merely confirms the last volatile text is not new
        // speech, so it must not extend the silence countdown.
        if isFinal ? !hadVolatile : text != previous { onSpeech() }
    }

    // Called when the result stream ends. Only finalized segments count.
    func processCompletion(failed: Bool, onFailure: () -> Void) {
        if isFinishing {
            guard finalText == nil else { return }
            if failed {
                resolve(.failure(SpeechCaptureError.recognitionFailed))
            } else {
                let text = finalizedSegments.joined(separator: " ")
                finalText = text
                resolve(.success(text))
            }
        } else if finalText == nil {
            // The stream ended before the controller asked to finish. Discard
            // the turn instead of silently leaving the UI in Listening.
            stopAudio()
            resolve(.failure(SpeechCaptureError.recognitionFailed))
            onFailure()
        }
    }

    func finish() async throws -> String {
        if let finalText { return finalText }
        guard let analyzer else { throw SpeechCaptureError.unavailable }
        isFinishing = true
        stopAudio()
        inputContinuation?.finish()
        inputContinuation = nil
        let id = operation
        finalization = Task { @MainActor [weak self] in
            do {
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            } catch {
                guard let self, self.operation == id else { return }
                self.processCompletion(failed: true, onFailure: {})
            }
        }
        return try await waitForFinalResult()
    }

    // Also exercises the real finalization continuation without starting audio.
    func waitForFinalResult() async throws -> String {
        isFinishing = true
        if let finalText { return finalText }
        return try await withCheckedThrowingContinuation { continuation in
            completion = continuation
            // Do not submit a partial transcript if Apple never supplies a final.
            let timeout = finalResultTimeout
            finalDeadline = Task { @MainActor [weak self] in
                do { try await Task.sleep(nanoseconds: timeout) }
                catch { return }
                self?.resolve(.failure(SpeechCaptureError.noFinalResult))
            }
        }
    }

    func cancel() {
        operation = UUID()
        stopAudio()
        inputContinuation?.finish()
        inputContinuation = nil
        resultsTask?.cancel()
        resultsTask = nil
        finalization?.cancel()
        finalization = nil
        if let analyzer {
            Task { await analyzer.cancelAndFinishNow() }
        }
        analyzer = nil
        finalizedSegments = []
        volatileText = ""
        finalText = nil
        isFinishing = false
        resolve(.failure(CancellationError()))
    }

    private func resolve(_ result: Result<String, Error>) {
        finalDeadline?.cancel()
        finalDeadline = nil
        let continuation = completion
        completion = nil
        continuation?.resume(with: result)
    }

    private func stopAudio() {
        engine.stop()
        if hasTap {
            engine.inputNode.removeTap(onBus: 0)
            hasTap = false
        }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}
