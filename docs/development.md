# Convoke developer setup and verification

Developer-only. There is no authentication or TLS on the server or the app. Use a trusted tailnet and restrict access on the Mac (firewall, tailnet ACLs). Tailscale does not protect other reachable interfaces.

Scope of this guide: slice 3, hands-free foreground turns (parent ticket #17; implementation #18; this checklist #19). Out of scope: barge-in, streaming TTS, background calls, CallKit, reconnect/resume, authentication, transcript storage, manual Submit, cloud recognition fallback.

## Requirements

- A Mac with Xcode that supports iOS 26 and macOS 26 SDKs, plus `xcodegen` if the project configuration changes.
- Swift 6.4 or later for `server/` (see `server/Package.resolved`).
- A physical iPhone on iOS 26 or later with Developer Mode enabled, signed into the same Tailscale tailnet as the Mac.
- An OpenAI-compatible chat endpoint reachable from the Mac (for example Ollama or llama.cpp). Optional: the Kokoro sidecar for speech (see `server/README.md`).

## Mac setup

1. Find the Mac's numeric Tailscale IP: `tailscale ip -4`.
2. Start the agent endpoint and the server (details and variables in `server/README.md`):

   ```sh
   export CONVOKE_AGENT_BASE_URL=http://localhost:11434/v1
   export CONVOKE_AGENT_MODEL=llama3.2
   # Optional Kokoro, bound to 127.0.0.1 only:
   # export CONVOKE_KOKORO_URL=http://127.0.0.1:8880
   cd server
   swift run ConvokeServer serve
   ```

3. Confirm the server listens on `0.0.0.0:8080` and that the Mac firewall only allows the tailnet.
4. Open `ios/Convoke/Convoke.xcodeproj`, scheme `Convoke`. Select your development team under Signing & Capabilities (signing is not tied to any account), choose the iPhone as destination, and run.

## Automated checks

Run on the Mac. Record the exact output in the results table below.

```sh
cd server && swift build && swift test
cd ios/Convoke && swift test
xcodebuild -project ios/Convoke/Convoke.xcodeproj -scheme Convoke \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build-for-testing
xcodebuild -project ios/Convoke/Convoke.xcodeproj -scheme Convoke \
  -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

`swift test` in `ios/Convoke` needs macOS 26 because `SpeechAnalyzer` requires it. Controller and adapter tests use fakes and need no microphone, speech model, phone or external server.

### Recorded automated results

Status values are `Pending` (not run), `Pass`, or `Fail`. Only the owner changes a row from Pending, and only after running the command. Do not copy results from another machine.

| Check | Where run | Status | Output / notes |
| --- | --- | --- | --- |
| `swift build` and `swift test` in `server/` | Mac | Pending | |
| `swift test` in `ios/Convoke` | Mac, macOS 26 | Pending | |
| `xcodebuild ... build-for-testing` (simulator) | Mac | Pending | |
| `xcodebuild ... -sdk iphoneos build` (device, unsigned) | Mac | Pending | |
| `node --test .sandcastle/models.test.mts` | Linux container (#19 implementation) | Pass | 7 tests, 7 pass, 0 fail |
| Protocol JSON syntax check | Linux container (#19 implementation) | Pass (vacuous) | 0 files under `protocol/`; nothing to validate |

The Linux container used for the documentation task has no Swift, Xcode or Apple SDKs, so no Swift check was run there.

## Physical-iPhone acceptance checklist

Run on the physical iPhone against the Mac server, after the automated checks. Every row starts as Pending. Record the date, iPhone model, iOS version, Mac/Xcode version, commit SHA, and per-row result. Never paste transcript text or audio into notes; describe outcomes only (for example "second turn played").

Test environment (fill in):

| Field | Value |
| --- | --- |
| Date | |
| Commit SHA | |
| iPhone model / iOS version | |
| Mac / macOS / Xcode version | |
| Agent endpoint and model | |
| Voice (macOS or Kokoro) | |

Result column: `Pending`, `Pass` or `Fail`, with notes.

### Connection and permissions

| # | Check | Expected | Result |
| --- | --- | --- | --- |
| 1 | Enter `ws://<Mac Tailscale IP>:8080/conversation`, relaunch the app | URL is remembered; it is the only saved setting | Pending |
| 2 | Tap Connect | Status Connected. The microphone indicator is not on and no permission prompt appears | Pending |
| 3 | Tap Start conversation on first run | Microphone permission prompt appears; allow it | Pending |
| 4 | First run with no speech model installed | "Preparing speech recognition" shows while the model downloads, then Listening | Pending |
| 5 | Tap End conversation, then Start conversation again with the model installed | No download state; Listening begins promptly | Pending |

### Hands-free turns

| # | Check | Expected | Result |
| --- | --- | --- | --- |
| 6 | Say a short sentence and stay silent | Submission about 2.5 s after you stop; status goes Finishing, Waiting for reply, Playing reply | Pending |
| 7 | Pause briefly (under 2.5 s) mid-sentence, then continue | One turn, not split at the pause | Pending |
| 8 | Stay silent before speaking for 10 s or more | No submission and no silence countdown until speech is heard | Pending |
| 9 | Wait for the full reply | Complete reply plays, then status returns to Listening without touching the phone | Pending |
| 10 | Complete at least three consecutive turns without touching the phone | Each turn is sent, answered and played; the agent has context from earlier turns | Pending |
| 11 | Keep talking for more than 60 s | The turn is submitted at the 60 s limit (note whether any words were sent) | Pending |
| 12 | Stay silent for 60 s | Nothing is sent; the app keeps listening, no error | Pending |
| 13 | Confirm there is no Submit button and no volatile/partial text is sent (compare spoken words with the agent's reaction) | Only finalized words are submitted | Pending |

### End conversation

| # | Check | Expected | Result |
| --- | --- | --- | --- |
| 14 | Tap End conversation while Listening | Listening stops, microphone indicator turns off, status Connected, connection stays open | Pending |
| 15 | Tap End conversation while Playing reply | Audio stops immediately; no new listening; connection stays open | Pending |
| 16 | Tap End conversation while Waiting for reply | Connection closes (protocol cannot cancel a turn); status Disconnected | Pending |
| 17 | After 14 or 15, tap Start conversation again | A new conversation starts without reconnecting | Pending |

### Errors and lifecycle

| # | Check | Expected | Result |
| --- | --- | --- | --- |
| 18 | Deny microphone permission in Settings, tap Start conversation | Visible message that microphone access is denied; app returns to Connected; no retry loop | Pending |
| 19 | Stop the server while Listening or Playing | Visible connection error; app shows Disconnected; no automatic reconnect | Pending |
| 20 | Background the app during a conversation | Capture and playback stop and the connection closes; no background audio | Pending |
| 21 | Tap Disconnect during a conversation | Everything stops; status Disconnected | Pending |
| 22 | Speak a very long turn if possible (over 4096 UTF-8 bytes) | "That was too long to send" appears and listening continues; nothing is sent | Pending |
| 23 | Review the Xcode device console and server log after a session | No transcript or reply text and no audio in either log | Pending |

## Reporting

Copy this document into the PR or ticket with the Result and results-table columns filled in. Slice acceptance is complete only when every automated row and every checklist row is `Pass`. A `Fail` or an unrun row must stay visible; do not edit expected results to match observed behavior.
