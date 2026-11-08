# Convoke — Plan

## Goal

Convoke is an open-source system anyone can self-host for two-way voice conversations with a personal agent, starting with a minimal native iOS app. The phone does as much of the speech work as possible, which is free, so the server spends its resources on the agent itself. The server protocol stays open to other clients later, such as a browser on desktop.

## Development workflow

Linux is the primary development host. Use the Mac for Xcode builds, signing, and physical-iPhone testing. For the first spoken-echo slice, the server also runs on the Mac and uses a built-in macOS voice.

## Guiding principles

- **On-device first:** speech-to-text (STT) runs on the iPhone. Text-to-speech (TTS) starts on the server with Kokoro, with the option to move it to the device later.
- **Text over the wire:** the phone sends text up; the server streams reply text and Kokoro audio down.
- **Thin client:** the app has no agent logic. It is just a microphone, a speaker, and a socket.
- **Protocol-first:** define the WebSocket message format before writing the app, so other clients can be added later.

## Architecture

1. **Trigger:** the Action Button runs a Shortcut, which opens the app straight into a live conversation through an App Intent (Apple's framework for exposing app actions to Shortcuts and Siri).
2. **Capture:** AVAudioEngine records the microphone, and Apple's SpeechAnalyzer and SpeechTranscriber (iOS 26) transcribe on device, streaming partial and final results.
3. **Turn detection:** the end of each turn is detected on device from silence, along with SpeechTranscriber's final results.
4. **Transport:** a single persistent WebSocket over TLS (Transport Layer Security) to the agent server, authenticated with a bearer token.
5. **Agent:** the server receives the user's text and streams back reply text in chunks.
6. **Speech out:** Kokoro runs on the server and streams audio chunks sentence by sentence over the WebSocket, and the app plays them as they arrive. Moving Kokoro onto the device (for example the KokoroSwift package on MLX Swift) stays an option for later, to save server resources and cut latency.
7. **Barge-in:** if the user starts speaking while the agent is talking, the app stops playback and sends an interrupt message.

## WebSocket protocol (draft)

JSON messages, each with a `type` field:

- `session.start`: protocol version and client capabilities, such as `stt: device`, `tts: server`
- `user.text`: final transcript of a user turn
- `user.partial`: optional, so the server can prefetch
- `user.audio`: reserved for clients without on-device STT, such as a future browser client using server-side Parakeet
- `agent.text.delta` / `agent.text.done`: streamed reply
- `agent.audio`: Kokoro audio chunks streamed from the server (the default to start)
- `control.interrupt`: barge-in; the server cancels the current generation
- `session.end`

## App interface (deliberately minimal)

- One screen: a large state indicator (listening, thinking, speaking), a scrolling transcript, and mute and end buttons.
- Settings: server URL, token, and voice choice.

## Background and call behaviour

- Audio background mode plus AVAudioSession configured for voice chat, which gives echo cancellation.
- Phase 2: CallKit, so a session behaves like a phone call. It shows on the lock screen, survives screen lock, and routes to AirPods and CarPlay.

## Repositories

Two repos, with the protocol spec owned by the main one.

| Repo | Contents |
| --- | --- |
| `convoke` | Reference server, SwiftUI iOS app, protocol spec (JSON Schemas, example messages, version history), self-hosting docs |
| `convoke-swift` | Swift SDK (software development kit) as a Swift package: protocol types, WebSocket session, reconnects, on-device transcription and turn detection, barge-in, `agent.audio` playback |

**Boundary rule:** the SDK owns anything another Convoke client on Apple platforms would also need; the app owns what is specific to this app's experience.

- **`convoke-swift`:** protocol types and version negotiation, the WebSocket session and reconnects, streaming `agent.audio` playback, barge-in (stop playback and send `control.interrupt`), and on-device transcription and turn detection with SpeechAnalyzer. Transcription ships as its own library product in the package, so the core stays usable without the iOS 26 requirement.
- **App (`convoke/ios`):** SwiftUI interface, App Intents and the Action Button shortcut, CallKit, AVAudioSession configuration, settings, and the server token in the Keychain.

* The app depends on `convoke-swift` through Swift Package Manager, pinned "up to next minor" while on 0.x.
* During parallel development, a local checkout of the SDK added to the Xcode project overrides the remote dependency.
* The SDK tests against a pinned copy of the protocol fixtures from `convoke`, via a git submodule or files synced at a tag.
* Continuous integration uses path filters so macOS builds run only when `ios/` or `protocol/` changes.

## Connectivity

The protocol is transport-agnostic: a WebSocket over TLS with bearer-token auth.

- Tailscale, or another VPN (virtual private network), is the documented and recommended way to reach a home server, not a hard requirement.
- A public endpoint or plain WireGuard also works.
- `session.start` carries a protocol version so mismatched client and server versions are detected early.

## Phases

1. **Prototype:** Action Button opens the app; on-device STT, WebSocket text exchange, and server-side Kokoro replies streamed back as audio. Push to talk is fine at this stage.
2. **Hands-free:** automatic turn detection, barge-in, and streaming TTS that starts speaking on the first sentence.
3. **Quality:** CallKit integration, optionally moving Kokoro onto the device, and reconnect and resume handling.
4. **Expansion:** a browser client using `user.audio` with server-side Parakeet, run only when needed.

## Open questions

- Is server-side Kokoro latency and load acceptable long term, or should TTS move onto the device?
- Which alternatives to Tailscale (for example plain WireGuard or a public endpoint) get their own setup guide?
- Should transcripts persist on the phone, the server, or both?
