#!/usr/bin/env bash

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
artifact_dir="$repo_root/Vendor/GhosttyKit.xcframework"
artifact_zip="$repo_root/Vendor/GhosttyKit.xcframework.zip"
checksum_file="$repo_root/Vendor/GhosttyKit.checksum"

if [[ ! -d "$artifact_dir" ]]; then
  echo "Missing $artifact_dir. Run ./Scripts/update-libghostty.sh first." >&2
  exit 1
fi

rm -f "$artifact_zip"
ditto -c -k --keepParent "$artifact_dir" "$artifact_zip"
swift package compute-checksum "$artifact_zip" >"$checksum_file"

echo "Packaged $artifact_zip"
echo "Checksum: $(cat "$checksum_file")"
