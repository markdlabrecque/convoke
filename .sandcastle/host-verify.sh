#!/usr/bin/env bash
set -euo pipefail

found=0
if [[ -f Package.swift ]]; then
  found=1
  [[ "$(uname -s)" == Darwin ]] || { echo "Host Swift verification requires macOS." >&2; exit 1; }
  swift test
fi

shopt -s nullglob
projects=(ios/*.xcodeproj)
if ((${#projects[@]})); then
  found=1
  [[ "$(uname -s)" == Darwin ]] || { echo "Host iOS builds require macOS and Xcode." >&2; exit 1; }
  for project in "${projects[@]}"; do
    scheme="$(xcodebuild -list -json -project "$project" | python3 -c 'import json,sys; print(json.load(sys.stdin)["project"]["schemes"][0])')"
    xcodebuild -project "$project" -scheme "$scheme" -destination 'generic/platform=iOS Simulator' build
  done
fi

if ((found == 0)); then
  echo "No Swift package or Xcode project yet; no host Apple-platform build to run."
fi
