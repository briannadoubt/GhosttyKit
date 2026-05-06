#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./Scripts/install-zig-from-ghostty.sh [--print-url]

Install the exact Zig toolchain required by Vendor/ghostty-upstream.

Options:
  --print-url  Print the resolved Zig tarball URL without downloading it.
  --help       Show this help text.
EOF
}

print_url=false

while (($# > 0)); do
  case "$1" in
    --print-url)
      print_url=true
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

repo_root="$(git rev-parse --show-toplevel)"
submodule_path="$repo_root/Vendor/ghostty-upstream"
index_url="https://ziglang.org/download/index.json"

zig_version="$(sed -n 's/.*minimum_zig_version = "\(.*\)".*/\1/p' "$submodule_path/build.zig.zon" | head -n 1)"

if [[ -z "$zig_version" ]]; then
  echo "Unable to determine Ghostty's required Zig version from build.zig.zon." >&2
  exit 1
fi

case "$(uname -s):$(uname -m)" in
  Darwin:arm64)
    zig_target="aarch64-macos"
    ;;
  Darwin:x86_64)
    zig_target="x86_64-macos"
    ;;
  Linux:aarch64 | Linux:arm64)
    zig_target="aarch64-linux"
    ;;
  Linux:x86_64)
    zig_target="x86_64-linux"
    ;;
  *)
    echo "Unsupported host for Zig install: $(uname -s):$(uname -m)" >&2
    exit 1
    ;;
esac

index_file="$(mktemp "${TMPDIR:-/tmp}/ghosttykit-zig-index.XXXXXX")"
cleanup_index() {
  rm -f "$index_file"
}
trap cleanup_index EXIT

curl -fsSL "$index_url" -o "$index_file"

metadata="$(
  python3 - "$index_file" "$zig_version" "$zig_target" <<'PY'
import json
import sys

index_path, version, target = sys.argv[1:]

with open(index_path, encoding="utf-8") as index_file:
    index = json.load(index_file)

try:
    artifact = index[version][target]
except KeyError:
    print(f"Zig {version} does not publish a {target} toolchain.", file=sys.stderr)
    sys.exit(1)

try:
    print(artifact["tarball"])
    print(artifact["shasum"])
except KeyError as error:
    print(f"Zig {version} {target} metadata is missing {error.args[0]}.", file=sys.stderr)
    sys.exit(1)
PY
)"

tarball_url="$(printf '%s\n' "$metadata" | sed -n '1p')"
tarball_shasum="$(printf '%s\n' "$metadata" | sed -n '2p')"

if [[ "$print_url" == true ]]; then
  echo "$tarball_url"
  exit 0
fi

if command -v zig >/dev/null 2>&1 && [[ "$(zig version)" == "$zig_version" ]]; then
  echo "zig $zig_version is already installed."
  exit 0
fi

install_parent="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/ghosttykit-zig"
download_dir="$(mktemp -d "$install_parent.download.XXXXXX")"
archive_path="$download_dir/zig.tar.xz"
toolchain_dir="$install_parent/$(basename "$tarball_url" .tar.xz)"

cleanup_download() {
  rm -rf "$download_dir"
}
trap 'cleanup_index; cleanup_download' EXIT

mkdir -p "$install_parent"
curl -fsSL "$tarball_url" -o "$archive_path"
printf '%s  %s\n' "$tarball_shasum" "$archive_path" | shasum -a 256 -c -
rm -rf "$toolchain_dir"
tar -xJf "$archive_path" -C "$install_parent"

if [[ ! -x "$toolchain_dir/zig" ]]; then
  echo "Downloaded Zig toolchain does not contain an executable zig binary." >&2
  exit 1
fi

if [[ "$("$toolchain_dir/zig" version)" != "$zig_version" ]]; then
  echo "Downloaded Zig toolchain version did not match $zig_version." >&2
  exit 1
fi

if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "$toolchain_dir" >>"$GITHUB_PATH"
else
  echo "Add $toolchain_dir to PATH to use zig $zig_version."
fi

echo "Installed zig $zig_version at $toolchain_dir."
