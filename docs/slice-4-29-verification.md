# Slice 4 deterministic regression verification

Historical implementation snapshot. Statements below that #30 is idle or hardware checks are Pending apply to this implementation run. See the [later automated evidence](development.md#automated-checks) and [November 16 physical session and closure](slice-4-30-device-session.md) for subsequent results. Issue #30 is closed at owner request with real interruption/route checks deferred and visible failure-message discrepancies unresolved, not fully accepted. Deterministic fixtures remain distinct from physical evidence.

## Base and scope

Implements #29 against the full approved plan and Q&A on #25. Fetched origin, then created `slice-4-29` in the existing `code/main` checkout from `origin/main` at `1dd4b1c85bbe5c9950858b3546d0b86fd864ad5f`.

- #27 is present as `05e7ed2`, merged through PR #33. Its ancestor check against `origin/main` exited 0.
- #28 is present as `1dd4b1c`, merged through PR #34. `git diff c465d6770c6220007c560e0fd1918c7a491e29af origin/main --stat` was empty, confirming the supplied pre-merge tree is present.
- Read `docs/development.md`, both predecessor verification records, and the server/iOS READMEs. No repository-local agent instructions were found outside dependency checkouts.
- No production code, wire contract, dependencies, or Xcode project configuration changed. The Swift package excludes the new scripts directory from its test target to avoid an unhandled-file warning. No tests were retired or assertions removed. The existing smoke assertions remain and have additional source-side diagnostics.
- `code/develop` and its files were not used or modified. The pre-existing untracked `docs/hands-free-plan.html` and `docs/hands-free-plan.packed.html` were left untouched and uncommitted.
- No production access, 1Password, models, hardware, content logging, persisted audio/transcripts, new threads or subagents. #30 remains idle; this is not epic or physical acceptance.

## Regression matrix

New ordering tests release protocol operations or fake completions explicitly. Timeouts bound hangs or exercise the actual server deadline; no test asserts a tight elapsed-time target. Existing tests remain part of the matrix rather than being replaced by parallel copies of production code.

