#!/usr/bin/env bash

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
submodule_path="$repo_root/Vendor/ghostty-upstream"
version_file="$repo_root/Vendor/libghostty.version"
artifact_zip="$repo_root/Vendor/GhosttyKit.xcframework.zip"
checksum_file="$repo_root/Vendor/GhosttyKit.checksum"

if [[ ! -f "$version_file" ]]; then
  echo "Missing $version_file. Run ./Scripts/update-libghostty.sh." >&2
  exit 1
fi

git -C "$repo_root" submodule update --init --recursive Vendor/ghostty-upstream >/dev/null

expected_commit="$(sed -n 's/^ghostty_commit=//p' "$version_file")"
actual_commit="$(git -C "$submodule_path" rev-parse HEAD)"

if [[ -z "$expected_commit" ]]; then
  echo "Missing ghostty_commit in $version_file." >&2
  exit 1
fi

if [[ "$expected_commit" != "$actual_commit" ]]; then
  echo "Vendored metadata is out of sync with Vendor/ghostty-upstream." >&2
  echo "Expected commit: $expected_commit" >&2
  echo "Actual commit:   $actual_commit" >&2
  echo "Run ./Scripts/update-libghostty.sh and commit the refreshed artifacts." >&2
  exit 1
fi

if [[ ! -f "$artifact_zip" ]]; then
  echo "Missing $artifact_zip. Run ./Scripts/package-artifact.sh." >&2
  exit 1
fi

if [[ ! -f "$checksum_file" ]]; then
  echo "Missing $checksum_file. Run ./Scripts/package-artifact.sh." >&2
  exit 1
fi

expected_checksum="$(tr -d '\n' <"$checksum_file")"
actual_checksum="$(swift package compute-checksum "$artifact_zip")"

if [[ "$expected_checksum" != "$actual_checksum" ]]; then
  echo "Artifact checksum is out of sync with $checksum_file." >&2
  echo "Expected checksum: $expected_checksum" >&2
  echo "Actual checksum:   $actual_checksum" >&2
  echo "Run ./Scripts/package-artifact.sh and commit the refreshed archive." >&2
  exit 1
fi

echo "Vendored libghostty metadata matches Vendor/ghostty-upstream."
