# Slice 4 physical acceptance session

## Closure and remaining work

[Issue #30](https://github.com/markdlabrecque/convoke/issues/30) is closed at the owner's explicit request after the November 16, 2026 MST acceptance session. This is an administrative closure with remaining work deferred, not full Slice 4 acceptance. [Epic #25](https://github.com/markdlabrecque/convoke/issues/25) and [dependency #27](https://github.com/markdlabrecque/convoke/issues/27) were not marked complete by this session.

- Real iOS interruption and audio-route/configuration-change checks remain **Pending, deferred**.
- Missing visible failure explanations on both development-server loss and Kokoro loss remain **Fail, acceptance discrepancies**. Playback stops and explicit recovery work, but the owner saw only Disconnected, without an error message.
- The historical opt-in simulator audio-initialization failure did not reproduce on a later opt-in run at `ef74132`: **3 passed, 0 failed, 0 skipped** on an iPhone 17 simulator (iOS 27.2, build `24B8117`). The retained `optional-engine.xcresult` summary was read back on the development Mac with `xcrun xcresulttool get test-results summary`. This is evidence for that simulator run only, not proof of a general fix or of physical-device interruption or route behavior.

The [development guide](development.md#physical-checklist-and-results) contains the consolidated physical table. Historical Linux, Mac and CI results remain at their original revisions. This session does not retroactively pass failed or unavailable checks.

**Later disposition:** [Slice 4](https://github.com/markdlabrecque/convoke/issues/25) was closed at the owner's request with exceptions. Real interruption and route changes remain unverified. The failure-message fix shipped in [#85](https://github.com/markdlabrecque/convoke/issues/85), but the physical server-loss and Kokoro-loss retests were waived, not passed. The original results below are unchanged.

## Environment and provenance

| Field | Session value / evidence |
| --- | --- |
| Date / timezone | November 16, 2026, MST. Some GitHub comments are dated November 17 in UTC. |
| Runtime revision | `ef74132a56668d8b614393f3a2b09eb724c8591d`. Installed iPhone revision was owner-reported. Ordinary Mac server uses this revision; EOF observations used a temporary instrumented build of the same runtime. |
| Checkout | `/Users/mark/Projects/convoke`; clean `main` confirmed during the End, underrun and privacy checks. Temporary helpers/builds lived under `/tmp`, not in committed application sources. |
| Mac | Apple M4 Pro development Mac; macOS 27.0.1, Xcode 27.2, per session environment record. |
| Phone | iPhone 17, iOS 27.0.1, owner-confirmed; built-in speaker. |
| Agent | Real local Ollama, `llama3.2`, `http://127.0.0.1:11434/v1`. No stub agent used for physical turns. |
| Speech | `ghcr.io/remsky/kokoro-fastapi-cpu:v0.10.0`, voice `af_heart`. |
| Image digest | `sha256:f54c5960c2b9387f6349080a9944f8bc7e8cdb98a4ef9238cb0b0f9ff9795f44`. |
| Sidecar privacy | Replaced before physical testing with log-disabled Kokoro. Docker inspection confirmed log driver `none`, empty LogPath, no mounts, and host binding only `127.0.0.1:8880`. This does not change the historical November 14 json-file container record. |
| Service management | Development services in Rex, not tmux. No production or credential-store access. |
| Physical observations | Owner-reported audio/UI/recognition behavior, not independently observed acoustic measurements or device callback tracing. Source events, service termination/restoration and temporary diagnostics were inspected directly where stated below. |

The merged Mac cancellation peer correction and gate supersede the old five-assertion blocker. [Post-merge main run 43998453989](https://github.com/markdlabrecque/convoke/actions/runs/43998453989) is the session handoff's passing gate reference. The correction was fixture-only, not a production cancellation change. See the [hosted Mac evidence](development.md#hosted-mac-server-gate-evidence-issue-48) for the diagnosis and earlier actual counts. No new complete build/test suite result is inferred from the physical session.

## Physical results

| Check | Result and basis |
| --- | --- |
| Three untouched hands-free turns | **Pass, owner-reported.** Three complete replies without controls between turns, earlier context retained, Listening only after the final audible sound. End while Listening retained Ready. No direct final-sample/done instrumentation claimed. |
| Continuity | **Pass, owner-reported.** No missing, repeated, reordered audio or unexpected audible gaps in normal turns. |
| Background | **Pass, owner-reported.** Home during audible playback stopped audio/capture; ten seconds in background and ten seconds after return produced no restart or automatic reconnect. Explicit Connect/Start recovered with no leftover audio. |
| Disconnect | **Pass, owner-reported.** Disconnect during audible playback stopped audio/capture; ten seconds without restart/reconnect. Explicit Connect returned Ready without listening; explicit Start completed a fresh turn normally. |
| Server loss | **Fail overall.** Agent stopped the development server during owner-reported active playback and verified no listener on 8080. Audio stopped and app became Disconnected, Start disabled. Owner saw no failure explanation. No automatic restart and successful explicit recovery were confirmed after restoration. An earlier inconclusive attempt is not counted. |
| Sidecar loss | **Fail overall.** Actual source truncation before EOF confirmed directly; active playback, prompt stop, Disconnected, no fallback/restart and explicit recovery confirmed by owner. No visible failure explanation. |
| Early audible playback | **Pass.** Owner-marked first sound preceded genuine successful source EOF by 27.523887 seconds on the same Mac monotonic clock. Full reply continued uninterrupted. Details below. |
| End before done/source EOF | **Pass, owner-reported with source evidence.** Active audio stopped promptly, Disconnected, capture off, no restart/reconnect for ten seconds. Explicit Connect returned Ready without listening. |
| End after done before drain | **Pass, owner-reported with source evidence.** Still-audible reply stopped, connection remained Ready, no restart for ten seconds, Start worked without reconnecting; fresh turn and subsequent End worked normally. |
| Temporary underrun | **Pass, owner-reported.** About one second of audio, nine seconds of silence while still Playing, then same reply resumed automatically. No obvious repeat/skip. Listening only after completion; a phrase spoken during the pause was not treated as another turn. Follow-up and End worked. |
| Real interruption | **Pending, deferred.** Owner could not perform it during the session. |
| Route/configuration change | **Pending, deferred.** Headphones connected but playback stayed on the phone; connection type unconfirmed. No active-headphone-route disconnect test completed. Missing Bluetooth-routing options are a possible explanation, not a confirmed diagnosis. |
| Privacy | **Pass for this session.** Technical review plus explicit owner confirmation. Scope and limits below. |

## Content-free ordering and failure evidence

### Genuine early playback

A temporary direct-source probe recorded successful HTTP response-body EOF in `BodyPuller.next()`. No relay, sleep, artificial EOF gate or source termination was used. The original source was restored byte-for-byte; default server build/tests passed before the instrumented server ran. The phone was not reinstalled.

The Ghostty helper timestamped Enter presses after the phone showed Waiting and immediately after the owner first heard reply audio. Both markers and source events used Mac `CLOCK_MONOTONIC`; phone and Mac wall clocks were not compared.

| Event | Monotonic seconds |
| --- | --- |
| Manually marked Waiting/submission | 862504.385479 |
| Source response start | 862509.462468 |
| Owner first-sound marker | 862514.944846 |
| Genuine source-body EOF | 862542.468733 |

Matching request ID: `F4634AC5-60BD-44F1-A8D1-9BACDCD2C692`. Sound marker was **27.523887 s before EOF**; manually marked submission-to-sound was approximately **10.559367 s**. Human reaction/key timing is not an automated acoustic latency measurement. No latency SLA applied. Owner confirmed uninterrupted completion and return to Listening.

Local artifact: `/tmp/convoke-eof-observation-E4alTh/result-1794892988060761000.json`, with matching `events.jsonl`. The helper stored timestamps/status only.

### Both End windows

Before-EOF request `DD10ACFC-0FCF-4308-AA06-116FAB7FABC1`: source-start `863201.748203`, manual pre-End marker `863205.555203`, post-End marker `863209.069611`. No successful source EOF event through the observation period. Absence alone is not a pass; it is paired with the owner-confirmed audible playback and End-triggered Disconnected result.

After-EOF request `8186042C-51E2-44B2-BB32-8A220BE48CE5`: source-start `863352.444609`, successful source EOF `863387.108948`, pre-End marker `863392.978029`, post-End marker `863398.038487`. EOF preceded the pre-End marker by **5.869081 s**.

All times use Mac `CLOCK_MONOTONIC`. Source EOF alone does not prove phone `agent.done` validation. The owner-confirmed Ready result and successful Start without reconnecting distinguish the controller's post-done End path; still-audible playback establishes that the queue had not drained. Internal device callbacks were not independently inspected.

Artifacts under `/tmp/convoke-eof-observation-E4alTh/`:

- `end-before-1794893664638272000.json`
- `end-after-1794893853604857000.json`

### Real sidecar failure

Temporary loopback relay `127.0.0.1:8882` forwarded pinned Kokoro, with no injected delay or fabricated error. A one-shot trigger killed the actual container after PCM forwarding began and at least one second had elapsed since first PCM. Synthetic integration checks passed on Linux and Mac; one unarmed real-Kokoro smoke passed before arming. This setup was only failure evidence, not latency evidence.

Relative to relay request start: first PCM **3.458822 s**, kill trigger **6.298569 s**, failure completion **6.572091 s**; **1,468,058 PCM bytes** forwarded. HTTP 200/chunked; Docker kill exit 0; actual source read failed, source EOF was not reached. Convoke still listened on 8080. Owner heard a mid-word cutoff, then Disconnected without an error explanation. After restoration, owner confirmed no automatic fallback/restart and successful explicit recovery. Local artifacts: `/tmp/convoke-kokoro-observer-6VHrdj/`.

### Deliberately delayed underrun

A separate test-only loopback relay `127.0.0.1:8883` forwarded exactly **48,000 bytes**, one second of 24 kHz mono s16 PCM, held downstream forwarding **10 seconds**, then resumed the same response. Upstream data stayed in bounded memory. Downstream EOF was held if necessary. This was intentionally delayed delivery, never genuine synthesis latency or early-playback evidence.

Preflight results, separate from physical results:

- Nine synthetic relay tests passed, zero failures/errors; checked exact gate byte count, withheld EOF, identical resumed data, one-shot consumption, source failure and size limits.
- Unarmed real-Kokoro smoke: one test, zero failures; 102482 bytes.
- Armed real-Kokoro smoke: one test, zero failures; 102488 bytes. Gate start `0.744938625 s`, release `10.7504065 s`, first post-gate bytes `10.752016375 s`, successful completion.

The owner confirmed the physical nine-second audible silence, Playing throughout, and normal resume. The guided follow-up replaced the relay's latest-request state before inspection. Consequently **no precise physical-request gate timings are claimed**. `owner-followup-state.json` records an unarmed successful follow-up, equal source/forwarded counts of 732988 bytes, no failure. Preflight timings are not relabeled as physical timings.

Local artifacts: `/tmp/convoke-underrun-test/{gated-smoke.log,gated-smoke-state.json,owner-followup-state.json}`.

## Commands and temporary setup limits

Ordinary server configuration, run in Rex from the repository root:

```sh
export CONVOKE_AGENT_BASE_URL=http://127.0.0.1:11434/v1
export CONVOKE_AGENT_MODEL=llama3.2
export CONVOKE_KOKORO_URL=http://127.0.0.1:8880
export CONVOKE_KOKORO_VOICE=af_heart
unset CONVOKE_EOF_OBSERVATION_FILE
server/.build/debug/ConvokeServer serve --hostname 0.0.0.0 --port 8080
```

Temporary End helpers, executed in Ghostty:

```sh
python3 /tmp/convoke-eof-observation-E4alTh/end_windows.py before
python3 /tmp/convoke-eof-observation-E4alTh/end_windows.py after
```

Underrun preparation commands actually used:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 /tmp/convoke-underrun-test/self_test.py
# Relay was run separately in Rex; it binds only 127.0.0.1:8883.
PYTHONDONTWRITEBYTECODE=1 python3 /tmp/convoke-underrun-test/relay.py
# Before each armed smoke or the single physical gated request:
curl -s -o /dev/null -w 'Arm HTTP %{http_code}\n' -X POST http://127.0.0.1:8883/arm
CONVOKE_TEST_KOKORO_URL=http://127.0.0.1:8883 CONVOKE_KOKORO_VOICE=af_heart \
  swift test --package-path server --skip-build --filter ConversationTests.testKokoroSidecarSmoke
```

For the physical underrun only, the Rex-managed server used `CONVOKE_KOKORO_URL=http://127.0.0.1:8883`. For EOF observations only, the temporary binary `/tmp/convoke-eof-observation-E4alTh/ConvokeServer` used `CONVOKE_EOF_OBSERVATION_FILE=/tmp/convoke-eof-observation-E4alTh/events.jsonl` with the direct sidecar URL. These files are session-local artifacts, not checked-in runnable test modes. They may disappear; do not assume a fresh checkout supplies them. Any future physical debug gate needs its own reviewed setup and provenance. Unit fixtures alone are not phone evidence.

Cleanup verified after the tests: ordinary direct-to-Kokoro server listening on 8080, healthy Kokoro HTTP 200, temporary underrun relay stopped and 8883 closed. Temporary failure relay and EOF-instrumented server were also replaced/stopped. Ordinary development services were left running, not all stopped. Server replacements required explicit phone reconnects; no automatic reconnect was added.

## Privacy review and limits

Source review found on-device recognition, in-memory capture/playback and per-connection server history, no app transcript/audio file writer, server-URL-only UserDefaults persistence, and content-free application log calls. Reviewed temporary helper/probe/relay sources and JSON/JSONL structures store counts, durations, IDs and status flags, not transcript/audio bodies. Inspected smoke logs contain ordinary test/status/size/timing output.

Active settings confirmed direct local Ollama/Kokoro URLs, no EOF probe variable on the restored server, Kokoro Docker logging disabled, no container mounts, and Ollama debug environment unset. Ollama stdout/stderr remained on its existing terminal. These settings do not reconstruct pre-session third-party behavior.

Owner explicitly confirmed no screen/audio recordings, saved spoken transcripts, network request/response body captures, or additional recognized-speech/reply/audio logging during acceptance. Privacy is **Pass for this session**, not a forensic guarantee about OS/framework caches, swap, crash reports, third-party internals or unrelated existing files. Temporary sources, binaries, build/test logs and content-free diagnostic records remain on disk; no deletion is claimed.
