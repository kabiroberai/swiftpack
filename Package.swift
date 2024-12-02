// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "swiftpack",
    platforms: [.macOS(.v12), .iOS(.v15)],
    products: [
        .executable(
            name: "pack",
            targets: ["Pack"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/jpsim/Yams", from: "5.1.3"),
    ],
    targets: [
        .executableTarget(
            name: "Pack",
            dependencies: [
                "PackCLI",
            ]
        ),
        .target(
            name: "PackCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "PackLib",
            ]
        ),
        .target(
            name: "PackLib",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
            ]
        ),
    ]
)