| Contract | Coverage | Linux outcome |
| --- | --- | --- |
| Independently released HTTP headers, body pieces and EOF; consumer PCM before EOF | New `KokoroTests.testHTTPHeadersPiecesAndEOFAreIndependent`, real loopback NIO HTTP peer. PCM arrives while EOF is still withheld, for audio/pcm, audio/l16, audio/x-pcm and a parameterized content type | Pass |
| Streaming request shape, whole-sample raw PCM, arbitrary odd/empty body splits, empty/incomplete EOF, no container sniffing | Existing Kokoro request/body-puller tests retained. Status/type rejection also extended to 204, octet-stream and empty content type | Pass |
| Actual truncated HTTP framing and cancellation of real upstream HTTP work | Existing `StreamingFailureTests`, including failure after partial PCM, body-read cancellation, cancellation/failure during a suspended write, disconnect and timeout with upstream channel closure | Pass |
| Synthesis waits for text write; socket backpressure suspends source; audio precedes source completion; exact text/audio/done order across two complete turns | New `ConversationTests.testGatedSocketAndSynthesisOrderingAcrossTwoTurns`. Text, each audio write, source EOF and done write have separate gates; carried sample and sequence reset checked on both turns | Pass |
| Exact sample/frame boundaries and immediate usable-sample forwarding | New `testSampleAndFrameBoundaryMatrixAndCumulativeCarryCap`, splits at 0/1/2/16383/16384/16385/32769/end; reconstructs exact PCM and checks each frame. Existing exact 16384-byte and 8 MiB completion-count tests retained | Pass |
| Cumulative streamed cap, not just a per-piece check | New `testIncrementalCumulativeBoundaryOnWire`, pull-driven odd-sized pieces at 8 MiB minus 2, exactly 8 MiB and plus 2. Checks sequence, sample alignment, frame bounds, total, exact done count or 1011 without done. Framer test includes pending half-sample accounting | Pass |
| Partial failure cannot become successful done | Existing thrown/odd-EOF/empty/overflow wire tests retained, plus incremental overflow test | Pass |
| Cleanup of suspended producers and consumers on slow writes, disconnect, deadline and write failure | New `ConnectionLifecycleTests.testSuspendedSocketConsumerCleansUpOnDisconnectDeadlineAndFailure`. Producer must exit without consuming its next piece; late write completion is harmless. Existing real-upstream cancellation tests retained | Pass |
| Deadline includes final done write; close cannot wait forever on a write; conversation released after closure | Existing `StreamingFailureTests.testDeadlineRemainsActiveThroughStalledDoneWrite` and connection lifecycle tests retained | Pass |
| Protocol validation and malformed wire metadata | Existing input size/UTF-8/fragmentation, masking, reserved-bit, close status/reason/deadline and overlapping-turn tests retained | Pass |
| Audio events before done without accumulated Data; strict keys/types/order/count; frame/total bounds; post-done rejection | Existing response/streaming-bound tests retained. New `testStrictAudioKeysTypesAndPostDoneFrames` and `testIncrementalEventsRetainOnlyScalarStateAtExactJSONBoundary`, including exact 32768-byte JSON acceptance and overflow rejection | Pass, limited core harness |
| EOF and playback completion independently gated in both orders; capture resumes exactly once; sequential hands-free turns | New `ResponseLifecycleTests.testIndependentlyGatedEOFAndPlaybackAcrossSequentialHandsFreeTurns`. Three complete turns per order, fake enqueue/read/EOF/capture barriers, no polling or sleep in the new test | Pass, limited core harness |
| End before/after EOF, buffering, underrun, receive/playback failure, background/disconnect, stale reply/connection callbacks | Existing response and session controller tests retained, including short EOF, both drain orders, same-connection restart and stale connection callbacks | Pass, limited core harness |
| 9600-byte startup, short flush, ordered pending/scheduled accounting, exact cap/release/overflow, underrun, stop and stale callbacks | New hardware-free `PCMPlayerQueueRegressionTests` in PCMPlayerTests.swift adds threshold matrix, per-buffer accounting in both EOF orders and repeated underruns. Existing production queue/lifetime tests retain cap, stop, interruption and stale-ID settlement coverage | Pass, limited core harness |
| PCM sample conversion and actual AVAudioEngine scheduling/callbacks | Existing conversion tests retained behind `canImport(AVFoundation)`; no production adapter changes | Pending, Apple runtime required |
| Live receiving and heartbeat while playback completion is held | New `WebSocketTransportTests.testReceiveAndHeartbeatContinueWhilePlaybackCompletionIsGated`, actual transport plus fixed loopback reply. Waits for done while fake playback is suspended, then arms observation of the next ping; ordered buffers and microphone gate checked | Pending, macOS-only test |
| Independently bounded raw frame count and raw bytes | Existing unread frame-count and heartbeat tests retained. New `testUnreadByteCapDisconnectsBelowFrameCountCap` sends 513 legal 32768-byte frames, over 16 MiB but below 1024 frames, while consumer is held | Pending, macOS-only test |
| Real-sidecar opt-in smoke | Extended `testKokoroSidecarSmoke` records first source PCM and source EOF separately from first wire audio and wire done, using one monotonic request start. Checks source/wire byte equality, nonempty aligned bounded chunks, non-silence, contiguous sequences and exact completion count. Emits sizes/durations/counts only, no URLs or content | Skipped by default; real sidecar Pending |

The queue and lifetime checks exercise the helpers used by PCMPlayer, not an alternate audio implementation. Ordered enqueue assertions and accounting do not prove AVAudioPlayerNode behavior, memory release by Apple frameworks, audible continuity or early speaker output. Those checks remain Pending. A short smoke reply or several network chunks also does not prove early physical playback.

## Commands and exact results

