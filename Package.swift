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
        .library(name: "SecuritySPI", targets: ["SecuritySPI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.3"),
        .package(url: "https://github.com/apple/swift-certificates", from: "1.0.0-beta.1"),
    ],
    targets: [
        .systemLibrary(name: "SecuritySPI"),
        .executableTarget(
            name: "Pack",
            dependencies: [
                "SecuritySPI",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "X509", package: "swift-certificates")
            ]
        ),
    ]
)
