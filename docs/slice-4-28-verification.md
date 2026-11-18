# Slice 4 lifecycle implementation verification

Historical implementation snapshot. Pending and blocked results below describe this revision/environment, not current acceptance. See the [later automated evidence](development.md#automated-checks) and [November 16 physical session](slice-4-30-device-session.md) for owner-reported End, background, Disconnect and underrun results. Issue #30 is closed by owner decision; real interruption/route checks remain deferred and missing failure messages remain discrepancies. Full Slice 4 acceptance is not complete.

## Scope and base

Implements issue #28 after #27, following the approved plan and Q&A on epic #25. Branch `slice-4-28` was created in the existing `code/main` checkout from fetched `origin/main` at `05e7ed2`, the merged PR #33 commit. `git merge-base --is-ancestor 05e7ed2 origin/main` exited 0.

The sibling `code/develop` checkout was not used. The pre-existing untracked `docs/hands-free-plan.html` and `docs/hands-free-plan.packed.html` were left untouched and excluded from commits. No production access, credentials, persisted audio/transcripts or content logging. No subagents or new threads. Issues #29 and #30 remain separate dependent work; this is not epic or physical acceptance.

## Behavior

- Each submitted reply owns an identity, network-finished and player-drained flags, independent of the visible status. First audio prepares a player; the start callback changes Waiting to Playing only when the node starts. Buffering and underruns keep capture off.
- Validated EOF allows local End to retain the connection, even if a short reply is still Waiting. Before EOF, End disconnects in both Waiting and Playing. End during recording keeps the connection.
- `endStream` flushes short replies and waits for actual playback. If the last queued buffer played before EOF, it returns immediately at EOF. If EOF came first, it waits for the final played-back callback. Only the current reply can complete and restart capture, exactly once.
- Reply teardown invalidates identity before cancellation/stop. Disconnect invalidates the connection and capture identity too. The queued finalizer checks identity before touching the player, as well as after suspension. Stale start, failure, completion, receive and disconnect callbacks cannot mutate a restarted conversation.
- `PCMPlaybackLifetime`, used by the AVAudioEngine adapter, owns stream identity, start-once and exactly-once settlement. Stop cancels pending work. Interruption/configuration failure notifies the controller immediately, including while the server is silent before EOF. The conversation disconnects with the existing content-free playback error and does not retry. Old buffer and notification callbacks are invalidated before audio teardown.
- `ContentView` is unchanged. Its existing background action calls disconnect, which stops capture and queued audio.

No wire messages, bounds, startup threshold, voice fallback or server behavior changed. Existing player fakes were updated for the callback contract. Existing assertions were retained; new tests cover buffering, short EOF, both drain/EOF orders, underrun recovery, interruption before/after EOF, End before a queued finalizer runs, same-connection restart and old connection callbacks.

## Results

Run on Linux x86_64, Swift 6.4.2, November 14, 2026. Checks ran against the implementation working tree on the base above. The PR commit contains these changes and this record.

| Check | Result | Evidence |
| --- | --- | --- |
| `swift build --package-path server` | Pass | Exit 0 |
| `swift test --package-path server` | Pass | Exit 0; 46 tests, 1 skipped, 0 failures. Real Kokoro smoke skipped because its opt-in URL was unset |
| `swift test --package-path ios/Convoke` | Blocked | Exit 1: Linux has no `Combine`. Full Apple package verification remains Pending |
| Portable controller/validator/queue/lifetime tests | Pass, limited | 67 tests, 0 failures. Unchanged checked-in sources/tests copied to a temporary package with a test-only Combine stand-in. Does not test Combine publication, AVFoundation, speech capture or the real WebSocket adapter |
| Portable suite repeated three times | Pass, limited | Each run exited 0; 67 tests, 0 failures |
| `swiftc -frontend -parse ios/Convoke/App/PCMPlayer.swift` | Pass, syntax only | Exit 0. Does not type-check or link Apple frameworks |
| `git diff --check` | Pass | Exit 0 |
| Full Apple Swift package tests | Pending | Needs macOS 26+ and Apple frameworks |
| Xcode simulator build-for-testing and tests | Pending | No Xcode/Apple SDKs or simulator on this Linux host |
| Unsigned generic iPhoneOS build | Pending | No Xcode/Apple SDKs |
| Actual engine scheduling, interruptions/configuration changes, macOS voice | Pending | Requires Apple runtime; pure lifetime tests are not hardware evidence |
| Real Kokoro/physical iPhone streaming acceptance | Pending | Not attempted here. Owner checks remain in #30 after dependencies |

Temporary local logs: `/tmp/convoke-28-server-build.log`, `/tmp/convoke-28-server-tests.log`, `/tmp/convoke-28-ios-tests.log`, `/tmp/convoke-28-portable-tests.log`, `/tmp/convoke-28-portable-repeat-{1,2,3}.log`. These are not committed and contain no captured transcript or PCM.

## Reproducing the limited Linux tests

From the repository root, with Swift installed. This deliberately does not change production sources or pretend to replace Combine on Apple:

```sh
CHECK=$(mktemp -d /tmp/convoke-28-check.XXXXXX)
mkdir -p "$CHECK/Sources/Combine" "$CHECK/Sources/ConvokeCore" "$CHECK/Tests/ConvokeCoreTests"
cat > "$CHECK/Package.swift" <<'SWIFT'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ConvokePortableChecks", products: [], targets: [
    .target(name: "Combine"),
    .target(name: "ConvokeCore", dependencies: ["Combine"]),
    .testTarget(name: "ConvokeCoreTests", dependencies: ["ConvokeCore"])
], swiftLanguageModes: [.v5])
SWIFT
cat > "$CHECK/Sources/Combine/Combine.swift" <<'SWIFT'
// Test-only stand-ins. No Combine publisher behavior is exercised.
@_exported import Foundation
@_exported import FoundationNetworking
public protocol ObservableObject: AnyObject {}
@propertyWrapper public struct Published<Value> {
    public var wrappedValue: Value
    public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}
SWIFT
cp ios/Convoke/Core/*.swift "$CHECK/Sources/ConvokeCore/"
cp ios/Convoke/Tests/{SessionControllerTests,ResponseTests,PCMPlaybackQueueTests,StreamingBoundsTests}.swift \
  "$CHECK/Tests/ConvokeCoreTests/"
swift test --package-path "$CHECK"
```

On a Mac, run the full package and Xcode commands in `docs/development.md`, using an actually installed simulator. Do not carry earlier slice results forward as evidence for this change.
