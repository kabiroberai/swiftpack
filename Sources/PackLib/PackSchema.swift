import Foundation
import Yams

public struct PackSchema: Codable, Sendable {
    public enum Version: Int, Codable, Sendable {
        case v1 = 1
    }

    public var version: Version

    public var orgID: String?
    public var bundleID: String?

    public var libraryProduct: String?
    public var binaryProduct: String?

    public func validate() throws {
        if version != .v1 {
            throw StringError("swiftpack.yml: Unsupported schema version: \(version.rawValue)")
        }
    }
}

extension PackSchema {
    public init() {
        self.version = .v1
    }

    public init(url: URL) async throws {
        let data = try await Data(reading: url)
        self = try YAMLDecoder().decode(Self.self, from: data)
        try self.validate()
    }
}

/*
 name: MyApp
 options:
   localPackagesGroup: ""
 packages:
   LocalPackage:
     path: ..
 targets:
   MyApp:
     type: application
     platform: iOS
     deploymentTarget: "18.0"
     sources:
       - Empty
     dependencies:
       - package: LocalPackage
         product: MyAppLib
     settings:
       PRODUCT_BUNDLE_IDENTIFIER: com.kabiroberai.MyApp
       GENERATE_INFOPLIST_FILE: YES
       CURRENT_PROJECT_VERSION: 1
       MARKETING_VERSION: 1
 */
