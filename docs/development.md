# Convoke developer setup and verification

Developer-only. There is no authentication or TLS on the server or the app. Use a trusted tailnet and restrict access on the Mac (firewall, tailnet ACLs). Tailscale does not protect other reachable interfaces.

This guide keeps the historical slice 3 checks and #23 complete-reply Kokoro baseline separate from [Slice 4 streaming verification](#slice-4-streaming-verification), tracked by #30 under epic #25. Streaming TTS is now implemented; its acceptance is blocked by the [Mac follow-up failures](#mac-follow-up-after-owner-authorized-ssh) and pending physical checks. Barge-in, agent-text streaming, sentence splitting, background calls, CallKit, reconnect/resume, authentication, transcript storage, manual Submit and cloud recognition fallback remain out of scope.

## Requirements

- A Mac with Xcode that supports iOS 26 and macOS 26 SDKs, plus `xcodegen` if the project configuration changes.
- Swift 6.4 or later for `server/` (see `server/Package.resolved`).
- A physical iPhone on iOS 26 or later with Developer Mode enabled, signed into the same Tailscale tailnet as the Mac.
- An OpenAI-compatible chat endpoint reachable from the Mac (for example Ollama or llama.cpp).
- For Kokoro verification, Docker running on the Mac and the CPU sidecar in `server/README.md`. Kokoro is optional for ordinary development but required for Slice 4 acceptance. The #23 checks below are historical baseline evidence.

## Mac setup

1. Find the Mac's numeric Tailscale IP: `tailscale ip -4`.
2. Start the agent endpoint and the server in separate Rex terminals, not tmux. See `server/README.md` for the localhost-only sidecar and variables:

   ```sh
   export CONVOKE_AGENT_BASE_URL=http://localhost:11434/v1
   export CONVOKE_AGENT_MODEL=llama3.2
   # For Kokoro verification, start the Docker sidecar first, as in server/README.md.
   export CONVOKE_KOKORO_URL=http://127.0.0.1:8880
   unset CONVOKE_KOKORO_VOICE # default af_heart
   cd server
   swift run ConvokeServer serve
   ```

   To use the macOS voice instead, unset `CONVOKE_KOKORO_URL` before starting Convoke. This does not count as Kokoro verification. Restart the server whenever changing its voice configuration.

3. Confirm the server listens on `0.0.0.0:8080` and that the Mac firewall only allows the tailnet.
4. Open `ios/Convoke/Convoke.xcodeproj`, scheme `Convoke`. Select your development team under Signing & Capabilities (signing is not tied to any account), choose the iPhone as destination, and run.

## Automated checks

Run these commands from the repository root. Default suites need no model, microphone, phone or external service. Loopback integration tests start their own peers.

| Tier | Local command | Prerequisites and CI check | Establishes / excludes |
| --- | --- | --- | --- |
| Server | `swift build --package-path server` then `swift test --package-path server` | Swift 6.4+ for committed dependency resolution. CI uses Ubuntu 24.04, `swift:6.4.2-noble`; **Server build and tests (Linux)** in `Swift Linux` | Protocol, HTTP/source/socket gates, limits and cancellation regressions. Linux excludes macOS voice code; real Kokoro is an explicit opt-in skip. Linux alone is not Mac cancellation evidence; see the hosted Mac result below. |
| Mac server | `swift build --package-path server` then `swift test --package-path server` | **Server build and tests (macOS)** in `Swift macOS`; hosted `xcode-27` preview image, explicitly selected `/Applications/Xcode_27.2.app` (Apple Swift 6.4.2). | Full server suite including AVAudioConverter and real upstream-close assertions; optional Kokoro and system voice remain skipped. Not iOS package or physical-device acceptance. Hosted build/tests Pass after the separately merged peer-observation fixture correction (see evidence below). |
| Limited portable core | `bash ios/Convoke/scripts/test-portable-core.sh` | Bash and Swift 6.0+; verified in CI with Swift 6.4.2. **Limited portable core (Combine stand-in)** in `Swift Linux` | Controller, validator, queue and lifetime subset in a temporary package with a test-only Combine stand-in. Not Combine publication, Apple adapters, capture or AVAudioEngine. |
| Apple | `bash ios/Convoke/scripts/test-apple.sh` | macOS 26+, full selected Xcode 26+, Swift 6.2+, iPhoneOS/iPhoneSimulator SDKs 26+, Python 3, Git and an installed available iPhone simulator on iOS 26+. **capture** in `iOS` | Full real-Combine Apple package tests, actual simulator `test` execution, then unsigned generic iPhoneOS compilation. No server suite, opt-in engine, real speech or physical audio evidence. An unsigned build is not a signed install or device test. |

The Apple package needs macOS 26 for `SpeechAnalyzer`; the server's Swift 6.4 requirement is separate. Do not downgrade SDKs to make a check pass. The Apple script rejects incompatible tools/OS/SDKs and missing or invalid simulator destinations with a nonzero exit, not a passing skip. It chooses the newest installed compatible runtime, then stable device name/UDID order, without downloading runtimes. To override it:

```sh
xcrun simctl list devices available
# Set this to an actual available iPhone UDID from the listing.
SIMULATOR_UDID=your-installed-iphone-udid bash ios/Convoke/scripts/test-apple.sh
```

The script resolves paths independently of the caller's directory. `APPLE_TEST_OUTPUT_DIR` optionally sets the parent of a unique `convoke-apple.*` results directory, otherwise under `$TMPDIR` or `/tmp`. After prerequisite validation, it prints SHA, dirty-tree state, environment and destination, retains available stage output on success or failure, including `driver.log`, `package.log`, `simulator.log`, `simulator-summary.json`, `device-build.log` and result bundles, and reports its exit status and results path. Prerequisite errors before directory creation go to stderr. A failed stage stops later stages; package/simulator summaries must contain nonzero passing tests. Inspect the failing stage, not just a build-success marker. The portable script prints XCTest output and deletes its temporary package on exit; retain terminal output if needed.

