// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "swiftpack",
    platforms: [.macOS(.v12), .iOS(.v15)],
    products: [
        .executable(
            name: "swiftpack",
            targets: ["Pack"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.3"),
    ],
    targets: [
        .executableTarget(
            name: "Pack",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
    ]
)
