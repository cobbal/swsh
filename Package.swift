// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "swsh",
    platforms: [
        .macOS(.v10_14),
    ],
    products: [
        .library(
            name: "swsh",
            targets: ["swsh"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "swsh",
            dependencies: [
                .target(name: "linuxSpawn", condition: .when(platforms: [.linux])),
                .target(name: "windowsSpawn", condition: .when(platforms: [.windows])),
            ]
        ),
        .testTarget(
            name: "swshTests",
            dependencies: ["swsh"]
        ),
        .target(
            name: "linuxSpawn",
            dependencies: []
        ),
        .target(
            name: "windowsSpawn",
            dependencies: []
        ),
    ]
)
