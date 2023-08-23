// swift-tools-version: 5.9

import PackageDescription
import Foundation

let package = Package(
    name: "swiftpack-support",
    platforms: [.macOS(.v12)],
    products: [
        .plugin(name: "plan-swiftpack", targets: ["Plan"]),
    ],
    targets: [
        .plugin(
            name: "Plan",
            capability: .command(intent: .custom(verb: "plan-swiftpack", description: "Plan swiftpack operation")),
            path: "."
        ),
    ]
)

if let path = ProcessInfo.processInfo.environment["SWIFTPACK_TARGET_PATH"] {
    package.dependencies.append(.package(path: path))
}
