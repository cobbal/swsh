// swift-tools-version:5.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swsh",
    platforms: [
        .macOS(.v10_14),
    ],
    products: [
        .library(
            name: "swsh",
            targets: ["swsh"]),
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "swsh",
            dependencies: ["linuxSpawn"]),
        .testTarget(
            name: "swshTests",
            dependencies: ["swsh"]),
        .target(
          name: "linuxSpawn",
          dependencies: []),
    ]
)
