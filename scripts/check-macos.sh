#!/usr/bin/env bash
# Full local gate: server plus existing Apple package/simulator/device checks.
set -euo pipefail
[[ $(uname -s) == Darwin ]] || { printf 'error: macOS and full Xcode are required; use check-linux.sh on Linux.\n' >&2; exit 1; }
command -v xcodebuild >/dev/null || { printf 'error: Install and select full Xcode.\n' >&2; exit 1; }
xcodebuild -version
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
"$script_dir/check-server.sh"
bash "$script_dir/../ios/Convoke/scripts/test-apple.sh"
