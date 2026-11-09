# First slice: spoken echo

## Goal

Prove a round trip between a physical iPhone and a server running on the developer's Mac. The user speaks into the app and hears the server speak a deterministic response containing the recognized words. This is a developer-only slice, not a self-hosting release.

## In scope

- Open a minimal iOS app and configure a server URL that persists between launches.
- Connect to the Mac over a WebSocket, using Tailscale for connectivity. The app has no bearer token or other application authentication in this slice.
- Use explicit Connect and Disconnect controls. Connecting completes the WebSocket handshake before recording is available.
- Tap once to start recording and again to submit the turn. Automatically stop and submit after 60 seconds of capture. Use an Apple speech recognition API; on-device recognition is not required for this slice.
- Wait for the final recognition result after stopping capture. Discard empty results and allow another recording. Permission or recognition failures return a connected session to ready, with a generic developer log and no text-input fallback.
- Send the final transcript to the server. The server responds with `You said: ` followed by the trimmed transcript, using no real agent or LLM.
- Synthesize the response on the Mac using a built-in macOS voice, then send the audio to the app in chunks. Synthesis may finish before the first chunk is sent, and the app may buffer all chunks before playback.
- Play the response on the iPhone. Disable recording while a response is being generated or played. Allow multiple sequential turns in one session.
- On socket loss or explicit Disconnect, stop capture and playback and discard the current turn. Backgrounding the app also disconnects. Reconnect manually with no automatic retry or resume.
- Synthesis, playback, and protocol failures stop the turn and close the connection. Log failures without transcript contents and require manual reconnect.
- Keep session transcripts and generated audio in memory only. Do not persist them after the app or server exits.
- Keep client code in this repository for now. Choose the server language based on the simplest implementation of these requirements.

## Network and privacy boundary

The server may listen on all interfaces and has no application authentication. The developer is responsible for firewall and Tailscale access controls; Tailscale alone does not prevent access through another reachable interface. Do not expose this server to an untrusted network. Apple speech recognition may send speech off the device, depending on the API and its configuration.

## Protocol

Use an internal WebSocket message format sufficient for final transcripts, responses, chunked audio, and session completion. Formal protocol versioning, JSON Schemas, and published fixtures are deferred. This is a deliberate departure from the protocol-first plan for this slice.

## Out of scope

- A real agent or LLM, Kokoro, voice selection, and continuous synthesis or low-latency playback.
- Action Button or Shortcuts launch, automatic turn detection, barge-in, and overlapping turns.
- CallKit, background and lock-screen behavior, automatic reconnect or session resume.
- A separate Swift SDK repository, production authentication, general-purpose deployment, and setup for other developers.
- Transcript or audio persistence, and a full transcript or connection-status interface.

## Acceptance checks

1. On a physical iPhone connected to the Mac through Tailscale, configure the server URL, start a recording, speak, and submit it. The phone plays a spoken response containing the recognized transcript.
2. Repeat for at least one more turn in the same session. Recording is unavailable while the preceding response is being generated or played.
3. Drop the connection during a turn. The turn stops, and a manual reconnect permits a new turn without resuming the old one.
4. Automated tests cover the internal message exchange and server logic, including deterministic response generation and chunk handling. See [developer setup and verification](development.md) for commands, recorded automated results, and the physical-iPhone checklist. A simulator or unsigned build does not satisfy the physical-device checks.
