import AsyncHTTPClient
import Vapor
import Foundation
import Logging

/// Turns reply text into headerless 24 kHz mono signed 16-bit little-endian PCM.
/// The Kokoro implementation plugs in here.
protocol SpeechSynthesizer {
    @MainActor func synthesize(_ text: String) async throws -> Data
    /// PCM in pieces of any size, pulled by the consumer as it sends them. Synthesizers that
    /// can only produce a whole reply inherit the default, which yields it as one piece.
    @MainActor func stream(_ text: String) async throws -> AsyncThrowingStream<Data, Error>
}

extension SpeechSynthesizer {
    @MainActor func stream(_ text: String) async throws -> AsyncThrowingStream<Data, Error> {
        try SpeechAudio.wholeReply(try await synthesize(text))
    }
}

enum SpeechAudio {
    /// A finished reply as a one-piece stream. Validated first, so a bad reply fails before any audio is sent.
    static func wholeReply(_ audio: Data) throws -> AsyncThrowingStream<Data, Error> {
        try ConversationProtocol.validateAudio(audio)
        return AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(audio)
            continuation.finish()
        }
    }

    static func stream(wrapping synthesize: @escaping Conversation.Synthesize) -> Conversation.SynthesizeStream {
        { text in try wholeReply(try await synthesize(text)) }
    }
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

/// Kokoro when `CONVOKE_KOKORO_URL` is set, on every platform; otherwise the platform voice.
@MainActor func makeSpeechSynthesizer(kokoro: KokoroConfig?, client: any Client, http: HTTPClient) -> any SpeechSynthesizer {
    if let kokoro { return KokoroSpeechSynthesizer(client: client, config: kokoro, http: http) }
    return makePlatformSpeechSynthesizer()
}
