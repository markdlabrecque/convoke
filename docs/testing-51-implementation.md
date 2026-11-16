# #51 implementation result: server audio/protocol pruning

Implementation: `787e5902577da427bf5835061c000540cdab0e39`, based on
`734561ed9386c3fcc8a9e31a6fac2b498311bd13`. Recovery adds this missing
handoff, not a second test refactor. The original worktree was clean.

## Recovery diagnosis and test policy

The previous verifier returned **INCONCLUSIVE**, not a behavior failure: the
writing-tests skill was absent from that sandbox, and the commit message lacked
a complete named assertion map and timing handoff. Its Linux checks passed.
During recovery the now-provisioned
`/home/agent/.pi/agent/skills/writing-tests/SKILL.md` and
`docs/development.md` were read, and the delivered tests were reviewed against
them. No `TESTING.md` is present.

The moved decisions belong at **unit tier**: `AudioFramer`,
`ConversationProtocol`, and both `SpeechAudio` whole-reply adapters are invoked
without a server. Existing **functional real-wire sentinels** remain necessary
for serialized sequence/done counts, connection reuse, distinct binary/decoder
routes, and close/no-done behavior; pure API calls cannot establish those
boundaries. No new expensive tests or production interfaces are needed.

The added owners and reduced wire rows were delivered together in one atomic
implementation commit; no delivered commit removes coverage without its owner.
Git snapshots cannot establish the original within-commit editing order. This
handoff does not invent that history or undo/reapply correct tests to simulate it.
The cheaper owners are present and passing in the retained verification evidence.

## Exact assertion ownership

All methods below are in
`server/Tests/ConvokeServerTests/ConversationTests.swift`.
The cap is 8,388,608 bytes; the maximum audio chunk is 16,384 bytes.

| Decision / retired row or assertion | Surviving named owner and assertion |
| --- | --- |
| P4: `testAudioFramerSplitsCarriesAndEnforcesCap`, initial one-byte carry and exact two-full-frame split | `testSampleAndFrameBoundaryMatrixAndCumulativeCarryCap`: first push emits zero chunks; next push emits exactly `[16_384, 16_384]`. |
| P4: odd finish and recovery by appending missing byte | Same owner: `finish()` throws with a carried half sample; appending `[0]` and subsequent `finish()` both succeed. |
| P4: empty-stream finish rejection | Same owner: a fresh `AudioFramer().finish()` throws. |
| P4: exact-cap acceptance and one-/two-byte overflow rejection | Same owner: accumulate to cap-minus-one, reject odd EOF, append `[7]`, assert total equals cap and finish successfully; pushing `[8]` and `[8, 9]` each throws. |
| P4: original keeper's sample/frame split matrix | Same owner retains splits `0, 1, 2, 16_383, 16_384, 16_385, 32_769, pcm.count`, immediate whole-sample forwarding, byte-for-byte reconstruction, nonempty/even/bounded chunks, cumulative byte accounting and valid finish. |
| D1: `testExactChunkAndAudioCapCompletionCounts`, sizes 2, 16,384 and cap | `testExactFramerChunkSizesAndOddSplitCumulativeBoundaries`, first loop: exact chunk-size arrays (respectively `[2]`, `[16_384]`, and 512 full chunks), summed bytes equal input size, and successful finish for each. |
| D1: serialized frame types, sequences, reconstruction, done counts and reuse | Unchanged `testSequentialTurnsAndChunkCounts`: two turns on one connection, text before audio, sequences 0–2, decoded byte reconstruction, done type and count 3. Exact-cap wire success also remains in D2's keeper below. |
| D2: cap-minus-two and exact cap with alternating odd source splits | `testExactFramerChunkSizesAndOddSplitCumulativeBoundaries`, second loop: pushes alternating 16,383/16,385-byte pieces (truncated at EOF); both completed streams finish and emitted/total byte counts equal the requested total. |
| D2: cap-plus-two with those odd source splits | Same pure loop: push crossing the cap throws and rejection is required only for the over-cap row. Real-wire cumulative overflow closure remains in D4's keeper. |
| D2: exact-cap successful streaming remains on wire | `testIncrementalCumulativeBoundaryOnWire`: text first; contiguous audio sequences; nonempty/even/chunk-bounded decoded PCM; total exactly cap; `agent.done.chunks` equals observed chunk count. |
| D3: whitespace-only `user.text` removed from `testInvalidFramesCloseConnection` | `testPrefixAndTrimmedUTF8Limit`: empty and whitespace-only text throw; valid surrounding whitespace is trimmed. |
| D3: excessive 4097-byte ASCII text removed from wire | `testPrefixAndTrimmedUTF8Limit`: UTF-8 byte limit accepts 2048 two-byte `é` characters (4096 bytes) and rejects 2049 (4098 bytes). It owns text-limit arithmetic rather than repeating ASCII on wire. |
| D3: wrong `agent.done` input removed from wire | `testMalformedAndUnexpectedInput`: that exact message type throws, alongside malformed JSON and invalid object/field shapes. |
| D3: pure frame-byte boundary | `testFrameByteBoundary`: exact padded maximum is accepted, one byte beyond throws; oversized output JSON also throws. |
| D3: distinct malformed JSON, binary callback and decoder frame-limit wire routes retained | `testInvalidFramesCloseConnection`: `"{"`, binary `[0, 1]` and a 32,769-byte text frame each close the connection; the synthesizer fails the test if reached. |
| D4: empty and odd-EOF stream rows removed from `testStreamFailuresAfterPartialAudioCloseWithoutDone` | `testSampleAndFrameBoundaryMatrixAndCumulativeCarryCap`: empty finish and carried-odd finish throw, including odd EOF just below the cumulative cap. |
| D4: thrown-after-partial-audio and cumulative over-cap source retained | `testStreamFailuresAfterPartialAudioCloseWithoutDone`: the thrown row must produce actual audio; both rows require 1011 closure, no successful done, bounded audio-frame count and at most cap emitted bytes. This owns overflow/no-done wiring removed from D2. |
| D5: empty, one-byte odd and cap-plus-two whole replies removed from `testSynthesisFailuresCloseConnection` | `testWholeReplyAdaptersValidateAndComplete`: each size is rejected directly by `SpeechAudio.wholeReply` AND through `SpeechAudio.stream(wrapping:)` before streaming. These exercise the supported adapter, not merely `validateAudio`. |
| D5: valid whole-reply compatibility and completion | Same pure owner: both direct and wrapped adapters yield exactly `[Data([1, 2, 3, 4])]`; iteration reaches successful EOF. |
| D5: unavailable synthesizer and generic synthesis error remain on wire | `testSynthesisFailuresCloseConnection`: both rows receive `agent.text`, then closure with 1011. |

