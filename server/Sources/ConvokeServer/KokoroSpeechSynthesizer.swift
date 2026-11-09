import Foundation
import Vapor

enum SpeechError: Error, CustomStringConvertible {
    case config(String)
    case http(status: UInt)
    case badResponse(String)

    // Status codes and reasons only: never text or audio, so safe to log.
    var description: String {
        switch self {
        case .config(let reason): return "speech configuration: \(reason)"
        case .http(let status): return "Kokoro returned HTTP \(status)"
        case .badResponse(let reason): return "Kokoro sent an unusable response: \(reason)"
        }
    }
}

/// `CONVOKE_KOKORO_URL` is the sidecar's root, for example `http://127.0.0.1:8880`.
/// When it is unset the platform voice is used instead (`nil` here).
struct KokoroConfig: Sendable {
    static let defaultVoice = "af_heart"
    let baseURL: String
    let voice: String

    init?(environment: [String: String]) throws {
        func value(_ name: String) -> String? {
            let trimmed = environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }
        guard let base = value("CONVOKE_KOKORO_URL") else { return nil }
        guard let url = URL(string: base), ["http", "https"].contains(url.scheme), url.host != nil else {
            throw SpeechError.config("CONVOKE_KOKORO_URL must be an http or https URL")
        }
        baseURL = base.hasSuffix("/") ? String(base.dropLast()) : base
        voice = value("CONVOKE_KOKORO_VOICE") ?? Self.defaultVoice
    }
}

/// Kokoro-FastAPI (or any OpenAI-style `/v1/audio/speech`). Asks for raw PCM, which Kokoro
/// returns as 24 kHz mono signed 16-bit little-endian, the format the wire protocol carries.
struct KokoroSpeechSynthesizer: SpeechSynthesizer {
    let client: any Client
    let config: KokoroConfig

    private struct Request: Content {
        var model = "kokoro"
        var input: String
        var voice: String
        var response_format = "pcm"
        var stream = false
    }

    private static let pcmTypes: Set<String> = ["audio/pcm", "audio/l16", "audio/x-pcm"]

    @MainActor func synthesize(_ text: String) async throws -> Data {
        let body = Request(input: text, voice: config.voice)
        let response = try await client.post(URI(string: config.baseURL + "/v1/audio/speech")) {
            try $0.content.encode(body, as: .json)
        }
        guard response.status == .ok else { throw SpeechError.http(status: response.status.code) }
        // An old image or another server may ignore response_format and send MP3 or WAV.
        let type = response.headers.first(name: .contentType)?.lowercased().split(separator: ";").first.map(String.init) ?? "none"
        guard Self.pcmTypes.contains(type) else { throw SpeechError.badResponse("content type \(type) is not raw PCM") }
        guard var buffer = response.body else { throw SpeechError.badResponse("empty body") }
        let audio = buffer.readData(length: buffer.readableBytes) ?? Data()
        do { try ConversationProtocol.validateAudio(audio) }
        catch { throw SpeechError.badResponse("not whole 16-bit samples or over the size limit (\(audio.count) bytes)") }
        return audio
    }
}
