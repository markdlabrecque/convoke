# Convoke iPhone app

Use the [glossary](../../GLOSSARY.md) and [domain model](../../docs/domain-model.md) for the distinction between sessions, conversations, utterances and turns. A conversation is one hands-free interaction within a session; stopping and starting can retain the session's earlier context.

Open `Convoke.xcodeproj` and use the shared `Convoke` scheme. The app supports iPhone on iOS 26+. There are no external package dependencies. The local `ConvokeCore` package contains the session controller and its tests.

For a physical phone, select your development team under Signing & Capabilities, choose the phone as the run destination, and run. Signing settings are intentionally not tied to a developer account.

The checked-in project and Info.plist are generated from `project.yml`. If the project configuration changes, regenerate with XcodeGen:

```sh
cd ios/Convoke
xcodegen generate
```

For the complete Mac/Tailscale setup, recorded automated results, and physical-iPhone acceptance checklist, see [`docs/development.md`](../../docs/development.md). The [November 16 physical session](../../docs/slice-4-30-device-session.md) records owner-reported passes and remaining discrepancies. Issue #30 is closed at owner request with real interruption/route tests deferred, not fully accepted.

## Conversation flow

1. Enter `ws://<Mac Tailscale IP>:8080/conversation`, replacing the placeholder with the Mac's numeric Tailscale IP. The URL is the only app setting saved to UserDefaults.
2. Tap Start conversation. Convoke connects to the saved server if needed and starts listening once the app is active and the WebSocket handshake has succeeded. Tap Disconnect to cancel while connecting. Use Connect by itself if you only want to check the server connection; it never opens the microphone.
3. Allow microphone access when prompted. The first run may download the on-device speech model ("Preparing speech recognition"). Recognition uses `SpeechAnalyzer` and `SpeechTranscriber` (iOS 26+) and runs on the device; there is no cloud fallback.
4. Speak. The turn is submitted automatically after 2.5 seconds of silence following speech; the countdown restarts on every transcript change and never runs before speech is heard. A 300-second (5-minute) capture limit also submits (an empty result just keeps listening). During "Finishing speech recognition," the app ends audio input and waits up to five seconds for the recognizer's finalized text. It never sends volatile or partial text as a substitute. Text over 16384 UTF-8 bytes or an encoded frame over 32768 bytes is rejected with a visible message.
5. A successful send leaves the app in Waiting while it buffers the response. Playing begins when the player starts, at 9600 PCM bytes buffered or at EOF for a shorter reply. Later chunks arrive while it plays. An empty queue before EOF is an underrun, not a reason to listen. Listening resumes only after validated `agent.done` and actual final playback drain.
6. Tap End conversation to stop. Listening and playback are cancelled and the connection stays open. If the server is still sending the reply (Waiting, or Playing before `agent.done`), the protocol cannot cancel the turn, so ending closes the connection. Disconnect and backgrounding also end the conversation.

Permission, model, locale and recognition failures end the conversation, return the connected session to Ready and show a content-free error on screen. The app does not retry in a loop. Change denied microphone permission in iOS Settings before retrying. There is no manual Submit.

The transport keeps a raw WebSocket read pending so URLSession processes remote close and pong frames even when no application receive is pending. It also sends a ping every two seconds and disconnects if the peer does not answer within five seconds. Raw application frames stay in memory until consumed, bounded to 1024 frames or 16 MiB including base64 overhead. Exceeding either unread-buffer limit closes the connection. No conversation messages are parsed here.

Disconnect discards capture, cancels timers and transport monitoring, clears buffered frames, stops the player, and closes the socket. Backgrounding the app does the same. The app never reconnects automatically. Failures write a generic developer log without transcript contents. In the November 16 physical server-loss and sidecar-loss checks, audio stopped and explicit recovery worked, but the owner saw only Disconnected without a failure explanation. The required visible-error behavior remains an acceptance discrepancy; generic developer logging is not a substitute.

The app has no bearer token or application authentication. Use only a trusted development network and enforce access controls on the Mac. The developer-configured numeric IP requires a cleartext ATS allowance, so this developer app includes `NSAllowsArbitraryLoads`. Do not add `NSAllowsLocalNetworking` alongside it, because on iOS 10+ that key causes the arbitrary-loads exception to be ignored. Do not carry the broad exception into a production release. Transcript text is held in memory for sending, not stored by the app or written to its logs.

## Start with the Action Button

On an iPhone with an Action Button, go to **Settings → Action Button → Shortcut**, tap **Choose a Shortcut**, and select Convoke's **Start Conversation**. Press and hold the button to open or focus Convoke and start without a second tap. You can also run the App Shortcut in Shortcuts or use the on-screen Start conversation button on any supported iPhone.

Unlock the phone if iOS asks. Convoke won't start capture while locked or in the background, and a cancelled launch won't start a conversation later. Another press during startup or an active conversation has no effect. If you pressed Connect separately, wait for it to finish before running the shortcut. If startup fails, read the error on the conversation screen, fix the address, server, or permissions as needed, then explicitly start again. Ordinary app launches and server disconnects never start listening.

### Physical-iPhone verification pending

On a signed development build and an Action Button iPhone, verify that the shortcut appears in Settings and can be assigned. Press it on an unlocked phone from Home with Convoke closed, from Home with Convoke already running, and with Convoke visible. Each should start once without an in-app tap. Press again during startup and while listening; neither should replace the conversation. Also verify:

