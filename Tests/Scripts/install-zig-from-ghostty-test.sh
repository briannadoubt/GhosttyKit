#!/usr/bin/env bash

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
zig_version="$(sed -n 's/.*minimum_zig_version = "\(.*\)".*/\1/p' "$repo_root/Vendor/ghostty-upstream/build.zig.zon" | head -n 1)"

if [[ -z "$zig_version" ]]; then
  echo "Unable to determine Ghostty's required Zig version." >&2
  exit 1
fi

case "$(uname -s):$(uname -m)" in
  Darwin:arm64)
    expected_tarball="zig-aarch64-macos-$zig_version.tar.xz"
    ;;
  Darwin:x86_64)
    expected_tarball="zig-x86_64-macos-$zig_version.tar.xz"
    ;;
  *)
    echo "Unsupported test host: $(uname -s):$(uname -m)" >&2
    exit 1
    ;;
esac

tarball_url="$("$repo_root/Scripts/install-zig-from-ghostty.sh" --print-url)"

case "$tarball_url" in
  "https://ziglang.org/download/$zig_version/$expected_tarball") ;;
  *)
    echo "Unexpected Zig tarball URL: $tarball_url" >&2
    echo "Expected: https://ziglang.org/download/$zig_version/$expected_tarball" >&2
    exit 1
    ;;
esac

curl -fsSL --range 0-0 "$tarball_url" >/dev/null
