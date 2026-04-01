// swift-tools-version: 6.0

import Foundation
import PackageDescription

let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()

let localLibraryDirectoryAbsolutePath = packageRoot
    .appendingPathComponent("Vendor/GhosttyKitStatic/macos-arm64")
    .path

let package = Package(
    name: "GhosttyKit",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "GhosttyKit",
            targets: ["GhosttyKit"]
        )
    ],
    targets: [
        .target(
            name: "CGhosttyKitBinary",
            path: "Sources/CGhosttyKitBinary",
            publicHeadersPath: ".",
            linkerSettings: [
                .unsafeFlags([
                    "-L", localLibraryDirectoryAbsolutePath,
                    "-lghostty-fat",
                ])
            ]
        ),
        .target(
            name: "GhosttyKit",
            dependencies: [
                "CGhosttyKitBinary",
            ],
            path: "Sources/GhosttyKitExports",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreText"),
                .linkedFramework("IOSurface"),
                .linkedFramework("Metal"),
                .linkedLibrary("c++"),
            ]
        ),
        .testTarget(
            name: "GhosttyKitTests",
            dependencies: [
                "GhosttyKit",
            ]
        )
    ]
)
