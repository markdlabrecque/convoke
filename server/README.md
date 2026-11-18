# Convoke server

The server waits for the complete text reply from an OpenAI-compatible chat endpoint, then streams Kokoro PCM to incremental iPhone playback. With Kokoro unset, it uses the buffered macOS voice adapter where available. The setup and verification guide is [`docs/development.md`](../docs/development.md).

For project language, see the [glossary](../GLOSSARY.md) and [domain model](../docs/domain-model.md). The server's `Conversation` class represents a session and its shared history, not one Start-to-End hands-free conversation.

## Run

Use a Mac running macOS 13 or later with Swift 6.4 or later, plus either the Docker Kokoro sidecar below or an installed system speech voice. The committed dependency resolution currently requires Swift 6.4.

Set the agent base URL and model first. The server will not start without them:

| Variable | Meaning |
| --- | --- |
| `CONVOKE_AGENT_BASE_URL` | Endpoint base, up to and including `/v1`. The server posts to `<base>/chat/completions`. |
| `CONVOKE_AGENT_MODEL` | Model name sent in each request. |
| `CONVOKE_AGENT_API_KEY` | Optional. Sent as a Bearer token. |
| `CONVOKE_BIND_HOST` | Optional. Defaults to `127.0.0.1` (loopback) when unset or blank. |
| `CONVOKE_TURN_TIMEOUT_SECONDS` | Optional. Whole-turn deadline in seconds. Defaults to `120`; if set, it must be an integer from `10` to `3600` or startup fails. |

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

Connect locally at `ws://127.0.0.1:8080/conversation`. For direct phone access, set `CONVOKE_BIND_HOST` to the Mac's numeric tailnet address before starting the server, then connect to `ws://<Mac-Tailscale-address>:8080/conversation`.

The loopback default keeps the server local. The server has **no application authentication or TLS**. If you override the bind host, restrict access with the Mac's firewall and tailnet ACLs. Tailscale does not protect other reachable interfaces. Do not expose this server to untrusted networks.

## Linux

