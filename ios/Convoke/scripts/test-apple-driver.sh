#!/bin/bash
# Contract tests with fake Apple tools. These do NOT establish Apple execution.
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$test_root/bin" "$test_root/results"
cat > "$test_root/bin/fake-tool" <<'SH'
#!/bin/bash
set -eu
case "$(basename "$0")" in
    uname) printf '%s\n' "${FAKE_OS:-Darwin}" ;;
    sw_vers) echo "${FAKE_MACOS:-26.0}" ;;
    xcode-select) echo /Applications/Fake-Xcode.app/Contents/Developer ;;
    xcodebuild)
        if [[ $1 == -version ]]; then printf 'Xcode 26.0\nBuild version fake\n'; exit; fi
        printf 'FAKE xcodebuild %s\n' "$*"
        exit "${FAKE_XCODE_STATUS:-0}"
        ;;
    xcrun)
        case "$1 $2" in
            'swift --version') echo 'Apple Swift version 6.2 (fake)' ;;
            'swift test')
                echo 'Executed 10 tests, with 2 tests skipped and 0 failures (0 unexpected)'
                exit "${FAKE_SWIFT_STATUS:-0}" ;;
            '--sdk iphoneos'|'--sdk iphonesimulator') echo 26.0 ;;
            'simctl list')
                echo '{"runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-26-0","version":"26.0","name":"iOS 26.0","isAvailable":true}],"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-0":[{"udid":"test-udid","name":"iPhone fake","deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-fake","isAvailable":true}]}}' ;;
            'xcresulttool get') echo '{"passedTests":8,"skippedTests":2,"failedTests":0,"result":"Passed"}' ;;
            *) echo "unexpected fake xcrun: $*" >&2; exit 99 ;;
        esac
        ;;
esac
SH
chmod +x "$test_root/bin/fake-tool"
for tool in uname sw_vers xcode-select xcodebuild xcrun; do
    ln -s fake-tool "$test_root/bin/$tool"
done
export PATH="$test_root/bin:$PATH" APPLE_TEST_OUTPUT_DIR="$test_root/results"
# Deliberately invoke the actual entry point from outside the checkout.
cd "$test_root"
run_case() {
    local name=$1 expected=$2 pattern=$3
    shift 3
    local status=0
    env "$@" "$script_dir/test-apple.sh" > "$test_root/$name.log" 2>&1 || status=$?
    if [[ $status != "$expected" ]] || ! grep -q "$pattern" "$test_root/$name.log"; then
        printf 'FAIL %s: expected status %s, got %s\n' "$name" "$expected" "$status"
        tail -n 30 "$test_root/$name.log"
        exit 1
    fi
    printf 'PASS mocked driver contract: %s, exit %s\n' "$name" "$status"
}
run_case missing-macos 1 'require macOS 26+' FAKE_OS=Linux
run_case old-macos 1 'macOS 26.0+ required' FAKE_MACOS=15.0
run_case invalid-udid 1 'SIMULATOR_UDID is invalid/unavailable' SIMULATOR_UDID=bad
run_case swift-failure 42 'Apple checks exit status: 42' FAKE_SWIFT_STATUS=42
run_case xcode-failure 65 'Apple checks exit status: 65' FAKE_XCODE_STATUS=65
run_case default-success 0 'PASS: real-Combine Apple package tests'
run_case valid-override 0 'UDID: test-udid' SIMULATOR_UDID=test-udid
printf 'Mocked driver contracts passed. No Apple tests executed by this check.\n'
