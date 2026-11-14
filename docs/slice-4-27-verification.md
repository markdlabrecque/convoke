# Streaming bounds and failure handling

Implementation for [issue 27](https://github.com/markdlabrecque/convoke/issues/27), based on main at `4ce682b`, branch `slice-4-27`. This is not physical acceptance for Slice 4.

## Bounds and cancellation

- Kokoro's pull reader ignores empty HTTP pieces, carries one trailing byte, and emits only complete Int16 samples. Empty EOF and a trailing half-sample fail. HTTP status/type checks precede delivery. HTTP framing failures propagate after partial delivery. Raw PCM is not sniffed for container signatures. Clean HTTP EOF on a whole sample cannot expose semantic truncation.
- The async PCM consumer awaits each socket write before requesting more source audio. No task-per-chunk producer or application hand-off queue is added. The pinned AsyncHTTPClient body uses NIO's high/low watermarks of 1 body element. Its underlying NIO socket allocator is bounded at 65536 bytes per read, with at most four reads per read cycle. Watermark overshoot/read-ahead is therefore bounded transport buffering, not a collected response. These are pinned dependency implementation details to recheck on upgrades, not a claim of zero read-ahead.
- The framer emits usable samples immediately, up to 16384 bytes per frame. Its 8 MiB cumulative cap includes the carried byte and is checked before copying source storage. Exactly 8 MiB is accepted. Empty/incomplete output and overflow cannot produce successful `agent.done`.
- The turn deadline remains active until the done write succeeds. Cancellation can interrupt a suspended socket-write wait without waiting for that write to finish. Unwinding releases the AHC body iterator and cancels its actual transaction. Cancellation during an HTTP body read also cancels the transaction. Real loopback HTTP-peer tests observe upstream connection closure, not merely local stream termination.
- Source/output failures close with 1011 and no successful done. Existing protocol-error and close-handshake tests remain in place. Late write completions cannot settle a cancelled waiter twice or reopen a closed turn. Unknown synthesis errors are logged by type, not arbitrary descriptions; HTTP content-type values are not logged.
- The client validator retains counters only and rejects frames after done. Existing strict frame/order/count checks remain. The WebSocket reader, raw-frame cap, heartbeat and close handling are unchanged.
- `PCMPlaybackQueue` counts pending plus scheduled-but-unplayed buffers in original Int16 PCM bytes. Its cap is 8 MiB; Float32 storage can occupy twice that. Played callbacks release accounting, and AVAudioPlayerNode owns/releases the scheduled buffers. No application array retains played audio. The adapter starts at 9600 bytes, flushes short replies at EOF, and keeps the same engine/node across an underrun. A zero-byte queue before EOF is not completion. Overflow throws through the existing visible playback-error/disconnect path; it does not drop audio.

## Verification on Linux

Run November 14, 2026. Environment: Linux `7.2.15-1-omarchy`, x86_64, Swift `6.4.2`, target `x86_64-unknown-linux-gnu`. No model service, production server, credential store or audio hardware was used. The pre-existing untracked `docs/hands-free-plan.html` and `docs/hands-free-plan.packed.html` were left untouched and excluded from the commit.

| Check | Result |
| --- | --- |
| `swift build --package-path server` | Pass, exit 0 |
| `swift test --package-path server` | Pass, exit 0; 46 tests executed, 1 skipped, 0 failures |
| `swift test --package-path server --filter StreamingFailureTests` repeat run | Pass, exit 0; 7 tests, 0 failures |
| `swiftc -frontend -parse ios/Convoke/App/PCMPlayer.swift` | Pass, syntax only. Does not resolve Apple frameworks or replace an Apple build. |
| Real-sidecar smoke within server suite | Skipped because `CONVOKE_TEST_KOKORO_URL` was unset. No real Kokoro result claimed. |
| `swift build --package-path ios/Convoke` | Blocked, exit 1; Linux has no `Combine` module. Full Apple build remains Pending. |
| `swift test --package-path ios/Convoke` | Blocked, exit 1; Linux has no `Combine` module. Full Apple package tests remain Pending. |
| Portable streaming-core subset described below | Pass, exit 0; 5 tests, 0 failures |
| `git diff --check` | Pass |
| macOS voice adapter build/tests | Pending, requires macOS/Apple frameworks |
| Xcode simulator build-for-testing and test | Pending, Xcode/simulator unavailable on Linux |
| Unsigned generic iPhoneOS build | Pending, Xcode/iPhoneOS SDK unavailable on Linux |
| Actual AVAudioEngine scheduling, buffer release, speaker output and physical-iPhone streaming acceptance | Pending, requires Apple runtime/device. Pure queue tests are not hardware evidence. |

Temporary full output: `/tmp/convoke-27-build.log`, `/tmp/convoke-27-tests.log`, `/tmp/convoke-27-focused.log`, `/tmp/convoke-27-ios-build.log`, `/tmp/convoke-27-ios-tests.log`, `/tmp/convoke-27-portable.log`. These are local build/test logs, not committed artifacts.

The portable subset compiled unchanged copies of `Core/ResponseAccumulator.swift` and `Core/PCMPlaybackQueue.swift`, and ran the checked-in `PCMPlaybackQueueTests.swift` and `StreamingBoundsTests.swift` in a temporary Swift package named `ConvokeCore`. It does not substitute for the blocked full package or AVFoundation checks. Reproduce without changing the app package:

```sh
# From repository root.
check_dir=$(mktemp -d /tmp/convoke-streaming-core.XXXXXX)
mkdir -p "$check_dir/Sources/ConvokeCore" "$check_dir/Tests/ConvokeCoreTests"
cp ios/Convoke/Core/{ResponseAccumulator,PCMPlaybackQueue}.swift "$check_dir/Sources/ConvokeCore/"
cp ios/Convoke/Tests/{PCMPlaybackQueueTests,StreamingBoundsTests}.swift "$check_dir/Tests/ConvokeCoreTests/"
printf '%s\n' '// swift-tools-version: 5.9' 'import PackageDescription' \
  'let package = Package(name: "StreamingCoreChecks", targets: [.target(name: "ConvokeCore"), .testTarget(name: "ConvokeCoreTests", dependencies: ["ConvokeCore"])])' \
  > "$check_dir/Package.swift"
swift test --package-path "$check_dir"
```

Focused tests cover odd splits, empty reads, incomplete/empty EOF, non-sniffed PCM, HTTP status/type rejection, real truncated HTTP framing after partial PCM, gated downstream writes, upstream cancellation during reads and writes, failed writes, conversation disconnect/timeout cancellation, the deadline through a stalled done write, 1011/no done after partial failure, exact frame/cumulative caps, post-done rejection, playback queue release/overflow, short EOF flush and underrun recovery. Existing tests remain, including close-handshake deadlines and malformed wire frames.

The two new iOS test files are registered in the checked-in Xcode project. XcodeGen is unavailable here, so those source references were added manually to match `project.yml`'s existing `Tests` source directory. Regeneration and Apple builds remain Pending.

## Handoff

No dependent ticket, epic acceptance, physical acceptance or merge was performed. The lifecycle task still owns actual playback-start state reporting, reply identities, interruption/End behavior and stale-callback controller coverage. The regression and physical-verification tasks remain separate. Use the Xcode commands and owner checklist in `docs/development.md` on the appropriate hardware; do not reuse older slice results as streaming acceptance.