See the implemented [Linux workflow](../.github/workflows/swift-linux.yml), [Mac server workflow](../.github/workflows/swift-macos.yml), [Apple workflow](../.github/workflows/ios.yml) and [Apple script](../ios/Convoke/scripts/test-apple.sh). These workflows run on matching pull requests and pushes to main. The Mac server workflow watches `server/**`, `protocol/**` and itself; it saves available environment, build and test logs as `mac-server-results-<SHA>` for 14 days, including on failure. A failed build stops the test step; a failed test fails the job. Build and test logs include command exit codes, preserved by EXIT traps without masking failures. The [hosted image inventory](https://github.com/actions/runner-images/blob/c0f5743aeac97a0d687047af9f309b34c254b261/images/macos/xcode-27-arm64-Readme.md), retrieved during this implementation, lists Xcode 27.2 (27B52), `/Applications/Xcode_27.2.app` and macOS SDK 27.2; the [preview announcement](https://github.com/actions/runner-images/issues/14404) documents the `xcode-27` label. Xcode 27.2 provided Swift 6.4.2 in the historical Mac run below, meeting the package's Swift tools 5.9 and resolved dependencies' Swift 6.4+ requirements. The preview image can change or have limited capacity: a missing selected Xcode must fail, not silently use the iOS toolchain. Actual hosted execution is recorded below, including retained initial failures and the subsequent passing result after [PR #59](https://github.com/markdlabrecque/convoke/pull/59) corrected the test peer's read suppression. This does not close [#27](https://github.com/markdlabrecque/convoke/issues/27) or physical acceptance. Linux watches `server/**`, `ios/**`, `protocol/**` and its own workflow; Apple watches `ios/**`, `protocol/**` and its own workflow. A docs-only change outside those paths does not trigger them. Apple CI also checks fake-tool failure propagation and an invalid simulator override, and uploads `apple-results-<SHA>` diagnostics even on failure, retained for 14 days. Default Apple checks explicitly clear optional test environment variables; setting an opt-in flag on this shared command does not enable real-engine tests.

### Hosted Mac server gate evidence (issue #48)

#### Passing result after peer-observation correction

[Run 43995994730](https://github.com/markdlabrecque/convoke/actions/runs/43995994730), clean checkout `a699409f664af49777f788e5f75518fdc504d881` (PR head `0d09739`), **Pass**: build exit 0 (270.57 s); full server tests exit 0, **58 tests, 2 optional skips, 0 failures** (6.552 s). All **7 StreamingFailureTests** pass with the original three-second actual peer-close assertions; all **4 SpeechAudioAccumulatorTests** pass. Environment: macOS 27.0.1 (26A434), arm64, Xcode 27.2 (27B52), Apple Swift 6.4.2. Kokoro and system voice remain skipped, not passed. Environment/build/test logs were downloaded and inspected in [artifact 14290218759](https://github.com/markdlabrecque/convoke/actions/runs/43995994730/artifacts/14290218759), retained 14 days until December 1, 2026 at 01:36:50 UTC.

The initial production-lifetime hypothesis was not supported: explicit request cancellation also failed the same five assertions in [run 43994565066](https://github.com/markdlabrecque/convoke/actions/runs/43994565066). That production experiment was fully reverted. The actual correction in [PR #59](https://github.com/markdlabrecque/convoke/pull/59), merged as `99530fd04bb7f75266933c9cecedaa6a1abad066`, is fixture-only: disable pipelining assistance on the single-request upstream peer. SwiftNIO's `HTTPServerPipelineHandler` suppresses reads while `.responseEndPending`; this fixture deliberately leaves its response unfinished, preventing Darwin from observing the TCP close. Keeping reads enabled restores observation; it does not fulfill the expectation or close the fixture artificially. Production code is unchanged. A local Linux negative control that deliberately retained the open request still failed the unchanged close assertion after three seconds (exit 1); the mutation was restored and is not committed. Restored full Linux suite: 53 tests, 1 optional skip, 0 failures.

This supersedes the earlier attribution of these five timeouts to a proven production cancellation defect. It does not retrospectively change historical runs, fix the optional simulator engine issue, or close #27/#30 acceptance. The gate's final post-rebase SHA still requires its own passing CI before merge.

#### Initial failed run (retained historical evidence)

[PR #57](https://github.com/markdlabrecque/convoke/pull/57), [hosted run 43979034219](https://github.com/markdlabrecque/convoke/actions/runs/43979034219), [Mac server job](https://github.com/markdlabrecque/convoke/actions/runs/43979034219/job/133690392579): **Fail; do not merge while red.** This is real hosted integration execution, not the earlier Linux/static verification.

| Evidence | Observed result |
| --- | --- |
| Revision | PR head `2de63ab1088ad3f66c82f770bb92755ced4816e4`; checkout/PR merge SHA `27ea03df4a504cd4e3797d1c500a45a6849fffb7`; clean tracked/untracked status in environment log |
| Hosted environment | `xcode-27`, macOS 27.0.1 (26A434), arm64, Xcode 27.2 (27B52), Apple Swift 6.4.2 (`swiftlang-6.4.2.1.9`), target `arm64-apple-macosx27.0.0` |
| `swift build --package-path server` | Exit **0**, build complete in 285.60 s |
| `swift test --package-path server` | Exit **1**, XCTest **56 tests, 2 optional skips, 5 assertion failures**, 28.052 s total. The subsequent Swift Testing zero-test summary is not the suite result. |
| `SpeechAudioAccumulatorTests` | All **4** converter/accumulator cases passed, 0.098 s |
| `StreamingFailureTests` | All **7** methods executed; **5** upstream HTTP-close assertion failures across 4 methods, 22.627 s |
| Optional skips | Real Kokoro sidecar and system voice skipped by default; no audio hardware, real sidecars or credentials enabled |
| Failure artifacts | Downloaded and inspected `environment.log`, `build.log`, `test.log` from [artifact 14283201882](https://github.com/markdlabrecque/convoke/actions/runs/43979034219/artifacts/14283201882), named `mac-server-results-27ea03df4a504cd4e3797d1c500a45a6849fffb7`; 14-day retention, expires November 30, 2026 at 23:32:34 UTC. Both command exit codes are retained. |

The unchanged three-second `upstream HTTP channel closed` expectation failed in `testCancellationDuringBodyReadClosesRealUpstreamRequest`, `testCancellationDuringSlowWriteClosesRealUpstreamRequest`, `testFailedWriteClosesRealUpstreamRequest`, and both disconnect/deadline iterations of `testConversationDisconnectAndTimeoutCancelRealRequest` (source lines 138, 32, 46 and 161 respectively). Backpressure, stalled-final-done deadline and truncated-body methods passed. This reproduced the historical [#27 cancellation failure](https://github.com/markdlabrecque/convoke/issues/27), initially attributed to production lifetime; the peer-observation correction and passing evidence above supersede that diagnosis without changing issue acceptance. No retry, timeout increase, assertion change, filtering or error suppression was used. The failed test failed the job, while the always-run artifact upload succeeded.

Local Linux Swift 6.4.2 verification on the same PR head: build exit 0 (43.97 s); full server tests exit 0, 51 tests, 1 Kokoro skip, 0 failures (7.968 s), all 7 StreamingFailureTests included. Apple converters and system voice are absent on Linux, not passed. Actionlint 1.7.12 passed with the documented preview label supplied via external label configuration (its built-in list lacks `xcode-27`); all embedded shell bodies passed `bash -n`. Synthetic exits 0 and 42 verified shell failure propagation and retained exit codes, not platform behavior. iOS checks and physical-device acceptance are separate and were not rerun or changed by this task.

### Optional real dependencies and known blockers

These are not mandatory passing PR gates. Use the existing [localhost-only Kokoro/Rex setup](../server/README.md#kokoro-speech-optional-sidecar), pinned to `ghcr.io/remsky/kokoro-fastapi-cpu:v0.10.0`, bound only to `127.0.0.1:8880`, with `af_heart`. Do not add service automation or model downloads to default checks. After the optional sidecar is healthy:

```sh
CONVOKE_TEST_KOKORO_URL=http://127.0.0.1:8880 CONVOKE_KOKORO_VOICE=af_heart \
  swift test --package-path server --filter testKokoroSidecarSmoke
```

That smoke uses a stub agent and proves non-silent source/wire PCM, not real agent generation or audible iPhone playback. For optional system-voice and real-engine commands, see the [Mac reproduction commands and results](#mac-follow-up-after-owner-authorized-ssh). Silent engine buffers are not acoustic evidence. The [historical Mac upstream cancellation failures](#cancellation-failure-details) are superseded by the hosted readable-peer result above. The [opt-in simulator audio initialization failure](#simulator-audio-initialization-blocker) remains unresolved; neither a server pass nor default Apple skips fix or waive it.

### Current CI verification

Inspected actual run logs on November 15, 2026, including checked-out SHAs, environment, XCTest totals, simulator result summary and unsigned build marker. Counts below are suite totals including skips, not all passing tests. This evidence is separate from historical records and physical acceptance.

| Run | Tested checkout SHA | Actual result |
| --- | --- | --- |
| Linux PR #44 [43746963280](https://github.com/markdlabrecque/convoke/actions/runs/43746963280) | `067fca98615533a5f1b21002ac98b932d593b8da`, PR merge checkout | Pass. Server build; server 51 tests, 1 skip, 0 failures; portable 73 tests, 0 skips/failures. Ubuntu 24.04, Swift 6.4.2. |
| Linux main [43747593799](https://github.com/markdlabrecque/convoke/actions/runs/43747593799) | `adebaa0cc85a62adc77d1b9f493e5ddcd3dd7d6f` | Pass. Same environment and totals as Linux PR run. Kokoro skipped; macOS voice excluded. |
| Apple PR #43 [43746632840](https://github.com/markdlabrecque/convoke/actions/runs/43746632840) | `f5b9e43ef24dbedf0f060de2beba996f4c1bfcc7`, PR merge checkout | Pass. Package 96 tests, 2 skips, 0 failures; simulator 89 total, 86 passed, 3 skipped, 0 failed; unsigned device `BUILD SUCCEEDED`. macOS 26.7.2, Xcode 26.6, Swift 6.3.3, iPhone 17 simulator / iOS 26.5. |
| Apple main [43747250497](https://github.com/markdlabrecque/convoke/actions/runs/43747250497) | `cfdc615697f533b19945744b0619fe34086ead6e` | Pass. Same environment and totals as Apple PR run. Two package / three simulator real-engine tests explicitly skipped. No Mac server or physical phone execution. |

### Ongoing physical-device smoke

For playback, capture or audio-session changes and releases, install the signed app on a physical iPhone and run the short checks below against the development Mac. Docs-only or unrelated server changes do not require repeating the complete phone checklist. Add focused deterministic regressions for new failures where feasible; there is no coverage-percentage target.

Record date, tested SHA and dirty-tree state, Mac/macOS/Xcode, iPhone/iOS, agent/model, voice/sidecar version and digest, plus whether each result was owner-reported or directly observed and by whom. Use Pass/Fail/Pending per row. Record outcomes and sizes/timings only, never transcripts or audio. Leave unrun or inconclusive checks Pending.

| Check | Expected outcome | Result |
| --- | --- | --- |
| Sequential audible turns | Three complete replies without touching the phone between turns; no missing/repeated/reordered audio; listening resumes only after the final playback sample | Pending |
| End before and after EOF/done | Before validated done, End stops audio/capture and disconnects. After done but before queued playback drains, End stops audio and keeps Ready; Start works. No stale callback restarts capture/playback | Pending |
| Lifecycle and audio session | Exercise background, Disconnect, a real interruption and a route/configuration change. Audio/capture stop, expected disconnect/error appears, no automatic restart | Pending |
| Streaming behavior changes | Long real Kokoro reply starts audibly before real source EOF and remains continuous. Use the [Slice 4 observation method and limits](#owner-handoff-mac-and-iphone); network frames or silent callbacks alone are insufficient | Pending |

This is an ongoing smoke checklist, not a replacement for the initial full [Slice 4 acceptance](#physical-checklist-and-results) in [#30](https://github.com/markdlabrecque/convoke/issues/30) under [#25](https://github.com/markdlabrecque/convoke/issues/25). Both remain open. All original failed/unrun rows below remain unchanged; current CI does not retrospectively pass them.

### Recorded automated results

Historical Slice 3 record, not current CI evidence.

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

## Kokoro verification

Historical #23 complete-reply baseline, preserved from PR #24. These results are separate from the earlier spike-3 session, whose voice backend was not confirmed. They predate Slice 4 and do not prove streaming or early playback. The commands below now exercise the current implementation if rerun; put new results in the Slice 4 section, not this baseline. Never substitute the macOS voice if Kokoro fails.

Start the localhost-only CPU sidecar using `server/README.md`, wait for `/health` to return `{"status":"healthy"}`, then run:

```sh
cd server
CONVOKE_TEST_KOKORO_URL=http://127.0.0.1:8880 CONVOKE_KOKORO_VOICE=af_heart \
  swift test --filter testKokoroSidecarSmoke
```

The smoke test uses a stub agent. For real replies, start Ollama with `llama3.2` installed and start Convoke with all three variables from Mac setup, including `CONVOKE_KOKORO_URL`. Connect the physical iPhone, tap Start conversation once, and complete three consecutive turns without touching the phone. Each reply must play fully, then Listening must resume automatically. Use a follow-up that depends on an earlier turn to check retained agent context. End the conversation after the third reply. Record outcomes only, not words spoken or audio.

### Recorded Kokoro results

Local checks run by the coding agent during the November 11-12 2026 session. The Kokoro smoke test ran November 11 at 23:15 MST. Checks were based on commit `7da5bb3bdd9c936485b4b74dbceee9de8122ddde` on `issue-23-kokoro-verification`, with documentation edits and the owner's untracked `bash.sh`. Mac: Apple M4 Pro, macOS 27.0.1, Swift 6.4.2, Docker Engine 29.8.2. No application code or protocol changes were needed.

| Check | Status | Actual result |
| --- | --- | --- |
| CPU sidecar image | Pass | `ghcr.io/remsky/kokoro-fastapi-cpu:v0.10.0`, pulled digest `sha256:f54c5960c2b9387f6349080a9944f8bc7e8cdb98a4ef9238cb0b0f9ff9795f44`; container `convoke-kokoro` |
| Localhost-only binding | Pass | Docker inspect reports `8880/tcp` published only at `127.0.0.1:8880` |
| Health | Pass | `/health` returned `{"status":"healthy"}` |
| Real Kokoro smoke test, stub agent | Pass | 1 test, 0 failures. `af_heart`, 102326 non-silent PCM bytes, 2.132 s audio, 7 chunks, first chunk 0.975 s, total 0.977 s |
| Real agent reply through Kokoro, local WebSocket | Pass | Ollama `llama3.2:latest`, Kokoro `af_heart`; nonempty agent text followed by 401710 non-silent PCM bytes, 25 sequential chunks and matching `agent.done`; total 5.457 s. No transcript or audio saved by the check. Not iPhone playback evidence. |
| Server build and full suite with real Kokoro enabled | Pass | November 12 at 05:51 MST. `swift build`, then `CONVOKE_TEST_KOKORO_URL=http://127.0.0.1:8880 CONVOKE_KOKORO_VOICE=af_heart swift test`. Exit 0; 35 tests, 1 skipped, 0 failures. Only the optional macOS voice smoke test skipped. Kokoro rerun produced 102496 bytes in 7 chunks, first chunk 0.795 s, total 0.800 s. |
| Physical iPhone turn 1 | Pass | Owner confirmed a real reply played fully and Listening resumed without touching the phone |
| Physical iPhone turn 2 | Pass | Owner confirmed another complete reply and automatic return to Listening |
| Physical iPhone turn 3 | Pass | Owner confirmed a third complete reply and automatic return to Listening, with earlier context retained |

The owner reported all three physical turns passing on November 12 2026 and confirmed the same iPhone 17 / iOS 27.0.1 and M4 Pro / macOS 27.0.1 / Xcode 27.2 environment. Convoke ran from the base commit above with documentation-only working-tree edits, configured explicitly for local Ollama `llama3.2` and Kokoro `af_heart`. Ollama and Convoke were started in separate Rex tabs in the Convoke session. Physical results are owner-reported, not independently observed by the coding agent, and were not copied from the earlier session. All #23 checks passed.

## Slice 4 streaming verification

This is the #30 verification record for epic #25. It does not replace the historical tables above. Acceptance is **blocked**, not complete. Automated results below were rerun; earlier #27/#28/#29 counts are not relabeled as current results. The initial Linux snapshot is followed by an authorized Mac run. Read both, especially the Mac cancellation failures; Linux passes do not override them.

### Initial Linux environment and provenance

| Field | Actual value for the initial Linux verification |
| --- | --- |
| Date | November 14, 2026, run started 11:58 MST |
| Checkout / branch | `/home/mark/Projects/convoke/code/main`, `slice-4-30`, created from fetched `origin/main` in this existing checkout |
| Tested runtime commit | `06fc49c8c4fc55eff7d2ed2c3fac1714684eac1f`, merged #29 / PR #35. This PR changes documentation only |
| Working tree at test start | No tracked edits; only existing untracked `docs/hands-free-plan.html` and `docs/hands-free-plan.packed.html`. Both left untouched/uncommitted; sibling `code/develop` not used |
| Host / Swift | Linux `7.2.15-1-omarchy`, x86_64; Swift 6.4.2, target `x86_64-unknown-linux-gnu` |
| Agent conducting checks / model | Pi coding agent through T3 / `openai/gpt-6.1-sol` |
| Real agent endpoint / model | Pending. No Ollama available locally; smoke uses a stub agent, not real Ollama replies |
| Mac / macOS / Xcode | Pending. Not available on this host; prior Mac versions above are not this run's environment |
| Physical iPhone / iOS | Pending. No device session run or reported |
| Docker / sidecar | Docker Engine 29.9.2, `ghcr.io/remsky/kokoro-fastapi-cpu:v0.10.0`, `af_heart` |
| Image digest | `sha256:f54c5960c2b9387f6349080a9944f8bc7e8cdb98a4ef9238cb0b0f9ff9795f44` from local image inspect, also matches running image ID |
| Sidecar binding / logging | `8880/tcp -> 127.0.0.1:8880`; Docker log driver `none`, stdout/stderr discarded. Temporary local service in Rex, stopped after checks |

Read the full ticket, epic, approved Q&A/plan comments and `docs/slice-4-{27,28,29}-verification.md`. GitHub inspection used `~/.config/nvm/versions/node/v24.20.0/bin/gh-axi` with `issue view 30 --comments --full`, `issue view 25 --comments --full`, and `pr view N --full` for 24 and 31 through 35. PR #24 is merged and its baseline documentation is available in this branch as `6a4e0b8`. Ancestor checks for `60118fd`, `6a4e0b8`, `05e7ed2`, `1dd4b1c` and `06fc49c` against fetched `origin/main` all exited 0. These cover #26, baseline #23, #27, #28 and #29.

The supplied #29 premerge commit `f49daf7f46301fee436cd32adae086dc5f2b2fbb` is not an ancestor after the squash merge. `git diff --exit-code f49daf7f46301fee436cd32adae086dc5f2b2fbb origin/main` exited 0 with no output, confirming identical trees at branch creation.

### Initial Linux commands and fresh results

The Pending Apple rows in this initial snapshot are superseded where actually run by the Mac follow-up below. From repository root, run individually and record exit codes. No transcript, PCM or arbitrary response body is captured. Temporary build/test logs are local compiler/XCTest output, not committed session recordings.

```sh
git fetch origin
git switch -c slice-4-30 origin/main
swift build --package-path server
swift test --package-path server
swift test --package-path ios/Convoke
bash ios/Convoke/scripts/test-portable-core.sh
xcrun simctl list devices available
command -v xcodebuild
```

The initial localhost health probe exited 7. Docker and the pinned image were available, so a local sidecar was started rather than leaving that check unattempted:

```sh
rex new convoke-30-smoke --cwd /home/mark/Projects/convoke/code/main -- bash -lc \
  'exec docker run --rm --log-driver none --name convoke-30-kokoro -p 127.0.0.1:8880:8880 ghcr.io/remsky/kokoro-fastapi-cpu:v0.10.0 >/dev/null 2>&1'
# Retry health until successful before testing. Do not save response bodies.
curl --fail --silent --max-time 2 --output /dev/null http://127.0.0.1:8880/health
docker port convoke-30-kokoro
docker inspect convoke-30-kokoro --format '{{.HostConfig.LogConfig.Type}} {{.Image}}'
docker image inspect ghcr.io/remsky/kokoro-fastapi-cpu:v0.10.0 --format '{{json .RepoDigests}}'
CONVOKE_TEST_KOKORO_URL=http://127.0.0.1:8880 CONVOKE_KOKORO_VOICE=af_heart \
  swift test --package-path server --filter testKokoroSidecarSmoke
CONVOKE_TEST_KOKORO_URL=http://127.0.0.1:8880 CONVOKE_KOKORO_VOICE=af_heart \
  swift test --package-path server
docker stop convoke-30-kokoro
```

| Check | Status | Actual output / limit |
| --- | --- | --- |
| Server build | Pass | Exit 0 |
| Default server tests | Pass | Exit 0; 51 tests, 1 optional real-sidecar smoke skipped, 0 failures. Linux excludes the macOS voice test |
| Full iOS package command on Linux | Fail | Exit 1, `no such module 'Combine'`. Platform blocker, not an Apple test failure or pass |
| Limited Linux core tests | Pass | Exit 0; 73 tests, 0 failures. Temporary test-only Combine stand-in; no Combine publication, Apple adapters, speech capture or AVAudioEngine verification |
| Focused HTTP/source/socket gate checks listed below | Pass | Both server filter commands rerun, each exit 0; 1 test, 0 failures each. These are not physical delayed-playback results |
| Pinned CPU sidecar health/binding | Pass | Health exit 0; localhost-only mapping and log driver verified above |
| Opt-in real-sidecar smoke | Pass | Exit 0; 1 test, 0 failures; 102316 non-silent PCM bytes, 2.131583 s audio, 9 wire chunks, 6 source pieces |
| Full server suite with real sidecar enabled | Pass | Exit 0; 51 tests, 0 skipped, 0 failures. Smoke produced 102488 bytes, 2.135167 s audio, 9 wire chunks, 6 source pieces |
| Full macOS iOS package / macOS voice adapter | Pending | Requires macOS 26+ and Apple frameworks; Linux results do not cover these |
| Simulator build-for-testing | Pending | Xcode/Apple SDK unavailable |
| Simulator test execution | Pending | `xcrun simctl list devices available` exit 127. No installed destination invented |
| Unsigned generic iPhoneOS build | Pending | `command -v xcodebuild` exit 1, no Xcode |
| Actual AVAudioEngine scheduling, buffer release, interruption/configuration notifications | Pending | Needs Apple runtime. Pure queue/lifetime tests are not hardware evidence |
| Real Ollama reply through Kokoro and physical early playback | Pending | Real agent, Mac and iPhone owner session required |
| Documentation whitespace | Pass | `git diff --check`, exit 0 |

Opt-in smoke timing output, all seconds relative to **one monotonic request start** within each run:

| Run | First source PCM | Source synthesis EOF | First wire audio | Wire done |
| --- | --- | --- | --- | --- |
| Focused smoke | 0.185977121 | 0.190595147 | 0.186910372 | 0.190927060 |
| Full suite smoke | 0.156923720 | 0.162123568 | 0.157651225 | 0.162284049 |

These prove source/wire delivery before source EOF in these short synthetic replies. They do **not** prove the iPhone started speaking before EOF. The measured first-wire-to-EOF window is only a few milliseconds, far less than the intended 200 ms startup buffer. A long real reply and physical evidence are still required. No latency SLA is invented.

Local logs: `/tmp/convoke-30-server-build.log`, `/tmp/convoke-30-server-tests.log`, `/tmp/convoke-30-ios-tests.log`, `/tmp/convoke-30-portable-tests.log`, `/tmp/convoke-30-smoke.log`, `/tmp/convoke-30-server-real-tests.log`, `/tmp/convoke-30-http-gates.log`, `/tmp/convoke-30-turn-gates.log`. The initial Linux run used no production, 1Password, remote-machine change, new thread, subagent, automatic fallback or persisted transcript/audio.

### Mac follow-up after owner-authorized SSH

On November 14, 2026 the owner authorized SSH to `macbook` and updates to `~/Projects/convoke`. The agent inspected a clean checkout on `issue-23-kokoro-verification`, fetched origin, and created local `slice-4-30` tracking the existing PR branch at `1fd8bce8843d10f3a0bfa0bb02152c4aa310fcb9`. Initial checks tested that commit. Final checks tested that runtime plus the opt-in tests added to `ios/Convoke/Tests/PCMPlayerTests.swift`; no production source changed.

| Field | Actual Mac environment |
| --- | --- |
| Date / time | November 14, 2026, started 12:49 MST |
| Host / path | `macbook`, `/Users/mark/Projects/convoke` |
| Hardware / OS | Apple M4 Pro, arm64; macOS 27.0.1, build 26A434 |
| Xcode / Swift | Xcode 27.2, build 27B52; Apple Swift 6.4.2, target arm64-apple-macosx27.0.0 |
| Simulator used | iPhone 17, iOS 27.2; UDID `E58183BA-D034-4773-B504-D1053EE3141E`, present in `xcrun simctl list devices available` |
| Device | No physical iPhone session or result |
| Existing services | Local Ollama, Convoke and pinned `convoke-kokoro` were already running. None was stopped, restarted or reconfigured |
| Mac sidecar | Docker Engine 29.8.2; pinned v0.10.0 digest matches the Linux record; localhost-only binding. Existing container uses `json-file` logging, so no new speech requests were sent through it |

From Mac repo root, these were run over SSH. Service processes were not started; no tmux, production, credential store, transcript/audio capture or new thread/subagent was used. The new runtime tests synthesize **silence in memory**, not speech, and capture no audio.

```sh
swift build --package-path server
swift test --package-path server
swift test --package-path server --filter StreamingFailureTests
CONVOKE_TEST_SYSTEM_VOICE=1 swift test --package-path server --filter testSystemVoiceSmoke
CONVOKE_TEST_SYSTEM_VOICE=1 swift test --package-path server
swift test --package-path ios/Convoke
CONVOKE_TEST_AUDIO_ENGINE=1 swift test --package-path ios/Convoke
CONVOKE_TEST_AUDIO_ENGINE=1 swift test --package-path ios/Convoke --filter PCMPlayerRuntimeTests
xcodebuild -project ios/Convoke/Convoke.xcodeproj -scheme Convoke \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build-for-testing
xcodebuild -project ios/Convoke/Convoke.xcodeproj -scheme Convoke \
  -destination 'platform=iOS Simulator,id=E58183BA-D034-4773-B504-D1053EE3141E' \
  CODE_SIGNING_ALLOWED=NO test
TEST_RUNNER_CONVOKE_TEST_AUDIO_ENGINE=1 xcodebuild \
  -project ios/Convoke/Convoke.xcodeproj -scheme Convoke \
  -destination 'platform=iOS Simulator,id=E58183BA-D034-4773-B504-D1053EE3141E' \
  CODE_SIGNING_ALLOWED=NO test
xcodebuild -project ios/Convoke/Convoke.xcodeproj -scheme Convoke \
  -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

| Check | Status | Actual output / scope |
| --- | --- | --- |
| Mac server build | Pass | Exit 0. Compiles the macOS voice adapter |
| Initial Mac server tests | Fail | Exit 1; 56 tests, 2 optional skips, 5 failed assertions in upstream cancellation checks |
| Focused cancellation repeat | Fail | Exit 1; same five upstream-closure assertions. Not dismissed as a flaky first run |
| System-voice smoke | Pass | Exit 0; 1 test, 0 failures. Actual macOS synthesis adapter, not a physical iPhone result |
| Mac server suite with system voice enabled | Fail | Exit 1; 56 tests, 1 optional Kokoro skip, 5 failed assertions. System voice passes; cancellation still fails |
| Initial Apple iOS package | Pass | Exit 0; 94 tests, 0 failures, including macOS-only live WebSocket tests. No fake Combine |
| Final Apple iOS package with actual engine enabled | Pass | Exit 0; 96 tests, 0 failures, no skips. Includes two new macOS AVAudioEngine runtime tests |
| Focused actual macOS engine tests | Pass | Exit 0; 2 tests, 0 failures. Three additional focused repeats each pass with 2 tests, 0 failures |
| Limited Linux core follow-up after adding opt-in tests | Pass | `bash ios/Convoke/scripts/test-portable-core.sh`, exit 0; 73 tests, 0 failures. Apple-only additions are excluded on Linux, not counted as passing |
| Simulator build-for-testing | Pass | Exit 0; `** TEST BUILD SUCCEEDED **`, rerun after adding tests |
| Initial simulator tests | Pass | Exit 0; 86 tests, 0 failures, `** TEST SUCCEEDED **`, before new opt-in tests |
| Final default simulator tests | Pass | Exit 0; 89 tests, 3 explicit opt-in engine skips, 0 failures, `** TEST SUCCEEDED **` |
| Opt-in actual iOS engine tests in simulator | Fail | Exit 65. Each of the 3 new runtime tests aborts during audio initialization with `Initialize: RPC timeout. Apparently deadlocked. Aborting now.` XCTest restarts the runner. The later 0-test suite summary is **not** a pass |
| Unsigned generic iPhoneOS build | Pass | Exit 0; `** BUILD SUCCEEDED **`, rerun after adding tests. Not a signed install or physical device run |
| Actual iOS session interruption / route changes | Pending | Synthetic interruption observer test compiles, but audio initialization aborts before it can execute. No real interruption or configuration-change result |
| Real Mac Ollama/Kokoro turns | Pending | Pre-existing services preserved. Existing sidecar logging not changed or used for new content requests; Linux real-sidecar smoke remains separate evidence |
| Physical early sound, continuity and three hands-free turns | Pending | No owner report or independently observed device session |

The new opt-in `PCMPlayerRuntimeTests` run the production `PCMPlayer` against an actual engine. On macOS they verify startup at 9600 bytes, short EOF flush, `dataPlayedBack` completion, cancellation of a pending drain by explicit stop, and replacement-stream completion. These are real Apple adapter checks, not queue fakes, but silent-buffer completion cannot establish audible iPhone output or acoustic continuity. The iOS-only case posts a synthetic interruption notification; even if it passes later, that would test observer wiring, not an actual phone interruption.

#### Cancellation failure details

**Historical record:** the hosted [peer-observation correction](#passing-result-after-peer-observation-correction) above supersedes the production-defect attribution and current failing status in this section. The original failed commands and observations remain recorded below; no physical or optional-engine acceptance is implied.

The failed expectation is `upstream HTTP channel closed`, bounded by 3 seconds. It fails in `testCancellationDuringBodyReadClosesRealUpstreamRequest`, `testCancellationDuringSlowWriteClosesRealUpstreamRequest`, `testFailedWriteClosesRealUpstreamRequest`, and both disconnect/deadline iterations of `testConversationDisconnectAndTimeoutCancelRealRequest`. Downstream cancellation returns, but the peer-close assertion does not complete. The truncated-body test and final-done-write deadline test pass.

A temporary sizes/content-free lifetime probe in `BodyPuller` showed its deinitialization after the focused failed-write test run rather than before the close expectation. That suggests delayed stream/iterator release on the Apple build, but does not establish the exact root cause. The probe was removed and production source restored byte-for-byte. No assertion was weakened, timeout increased or test retired. Treat real upstream cancellation on Mac as **unverified and failing**, not as a passing Linux contract. It must be resolved before acceptance.

#### Simulator audio initialization blocker

Opt-in tests exercise the real adapter only when `CONVOKE_TEST_AUDIO_ENGINE=1`. Xcode receives it through `TEST_RUNNER_CONVOKE_TEST_AUDIO_ENGINE=1`. The default suite deliberately skips them because it must remain usable without an audio route. An experimental app-hosted test runner also hit the same RPC timeout, so simply adding a test host did not solve it. Temporary project/host changes were reverted; no speculative runner change is included. A command-line host override also failed at linking and was discarded. The normal simulator build/test remains passing, while the opt-in simulator audio result remains Fail. It is not evidence of physical-device failure or success.

Mac logs are under `/tmp/convoke-30-mac-*.log`: `server-build`, `server-tests`, `cancellation-repeat`, `system-voice`, `server-final`, `ios-tests`, `ios-final`, `engine-tests`, `engine-repeat-{1,2,3}`, `simulator-build-final`, `simulator-default-final`, `simulator-final`, `simulator-hosted-final`, and `device-build-final`. They are local build/test diagnostics, not committed recordings. Inspecting service transcripts or device logs was not needed. The follow-up Linux log is `/tmp/convoke-30-portable-followup.log`. The selected simulator was Shutdown at completion, matching its initial state; other booted simulators were left alone.

### Completed-harness refresh, November 15, 2026

This follow-up for [#42](https://github.com/markdlabrecque/convoke/issues/42) applies the completed [#38](https://github.com/markdlabrecque/convoke/issues/38) automation to Slice 4. It adds fresh software evidence, not physical acceptance. [#30](https://github.com/markdlabrecque/convoke/issues/30) and [#25](https://github.com/markdlabrecque/convoke/issues/25) remain open. All historical tables, including the Mac failures above, are preserved.

#### Revision and evidence inspected

The tested integrated `main` revision is [`94a35a7509a778b75b0b57215690b730425ecd2f`](https://github.com/markdlabrecque/convoke/commit/94a35a7509a778b75b0b57215690b730425ecd2f). It includes Linux PR #44 at `adebaa0`, Apple PR #43 at `cfdc615`, and command/evidence guide PR #45 at `94a35a7`. All three are ancestors of this checkout. This refresh changes documentation only.

On November 15, the agent inspected the full exact-SHA job logs with `gh-axi run view RUN --log`, checked the run API's `head_sha`, and downloaded the Apple artifact with `gh-axi run download 43748973393`. This is direct inspection of hosted CI evidence, not a new local Apple run or owner-reported device result. The Apple `driver.log` reports an empty dirty-tree state. Linux jobs log the same checkout SHA but do not separately print a dirty-tree status. The local documentation checkout was clean before this edit; no local runtime test result is claimed.

| Evidence | Actual environment and result |
| --- | --- |
| [Linux run 43748973341](https://github.com/markdlabrecque/convoke/actions/runs/43748973341), jobs [server](https://github.com/markdlabrecque/convoke/actions/runs/43748973341/job/132918462256) and [portable core](https://github.com/markdlabrecque/convoke/actions/runs/43748973341/job/132918462273) | November 15, 18:50 UTC start; Ubuntu 24.04 hosted runners, `swift:6.4.2-noble`, Swift 6.4.2, `x86_64-unknown-linux-gnu`. Server build Pass; server XCTest total 51, 1 skip, 0 failures, so 50 passed. Portable total 73, 0 skips/failures. |
| [Apple run 43748973393](https://github.com/markdlabrecque/convoke/actions/runs/43748973393/job/132918462523) | November 15, 18:50 UTC start; macOS 26.7.2 build 25G332, arm64; Xcode 26.6 build 17F113; Apple Swift 6.3.3, target `arm64-apple-macosx26.0`; iPhoneOS and simulator SDK 26.5. Real-Combine package total 96, 2 skips, 0 failures, so 94 passed. Simulator total 89, 3 skips, 0 failures, so 86 passed. Unsigned generic iPhoneOS build Pass. Shared command exits 0. |
| [Apple artifact 14175428048](https://github.com/markdlabrecque/convoke/actions/runs/43748973393/artifacts/14175428048) | Downloaded and inspected `convoke-apple.dTWUSG/{driver.log,package.log,simulator.log,simulator-summary.json,device-build.log,destination.txt,simulators.json}`. Includes `simulator.xcresult` and `device-build.xcresult`. Simulator summary exported by `xcresulttool` on the Mac agrees with XCTest: 86 passed, 3 skipped, 0 failed, `Passed`. Raw result bundles are retained, not re-decoded on Linux. Artifact retention is 14 days; it was available during this review. |
| [Protocol run 43748973351](https://github.com/markdlabrecque/convoke/actions/runs/43748973351/job/132918462174) | Same SHA and date; Factory model/provider tests 7 passed, 0 failed. JSON command reports **0 protocol JSON files**. Job success proves command execution, not protocol schema coverage. |

Apple simulator discovery selected iPhone 17, iOS 26.5 build 23F77, arm64, UDID `23C8F95C-765D-46A9-AE82-0BEE2921C8D7`. `destination.txt`, discovery JSON, the invocation, and the result summary agree. Logs show `** TEST SUCCEEDED **` and `** BUILD SUCCEEDED **`, not merely a simulator build-for-testing. The two skipped package cases are actual-engine threshold/short-EOF drain and stop/restart. Simulator skips those same two plus the injected session-interruption adapter case, all explicitly requiring `CONVOKE_TEST_AUDIO_ENGINE=1`. Linux skips `testKokoroSidecarSmoke` because `CONVOKE_TEST_KOKORO_URL` is unset; macOS system voice is excluded on Linux, not counted as a skip or pass.

#### Commands actually executed

The Linux jobs ran these commands, not a full Apple package command with a Combine substitute:

```sh
swift build --package-path server
swift test --package-path server
bash ios/Convoke/scripts/test-portable-core.sh
```

Apple CI ran `ios/Convoke/scripts/test-apple.sh` by absolute checkout path from the runner's temporary directory, with `APPLE_TEST_OUTPUT_DIR=/Users/runner/work/_temp/convoke-apple-results`. For this run the script expanded to the following test/build commands. Paths and the discovered destination are recorded here so the evidence can be reproduced without guessing a simulator:

```sh
package_dir=/Users/runner/work/convoke/convoke/ios/Convoke
output_dir=/Users/runner/work/_temp/convoke-apple-results/convoke-apple.dTWUSG
xcrun swift test --package-path "$package_dir" --scratch-path "$output_dir/swift-build"
xcodebuild -project "$package_dir/Convoke.xcodeproj" -scheme Convoke \
  -destination 'platform=iOS Simulator,id=23C8F95C-765D-46A9-AE82-0BEE2921C8D7' \
  -destination-timeout 120 -parallel-testing-enabled NO \
  -derivedDataPath "$output_dir/simulator-derived-data" \
  -resultBundlePath "$output_dir/simulator.xcresult" CODE_SIGNING_ALLOWED=NO test
xcrun xcresulttool get test-results summary --path "$output_dir/simulator.xcresult"
xcodebuild -project "$package_dir/Convoke.xcodeproj" -scheme Convoke \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath "$output_dir/device-derived-data" \
  -resultBundlePath "$output_dir/device-build.xcresult" CODE_SIGNING_ALLOWED=NO build
```

The script retains tee'd logs, exports the simulator summary, and checks nonzero passing test counts. It deliberately unsets audio-engine, system-voice and Kokoro opt-ins. Setting those variables around this default command would not rerun the optional checks. Apple CI also passed the existing fake-tool driver checks and rejected an invalid simulator override before compilation. These script checks are not application/device acceptance.

#### Coverage inventory and acceptance mapping

Pass in this table applies only to the stated automated contract at the tested SHA/platform. It never changes a physical row below. The suite/test names are present in the inspected logs and retained source fixtures.

| Slice 4 requirement / original row | Classification and fresh evidence | Remaining acceptance boundary |
| --- | --- | --- |
| Server build, strict PCM/message limits, odd splits, empty/trailing EOF and source errors | Default automation, Pass on Linux. `KokoroTests`, `ConversationTests` and `StreamingBoundsTests` cover their respective server/client boundaries. | The historical Apple CI run did not run the Mac server suite. No new Mac server build/test result was available in this refresh. |
| First delivery before source EOF; sequential wire turns and backpressure | Default automation, Pass on Linux. `testHTTPHeadersPiecesAndEOFAreIndependent`, `testAudioIsSentBeforeSynthesisFinishes`, `testGatedSocketAndSynthesisOrderingAcrossTwoTurns`, and `testConsumerWriteBackpressuresFurtherSourcePulls` passed. | Deterministic gates prove source/socket ordering only. Real Ollama/Kokoro early **audible** playback remains Pending. |
| Disconnect, slow/failed write, deadline, truncated body; no successful done after failure | Default automation, Pass on Linux. All 7 `StreamingFailureTests` passed, including real upstream peer-close assertions and stalled final-done deadline. Connection lifecycle gates also passed. | Known Mac cancellation Fail remains unresolved. The Linux test-only WebSocket client added by PR #44 is not a Mac cancellation fix; Apple keeps URLSession and Apple CI tests only the iOS package/app. |
| Full Apple package, simulator execution, unsigned iPhoneOS build | Default automation, Pass within the counts/skips above. Replaces the need for an owner to repeat the initial Linux snapshot's unavailable Apple software commands on this revision. | Compilation is not signing, installation, a phone session, or actual-engine execution. |
| 9600-byte startup, short EOF flush, ordered accounting, 8 MiB cap/release, underrun | Default automation, Pass for queue logic. Apple package/simulator `PCMPlaybackQueueTests`, `PCMPlayerQueueRegressionTests` and `PCMPlaybackLifetimeTests`; limited portable core also passed. | Physical continuity, buffer playback and audible underrun recovery remain Pending. Queue callbacks do not measure speaker output. |
| Mic off until EOF plus drain, either completion order, exactly-once resume | Default automation, Pass for controller/fake-player logic. `ResponseLifecycleTests`, including independently gated sequential turns, drain-before-EOF, short reply and stale-callback cases, passed in Apple package/simulator. | Three untouched real turns, retained real-agent context and microphone/speaker interaction remain Pending. |
| End before done disconnects; End after done keeps Ready; background/disconnect/interruption stop and ignore stale work | Default automation, Pass for injected controller/lifetime behavior. Corresponding `ResponseLifecycleTests` and lifetime cases passed. Mac package also passed all 8 live `WebSocketTransportTests`, including receive/heartbeat during gated playback. | Both physical End rows, background, Disconnect and real interruption/configuration change remain Pending. Simulator omits macOS-only live WebSocket tests. |
| Actual engine scheduling/drain/stop/restart and interruption observer | Optional runnable checks. Current default Mac package skips 2 runtime tests; simulator skips 3. No fresh optional Pass. | Historical actual macOS engine Pass is preserved at its original revision. Historical opt-in simulator audio-initialization **Fail** remains unresolved; notification wiring and real iOS interruption/configuration remain Pending. |
| Pinned real Kokoro, system voice, real Mac agent integration | Optional runnable checks. Current real-sidecar, system-voice and real Ollama checks Pending, not run in this refresh. | Historical Linux sidecar timing and Mac system-voice Pass retain their original provenance. No available authorized local Apple/real-agent session was used; no service was started or changed. |
| Privacy / physical diagnostics | Owner/device check, Pending. This documentation review adds no transcript, PCM, response-body capture or production logging. | Actual owner session still needs content-free diagnostics and recorded provenance. No new physical results were supplied. |

The earlier Mac upstream cancellation result remains **Fail**, including all five assertions described above. The opt-in simulator RPC timeout remains **Fail**. Neither was rerun on its affected platform here. No assertions, timeouts, application behavior or checks changed. Optional unrun checks are Pending; skips are not fixes. The earlier Linux Combine failure remains a historical platform limitation, not an Apple failure.

#### Reduced owner work

Do not repeat passing default builds just to fill this record. Resolve and rerun the Mac upstream-cancellation failure in separately authorized development work before Slice 4 acceptance; reproduce the opt-in simulator engine failure separately. The default script is not a replacement for either rerun. The remaining owner session uses the full physical table below, grouped here without dropping any row:

1. Record device/environment/revision provenance and privacy checks. Use real Ollama, pinned localhost-only Kokoro v0.10.0 and `af_heart`, with development services in Rex. No new service or other-machine change was authorized or made in this refresh.
2. Observe early audible playback before genuine source EOF, startup delay, three untouched context-retaining turns and continuous ordered audio. Use the common-clock/causal-order method below; no silent-buffer or wire-chunk substitute.
3. Exercise both End windows, temporary underrun with an explicitly test-only debug gate, and separate sidecar/server failures. If the physical delayed-source setup is unavailable, keep that row Pending and request assistance rather than treating the unit fixture as a phone mode.
4. Exercise background, Disconnect, real interruption and route/configuration change. Confirm audio/capture stop and no stale callback or automatic restart. Report each original row as Pass/Fail/Pending, without transcripts or recordings.

All eleven physical rows remain Pending. This evidence refresh can complete independently of Slice 4 acceptance. Epic #38's automation/documentation criteria can be satisfied without a physical pass; its coordinator must verify the merged refresh and the linked #30 progress comment before closing that epic.

### Owner handoff: Mac and iPhone

The agent has now performed the available Mac builds and tests above. The remaining owner session is for the physical rows, after the cancellation failure is resolved; the commands below are retained for reproduction, not a request to repeat passing builds. Owner participation is required in this T3 thread. Do not mark #30 or epic #25 complete from the Linux results. Record owner-reported checks explicitly as **owner-reported**, with date, tested SHA, dirty-tree state, Mac/macOS/Xcode, iPhone/iOS, Ollama model, image digest and voice. Leave every unrun or inconclusive row Pending. Mac checkout updates and tests above were performed only after the owner explicitly authorized SSH. Pre-existing services were preserved.

1. On the Mac, obtain this PR branch and record `git rev-parse HEAD` and `git status --short`. Run `sw_vers`, `xcodebuild -version`, `swift --version`, `docker version --format '{{.Server.Version}}'`. Fill in the actual phone model/iOS from Settings. Do not reuse the #23 environment without reconfirming it.
2. From repo root run the following Apple checks. Select an installed simulator from the listing; substitute its actual UDID for the shell variable before the final test command. Report exit status, tests/skips/failures and the build-success markers, without saving content-bearing device console output.

   ```sh
   swift build --package-path server
   swift test --package-path server
   CONVOKE_TEST_SYSTEM_VOICE=1 swift test --package-path server
   swift test --package-path ios/Convoke
   xcrun simctl list devices available
   xcodebuild -project ios/Convoke/Convoke.xcodeproj -scheme Convoke \
     -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
     CODE_SIGNING_ALLOWED=NO build-for-testing
   xcodebuild -project ios/Convoke/Convoke.xcodeproj -scheme Convoke \
     -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
     CODE_SIGNING_ALLOWED=NO test
   xcodebuild -project ios/Convoke/Convoke.xcodeproj -scheme Convoke \
     -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
   ```

3. In separate Rex terminals start the pinned localhost CPU sidecar using `server/README.md`, Ollama with the actual installed `llama3.2` model, and Convoke with explicit `CONVOKE_AGENT_BASE_URL=http://localhost:11434/v1`, `CONVOKE_AGENT_MODEL=llama3.2`, `CONVOKE_KOKORO_URL=http://127.0.0.1:8880`, `CONVOKE_KOKORO_VOICE=af_heart`. Repeat the opt-in smoke above and record the digest and binding. Install the updated signed app through Xcode on the physical phone, then connect over the trusted tailnet. Unsigned build alone is not an installed-device test.
4. Run the physical rows below. For early playback, request a sufficiently long real reply. Use sizes/timings-only diagnostics or non-stopping debugger tracepoints to observe source EOF and playback start; do not inspect or persist text/PCM. Existing smoke diagnostics cover source and wire, not physical output. The normal app/server do not currently emit a paired runtime playback-start/source-EOF timing report. A debug observation setup is still needed. The successful EOF branch of `BodyPuller.next()` in `server/Sources/ConvokeServer/KokoroSpeechSynthesizer.swift` is the source-EOF observation point; a probe must auto-continue without printing request data or delaying the producer. If using separate Mac/phone timers, their raw timestamps cannot be compared. Use a common monotonic observation clock or explicit causal ordering, and describe the method and uncertainty. For example, an owner hearing the first sound while a live non-stopping source-EOF probe still shows synthesis active establishes ordering; record startup delay using that same observer's timer from turn submission. If EOF is too close to distinguish, keep early playback Pending. An AVAudioPlayerNode start callback or network frame alone is not proof of audible output. Do not pause or artificially gate real Kokoro EOF to manufacture an early-playback pass.
5. Return the environment, per-row Pass/Fail/Pending, startup delay and ordering method in this thread. Report failures before retrying, including whether audio/capture stopped. Keep transcripts, arbitrary response bodies, audio and screen/audio recordings out of the report. Stop development services afterward.

### Physical checklist and results

All rows are Pending. There has been no owner device report for this branch. Controller and queue test passes do not change these rows.

| Check | Procedure and required evidence | Result |
| --- | --- | --- |
| Early audible playback | Long real Ollama reply, `af_heart`; actual sound before real source EOF. Record common-clock duration or explicit ordering and observed startup delay, not network chunk count | Pending |
| Three untouched hands-free turns | Start once, let three replies finish, use earlier context in a follow-up. Report retained context without quoting it. Listening resumes only after validated done and the last played sample | Pending |
| Continuity | During normal trusted-tailnet turns, no missing, repeated, reordered audio or audible gaps | Pending |
| End before done | During playback while EOF is still pending, tap End. Audio/capture stop and connection closes; no later callback restarts them | Pending |
| End after done before drain | With validated done observed and queued audio still playing, tap End. Audio stops, connection remains Ready; Start works without reconnecting | Pending |
| Temporary underrun | Hold later source data with the deterministic fixture, let the queue drain, then release. Same reply resumes in order, mic stays off until EOF plus drain | Pending |
| Mid-stream source/server failure | Stop the local sidecar during active generation, and separately stop Convoke during playback. Error visible, playback/capture stop, no macOS fallback, retry or automatic restart | Pending |
| Background | Background during buffering/playback. Audio/capture stop and connection closes; no late callback restart | Pending |
| Disconnect | Tap Disconnect during playback. Everything stops, no automatic reconnect or restart | Pending |
| Audio interruption/configuration change | Exercise a real iOS audio interruption and route/engine configuration change. Playback/capture stop, visible error/disconnect, no stale callback restart | Pending |
| Privacy | Inspect only content-free diagnostics. No persisted transcript/audio or content logging introduced during verification | Pending |

For reproducible delayed-stream logic, the existing deterministic fixtures run without models or hardware:

```sh
swift test --package-path server --filter testHTTPHeadersPiecesAndEOFAreIndependent
swift test --package-path server --filter testGatedSocketAndSynthesisOrderingAcrossTwoTurns
swift test --package-path ios/Convoke --filter ResponseLifecycleTests
swift test --package-path ios/Convoke --filter PCMPlayerQueueRegressionTests
```

These are test-only injected fixtures, not a runnable server mode for a physical iPhone. They prove gate/underrun logic, not audible recovery. A physical delayed-stream check needs an explicitly test-only in-memory source gate in the owner's debug session; do not point the production sidecar at an untrusted proxy or present the unit fixture as device evidence. If that setup is unavailable, leave the physical underrun row Pending and request assistance here. No artificial delay may be used as the real-Kokoro early-playback acceptance result.

## Reporting

Copy this document into the PR or ticket with the Result and results-table columns filled in. Slice acceptance is complete only when every automated row and every checklist row is `Pass`. A `Fail` or an unrun row must stay visible; do not edit expected results to match observed behavior.
