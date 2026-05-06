#!/usr/bin/env bash

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/ghosttykit-static-lib-test.XXXXXX")"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

xcframework="$tmpdir/GhosttyKit.xcframework"
mkdir -p "$xcframework/macos-arm64" "$xcframework/ios-arm64"
touch "$xcframework/macos-arm64/libghostty-internal-fat.a"
touch "$xcframework/ios-arm64/libghostty-ios.a"

resolved="$("$repo_root/Scripts/find-ghosttykit-static-library.sh" "$xcframework")"
expected="$xcframework/macos-arm64/libghostty-internal-fat.a"

if [[ "$resolved" != "$expected" ]]; then
  echo "Unexpected static library path: $resolved" >&2
  echo "Expected: $expected" >&2
  exit 1
fi
