import Foundation

public enum ResponseError: Error { case invalid }

/// A single response, discarded on completion or disconnect.
struct ResponseAccumulator {
    private var hasText = false
    private var chunks = 0
    private var audio = Data()

    mutating func consume(_ frame: URLSessionWebSocketTask.Message) throws -> Data? {
        guard case .string(let text) = frame, text.utf8.count <= 32768 else {
            throw ResponseError.invalid
        }
        let message = try JSONDecoder().decode(Message.self, from: Data(text.utf8))
        switch message.type {
        case "agent.text":
            guard !hasText, message.keys == ["type", "text"],
                  let text = message.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ResponseError.invalid
            }
            hasText = true
        case "agent.audio":
            guard hasText, message.keys == ["type", "sequence", "data"],
                  message.sequence == chunks, let encoded = message.data,
                  let data = Data(base64Encoded: encoded), !data.isEmpty,
                  data.count <= 16384, data.count.isMultiple(of: 2),
                  audio.count + data.count <= 8 * 1024 * 1024 else { throw ResponseError.invalid }
            audio.append(data)
            chunks += 1
        case "agent.done":
            guard hasText, message.keys == ["type", "chunks"],
                  message.chunks == chunks, chunks > 0 else { throw ResponseError.invalid }
            return audio
        default: throw ResponseError.invalid
        }
        return nil
    }

    private struct Message: Decodable {
        let type: String
        let text: String?
        let data: String?
        let sequence: Int?
        let chunks: Int?
        let keys: Set<String>
        private struct Key: CodingKey {
            let stringValue: String
            let intValue: Int? = nil
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { return nil }
        }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Key.self)
            keys = Set(container.allKeys.map(\.stringValue))
            type = try container.decode(String.self, forKey: Key(stringValue: "type")!)
            text = try container.decodeIfPresent(String.self, forKey: Key(stringValue: "text")!)
            data = try container.decodeIfPresent(String.self, forKey: Key(stringValue: "data")!)
            sequence = try container.decodeIfPresent(Int.self, forKey: Key(stringValue: "sequence")!)
            chunks = try container.decodeIfPresent(Int.self, forKey: Key(stringValue: "chunks")!)
        }
    }
}
