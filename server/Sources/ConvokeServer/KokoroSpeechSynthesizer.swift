import AsyncHTTPClient
import Foundation
import NIOCore
import NIOHTTP1
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
    /// The shared AsyncHTTPClient, used for the streamed response body.
    let http: HTTPClient

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
        guard Self.pcmTypes.contains(type) else { throw SpeechError.badResponse("content type is not raw PCM") }
        guard var buffer = response.body else { throw SpeechError.badResponse("empty body") }
        let audio = buffer.readData(length: buffer.readableBytes) ?? Data()
        do { try ConversationProtocol.validateAudio(audio) }
        catch { throw SpeechError.badResponse("not whole 16-bit samples or over the size limit (\(audio.count) bytes)") }
        return audio
    }

    /// Pull-based HTTP body reads preserve AHC's bounded transport read-ahead. Its body uses
    /// NIO's high/low watermark producer, not an unbounded application queue. Dropping the
    /// iterator on consumer failure cancels the transaction; cancellation during next() also
    /// cancels it. Non-200 and non-PCM responses fail before any audio is returned.
    @MainActor func stream(_ text: String) async throws -> AsyncThrowingStream<Data, Error> {
        var request = HTTPClientRequest(url: config.baseURL + "/v1/audio/speech")
        request.method = .POST
        request.headers.add(name: "content-type", value: "application/json")
        request.body = .bytes(try JSONEncoder().encode(Request(input: text, voice: config.voice, stream: true)))
        let response = try await http.execute(request, timeout: .seconds(120))
        guard response.status == .ok else { throw SpeechError.http(status: response.status.code) }
        let type = response.headers.first(name: "content-type")?.lowercased().split(separator: ";").first.map(String.init) ?? "none"
        guard Self.pcmTypes.contains(type) else { throw SpeechError.badResponse("content type is not raw PCM") }
        let body = BodyPuller(response.body)
        return AsyncThrowingStream<Data, Error>(unfolding: { try await body.next() })
    }
}

/// Pulls one body part at a time. Used by one consumer, which awaits each pull.
final class BodyPuller<Body: AsyncSequence>: @unchecked Sendable where Body.Element == ByteBuffer {
    private var iterator: Body.AsyncIterator
    private var trailing: UInt8?
    private var emitted = false
    init(_ body: Body) { iterator = body.makeAsyncIterator() }

    func next() async throws -> Data? {
        while true {
            try Task.checkCancellation()
            guard var buffer = try await iterator.next() else {
                guard trailing == nil, emitted else { throw SpeechError.badResponse("empty or incomplete PCM") }
                return nil
            }
            guard buffer.readableBytes > 0 else { continue }
            var data = Data()
            if let trailing { data.append(trailing); self.trailing = nil }
            data.append(buffer.readData(length: buffer.readableBytes) ?? Data())
            if !data.count.isMultiple(of: 2) { trailing = data.removeLast() }
            guard !data.isEmpty else { continue }
            emitted = true
            return data
        }
    }
}
