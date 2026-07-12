// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "FlipbookDesignSystem",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "FlipbookDesignSystem",
            targets: ["FlipbookDesignSystem"]
        ),
    ],
    dependencies: [
        .package(path: "../FlipbookCore"),
    ],
    targets: [
        .target(
            name: "FlipbookDesignSystem",
            dependencies: [
                .product(name: "FlipbookCore", package: "FlipbookCore"),
            ]
        ),
        .testTarget(
            name: "FlipbookDesignSystemTests",
            dependencies: ["FlipbookDesignSystem"]
        ),
    ]
)
