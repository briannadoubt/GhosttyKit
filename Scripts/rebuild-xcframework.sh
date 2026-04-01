#!/usr/bin/env bash

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
static_library="$repo_root/Vendor/GhosttyKitStatic/macos-arm64/libghostty-fat.a"
headers_dir="$repo_root/Sources/CGhosttyKitBinary"
xcframework_dir="$repo_root/Vendor/GhosttyKit.xcframework"
version="${1:-0.1.6}"
workdir="$(mktemp -d "${TMPDIR:-/tmp}/ghosttykit-framework.XXXXXX")"
framework_dir="$workdir/CGhosttyKitBinary.framework"

cleanup() {
  rm -rf "$workdir"
}
trap cleanup EXIT

if [[ ! -f "$static_library" ]]; then
  echo "Missing $static_library" >&2
  exit 1
fi

mkdir -p "$framework_dir/Headers" "$framework_dir/Modules"

cp "$static_library" "$framework_dir/CGhosttyKitBinary"
cp -R "$headers_dir/ghostty.h" "$framework_dir/Headers/ghostty.h"
cp -R "$headers_dir/ghostty" "$framework_dir/Headers/ghostty"

cat >"$framework_dir/Modules/module.modulemap" <<'EOF'
framework module CGhosttyKitBinary {
    umbrella header "ghostty.h"
    export *
    module * { export * }
}
EOF

cat >"$framework_dir/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>CGhosttyKitBinary</string>
    <key>CFBundleExecutable</key>
    <string>CGhosttyKitBinary</string>
    <key>CFBundleIdentifier</key>
    <string>dev.bri.CGhosttyKitBinary</string>
    <key>CFBundleName</key>
    <string>CGhosttyKitBinary</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>$version</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>MacOSX</string>
    </array>
    <key>CFBundleVersion</key>
    <string>$version</string>
    <key>MinimumOSVersion</key>
    <string>13.0</string>
</dict>
</plist>
EOF

rm -rf "$xcframework_dir"
xcodebuild -create-xcframework \
  -framework "$framework_dir" \
  -output "$xcframework_dir" >/dev/null

echo "Rebuilt $xcframework_dir"
