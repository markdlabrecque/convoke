#!/usr/bin/env bash
# Limited Linux regression checks, NOT an Apple package or AVAudioEngine pass.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
check=$(mktemp -d "${TMPDIR:-/tmp}/convoke-portable.XXXXXX")
trap 'rm -rf "$check"' EXIT
mkdir -p "$check/Sources/Combine" "$check/Sources/ConvokeCore" "$check/Tests/ConvokeCoreTests"
cat > "$check/Package.swift" <<'SWIFT'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ConvokePortableChecks", products: [], targets: [
    .target(name: "Combine"),
    .target(name: "ConvokeCore", dependencies: ["Combine"]),
    .testTarget(name: "ConvokeCoreTests", dependencies: ["ConvokeCore"])
], swiftLanguageModes: [.v5])
SWIFT
cat > "$check/Sources/Combine/Combine.swift" <<'SWIFT'
// Test-only stand-ins. These do not exercise Combine publisher behavior.
@_exported import Foundation
@_exported import FoundationNetworking
public protocol ObservableObject: AnyObject {}
@propertyWrapper public struct Published<Value> {
    public var wrappedValue: Value
    public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}
SWIFT
cp "$root"/Core/*.swift "$check/Sources/ConvokeCore/"
for name in AsyncTestGate SessionControllerTests ResponseTests PCMPlaybackQueueTests PCMPlayerTests; do
    cp "$root/Tests/$name.swift" "$check/Tests/ConvokeCoreTests/"
done
printf '%s\n' 'Limited core checks with test-only Combine stand-in. Apple adapters are not exercised.'
swift test --package-path "$check" "$@"
