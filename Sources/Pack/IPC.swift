// NB: this file is shared with swiftpack-support.
// If you break API, update the Plan plugin accordingly.

struct Plan: Codable {
    let product: String
    let resources: [Resource]
}

enum Resource: Codable {
    case bundle(package: String, target: String)
    case binaryTarget(name: String)
    case library(name: String)
}
