#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <GhosttyKit.xcframework>" >&2
  exit 1
fi

xcframework="$1"

if [[ ! -d "$xcframework" ]]; then
  echo "Missing XCFramework directory: $xcframework" >&2
  exit 1
fi

libraries=()
while IFS= read -r -d '' library; do
  libraries+=("$library")
done < <(find "$xcframework" -path '*/macos-arm64/*.a' -type f -print0)

if [[ "${#libraries[@]}" -ne 1 ]]; then
  echo "Expected exactly one macos-arm64 static library in $xcframework, found ${#libraries[@]}." >&2
  printf '  %s\n' "${libraries[@]}" >&2
  exit 1
fi

echo "${libraries[0]}"
