// swift-tools-version: 6.0

import Foundation
import PackageDescription

let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()

let localLibraryDirectoryPath = "Vendor/GhosttyKitStatic/macos-arm64"
let localLibraryDirectoryAbsolutePath = packageRoot
    .appendingPathComponent(localLibraryDirectoryPath)
    .path
let localLibraryAbsolutePath = packageRoot
    .appendingPathComponent("\(localLibraryDirectoryPath)/libghostty-fat.a")
    .path

let useLocalStaticBinary = ProcessInfo.processInfo.environment["GHOSTTYKIT_USE_LOCAL_STATIC"] == "1"

let releaseTag = "0.1.1"
let releaseArtifactURL = "https://raw.githubusercontent.com/briannadoubt/GhosttyKit/\(releaseTag)/Vendor/GhosttyKit.xcframework.zip"
let releaseChecksum = try String(
    contentsOf: packageRoot.appendingPathComponent("Vendor/GhosttyKit.checksum"),
    encoding: .utf8
).trimmingCharacters(in: .whitespacesAndNewlines)

let binaryTarget: Target = if useLocalStaticBinary && FileManager.default.fileExists(atPath: localLibraryAbsolutePath) {
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
    )
} else {
    .binaryTarget(
        name: "CGhosttyKitBinary",
        url: releaseArtifactURL,
        checksum: releaseChecksum
    )
}

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
        binaryTarget,
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
