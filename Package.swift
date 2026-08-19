// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "DynamicNotch",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "DynamicNotch",
            targets: ["DynamicNotch"]
        ),
        .executable(
            name: "DynamicNotchDemo",
            targets: ["DynamicNotchDemo"]
        )
    ],
    targets: [
        .target(
            name: "DynamicNotch"
        ),
        .executableTarget(
            name: "DynamicNotchDemo",
            dependencies: ["DynamicNotch"]
        ),
        .testTarget(
            name: "DynamicNotchTests",
            dependencies: ["DynamicNotch"]
        )
    ]
)
