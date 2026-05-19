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
        ),
        .executable(
            name: "GhosttyKitDemo",
            targets: ["GhosttyKitDemo"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "CGhosttyKitBinary",
            path: "Vendor/GhosttyKit.xcframework"
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
        .executableTarget(
            name: "GhosttyKitDemo",
            dependencies: [
                "GhosttyKit",
            ],
            path: "Sources/GhosttyKitDemo",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
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