- Cancel the unlock prompt or foreground handoff; an ordinary launch after that must not listen.
- Tap Disconnect during connection startup or leave the app. A late handshake must not start capture. Backgrounding during a conversation must stop capture and close the connection.
- Tap Start conversation while disconnected. With a reachable development server and permissions granted, one tap should reach Listening. On first use, confirm the permission prompt and model preparation finish before the microphone opens. Switch the Bluetooth audio route during speech preparation and check that capture starts on the current route or fails safely.
- Try an unreachable development server or deny microphone access. The app should show an error without retrying or recording later on its own. Fix the problem and retry explicitly.

## Conversation accessibility

The conversation screen shows the current status in text and sends status changes and new errors to VoiceOver.

Physical iPhone verification is pending. At the largest text size with VoiceOver on, check the reading order and reach Start, End, Connect and Disconnect. Edit the URL and check scrolling with the keyboard open. On the speaker, listen for Listening, Waiting for reply and Playing reply. Check that focus stays put, the reply remains audible, and the microphone does not pick up VoiceOver as a new turn. Try an invalid URL twice and deny microphone permission separately. Each failure should be announced and remain available to read.

## Tests and builds

Use the [automated checks guide](../../docs/development.md#automated-checks) for the shared Apple command, prerequisites, simulator override, failure logs and exact CI check names. It also covers the limited Linux core command and optional real-engine checks. The [ongoing physical-device smoke checklist](../../docs/development.md#ongoing-physical-device-smoke) describes when a signed phone run is needed; default Apple passes and unsigned builds do not establish physical audio behavior.

Tests cover persistence, connection lifecycle and failures, state gating, JSON encoding, empty results, UTF-8 and frame limits, the 2.5-second silence and 300-second capture timers, automatic listening after playback, End conversation during every state, visible errors, cleanup, and late callbacks after disconnect. Controller tests use fakes. On macOS, localhost integration tests exercise the actual transport without an application receive, including remote close, missing pong, reconnection, cancellation, and raw-frame delivery. Adapter tests exercise premature completion through the controller, finalized-segment joining, volatile-text exclusion, speech-activity reporting, finalization cancellation, and the five-second deadline without permissions, speech models or microphone access. The same adapter sources compile in the Swift package test target; only iOS audio-session configuration is conditional. The package targets macOS 26 because SpeechAnalyzer requires it. Model preparation, microphone input and actual recognition need a physical phone. They were unavailable in the original Linux implementation environment; the later November 16 session exercised real on-device recognition and hands-free turns. That session does not independently instrument model download or microphone/callback internals.

On Linux, the portable command in the guide runs a limited controller/validator/queue/lifetime subset in a temporary package with a test-only Combine stand-in. It does not test Combine publishing, Apple adapters or audio hardware and is not a full Apple package pass. See the [historical Slice 4 regression matrix](../../docs/slice-4-29-verification.md), [later automated evidence](../../docs/development.md#automated-checks) and [physical session](../../docs/slice-4-30-device-session.md) for their separate scopes and results.

## Pending phone verification: unexpected connection loss

The owner-reported server-loss and sidecar-loss failures are recorded in [PR 60](https://github.com/markdlabrecque/convoke/pull/60); both visible-feedback checks remain **Pending** on a new dated build. Software tests do not establish physical iPhone behavior. After separate approval for installation and development-service failure setup, the owner can:

1. During partial playback, separately exercise development server loss and speech sidecar loss. For each, check for a content-free error, disconnected/inactive state, stopped capture and playback, and no automatic recovery.
2. Restore services and tap Start conversation to connect and start a fresh turn. Separately, check that Connect alone still reaches Ready without listening. Confirm intentional End, Disconnect and backgrounding do not create a false error.
3. Record the date, build, device and result for each case. No owner verification or an inconclusive trigger means Pending. Interruption and route checks remain separate.

## Response playback

The controller owns one receive loop over `ConversationTransport.receive()`. `WebSocketTransport` keeps ownership of the URLSession reader. The controller accepts `agent.text`, sequential zero-based `agent.audio` chunks, then a matching `agent.done`. Binary frames, malformed JSON, extra fields, invalid types/order, empty or unaligned PCM, and unsupported session states disconnect with a generic log. Frame, chunk, and total PCM limits are 32768 UTF-8 bytes, 16384 decoded bytes, and 8 MiB. Transcript contents and audio are never written to disk or logs.

`ConversationPlayer` is streaming: `beginStream(onStarted:onFailure:)` on the first chunk, `enqueue(pcm:)` per chunk, and `endStream()` after `agent.done`, which returns only when every chunk has played. The start callback changes the visible status, not reception of text or an initial buffered chunk. The failure callback immediately disconnects even if the server has not sent another frame. Reply and connection identities reject old callbacks before teardown cancels tasks or stops audio. `PCMPlaybackLifetime` owns exactly-once settlement and invalidates buffer callbacks on stop, interruption, configuration change and success. The app's `PCMPlayer` converts each chunk (24 kHz mono signed 16-bit little-endian PCM) to an AVAudioPCMBuffer and schedules it on one AVAudioPlayerNode with the played-back completion callback. The controller keeps only counts, not audio. Audio engine changes or audio-session interruptions fail the turn. Disconnect cancels receive/playback work, stops the player, and discards buffered response data. Manual Connect starts a fresh session, with no reconnect, resume, or barge-in.

Response tests cover decoding and ordering, exact chunk and buffer limits, count mismatches, recording gating, repeated turns, playback failure, socket loss, disconnect cleanup, and stale completion after manual reconnect. The November 16 physical session established owner-heard playback before genuine source EOF using common-Mac-clock markers, plus both End windows and delayed-delivery underrun recovery. These are physical-session results, not properties established by the fake-player tests. Actual iOS interruption and route/configuration changes remain deferred/Pending; closure of #30 does not pass them or resolve the missing server/sidecar failure messages.
