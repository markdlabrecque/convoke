# Convoke server

The server sends each spoken turn to an OpenAI-compatible chat endpoint and speaks the reply. It began as the spoken-echo first slice (`first-slice.md` in the work root); the echo is gone. Kokoro speech comes later (`plan.md`). The setup and verification guide is `development.md` in the same work root.

## Run

Use a Mac running macOS 13 or later, with an installed system speech voice and Swift 6.4 or later. The committed dependency resolution currently requires Swift 6.4.

Set the agent first. The server will not start without these:

| Variable | Meaning |
| --- | --- |
| `CONVOKE_AGENT_BASE_URL` | Endpoint base, up to and including `/v1`. The server posts to `<base>/chat/completions`. |
| `CONVOKE_AGENT_MODEL` | Model name sent in each request. |
| `CONVOKE_AGENT_API_KEY` | Optional. Sent as a Bearer token. |

```sh
# Ollama (ollama serve; ollama pull llama3.2)
export CONVOKE_AGENT_BASE_URL=http://localhost:11434/v1
export CONVOKE_AGENT_MODEL=llama3.2
# llama.cpp (llama-server -m model.gguf --port 8081); the model name is mostly ignored
# export CONVOKE_AGENT_BASE_URL=http://localhost:8081/v1
# export CONVOKE_AGENT_MODEL=local

cd server
swift run ConvokeServer serve
# Optional port override:
PORT=9090 swift run ConvokeServer serve
```

Connect to `ws://<Mac-Tailscale-address>:8080/conversation`.

The server binds `0.0.0.0` and has **no application authentication or TLS**. Restrict access with the Mac's firewall and tailnet ACLs. Tailscale does not protect other reachable interfaces. Do not expose this server to untrusted networks.

## Linux

The server builds and tests on Linux (`swift build`, `swift test` in `server/`). Speech goes through the `SpeechSynthesizer` protocol (`Sources/ConvokeServer/SpeechSynthesizer.swift`). Only macOS has a synthesizer today, so on Linux each turn sends `agent.text`, logs `No speech synthesizer is available on this platform`, and closes the connection without audio. Two chunked-audio tests are skipped on Linux because its `URLSessionWebSocketTask` truncates large messages.

## Internal exchange

Send a JSON text message containing only `type` and `text`:

```json
{"type":"user.text","text":"hello"}
```

The server trims whitespace and sends the text, with this connection's earlier turns, to the agent. A short system prompt asks for brief, plain spoken replies without markdown. The whole reply goes back as `agent.text`. The server synthesizes it with the default macOS voice, converts it with `AVAudioConverter`, and sends:

- `agent.audio` with zero-based `sequence` and base64 `data`. The decoded bytes are headerless, 24 kHz mono signed 16-bit little-endian PCM.
- `agent.done` with `chunks` equal to the number of audio messages sent.

Wait for `agent.done` before sending another turn. Playback and microphone control belong to the client.

Limits are 4096 UTF-8 bytes of trimmed input, 32768 UTF-8 bytes per JSON message, 16384 decoded bytes per audio chunk, and 8 MiB of accumulated PCM per turn. Fragmented incoming messages share the same 32768-byte limit. A turn has a 120-second deadline, including synthesis and writes. Invalid input, binary messages, overlapping turns, conversion or synthesis errors, oversized audio, and timeouts close the connection. A close handshake has a one-second deadline, after which TCP is forcibly closed even if the peer does not acknowledge or a write is stalled. No further application or ping messages are processed while closing. Client frames must be masked and must not set reserved bits, since no extensions are negotiated. A disconnect cancels synthesis and releases the conversation. Reconnecting starts a new session; interrupted turns are not resumed.

Transcripts and audio stay in memory. The application neither writes them to disk nor logs transcript content. Each connection keeps its own history in memory (the last 40 messages) and drops it on disconnect. Logs carry sizes and status codes, never transcript or reply text. If the endpoint is unreachable, returns an error, or sends an empty reply, the server logs the reason and closes the connection with WebSocket code 1011 (server error). It never falls back to an echo. There is no voice selection or Kokoro yet; the agent request is not streamed.

## Tests

On a Mac, run `swift build` first: it is the only check that compiles the macOS voice code, which Linux skips.

```sh
cd server
swift build
swift test
# Also exercise the installed voice over a local WebSocket for two turns:
CONVOKE_TEST_SYSTEM_VOICE=1 swift test
```

The default XCTest suite injects the agent and synthesis and needs no audio hardware or model. A stubbed endpoint checks the agent request shape, auth header and error handling. It covers validation, wire and fragmented-message limits, invalid UTF-8, ordering and chunk counts, sequential turns, failure closure, timeout and disconnect cancellation. Regression tests check conversation deallocation, unacknowledged close handshakes, stalled writes, and masking/reserved-bit violations on complete and fragmented wire frames. Converter tests use generated PCM buffers to check resampling, mono Int16 little-endian output, and the cap during accumulation. Tests bind loopback on an ephemeral port, regardless of the run-time host and port configuration.

The opt-in voice check verifies non-silent PCM, not physical iPhone playback or Tailscale connectivity. Those remain separate first-slice acceptance checks.
