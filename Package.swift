// swift-tools-version: 6.0

import Foundation
import PackageDescription

let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()

let localArtifactPath = "Vendor/GhosttyKit.xcframework"
let localArtifactAbsolutePath = packageRoot
    .appendingPathComponent("Vendor/GhosttyKit.xcframework")
    .path

let releaseTag = "0.1.0"
let releaseArtifactURL = "https://raw.githubusercontent.com/briannadoubt/GhosttyKit/\(releaseTag)/Vendor/GhosttyKit.xcframework.zip"
let releaseChecksum = try String(
    contentsOf: packageRoot.appendingPathComponent("Vendor/GhosttyKit.checksum"),
    encoding: .utf8
).trimmingCharacters(in: .whitespacesAndNewlines)

let binaryTarget: Target = if FileManager.default.fileExists(atPath: localArtifactAbsolutePath) {
    .binaryTarget(
        name: "CGhosttyKitBinary",
        path: localArtifactPath
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
