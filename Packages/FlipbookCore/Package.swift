// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "FlipbookCore",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "FlipbookCore",
            targets: ["FlipbookCore"]
        ),
    ],
    targets: [
        .target(
            name: "FlipbookCore"
        ),
        .testTarget(
            name: "FlipbookCoreTests",
            dependencies: ["FlipbookCore"]
        ),
    ]
)