No production code, limits, imports, discovery/membership, workflows, scheduling,
simulator selectors, or D6–D7 metadata/close matrices changed. The early-audio,
two-turn ordering, valid/invalid fragmented UTF-8, opcode/overflow, history/agent
failure, cancellation, lifecycle and actual HTTP-boundary tests remain unchanged.
In particular, `StreamingFailureTests` and their tolerances are untouched.

## Measured verification evidence

The retained previous verifier artifacts under
`/home/agent/evidence/51/history/` record these actual Linux Swift 6.4.2 results.
These are previous-run observations, not fresh recovery executions:

| Revision / command | XCTest result and duration | Command wall time |
| --- | --- | --- |
| Baseline `734561e`: `swift test --package-path server` (`baseline-server-full.txt`) | 51 total, 50 passed, 1 optional Kokoro skip, 0 failures; 7.497 s | 14.969 s |
| Implementation `787e590`: same full command, comparison run (`after-comparison-full.txt`) | 51 total, 50 passed, 1 optional Kokoro skip, 0 failures; 6.250 s | 12.114 s |
| Implementation: focused command below (`after-focused.txt`) | 11 passed, 0 skips/failures; 0.781 s | 4.481 s |
| Implementation: first full command after focused (`after-server-full.txt`) | 51 total, 50 passed, 1 optional Kokoro skip, 0 failures; 6.157 s | 9.798 s |
| Implementation: `swift build --package-path server` (`after-build.txt`) | Exit 0 | 4.996 s |
| Implementation: `bash ios/Convoke/scripts/test-portable-core.sh` (`after-portable.txt`) | 73 passed, 0 skips/failures; 0.736 s | 4.438 s |

The exact focused command is:

```sh
swift test --package-path server --filter 'ConversationTests.test(WholeReplyAdaptersValidateAndComplete|ExactFramerChunkSizesAndOddSplitCumulativeBoundaries|SampleAndFrameBoundaryMatrixAndCumulativeCarryCap|IncrementalCumulativeBoundaryOnWire|InvalidFramesCloseConnection|StreamFailuresAfterPartialAudioCloseWithoutDone|SynthesisFailuresCloseConnection|PrefixAndTrimmedUTF8Limit|MalformedAndUnexpectedInput|FrameByteBoundary|SequentialTurnsAndChunkCounts)$'
```

Baseline and comparison runs each rebuilt the changed test file with a reused
cache; the first full implementation run was warm. Wall times include planning,
build and runner overhead; XCTest durations do not. These are individual local
observations, not a controlled benchmark or a promised percentage improvement.
The previous timing summary counted 110 baseline versus 97 implementation Vapor
server-start log events despite unchanged total test count: rows moved to pure
tests rather than being hidden in a single large wire scenario.

## Fresh recovery checks (November 16, 2026, Linux Swift 6.4.2)

Run in order against the unchanged implementation plus this handoff. Exact
commands/output are retained in `/home/agent/evidence/51/recovery-*.log`.

| Command | Actual result | Command wall time |
| --- | --- | --- |
| `swift build --package-path server` | Exit 0; new sandbox dependency fetch/build | 118.865 s |
| Exact focused command above | Exit 0; 11 passed, 0 skips/failures; 0.728 s XCTest | 7.582 s |
| `swift test --package-path server` | Exit 0; 51 total, 50 passed, 1 optional Kokoro skip, 0 failures; 6.431 s XCTest | 9.910 s |
| `bash ios/Convoke/scripts/test-portable-core.sh` | Exit 0; 73 passed, 0 skips/failures; 1.023 s XCTest | 4.608 s |

All seven `StreamingFailureTests` passed on Linux. No failed run was retried or
hidden. `git diff 787e590 -- server ios protocol .github .factory` is empty;
recovery preserves all implementation/test/workflow bytes. The trailing Swift
Testing zero-test summary is separate from the nonzero XCTest totals above.

## Platform limitations

Compatible Mac server checks: **Pending** for the owner after merge. This recovery
sandbox is Linux without Xcode, xcrun, Apple SDKs or a physical iPhone. The known
actual Mac upstream HTTP-close failures documented in `docs/development.md`
remain failures owned by #27, not waived or repaired by a Linux pass. Mac-only
cases are excluded on Linux, not counted as passing. Real Kokoro and system voice
remain opt-in; the default Kokoro skip is not a real-sidecar pass. The portable
core harness uses a test-only Combine stand-in and is not an Apple-platform pass.
No host workflow update, service change, credential or remote access is needed
for this handoff repair.
