import Foundation
import Logging

/// Turns reply text into headerless 24 kHz mono signed 16-bit little-endian PCM.
/// The Kokoro implementation plugs in here.
protocol SpeechSynthesizer {
    @MainActor func synthesize(_ text: String) async throws -> Data
}

/// Used where no synthesizer exists. Fails every turn loudly, never silently.
struct UnavailableSpeechSynthesizer: SpeechSynthesizer {
    private let logger = Logger(label: "convoke.speech")

    @MainActor func synthesize(_ text: String) async throws -> Data {
        logger.error("No speech synthesizer is available on this platform; closing the turn without audio.")
        throw ConversationError.noSynthesizer
    }
}

@MainActor func makePlatformSpeechSynthesizer() -> any SpeechSynthesizer {
    #if canImport(AVFoundation)
    return MacSpeechSynthesizer()
    #else
    return UnavailableSpeechSynthesizer()
    #endif
}
