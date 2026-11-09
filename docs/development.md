# Spoken-echo development and verification

This guide covers the developer-only [first slice](first-slice.md). The Mac server, iPhone capture, and sequential playback implementations are already on `main`. Real agents, Kokoro, background calls, and production deployment are out of scope.

## Prerequisites

- A Mac running macOS 13 or later with a built-in speech voice installed. Use System Settings > Accessibility > Spoken Content to check voices if synthesis fails. The voice settings name can vary by macOS version.
- Full Xcode with an iOS SDK and simulator runtime. The committed server dependency resolution requires Swift 6.4 or later, even though the package manifest declares tools version 5.9. Check `swift --version`, `xcodebuild -version`, and `xcode-select -p`; the active developer directory must point to Xcode, not only Command Line Tools.
- A physical iPhone running iOS 16 or later, paired with Xcode, with Developer Mode enabled and a development signing team available. Follow Xcode's pairing and trust prompts. Enable Developer Mode under Settings > Privacy & Security when prompted.
- Tailscale running on both the Mac and iPhone, with policy permitting the phone to reach the Mac's selected TCP port. Obtain the Mac's numeric Tailscale IP from its Tailscale app or `tailscale ip -4` if the CLI is installed.
- Internet access for initial Swift dependency resolution and, when required by Apple Speech, recognition.

The checked-in Xcode project and shared scheme are ready to open. XcodeGen is only needed when changing `ios/Convoke/project.yml`, not for normal builds.

## Network and privacy restrictions

The server binds `0.0.0.0`, has no authentication, and uses cleartext WebSockets. Before starting it, restrict the chosen port using the Mac's firewall/network controls and Tailscale policy. Tailscale policy does not block access through the Mac's Wi-Fi, Ethernet, or other reachable interfaces. Do not forward this port, publish it through a tunnel, or run the server on an untrusted network. Stop it when testing ends.

The app's broad ATS exception supports developer-configured numeric IPs on iOS 16. It is not a production security configuration. No bearer token is required.

Apple speech recognition may send microphone audio to Apple. The app sends only the final recognized text to the Mac. Convoke holds transcripts and generated audio in memory and does not write their contents to its logs or files. The server synthesizes with the default macOS voice. Test with non-sensitive phrases and do not paste recognized speech into issue reports.

## Start the Mac server

From the repository root:

```sh
cd server
swift package resolve
swift run ConvokeServer serve
```

The default endpoint is `ws://<Mac Tailscale IP>:8080/conversation`. For another port:

```sh
PORT=9090 swift run ConvokeServer serve
```

Change the phone URL and network rules to match. Stop the server with Control-C. Audio synthesis finishes in memory before chunk delivery; this slice does not promise real-time synthesis.

See [the server README](../server/README.md) for message limits, turn deadlines, and protocol details.

## Install and connect the iPhone app

1. Open `ios/Convoke/Convoke.xcodeproj` in Xcode and select the shared `Convoke` scheme.
2. Select the Convoke app target, then Signing & Capabilities. Choose your development team. If Xcode requires a unique bundle identifier, use one registered to your team locally. Do not commit personal signing settings.
3. Select the paired physical iPhone as the run destination and run the app. Complete any device trust or signing prompts.
4. Keep the app in the foreground. Enter `ws://<Mac Tailscale IP>:8080/conversation`, replacing the placeholder with the actual numeric IP and using your chosen port. The URL persists between launches.
5. Tap Connect and wait for Ready. Tap Start recording and allow Microphone and Speech Recognition. Allow Local Network access if iOS asks. Denied permissions can be changed in iOS Settings for Convoke; speech recognition access is also listed under Privacy & Security > Speech Recognition.
6. Speak, then tap Submit recording. Expect Waiting, then Playing, then Ready. The spoken response begins with "You said:" and contains the recognized words. Recording remains disabled while finalizing recognition, waiting, and playing.

Capture stops automatically after 60 seconds, then waits up to five seconds for the final result. Empty results return to Ready without a server turn. Permission or recognition errors log a generic failure and allow another capture while connected. If Apple ends recognition early, the app discards that capture rather than submitting a partial result.

Disconnect stops capture/playback and discards pending data. Backgrounding also disconnects. Socket loss, invalid messages, synthesis failure, or playback failure require manual Connect; old turns never resume. A dead connection may take several seconds to detect through the transport's ping timeout.

## Automated checks

Run from the repository root on a Mac. Server tests bind only loopback on ephemeral ports and do not need a separately running server. Client tests use injected recognition and playback; macOS transport tests start their own loopback peers.

