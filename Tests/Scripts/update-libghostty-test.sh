#!/usr/bin/env bash

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
script="$repo_root/Scripts/update-libghostty.sh"

if ! grep -q -- "-Demit-xcframework=true" "$script"; then
  echo "update-libghostty.sh no longer enables Ghostty XCFramework output." >&2
  exit 1
fi

if ! grep -q -- "-Demit-macos-app=false" "$script"; then
  echo "update-libghostty.sh should not build the upstream Ghostty app bundle." >&2
  exit 1
fi
