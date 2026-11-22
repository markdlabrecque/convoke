#!/usr/bin/env bash
# Server plus limited portable client-core checks; not an iOS validation gate.
set -euo pipefail
[[ $(uname -s) == Linux ]] || { printf 'error: Use check-macos.sh on a Mac.\n' >&2; exit 1; }
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
"$script_dir/check-server.sh"
bash "$script_dir/../ios/Convoke/scripts/test-portable-core.sh"
printf 'PASS: Linux server and limited portable core only. Xcode checks remain required.\n'
