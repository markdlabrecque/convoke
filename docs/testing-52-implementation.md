# D6–D7: embedded WebSocket metadata and close-payload ownership

## Scope and base

Issue #52, part of #47. Test-only; no production extraction, dependency, CI,
clock/deadline, cancellation, or timeout changes. Started at main `b7f70d1`.
PR #54 actually merged into `factory-v2-migration`, not main. Its isolated
merge diff (`c0f3f127`, first parent) is preserved here, without the Factory
migration, to retain #51's D1–D5/P4 work.

## Fixture and assertions

`EmbeddedConnectionFramesTests` invokes **the real
`ConversationUpgrader.applyUpgrade(...).upgrade(...)`**, using an
`EmbeddedChannel` and a Vapor application with no listening server. This avoids
copying/inventing the private `StrictTextFrames` implementation. Installed order:

```text
WebSocketFrameEncoder (outbound)
ByteToMessageHandler<WebSocketFrameDecoder> (inbound)
ConnectionFrames
NIOWebSocketFrameAggregator
DeliveredFrames (passive test probe only)
StrictTextFrames
WebSocketKit.WebSocketHandler (real close responder)
```

The context probe is relocated after upgrade; all production handlers remain
installed in their original relative order. Inputs are encoded bytes with a
zero-valued four-byte mask, so decoding preserves both bytes and mask metadata.
The event loop is explicitly run; close deadlines use embedded time, not sleeps.
Each row gets a fresh channel and real handler state. Four applications total
(one per matrix), **zero real-server starts** for all 51 embedded rows.

- Metadata: output must be exactly one unmasked close 1002, no other output,
  no forwarded frame, no inbound tail delivery, and inactive channel. A valid
  initial fragment is first shown to remain buffered; invalid initial fragments
  must be rejected even without FIN. Invalid continuation metadata cannot be
  hidden by aggregation.
- Invalid closes: exact single close 1002 (length/code) or 1007 (UTF-8), no
  forwarding, no extra output, inactive channel.
- Valid closes: exactly one complete original close payload forwarded downstream
  of aggregation, including every reason byte; real WebSocketKit echoes the
  **code only**, as before. Exact single close output and inactive channel.
  Empty payload maps to code 1000. We do not claim WebSocketKit echoes reasons.
- `assertReply` compares the complete encoded output to four expected bytes,
  rather than inspecting only the first emitted frame.

## Exact row ownership

All owners below are methods on `EmbeddedConnectionFramesTests`. Every original
row survives. **Source/baseline count correction:** the issue says 13 invalid
length/code rows and 51 total, but main's source actually has 12 and 50. The
baseline run confirms 50 server starts. Added invalid reserved code 1999 is
identified below; it is not misrepresented as a moved baseline row. New embedded
total is 12 + 13 + 5 + 21 = **51**.

### D6 — `testMaskAndReservedBitsAreRejectedBeforeAggregation`

Every row: 1002, no downstream/application delivery, closed.

| ID | Frame placement | Metadata fault |
| --- | --- | --- |
| M01 | Complete initial text | Unmasked |
| M02 | Complete initial text | RSV1 |
| M03 | Complete initial text | RSV2 |
| M04 | Complete initial text | RSV3 |
| M05 | Non-final initial text | Unmasked |
| M06 | Non-final initial text | RSV1 |
| M07 | Non-final initial text | RSV2 |
| M08 | Non-final initial text | RSV3 |
| M09 | Final continuation after valid initial fragment | Unmasked |
| M10 | Final continuation after valid initial fragment | RSV1 |
| M11 | Final continuation after valid initial fragment | RSV2 |
| M12 | Final continuation after valid initial fragment | RSV3 |

### D7 — `testInvalidClosePayloadLengthsAndStatusCodes`

Every row: 1002, no forwarding, closed.

| ID | Payload/code |
| --- | --- |
| I01 | Single byte `01` |
| I02 | 0 |
| I03 | 999 |
| I04 | 1004 |
| I05 | 1005 |
| I06 | 1006 |
| I07 | 1015 |
| I08 | 1016 |
| I09 | 1999 (**added**, not a baseline row) |
| I10 | 2000 |
| I11 | 2999 |
| I12 | 5000 |
| I13 | 65535 |

### D7 — `testInvalidCloseReasonUTF8`

Each reason follows valid code 1000. Every row: 1007, no forwarding, closed.

