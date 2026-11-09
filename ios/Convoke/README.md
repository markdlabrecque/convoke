# iPhone spoken echo

Open `Convoke.xcodeproj` and use the shared `Convoke` scheme. The app supports iPhone on iOS 16+. There are no external package dependencies. The local `ConvokeCore` package contains the session controller and its tests.

For a physical phone, select your development team under Signing & Capabilities, choose the phone as the run destination, and run. Signing settings are intentionally not tied to a developer account.

The checked-in project and Info.plist are generated from `project.yml`. If the project configuration changes, regenerate with XcodeGen:

```sh
cd ios/Convoke
xcodegen generate
```

For the complete Mac/Tailscale setup, recorded automated results, and physical-iPhone acceptance checklist, see [developer setup and verification](../../docs/development.md).

## Capture flow

1. Enter `ws://<Mac Tailscale IP>:8080/conversation`, replacing the placeholder with the Mac's numeric Tailscale IP. The URL is the only app setting saved to UserDefaults.
2. Tap Connect and wait for Ready. This means the WebSocket handshake completed, not just that a task was created.
3. Tap Start recording. Allow speech recognition and microphone access. Apple recognition may send audio to Apple.
4. Speak, then tap Submit recording. After 60 seconds of capture the app submits automatically. It ends audio input and waits up to five seconds for Apple's final result. It never sends a partial transcript as a substitute. Empty results are discarded; text over 4096 UTF-8 bytes is rejected.
5. A successful send leaves the app in Waiting while it buffers the response. After a valid `agent.done`, it plays the PCM through the speaker and shows Playing. Recording stays disabled until playback finishes and the app returns to Ready for another turn.

If Apple ends recognition before Submit or the capture deadline, the app discards that interrupted turn and returns to Ready rather than silently stopping the microphone while still showing Recording.

The transport keeps a raw WebSocket read pending so URLSession processes remote close and pong frames even when no application receive is pending. It also sends a ping every two seconds and disconnects if the peer does not answer within five seconds. Raw application frames stay in memory until consumed, bounded to 1024 frames or 16 MiB including base64 overhead. Exceeding either unread-buffer limit closes the connection. No conversation messages are parsed here.

Disconnect discards capture, cancels timers and transport monitoring, clears buffered frames, stops the player, and closes the socket. Backgrounding the app does the same. The app never reconnects automatically. Permission or recognition failures return a connected session to Ready and write a generic developer log without transcript contents. Change denied permissions in iOS Settings before retrying.

The app has no bearer token or application authentication. Use only a trusted development network and enforce access controls on the Mac. The developer-configured numeric IP requires a cleartext ATS allowance on iOS 16, so this developer app includes `NSAllowsArbitraryLoads`. Do not add `NSAllowsLocalNetworking` alongside it, because on iOS 10+ that key causes the arbitrary-loads exception to be ignored. Do not carry the broad exception into a production release. Transcript text is held in memory for recognition and sending, not stored by the app or written to its logs.

## Tests and builds

From this directory on a Mac with Xcode installed:

```sh
# Controller and adapter tests, no microphone, phone, or external server required.
# Transport integration tests start their own loopback-only WebSocket peers.
swift test

# Compile the app and its iOS unit test bundle without a booted simulator.
xcodebuild -project Convoke.xcodeproj -scheme Convoke \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build-for-testing

# Execute those same tests in an installed iPhone simulator.
# Replace the name with an available device from xcrun simctl list devices available.
xcodebuild -project Convoke.xcodeproj -scheme Convoke \
  -destination 'platform=iOS Simulator,name=iPhone 17' test

# Compile for a physical device without signing or installing.
xcodebuild -project Convoke.xcodeproj -scheme Convoke \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

Tests cover persistence, connection lifecycle and failures, state gating, JSON encoding, empty results, UTF-8 and frame limits, the capture deadline, cleanup, and late callbacks after disconnect. Controller tests use fakes. On macOS, localhost integration tests exercise the actual transport without an application receive, including remote close, missing pong, reconnection, cancellation, and raw-frame delivery. Adapter tests exercise premature recognition completion through the controller, final-result ordering, finalization cancellation, and deadlines without permissions or microphone access. The same adapter sources compile in the Swift package test target; only iOS audio-session configuration is conditional. Hardware permissions and actual recognition still need a physical-phone check.

## Response playback

The controller owns one receive loop over `ConversationTransport.receive()`. `WebSocketTransport` keeps ownership of the URLSession reader. The controller accepts `agent.text`, sequential zero-based `agent.audio` chunks, then a matching `agent.done`. Binary frames, malformed JSON, extra fields, invalid types/order, empty or unaligned PCM, and unsupported session states disconnect with a generic log. Frame, chunk, and total PCM limits are 32768 UTF-8 bytes, 16384 decoded bytes, and 8 MiB. Transcript contents and audio are never written to disk or logs.

`ConversationPlayer.play(pcm:)` completes only after playback finishes. The app's `PCMPlayer` converts 24 kHz mono signed 16-bit little-endian PCM to an AVAudioPCMBuffer and schedules it on AVAudioPlayerNode using the played-back completion callback. Audio engine changes or audio-session interruptions fail the turn. Disconnect cancels receive/playback work, stops the player, and discards buffered response data. Manual Connect starts a fresh session, with no reconnect, resume, or barge-in.

Response tests cover decoding and ordering, exact chunk and buffer limits, count mismatches, recording gating, repeated turns, playback failure, socket loss, disconnect cleanup, and stale completion after manual reconnect. Physical speaker output still requires the phone check described in the follow-up verification issue.