The server builds and tests on Linux; see the [automated checks guide](../docs/development.md#automated-checks) for root-relative commands and CI check names. Speech goes through the `SpeechSynthesizer` protocol (`Sources/ConvokeServer/SpeechSynthesizer.swift`). Without Kokoro, only macOS has a synthesizer, so on Linux (unless `CONVOKE_KOKORO_URL` is set) each turn sends `agent.text`, logs `No speech synthesizer is available on this platform`, and closes the connection without audio. The chunked-audio tests read frames with WebSocketKit's client, because Linux's `URLSessionWebSocketTask` truncates large messages.

## Kokoro speech (optional sidecar)

Set `CONVOKE_KOKORO_URL` and the server speaks with [Kokoro](https://github.com/remsky/Kokoro-FastAPI) on every platform, Mac included. Unset, a Mac uses the macOS voice and Linux logs that no synthesizer is available.

| Variable | Meaning |
| --- | --- |
| `CONVOKE_KOKORO_URL` | Sidecar root, for example `http://127.0.0.1:8880`. The server posts to `<url>/v1/audio/speech` with `response_format: pcm`, which is 24 kHz mono signed 16-bit PCM, the same bytes the wire carries. |
| `CONVOKE_KOKORO_VOICE` | Optional. Defaults to `af_heart`. |

Run development services in Rex, not tmux. In a Rex terminal, run the pinned CPU sidecar in the foreground, bound to this machine only. The server has no authentication, and neither does the sidecar, so never publish its port beyond `127.0.0.1`. Disable Docker log persistence and discard sidecar output so third-party diagnostics cannot persist request content:

```sh
docker run --rm --log-driver none --name convoke-kokoro \
  -p 127.0.0.1:8880:8880 ghcr.io/remsky/kokoro-fastapi-cpu:v0.10.0 >/dev/null 2>&1
# In a second Rex terminal, retry health until healthy:
curl --fail http://127.0.0.1:8880/health
docker port convoke-kokoro # must show only 127.0.0.1:8880
docker image inspect ghcr.io/remsky/kokoro-fastapi-cpu:v0.10.0 \
  --format '{{json .RepoDigests}}' # record the digest for this session
export CONVOKE_KOKORO_URL=http://127.0.0.1:8880
unset CONVOKE_KOKORO_VOICE               # use the default af_heart
# Start Convoke in this shell using the Run instructions above.
# In another shell, when finished with Convoke:
# docker stop convoke-kokoro
```

The same command works on an Apple Silicon Mac. Docker must be running; the first pull and startup can take time. Keep this development sidecar local and verify the published binding with `docker port convoke-kokoro`, which must show `127.0.0.1:8880`. Restart Convoke after setting the environment variables; exporting them in a different shell does not change an already-running server. An unreachable or failing sidecar logs the reason (a status code or error type, never text or audio) and closes the turn with WebSocket code 1011 (server error); there is no fallback to another voice. Accepted PCM content types are `audio/pcm`, `audio/l16` and `audio/x-pcm`, with optional parameters. MP3, WAV and other content types are rejected. Raw PCM is not inspected for container signatures.

## Hermes

**Deferred and untested with a physical iPhone.** This setup is retained for reference; it is not part of [server and iOS completion](../docs/development.md#current-priority-finish-the-server-and-ios-app). This configuration uses Hermes' existing OpenAI-compatible API; it does not enable the API or change Hermes configuration. Use a Linux development machine already running the main Hermes agent with its API on IPv4 loopback, port `8642` (`localhost` must resolve to that listener).

1. On that machine, use the [Linux notes](#linux) and start the [Kokoro sidecar](#kokoro-speech-optional-sidecar). Set `CONVOKE_KOKORO_URL` in the Rex terminal where you'll start Convoke. Kokoro is required for speech on Linux.
2. From the repository root in that Bash terminal, adapt the [Run command](#run) as follows. At the hidden prompt, enter only the existing `API_SERVER_KEY` value from `~/.hermes/.env`. Do not source the file or paste the key into a command, the phone, or any notes. The prompt does not echo the key, and the export is confined to the server's launch subshell and its children.

   ```bash
   (
     set +x
     export CONVOKE_AGENT_BASE_URL=http://localhost:8642/v1
     export CONVOKE_AGENT_MODEL=hermes-agent
     unset CONVOKE_BIND_HOST PORT  # use the default loopback bind and port 8080
     export CONVOKE_TURN_TIMEOUT_SECONDS=600
     IFS= read -rs -p 'Hermes API_SERVER_KEY: ' CONVOKE_AGENT_API_KEY || exit 1
     printf '\n'
     [[ -n "$CONVOKE_AGENT_API_KEY" ]] || exit 1
     export CONVOKE_AGENT_API_KEY
     cd server || exit 1
     exec swift run ConvokeServer serve
   )
   ```

   The suggested `600` seconds gives tool-using turns more time; the default is `120`. The deadline covers the agent reply, synthesis, and socket writes, not just Hermes' work.
3. With the phone and Linux machine on the same trusted tailnet, use [Tailscale Serve](https://tailscale.com/kb/1242/tailscale-serve) in a separate terminal on the Linux machine. With tailnet HTTPS enabled, this example forwards tailnet HTTPS port `8443` to Convoke's loopback port `8080`:

   ```sh
   tailscale serve --https=8443 8080
   ```

   In the iPhone app, enter `wss://<machine>.<tailnet>.ts.net:<port>/conversation`. Use the DNS name shown by Serve and replace `<port>` with `8443` (or the HTTPS port you chose), not `8080`. This WSS connection is **untested with Convoke**. Serve terminates TLS, but Convoke has **no client token authentication**: any tailnet client allowed to reach this port can use the Hermes agent through it. Restrict access to the intended user/device with tailnet access rules. Do not use Funnel or expose the server publicly.

Known limits (Hermes behavior inferred from source, not confirmed by this setup):

- The phone cannot approve guarded actions. They are expected to be refused, but this is unconfirmed. Do not treat approval guards as a sandbox.
- Hanging up or hitting the turn deadline stops speech on the phone, not necessarily the Hermes run. Hermes may finish the turn, including tool calls.
- Hermes derives its session from the system prompt and first user message. Two conversations that open with the same words may share a Hermes session even after reconnecting.
- Memory is shared with the main Hermes agent. A new conversation is not a memory reset. Use only harmless, non-sensitive content.

See the [owner's live checklist](../docs/hermes-basic-check.md) for pending verification and [deferred native Hermes work (#91)](https://github.com/markdlabrecque/convoke/issues/91) for features this configuration does not provide.

## Internal exchange

Send a JSON text message containing only `type` and `text`:

```json
{"type":"user.text","text":"hello"}
```

The server trims whitespace and sends the text, with this connection's earlier turns, to the agent. A short system prompt asks for brief, plain spoken replies without markdown. The whole reply goes back as `agent.text`. The server then synthesizes it and sends the PCM as it is produced. With Kokoro, it requests `stream: true` and forwards each part of the HTTP body as `agent.audio` frames, so the phone can start playing before synthesis finishes. The next body part is read only after the previous frame has been written (backpressure). The macOS voice still produces the whole reply first, which is then sent in the same frames, and Kokoro failures never fall back to it. The agent still finishes its whole text reply before speech starts. Frames:

- `agent.audio` with zero-based `sequence` and base64 `data`. The decoded bytes are headerless, 24 kHz mono signed 16-bit little-endian PCM.
- `agent.done` with `chunks` equal to the number of audio messages sent.

The iPhone receives while playing on one audio engine per reply. It starts at 9600 PCM bytes, about 200 ms, or flushes a shorter completed reply at EOF. It keeps capture off during buffering, playback and temporary underruns. A turn finishes only after validated `agent.done` AND actual playback of the last scheduled sample. An empty queue before done is not completion. Neither multiple network frames nor first wire audio proves early speaker output.

End conversation before validated done stops playback and disconnects to cancel unfinished server work. After done, End stops queued playback but can keep the connection ready. Backgrounding, disconnect and audio interruption stop capture/playback; stale callbacks cannot restart them. There is no barge-in, automatic reconnect or voice fallback.

Limits are 16384 UTF-8 bytes of trimmed input, 32768 UTF-8 bytes per JSON message, 16384 decoded bytes per audio chunk, and 8 MiB of accumulated PCM per turn. Fragmented incoming messages share the same 32768-byte limit. The deadline covers the whole turn, including the agent request, synthesis and socket writes. It defaults to 120 seconds and is configurable with `CONVOKE_TURN_TIMEOUT_SECONDS`. Invalid input, binary messages, overlapping turns, conversion or synthesis errors, oversized audio, and timeouts close the connection. A synthesis failure after some audio was sent closes the connection (1011) without `agent.done`; the 8 MiB cap is enforced as audio arrives. A close handshake has a one-second deadline, after which TCP is forcibly closed even if the peer does not acknowledge or a write is stalled. No further application or ping messages are processed while closing. Client frames must be masked and must not set reserved bits, since no extensions are negotiated. A disconnect, failed socket write or turn deadline cancels synthesis, including the actual upstream Kokoro HTTP request, and releases the conversation. The deadline stays active through the final done write. Cancellation and partial failures cannot send successful done or later audio after closure. Reconnecting starts a new session; interrupted turns are not resumed.

Transcripts and audio stay in memory. The application neither writes them to disk nor logs transcript content. Each connection keeps its own history in memory (the last 40 messages) and drops it on disconnect. Logs carry sizes and status codes, never transcript or reply text. If the endpoint is unreachable, returns an error, or sends an empty reply, the server logs the reason and closes the connection with WebSocket code 1011 (server error). It never falls back to an echo. Kokoro voice selection uses `CONVOKE_KOKORO_VOICE`. Agent text generation is not streamed; Kokoro audio is.

## Tests

Use the [automated checks guide](../docs/development.md#automated-checks) for server build/test commands, prerequisites, actual CI names, optional Kokoro smoke and system-voice reproduction links. Run the server build on a Mac to compile the macOS voice adapter, which Linux excludes. The shared Apple app command does not run the server suite. See the [ongoing physical-device smoke checklist](../docs/development.md#ongoing-physical-device-smoke) for audio changes and releases; unrelated server changes do not require the complete phone checklist.

The default XCTest suite injects the agent and synthesis and needs no audio hardware or model. A stubbed endpoint checks the agent request shape, auth header and error handling. It covers validation, wire and fragmented-message limits, invalid UTF-8, ordering and chunk counts, sequential turns, failure closure, timeout and disconnect cancellation. Regression tests check conversation deallocation, unacknowledged close handshakes, stalled writes, and masking/reserved-bit violations on complete and fragmented wire frames. Converter tests use generated PCM buffers to check resampling, mono Int16 little-endian output, and the cap during accumulation. Tests bind loopback on an ephemeral port, regardless of the run-time host and port configuration.

The Kokoro smoke test uses a stub agent with the real sidecar. It verifies non-silent PCM over a local WebSocket and reports first source PCM, synthesis EOF, first wire audio and wire done relative to one monotonic request start. Output contains sizes, durations and counts only. It does not prove real agent generation, physical early playback or Tailscale connectivity. Record those separately in the [Slice 4 verification and owner handoff](../docs/development.md#slice-4-streaming-verification). The earlier Kokoro section is historical complete-reply baseline evidence, not streaming acceptance.

The [Slice 4 regression matrix](../docs/slice-4-29-verification.md) maps deterministic HTTP, source and socket gates to completion, boundary, cancellation and cleanup tests. The historical five Mac upstream-close assertion failures were resolved by the [test-peer observation correction and passing hosted gate](../docs/development.md#passing-result-after-peer-observation-correction), without a production cancellation change. The later [opt-in simulator rerun](../docs/slice-4-27-verification.md#acceptance-evidence-review) passed; real iPhone interruption and route changes remain unverified.

The [November 16 physical session](../docs/slice-4-30-device-session.md) records owner-reported early playback, hands-free turns, both End windows, controlled underrun, background/Disconnect and privacy passes. Actual server and sidecar loss stopped playback and allowed explicit recovery, but the app showed only Disconnected without a failure explanation, so both failure subcases remain Fail overall. Real interruption and route/configuration tests are deferred/Pending. Issue #30 is closed at owner request, not fully accepted; epic #25 remains open. Temporary relays/probes were stopped and the ordinary direct-to-Kokoro development server restored. Session-local helpers are not permanent server modes.
