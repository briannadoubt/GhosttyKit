#!/usr/bin/env bash

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
artifact_dir="$repo_root/Vendor/GhosttyKit.xcframework"
artifact_zip="$repo_root/Vendor/GhosttyKit.xcframework.zip"

if [[ -d "$artifact_dir" ]]; then
  exit 0
fi

if [[ ! -f "$artifact_zip" ]]; then
  echo "Missing $artifact_zip." >&2
  exit 1
fi

ditto -x -k "$artifact_zip" "$repo_root/Vendor"
echo "Unpacked $artifact_zip"
