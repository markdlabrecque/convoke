# Mac spoken-echo server

This implements `docs/first-slice.md`, not the later agent/Kokoro design in `plan.md`.

For the complete iPhone/Tailscale setup, recorded automated results, and physical-device checklist, see [developer setup and verification](../docs/development.md).

## Run

Use a Mac running macOS 13 or later, with an installed system speech voice and Swift 6.4 or later. The committed dependency resolution currently requires Swift 6.4.

```sh
cd server
swift run ConvokeServer serve
# Optional port override:
PORT=9090 swift run ConvokeServer serve
```

Connect to `ws://<Mac-Tailscale-address>:8080/conversation`.

The server binds `0.0.0.0` and has **no application authentication or TLS**. Restrict access with the Mac's firewall and tailnet ACLs. Tailscale does not protect other reachable interfaces. Do not expose this server to untrusted networks.

## Internal exchange

Send a JSON text message containing only `type` and `text`:

```json
{"type":"user.text","text":"hello"}
```

The server trims whitespace and replies with `agent.text` containing `You said: hello`. It synthesizes that response with the default macOS voice, converts it with `AVAudioConverter`, and sends:

- `agent.audio` with zero-based `sequence` and base64 `data`. The decoded bytes are headerless, 24 kHz mono signed 16-bit little-endian PCM.
- `agent.done` with `chunks` equal to the number of audio messages sent.

Wait for `agent.done` before sending another turn. Playback and microphone control belong to the client.

Limits are 4096 UTF-8 bytes of trimmed input, 32768 UTF-8 bytes per JSON message, 16384 decoded bytes per audio chunk, and 8 MiB of accumulated PCM per turn. Fragmented incoming messages share the same 32768-byte limit. A turn has a 120-second deadline, including synthesis and writes. Invalid input, binary messages, overlapping turns, conversion or synthesis errors, oversized audio, and timeouts close the connection. A close handshake has a one-second deadline, after which TCP is forcibly closed even if the peer does not acknowledge or a write is stalled. No further application or ping messages are processed while closing. Client frames must be masked and must not set reserved bits, since no extensions are negotiated. A disconnect cancels synthesis and releases the conversation. Reconnecting starts a new session; interrupted turns are not resumed.

Transcripts and audio stay in memory. The application neither writes them to disk nor logs transcript content. There is no agent integration, voice selection, or Kokoro.

## Tests

```sh
cd server
swift test
# Also exercise the installed voice over a local WebSocket for two turns:
CONVOKE_TEST_SYSTEM_VOICE=1 swift test
```

The default XCTest suite injects synthesis and needs no audio hardware. It covers validation, wire and fragmented-message limits, invalid UTF-8, ordering and chunk counts, sequential turns, failure closure, timeout and disconnect cancellation. Regression tests check conversation deallocation, unacknowledged close handshakes, stalled writes, and masking/reserved-bit violations on complete and fragmented wire frames. Converter tests use generated PCM buffers to check resampling, mono Int16 little-endian output, and the cap during accumulation. Tests bind loopback on an ephemeral port, regardless of the run-time host and port configuration.

The opt-in voice check verifies non-silent PCM, not physical iPhone playback or Tailscale connectivity. Those remain separate first-slice acceptance checks.
