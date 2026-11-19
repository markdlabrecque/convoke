#!/usr/bin/env bash
# Build and test the server on Linux or macOS, from any working directory.
set -euo pipefail
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
command -v swift >/dev/null || { printf 'error: Swift is required.\n' >&2; exit 1; }
printf 'Checking current checkout: %s\n' "$(git -C "$repo_dir" rev-parse --short HEAD)"
printf 'Working-tree changes (allowed):\n'
git -C "$repo_dir" status --short
swift --version
# Default regression suite only: no locally opted-in live audio services.
unset CONVOKE_TEST_KOKORO_URL CONVOKE_TEST_SYSTEM_VOICE
swift build --package-path "$repo_dir/server"
swift test --package-path "$repo_dir/server"
