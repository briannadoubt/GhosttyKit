#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./Scripts/update-libghostty.sh [--ref <git-ref> | --latest-tag] [--skip-fetch]

Rebuild the vendored GhosttyKit XCFramework and synced public headers from the
upstream Ghostty source tracked in Vendor/ghostty-upstream.

Options:
  --ref <git-ref>  Check out the given ref in the submodule before building.
  --latest-tag     Check out the latest upstream v* tag before building.
  --skip-fetch     Do not fetch new commits/tags from origin before building.
  --help           Show this help text.
EOF
}

requested_ref=""
use_latest_tag=false
skip_fetch=false

while (($# > 0)); do
  case "$1" in
    --ref)
      requested_ref="${2:-}"
      if [[ -z "$requested_ref" ]]; then
        echo "--ref requires a git ref" >&2
        exit 1
      fi
      shift 2
      ;;
    --latest-tag)
      use_latest_tag=true
      shift
      ;;
    --skip-fetch)
      skip_fetch=true
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -n "$requested_ref" && "$use_latest_tag" == true ]]; then
  echo "Use either --ref or --latest-tag, not both." >&2
  exit 1
fi

repo_root="$(git rev-parse --show-toplevel)"
submodule_path="$repo_root/Vendor/ghostty-upstream"
vendor_path="$repo_root/Vendor/GhosttyKit.xcframework"
static_library_path="$repo_root/Vendor/GhosttyKitStatic/macos-arm64"
headers_path="$repo_root/Sources/GhosttyKit/include"
shim_path="$repo_root/Sources/CGhosttyKitBinary"
version_file="$repo_root/Vendor/libghostty.version"

git -C "$repo_root" submodule update --init --recursive Vendor/ghostty-upstream

if [[ "$skip_fetch" != true ]]; then
  git -C "$submodule_path" fetch --force --tags origin main
fi

if [[ "$use_latest_tag" == true ]]; then
  requested_ref="$(git -C "$submodule_path" tag --list 'v*' --sort=version:refname | tail -n 1)"
  if [[ -z "$requested_ref" ]]; then
    echo "No upstream v* tags found in ghostty-org/ghostty." >&2
    exit 1
  fi
fi

if [[ -n "$requested_ref" ]]; then
  git -C "$submodule_path" checkout "$requested_ref"
fi

upstream_commit="$(git -C "$submodule_path" rev-parse HEAD)"
upstream_ref="$(git -C "$submodule_path" describe --tags --always --match 'v*' "$upstream_commit")"
zig_version="$(sed -n 's/.*minimum_zig_version = "\(.*\)".*/\1/p' "$submodule_path/build.zig.zon" | head -n 1)"

if [[ -z "$zig_version" ]]; then
  echo "Unable to determine Ghostty's required Zig version from build.zig.zon." >&2
  exit 1
fi

if ! command -v zig >/dev/null 2>&1; then
  echo "zig $zig_version is required to rebuild GhosttyKit.xcframework." >&2
  exit 1
fi

installed_zig="$(zig version)"
if [[ "$installed_zig" != "$zig_version" ]]; then
  echo "Expected zig $zig_version but found $installed_zig." >&2
  echo "Install the matching Zig toolchain before running this updater." >&2
  exit 1
fi

workdir="$(mktemp -d "${TMPDIR:-/tmp}/ghosttykit.XXXXXX")"
cleanup() {
  rm -rf "$workdir"
}
trap cleanup EXIT

git clone --quiet --local "$submodule_path" "$workdir/ghostty"
git -C "$workdir/ghostty" checkout --quiet --detach "$upstream_commit"

(
  cd "$workdir/ghostty"
  zig build \
    -Doptimize=ReleaseFast \
    -Demit-xcframework=true \
    -Dxcframework-target=native
)

rsync -a --delete "$workdir/ghostty/include/" "$headers_path/"
mkdir -p "$static_library_path" "$shim_path"
cp "$workdir/ghostty/macos/GhosttyKit.xcframework/macos-arm64/libghostty-fat.a" "$static_library_path/libghostty-fat.a"
strip -S "$static_library_path/libghostty-fat.a"
rsync -a --delete --exclude 'module.modulemap' "$headers_path/" "$shim_path/"

cat >"$headers_path/module.modulemap" <<'EOF'
module CGhosttyKitBinary {
    header "ghostty.h"
    export *
}
EOF

cat >"$shim_path/module.modulemap" <<'EOF'
module CGhosttyKitBinary {
    header "ghostty.h"
    export *
}
EOF

cat >"$shim_path/stub.c" <<'EOF'
#include "ghostty.h"
EOF

"$repo_root/Scripts/rebuild-xcframework.sh"

cat >"$version_file" <<EOF
ghostty_ref=$upstream_ref
ghostty_commit=$upstream_commit
zig_version=$zig_version
updated_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

"$repo_root/Scripts/package-artifact.sh" >/dev/null

echo "Updated GhosttyKit.xcframework from $upstream_ref ($upstream_commit)."