Run November 14, 2026 on Linux x86_64, Swift 6.4.2, target `x86_64-unknown-linux-gnu`, against this branch's implementation working tree.

| Command/check | Result | Evidence |
| --- | --- | --- |
| `swift build --package-path server` | Pass | Exit 0 |
| `swift test --package-path server` | Pass | Exit 0; 51 tests, 1 skipped, 0 failures. Only opt-in Kokoro smoke skipped. Linux excludes the macOS system-voice test |
| Same server suite, final repeat | Pass | Exit 0; 51 tests, 1 skipped, 0 failures |
| `swift test --package-path ios/Convoke` | Blocked | Exit 1, `no such module 'Combine'`. Not an Apple package pass |
| `bash ios/Convoke/scripts/test-portable-core.sh` | Pass, limited | Exit 0; 73 tests, 0 failures |
| Same portable command, three further fresh-package runs | Pass, limited | Each exit 0; 73 tests, 0 failures |
| `swiftc -frontend -parse ios/Convoke/Tests/WebSocketTransportTests.swift ios/Convoke/Tests/PCMPlayerTests.swift` | Pass, syntax only | Exit 0. No Apple framework type-checking/linking or execution |
| `bash -n ios/Convoke/scripts/test-portable-core.sh` | Pass | Exit 0; script also ran end to end above |
| `git diff --check` | Pass | Exit 0 |
| `xcrun simctl list devices available` | Unavailable | Exit 127; no xcrun. `command -v xcodebuild` also found no executable |
| Simulator build-for-testing/test and unsigned generic iPhoneOS build from docs/development.md | Pending | No Xcode, Apple SDKs or installed simulator here; no destination invented |
| Full macOS package/transport tests, macOS voice build/tests | Pending | Need macOS 26+ and Apple frameworks |
| Opt-in real Kokoro run at 127.0.0.1:8880 | Pending | Health probe `curl --silent --max-time 2 --output /dev/null http://127.0.0.1:8880/health` exited 7. No sidecar listening; no model was started. Default suite correctly skipped the smoke |
| Actual AVAudioEngine, interruptions, configuration notifications, device playback and physical acceptance | Pending | No Apple runtime or device available; owner checks remain in #30 after this dependency |

Prior #28 reported 46 server tests with one smoke skip and 67 limited portable core tests. These are context only, not reused evidence for this branch. This change adds five server test cases, six portable core cases, and two macOS-only transport cases. No old tests were silently retired. Existing server test warnings about an unchanged local `var` and async NSLock use remain; they are not new test failures.

Local full logs are `/tmp/convoke-29-server-build.log`, `/tmp/convoke-29-server-tests.log`, `/tmp/convoke-29-server-repeat.log`, `/tmp/convoke-29-ios-tests.log`, `/tmp/convoke-29-portable-tests.log`, `/tmp/convoke-29-portable-repeat-{1,2,3}.log`, `/tmp/convoke-29-apple-parse.log` and `/tmp/convoke-29-xcrun.log`. They are not committed.

## Reproduction and handoff

The checked-in portable script copies unchanged Core sources and selected test files into a temporary Swift package, supplies a clearly test-only Combine stand-in, runs the tests and removes the temporary package. It does not exercise Combine publishing, AVFoundation, speech capture or the real WebSocket adapter. Use it on Linux for limited regression feedback, never instead of the full Apple package:

```sh
bash ios/Convoke/scripts/test-portable-core.sh
```

On macOS, run the full package and Xcode checks from `docs/development.md`, selecting an actually installed simulator. Start a local sidecar only when intentionally running the opt-in smoke:

```sh
CONVOKE_TEST_KOKORO_URL=http://127.0.0.1:8880 \
  swift test --package-path server --filter testKokoroSidecarSmoke
```

Record actual smoke timings, Apple test results and device evidence separately. Do not merge or declare epic/physical acceptance from Linux test results. #30 has not been started by this work.