```sh
(cd server && swift test)

# Also verify non-silent PCM from the installed macOS voice across two turns.
(cd server && CONVOKE_TEST_SYSTEM_VOICE=1 swift test)

(cd ios/Convoke && swift test)

# Compile both the app and iOS test bundle without running a simulator.
xcodebuild -project ios/Convoke/Convoke.xcodeproj -scheme Convoke \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build-for-testing

# Select an available iPhone simulator name or use its id in the destination.
xcrun simctl list devices available
xcodebuild -project ios/Convoke/Convoke.xcodeproj -scheme Convoke \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  CODE_SIGNING_ALLOWED=NO test

# Check physical-device compilation only; this does not install or run the app.
xcodebuild -project ios/Convoke/Convoke.xcodeproj -scheme Convoke \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

### Recorded automated verification

Run on 2026-11-08 against main commit `87c96c0`, before these documentation-only changes, using Xcode 27.2 and Apple Swift 6.4.2 on an arm64 Mac running macOS 27.0.1.

| Check | Result |
| --- | --- |
| Server `swift test` | 26 tests, 0 failures, 1 expected skip for opt-in system voice |
| Server with `CONVOKE_TEST_SYSTEM_VOICE=1` | 26 tests, 0 failures, no skips; real voice and two loopback WebSocket turns passed |
| Client package `swift test` | 41 tests, 0 failures, including macOS transport integration |
| iOS simulator `xcodebuild test` | 35 tests, 0 failures on iPhone 18 Pro, iOS 27.0; app and test bundle built successfully |
| Unsigned `iphoneos` build | Passed; no installation or physical execution |

The simulator suite excludes the six macOS-only loopback transport tests, accounting for the count difference. Xcode emitted test-only linker warnings because its XCTest libraries target iOS 17 while the test target declares iOS 16; execution on the installed iOS 27 runtime passed. Execution on the minimum iOS 16 version was not verified. These checks do not prove microphone permissions, real speech recognition, audible speaker playback, or iPhone-to-Mac Tailscale connectivity.

## Physical-iPhone acceptance checklist

**Passed on 2026-11-08**, reported by the developer using an iPhone 17 running iOS 27.0.1, a Mac running macOS 27.0.1, Xcode 27.2, and port 8080. The source revision was `52df9b6`; Xcode also changed local signing, deployment-target, and scheme settings for the device build. The automated checks were also rerun at `52df9b6`: server with system voice, 26 passed; client package, 41 passed; iPhone 18 Pro simulator, 35 passed. The device test target could not run on hardware because it is tool-hosted without a host application. The physical checks below were performed manually.

Do not include private IPs, transcripts, or audio in reports.

| Check | Procedure and expected result | Result |
| --- | --- | --- |
| Spoken echo over Tailscale | With both devices connected to Tailscale, connect using the Mac's Tailscale IP. Record a short non-sensitive phrase and submit. Hear "You said:" followed by the recognized words from the iPhone speaker. | Passed |
| Sequential turns and gating | Without reconnecting, submit a second distinct phrase. During Waiting and Playing, verify Start recording is disabled. It becomes available only after playback ends. Hear the second echo. | Passed |
| Interrupted turn and fresh reconnect | Start a turn, then stop the Mac server with Control-C while the phone is recording, waiting, or playing. Verify the phone reaches Disconnected and capture/playback stops. Restart the server, tap Connect manually, and complete a new turn. No old response resumes or plays. | Passed |
| Tailscale path interruption | Start a turn and interrupt Tailscale connectivity using the phone's Tailscale controls. Returning to Convoke also disconnects because it was backgrounded. Restore Tailscale, return to Convoke, manually Connect, and complete a new turn without replaying the old one. Use the server-stop check above to test socket loss while the app stays foregrounded. | Passed |

Additional useful checks: leave capture running to confirm automatic submission at 60 seconds, try silence to confirm empty recognition is discarded, deny permissions and retry after restoring them, and background the app during playback to confirm cleanup. Recognition may fail on silence rather than return an empty final result; either outcome should return a connected session to Ready without sending text.

The physical-device checks above cover the first-slice acceptance criteria. The optional checks remain unverified.

## Troubleshooting

- Cannot connect: confirm the server is running, the URL uses `ws://`, the numeric Mac Tailscale IP and port are correct, and the path is `/conversation`. Check both Tailscale status and port access policy. Do not solve this by exposing the port publicly.
- Stays Ready after capture: check speech/microphone permissions and generic Xcode console errors. Empty, interrupted, or failed recognition never sends a partial transcript.
- Disconnects while waiting: check the Mac console for synthesis, conversion, or turn-timeout errors. Retry manually after fixing the cause.
- Playing but no audible sound: raise the phone's media volume and check its audio output route for headphones or Bluetooth. Speaker behavior must be checked on hardware.
- Unexpected disconnect when switching apps: foreground-only behavior is intentional. Return and tap Connect for a new session.

The [iPhone README](../ios/Convoke/README.md) describes capture, transport monitoring, playback, and project generation in more detail.
