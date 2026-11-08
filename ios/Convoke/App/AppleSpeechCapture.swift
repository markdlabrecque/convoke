import AVFoundation
import ConvokeCore
import Speech

@MainActor
final class AppleSpeechCapture: SpeechCapture {
    private enum CaptureError: Error { case permissionDenied, unavailable, noFinalResult }
    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var finalText: String?
    private(set) var isFinishing = false
    private let finalResultTimeout: UInt64
    private var completion: CheckedContinuation<String, Error>?
    private var finalDeadline: Task<Void, Never>?
    private var failure: (() -> Void)?
    private var operation = UUID()
    private var hasTap = false

    init(finalResultTimeout: UInt64 = 5_000_000_000) {
        self.finalResultTimeout = finalResultTimeout
    }

    func start(onFailure: @escaping () -> Void) async throws {
        cancel()
        let id = operation
        let speechAllowed = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard operation == id else { throw CancellationError() }
        guard speechAllowed else { throw CaptureError.permissionDenied }
        let microphoneAllowed = await AVCaptureDevice.requestAccess(for: .audio)
        guard operation == id else { throw CancellationError() }
        guard microphoneAllowed else { throw CaptureError.permissionDenied }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            throw CaptureError.unavailable
        }
        self.recognizer = recognizer
        failure = onFailure
        do {
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true)
            #endif
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = false
            self.request = request
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw CaptureError.unavailable
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            hasTap = true
            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let final = result?.isFinal == true ? result?.bestTranscription.formattedString : nil
                let failed = error != nil
                Task { @MainActor in
                    guard let self, self.operation == id else { return }
                    self.processRecognitionResult(final: final, failed: failed) { self.failure?() }
                }
            }
            engine.prepare()
            try engine.start()
        } catch {
            cancel()
            throw error
        }
    }

    // Kept separate from Apple's callback so terminal-result ordering can be
    // tested without requesting permissions or opening the microphone.
    func processRecognitionResult(final: String?, failed: Bool, onFailure: () -> Void) {
        if let final, isFinishing {
            finalText = final
            stopAudio()
            resolve(.success(final))
        } else if finalText == nil, final != nil || failed {
            // A final before Submit means Apple ended capture prematurely.
            // Discard it instead of silently leaving the UI in Recording.
            stopAudio()
            resolve(.failure(CaptureError.noFinalResult))
            onFailure()
        }
    }

    func finish() async throws -> String {
        if let finalText { return finalText }
        guard request != nil else { throw CaptureError.unavailable }
        isFinishing = true
        stopAudio()
        request?.endAudio()
        return try await waitForFinalResult()
    }

    // Also exercises the real finalization continuation without starting audio.
    func waitForFinalResult() async throws -> String {
        isFinishing = true
        return try await withCheckedThrowingContinuation { continuation in
            completion = continuation
            // Do not submit a partial transcript if Apple never supplies a final.
            let timeout = finalResultTimeout
            finalDeadline = Task { @MainActor [weak self] in
                do { try await Task.sleep(nanoseconds: timeout) }
                catch { return }
                self?.resolve(.failure(CaptureError.noFinalResult))
            }
        }
    }

    func cancel() {
        operation = UUID()
        failure = nil
        stopAudio()
        request?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        request = nil
        recognizer = nil
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
