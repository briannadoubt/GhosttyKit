// swift-tools-version: 6.0

import PackageDescription

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
        .binaryTarget(
            name: "GhosttyKitBinary",
            path: "Vendor/GhosttyKit.xcframework"
        ),
        .target(
            name: "CGhosttyKitBinary",
            dependencies: [
                "GhosttyKitBinary",
            ],
            path: "Sources/CGhosttyKitBinary",
            publicHeadersPath: "."
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
