# First slice: spoken echo

## Goal

Prove a round trip between a physical iPhone and a server running on the developer's Mac. The user speaks into the app and hears the server speak a deterministic response containing the recognized words. This is a developer-only slice, not a self-hosting release.

## In scope

- Open a minimal iOS app and configure a server URL that persists between launches.
- Connect to the Mac over a WebSocket, using Tailscale for connectivity. The app has no bearer token or other application authentication in this slice.
- Tap once to start recording and again to submit the turn. Use an Apple speech recognition API; on-device recognition is not required for this slice.
- Send the final transcript to the server. The server responds with the transcript prefixed by a fixed phrase, using no real agent or LLM.
- Synthesize the response on the Mac using a built-in macOS voice, then send the audio to the app in chunks. Synthesis may finish before the first chunk is sent, and the app may buffer all chunks before playback.
- Play the response on the iPhone. Disable recording while a response is being generated or played. Allow multiple sequential turns in one session.
- On disconnection, stop the current turn and allow a manual reconnect. Do not resume the interrupted turn. Permission and speech-recognition failures may be reported in developer logs; no text fallback is required.
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
4. Automated tests cover the internal message exchange and server logic, including deterministic response generation and chunk handling. Document the steps for the real-iPhone check.
