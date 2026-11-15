#!/bin/bash
# Run from any directory. APPLE_TEST_OUTPUT_DIR is a parent for a unique run directory.
# SIMULATOR_UDID optionally selects an installed, available iPhone on iOS 26+.
set -euo pipefail

fail() { printf 'error: %s\n' "$*" >&2; exit 1; }
[[ $(uname -s) == Darwin ]] || fail 'Apple checks require macOS 26+ and full Xcode 26+. Linux portable tests are not a substitute.'
for tool in git sw_vers xcodebuild xcrun python3; do
    command -v "$tool" >/dev/null || fail "Missing $tool. Install full Xcode 26+ and select it with xcode-select."
done
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
package_dir=$(cd "$script_dir/.." && pwd)
repo_dir=$(git -C "$package_dir" rev-parse --show-toplevel)

# Fail before compilation with an actionable explanation, not a passing skip.
os_version=$(sw_vers -productVersion)
xcode_version=$(xcodebuild -version)
swift_version=$(xcrun swift --version)
device_sdk=$(xcrun --sdk iphoneos --show-sdk-version)
simulator_sdk=$(xcrun --sdk iphonesimulator --show-sdk-version)
python3 - "$os_version" "$xcode_version" "$swift_version" "$device_sdk" "$simulator_sdk" <<'PY'
import re
import sys
requirements = [
    ("macOS", sys.argv[1], r"^(\d+)(?:\.(\d+))?", (26, 0)),
    ("Xcode", sys.argv[2], r"Xcode (\d+)(?:\.(\d+))?", (26, 0)),
    ("Swift", sys.argv[3], r"Swift version (\d+)(?:\.(\d+))?", (6, 2)),
    ("iPhoneOS SDK", sys.argv[4], r"^(\d+)(?:\.(\d+))?", (26, 0)),
    ("iPhoneSimulator SDK", sys.argv[5], r"^(\d+)(?:\.(\d+))?", (26, 0)),
]
for name, text, pattern, minimum in requirements:
    match = re.search(pattern, text)
    if not match or tuple(int(n or 0) for n in match.groups()) < minimum:
        sys.exit(f"error: {name} {minimum[0]}.{minimum[1]}+ required; found {text!r}. Select a compatible full Xcode installation; no SDK downgrade is supported.")
PY

output_parent=${APPLE_TEST_OUTPUT_DIR:-${TMPDIR:-/tmp}}
mkdir -p "$output_parent"
output_dir=$(mktemp -d "$output_parent/convoke-apple.XXXXXX")
# Keep logs/results on success and failure. Never erase user data or stop simulators.
exec > >(tee "$output_dir/driver.log") 2>&1
trap 'status=$?; printf "Apple checks exit status: %s\nResults retained: %s\n" "$status" "$output_dir"' EXIT
printf 'Tested SHA: %s\n' "$(git -C "$repo_dir" rev-parse HEAD)"
printf 'Dirty-tree state (empty means clean):\n'
git -C "$repo_dir" status --short
sw_vers
printf '%s\n%s\niPhoneOS SDK: %s\niPhoneSimulator SDK: %s\n' "$xcode_version" "$swift_version" "$device_sdk" "$simulator_sdk"
printf 'Developer directory: %s\n' "$(xcode-select -p)"
printf 'Results retained: %s\n' "$output_dir"

xcrun simctl list --json > "$output_dir/simulators.json"
python3 - "$output_dir/simulators.json" "${SIMULATOR_UDID:-}" > "$output_dir/destination.txt" <<'PY'
import json
import sys
with open(sys.argv[1]) as source:
    inventory = json.load(source)
candidates = []
for runtime in inventory["runtimes"]:
    version = tuple(int(n) for n in runtime["version"].split("."))
    if not runtime.get("isAvailable") or ".iOS-" not in runtime["identifier"] or version < (26,):
        continue
    for device in inventory["devices"].get(runtime["identifier"], []):
        if device.get("isAvailable") and device.get("deviceTypeIdentifier", "").startswith("com.apple.CoreSimulator.SimDeviceType.iPhone-"):
            candidates.append((version, device["name"], device["udid"], runtime["name"], runtime["identifier"]))