| ID | Reason bytes |
| --- | --- |
| U01 | FF |
| U02 | C3 |
| U03 | C0 AF |
| U04 | ED A0 80 |
| U05 | F4 90 80 80 |

### D7 — `testValidClosePayloads`

Every row: original complete payload forwarded, exact code-only echo, closed.

| ID | Payload | Echo code |
| --- | --- | --- |
| V01 | Empty | 1000 |
| V02 | 1000 | 1000 |
| V03 | 1001 | 1001 |
| V04 | 1002 | 1002 |
| V05 | 1003 | 1003 |
| V06 | 1007 | 1007 |
| V07 | 1008 | 1008 |
| V08 | 1009 | 1009 |
| V09 | 1010 | 1010 |
| V10 | 1011 | 1011 |
| V11 | 1012 | 1012 |
| V12 | 1013 | 1013 |
| V13 | 1014 | 1014 |
| V14 | 3000 | 3000 |
| V15 | 3999 | 3999 |
| V16 | 4000 | 4000 |
| V17 | 4999 | 4999 |
| V18 | 1000 + `goodbye` | 1000 |
| V19 | 1000 + `À bientôt 🌍` | 1000 |
| V20 | 1000 + U+FFFD | 1000 |
| V21 | 1000 + 123 ASCII x bytes (125-byte control payload) | 1000 |

## Raw-wire installation ownership

`ConnectionLifecycleTests.testWireUpgraderRejectsUnmaskedAndReservedContinuation`
owns M09/M10 as **two installation sentinels**, checking close 1002 rather than
agent output, then TCP EOF. It exercises the real HTTP route/upgrader, not only
an embedded invocation. Other metadata combinations execute only embedded.

`ConnectionLifecycleTests.testWireClosePayloadSentinels` owns five installation
and byte-handling sentinels: prohibited code 1004 → 1002; reason FF → 1007;
empty → 1000; private 4999 → 4999; valid U+FFFD reason → 1000. Each checks exact
close payload and TCP EOF. Other close combinations execute only embedded.

The old four exhaustive wire methods are replaced, not retained alongside a
second exhaustive matrix. Raw-peer helpers remain. The following lifecycle
methods are unchanged: invalid close acknowledgment; nonacknowledging peer
error/timeout; blocked-write close deadline; conversation release; suspended
consumer cleanup. `StreamingFailureTests` and all production files are unchanged.

## Local execution evidence (Linux, Swift 6.4.2)

Commands run without real sidecar/system voice or credentials:

```sh
# Before editing, after preserving #51:
swift test --package-path server --filter 'ConnectionLifecycleTests.test(MaskAndReserved|InvalidClosePayload|InvalidCloseReason|ValidClosePayload)'
# First prove new matrices before reducing wire coverage:
swift test --package-path server --filter EmbeddedConnectionFramesTests
# After wire reduction:
swift test --package-path server --filter 'EmbeddedConnectionFramesTests|ConnectionLifecycleTests.testWire'
swift test --package-path server
```

- Before: 4 methods, 50 real-server starts (counted `Server started` lines),
  0 failures, XCTest 0.259 s. Initial dependency/build log reports 39.97 s build;
  baseline command wall time was not separately measured.
- Embedded-only, before deleting exhaustive wire execution: 4 methods, all 51
  rows, 0 failures, XCTest 0.020 s (5.99 s build).
- After focused: 6 methods, 7 real-server starts (counted log lines), 0 failures,
  XCTest 0.112 s (wire 0.104 s, embedded 0.007 s; rounded), wall 7.787 s including
  incremental build. This is a single observation, not a promised speedup.
- Full: 53 methods, 1 optional Kokoro skip, 0 failures, XCTest 6.335 s,
  command wall 10.941 s. All 7 `StreamingFailureTests` pass on this Linux run;
  this does not erase known Apple upstream peer-close failures or resolve #27.
- Local Mac execution **Pending**: this host is Linux; no Apple SDK. Hosted
  evidence will be reported on the PR, with the tested SHA and actual check
  conclusions. A sibling branch's Mac result is not evidence for this SHA.

Logs were captured locally in `/tmp/52-{baseline,embedded,focused,full}.log`;
wall times use Bash `time` (GNU `/usr/bin/time` is not installed). Hosted CI
results, not these machine-local paths, are the durable merge gate.
