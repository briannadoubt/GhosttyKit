# GhosttyKit

Swift Package Manager wrapper around the upstream `libghostty` macOS XCFramework.

`GhosttyKit` publishes a normal Swift package product that client apps can
import directly. The repo tracks a zipped `GhosttyKit.xcframework` artifact for
distribution and keeps an unzipped local XCFramework only for maintainer builds.
The vendored binary and header mirror come from
[`ghostty-org/ghostty`](https://github.com/ghostty-org/ghostty).

## Install

After the initial tag is published:

```swift
.package(url: "https://github.com/briannadoubt/GhosttyKit.git", from: "0.1.1")
```

Then depend on the `GhosttyKit` product from your target.

This package currently ships a macOS arm64 binary built with a minimum deployment
target of macOS 13.

By default, published builds resolve the zipped `GhosttyKit.xcframework` artifact
from the tagged repository contents, so downstream packages can depend on
`GhosttyKit` without unsafe build flags.

## Maintainer Local Static Mode

Maintainers can opt into the tracked flat static library and header shim when
they need to iterate on the package locally:

```sh
GHOSTTYKIT_USE_LOCAL_STATIC=1 swift build
```

That mode uses `Vendor/GhosttyKitStatic` plus `Sources/CGhosttyKitBinary`.

## Updating libghostty

The vendored artifact and headers are refreshed from the upstream Ghostty source
tracked in the `Vendor/ghostty-upstream` submodule.

For a manual refresh:

```sh
git submodule update --init --recursive
./Scripts/update-libghostty.sh
```

To pin a specific upstream ref first:

```sh
./Scripts/update-libghostty.sh --ref origin/main
./Scripts/update-libghostty.sh --latest-tag
```

The script rebuilds `GhosttyKit.xcframework`, syncs the public headers, refreshes
the local static-library fallback files, and records the exact upstream commit in
`Vendor/libghostty.version`.

To refresh the tracked distribution archive without rebuilding:

```sh
./Scripts/unpack-artifact.sh
./Scripts/package-artifact.sh
```

## Automation

- CI validates the package builds and tests cleanly on macOS arm64 and checks
  that the repo is publishable without SwiftPM unsafe flags.
- Dependabot watches both GitHub Actions and the `Vendor/ghostty-upstream`
  submodule.
- A GitHub Actions workflow amends Dependabot submodule PRs by regenerating the
  zipped XCFramework, header mirror, and metadata so upstream `libghostty`
  changes arrive as a reviewable pull request instead of manual repo surgery.

## License

This wrapper is MIT licensed. The bundled `libghostty` sources and binary are
derived from upstream Ghostty, which is also MIT licensed.