# Newest available runtime, then stable name/UDID order. Never download a runtime.
candidates.sort(key=lambda row: (tuple(-n for n in row[0]), row[1], row[2]))
if sys.argv[2]:
    candidates = [row for row in candidates if row[2] == sys.argv[2]]
if not candidates:
    sys.exit("error: SIMULATOR_UDID is invalid/unavailable or no compatible iPhone simulator is installed. Install an iOS 26+ runtime and iPhone device in Xcode, then choose an available UDID from `xcrun simctl list --json`.")
version, name, udid, runtime_name, runtime_id = candidates[0]
print(udid)
print(f"Simulator: {name}; UDID: {udid}; runtime: {runtime_name} ({runtime_id})")
PY
simulator_udid=$(head -n 1 "$output_dir/destination.txt")
# Show both the machine-readable destination and the human-readable runtime.
while IFS= read -r line; do printf '%s\n' "$line"; done < "$output_dir/destination.txt"
printf 'Default suites only. Optional audio-engine checks remain explicit XCTest skips.\n'
# Keep accidental local opt-ins out of this default-only command, too.
unset CONVOKE_TEST_AUDIO_ENGINE CONVOKE_TEST_SYSTEM_VOICE CONVOKE_TEST_KOKORO_URL CONVOKE_KOKORO_VOICE
unset TEST_RUNNER_CONVOKE_TEST_AUDIO_ENGINE TEST_RUNNER_CONVOKE_TEST_SYSTEM_VOICE

xcrun swift test --package-path "$package_dir" --scratch-path "$output_dir/swift-build" 2>&1 | tee "$output_dir/package.log"
xcodebuild -project "$package_dir/Convoke.xcodeproj" -scheme Convoke \
    -destination "platform=iOS Simulator,id=$simulator_udid" \
    -destination-timeout 120 -parallel-testing-enabled NO \
    -derivedDataPath "$output_dir/simulator-derived-data" \
    -resultBundlePath "$output_dir/simulator.xcresult" \
    CODE_SIGNING_ALLOWED=NO test 2>&1 | tee "$output_dir/simulator.log"
xcrun xcresulttool get test-results summary --path "$output_dir/simulator.xcresult" > "$output_dir/simulator-summary.json"
python3 - "$output_dir/package.log" "$output_dir/simulator-summary.json" <<'PY'
import json
import re
import sys
with open(sys.argv[1]) as source:
    counts = re.findall(r"Executed (\d+) tests?, with (\d+) tests? skipped and (\d+) failures", source.read())
if not counts or int(counts[-1][0]) <= int(counts[-1][1]) or int(counts[-1][2]):
    sys.exit("error: package log did not report nonzero executed, passing tests; inspect package.log")
print("Package totals: %s tests, %s skipped, %s failures" % counts[-1])
with open(sys.argv[2]) as source:
    summary = json.load(source)
print("Simulator summary:")
print(json.dumps(summary, indent=2))
if summary.get("passedTests", 0) <= 0 or summary.get("failedTests", 0) or summary.get("result") != "Passed":
    sys.exit("error: simulator result did not report nonzero passing tests; inspect simulator.xcresult")
PY
xcodebuild -project "$package_dir/Convoke.xcodeproj" -scheme Convoke \
    -sdk iphoneos -destination 'generic/platform=iOS' \
    -derivedDataPath "$output_dir/device-derived-data" \
    -resultBundlePath "$output_dir/device-build.xcresult" \
    CODE_SIGNING_ALLOWED=NO build 2>&1 | tee "$output_dir/device-build.log"
printf 'PASS: real-Combine Apple package tests, simulator tests, unsigned iPhoneOS build.\n'
