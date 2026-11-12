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
# Choose an available simulator from xcrun simctl list devices available.
xcodebuild -project ios/Convoke/Convoke.xcodeproj -scheme Convoke \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.2' \
  CODE_SIGNING_ALLOWED=NO test
```

`swift test` in `ios/Convoke` needs macOS 26 because `SpeechAnalyzer` requires it. Controller and adapter tests use fakes and need no microphone, speech model, phone or external server.

### Recorded automated results

Status values are `Pending` (not run), `Pass`, or `Fail`. Only the owner changes a row from Pending, and only after running the command. Do not copy results from another machine.

| Check | Where run | Status | Output / notes |
| --- | --- | --- | --- |
| `swift build` and `swift test` in `server/` | Mac, macOS 27.0.1 | Pass | Exit 0; 35 tests, 2 skipped, 0 failures. Optional real Kokoro and system-voice smoke tests not enabled. |
| `swift test` in `ios/Convoke` | Mac, macOS 27.0.1 | Pass | Exit 0; 64 tests, 0 failures. |
| `xcodebuild ... build-for-testing` (simulator) | Mac, Xcode 27.2 | Pass | Exit 0; `** TEST BUILD SUCCEEDED **`. Compiled tests only; no simulator test execution. |
| `xcodebuild ... -sdk iphoneos build` (device, unsigned) | Mac, Xcode 27.2 | Pass | Exit 0; `** BUILD SUCCEEDED **`. |
| `xcodebuild ... test` (simulator execution) | Mac, Xcode 27.2; iPhone 17 simulator, iOS 27.2 | Pass | Exit 0; 58 tests, 0 failures; `** TEST SUCCEEDED **`. |
| `node --test .sandcastle/models.test.mts` | Linux container (#19 implementation) | Pass | 7 tests, 7 pass, 0 fail |
| Protocol JSON syntax check | Linux container (#19 implementation) | Pass (vacuous) | 0 files under `protocol/`; nothing to validate |

The Linux container used for the documentation task has no Swift, Xcode or Apple SDKs, so no Swift check was run there.

The four Mac checks above were run locally by the coding agent at the owner's request on 2026-11-11 at 22:41 MST, against commit `73e6d960b7ed2c55583ab1d75f3b37ab94428569`, with documentation edits and an untracked `bash.sh` present. Environment: macOS 27.0.1, Xcode 27.2 (27B52), Apple Swift 6.4.2. Full command output is in `/tmp/convoke-mac-checks.kpGeOc/{server,ios-package,simulator,device}.log`; these local temporary files are not committed.

Simulator tests were subsequently executed locally on 2026-11-11 at 23:00 MST against commit `20ad871`, using destination `platform=iOS Simulator,id=E58183BA-D034-4773-B504-D1053EE3141E`. Output: `/tmp/convoke-mac-checks.kpGeOc/simulator-tests.log`. All five Mac checks now pass.

## Physical-iPhone acceptance checklist

Run on the physical iPhone against the Mac server, after the automated checks. Every row starts as Pending. Record the date, iPhone model, iOS version, Mac/Xcode version, commit SHA, and per-row result. Never paste transcript text or audio into notes; describe outcomes only (for example "second turn played").

The owner confirms that all 23 physical-device checklist checks passed, including the 11 detailed checks not covered by the initial grouped report. All physical results below are owner-reported, not independently observed by the coding agent. All five required Mac automated checks, including simulator execution, also passed as recorded above. All required checklist rows are now Pass. The voice backend used for the physical session remains unconfirmed.

Recorded test environment:

| Field | Value |
| --- | --- |
| Date | November 11 2026 |
| Commit SHA | 73e6d96 |
| iPhone model / iOS version | iPhone 17 / iOS 27.0.1 |
| Mac / macOS / Xcode version | Apple M4 Pro / Golden Gate 27.0.1 / 27.2 |
| Agent endpoint and model | Ollama / Llama3.2 |
| Voice (macOS or Kokoro) | Not confirmed by owner |

Result column: `Pending`, `Pass` or `Fail`, with notes.

### Connection and permissions

| # | Check | Expected | Result |
| --- | --- | --- | --- |
| 1 | Enter `ws://<Mac Tailscale IP>:8080/conversation`, relaunch the app | URL is remembered; it is the only saved setting | Pass |
| 2 | Tap Connect | Status Connected. The microphone indicator is not on and no permission prompt appears | Pass, owner-reported physical-device check |
| 3 | Tap Start conversation on first run | Microphone permission prompt appears; allow it | Pass, owner-reported physical-device check |
| 4 | First run with no speech model installed | "Preparing speech recognition" shows while the model downloads, then Listening | Pass, owner-reported physical-device check |
| 5 | Tap End conversation, then Start conversation again with the model installed | No download state; Listening begins promptly | Pass |

### Hands-free turns

| # | Check | Expected | Result |
| --- | --- | --- | --- |
| 6 | Say a short sentence and stay silent | Submission about 2.5 s after you stop; status goes Finishing, Waiting for reply, Playing reply | Pass, owner-reported physical-device check |
| 7 | Pause briefly (under 2.5 s) mid-sentence, then continue | One turn, not split at the pause | Pass, owner-reported physical-device check |
| 8 | Stay silent before speaking for 10 s or more | No submission and no silence countdown until speech is heard | Pass |
| 9 | Wait for the full reply | Complete reply plays, then status returns to Listening without touching the phone | Pass, owner-reported physical-device check |
| 10 | Complete at least three consecutive turns without touching the phone | Each turn is sent, answered and played; the agent has context from earlier turns | Pass, owner-reported physical-device check |
| 11 | Keep talking for more than 60 s | The turn is submitted at the 60 s limit (note whether any words were sent) | Pass |
| 12 | Stay silent for 60 s | Nothing is sent; the app keeps listening, no error | Pass |
| 13 | Confirm there is no Submit button and no volatile/partial text is sent (compare spoken words with the agent's reaction) | Only finalized words are submitted | Pass |

### End conversation

| # | Check | Expected | Result |
| --- | --- | --- | --- |
| 14 | Tap End conversation while Listening | Listening stops, microphone indicator turns off, status Connected, connection stays open | Pass, owner-reported physical-device check |
| 15 | Tap End conversation while Playing reply | Audio stops immediately; no new listening; connection stays open | Pass, owner-reported physical-device check |
| 16 | Tap End conversation while Waiting for reply | Connection closes (protocol cannot cancel a turn); status Disconnected | Pass, owner-reported physical-device check |
| 17 | After 14 or 15, tap Start conversation again | A new conversation starts without reconnecting | Pass |

### Errors and lifecycle

| # | Check | Expected | Result |
| --- | --- | --- | --- |
| 18 | Deny microphone permission in Settings, tap Start conversation | Visible message that microphone access is denied; app returns to Connected; no retry loop | Pass |
| 19 | Stop the server while Listening or Playing | Visible connection error; app shows Disconnected; no automatic reconnect | Pass |
| 20 | Background the app during a conversation | Capture and playback stop and the connection closes; no background audio | Pass, owner-reported physical-device check |
| 21 | Tap Disconnect during a conversation | Everything stops; status Disconnected | Pass, owner-reported physical-device check |
| 22 | Speak a very long turn if possible (over 4096 UTF-8 bytes) | "That was too long to send" appears and listening continues; nothing is sent | Pass |
| 23 | Review the Xcode device console and server log after a session | No transcript or reply text and no audio in either log | Pass |

## Reporting

Copy this document into the PR or ticket with the Result and results-table columns filled in. Slice acceptance is complete only when every automated row and every checklist row is `Pass`. A `Fail` or an unrun row must stay visible; do not edit expected results to match observed behavior.
