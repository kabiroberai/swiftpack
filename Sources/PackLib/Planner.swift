import Foundation

public struct Planner: Sendable {
    public var swiftPMSettings: SwiftPMSettings
    public var schema: PackSchema

    public init(
        swiftPMSettings: SwiftPMSettings,
        schema: PackSchema
    ) {
        self.swiftPMSettings = swiftPMSettings
        self.schema = schema
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    public func createPlan() async throws -> Plan {
        // TODO: cache plan using (Package.swift+Package.resolved) as the key?

        let dependencyData = try await _dumpAction(
            arguments: ["show-dependencies", "--format", "json"],
            path: swiftPMSettings.packagePath
        )
        let dependencyRoot = try Self.decoder.decode(PackageDependency.self, from: dependencyData)

        let packages = try await withThrowingTaskGroup(
            of: (PackageDependency, PackageDump).self,
            returning: [String: PackageDump].self
        ) { group in
            var visited: Set<String> = []
            var dependencies: [PackageDependency] = [dependencyRoot]
            while let dependencyNode = dependencies.popLast() {
                guard visited.insert(dependencyNode.identity).inserted else { continue }
                dependencies.append(contentsOf: dependencyNode.dependencies)
                group.addTask { (dependencyNode, try await dumpPackage(at: dependencyNode.path)) }
            }

            var packages: [String: PackageDump] = [:]
            while let result = await group.nextResult() {
                switch result {
                case .success((let dependency, let dump)):
                    packages[dependency.identity] = dump
                case .failure(_ as CancellationError):
                    // continue loop
                    break
                case .failure(let error):
                    group.cancelAll()
                    throw error
                }
            }

            return packages
        }

        var packagesByProductName: [String: String] = [:]
        for (packageID, package) in packages {
            for product in package.products ?? [] {
                packagesByProductName[product.name] = packageID
            }
        }

        let rootPackage = packages[dependencyRoot.identity]!
        let deploymentTarget = rootPackage.platforms?.first { $0.name == "ios" }?.version ?? "13.0"

        let staticLibraries = rootPackage.products?.filter { $0.type == .staticLibrary } ?? []

        let library = try selectLibrary(
            from: staticLibraries,
            matching: schema.base.product
        )

        var resources: [Resource] = []
        var visited: Set<String> = []
        var targets = library.targets.map { (rootPackage, $0) }
        while let (targetPackage, targetName) = targets.popLast() {
            guard let target = targetPackage.targets?.first(where: { $0.name == targetName }) else {
                throw StringError("Could not find target '\(targetName)' in package '\(targetPackage.name)'")
            }
            guard visited.insert(targetName).inserted else { continue }
            if target.moduleType == "BinaryTarget" {
                resources.append(.binaryTarget(name: targetName))
            }
            if target.resources?.isEmpty == false {
                resources.append(.bundle(package: targetPackage.name, target: targetName))
            }
            for targetName in (target.targetDependencies ?? []) {
                targets.append((targetPackage, targetName))
            }
            for productName in (target.productDependencies ?? []) {
                guard let packageID = packagesByProductName[productName] else {
                    throw StringError("Could not find package containing product '\(productName)'")
                }
                guard let package = packages[packageID] else {
                    throw StringError("Could not find package by id '\(packageID)'")
                }
                guard let product = package.products?.first(where: { $0.name == productName }) else {
                    throw StringError("Could not find product '\(productName)' in package '\(packageID)'")
                }
                if product.type == .dynamicLibrary {
                    resources.append(.library(name: productName))
                }
                targets.append(contentsOf: product.targets.map { (package, $0) })
            }
        }

        let bundleID = schema.idSpecifier.formBundleID(product: library.name)

        let infoPlist: [String: Sendable]
        if let plist = self.schema.base.infoPath {
            let data = try await Data(reading: URL(fileURLWithPath: plist))
            let info = try PropertyListSerialization.propertyList(from: data, format: nil)
            if let info = info as? [String: Sendable] {
                infoPlist = info
            } else {
                throw StringError("Info.plist has invalid format: expected a dictionary.")
            }
        } else {
            infoPlist = [
                "CFBundleInfoDictionaryVersion": "6.0",
                "UIRequiredDeviceCapabilities": ["arm64"],
                "LSRequiresIPhoneOS": true,
                "CFBundleSupportedPlatforms": ["iPhoneOS"],
                "CFBundlePackageType": "APPL",
                "UIDeviceFamily": [1, 2],
                "CFBundleDevelopmentRegion": "en",
                "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait"],
                "UISupportedInterfaceOrientations~ipad": [
                  "UIInterfaceOrientationPortrait",
                  "UIInterfaceOrientationPortraitUpsideDown",
                  "UIInterfaceOrientationLandscapeLeft",
                  "UIInterfaceOrientationLandscapeRight"
                ],
                "UILaunchScreen": [:] as [String: Sendable],
                "CFBundleVersion": "1",
                "CFBundleShortVersionString": "1.0.0",
                "MinimumOSVersion": deploymentTarget,
                "CFBundleIdentifier": bundleID,
                "CFBundleName": "\(library.name)",
                "CFBundleExecutable": "\(library.name)",
            ]
        }

        return Plan(
            product: library.name,
            deploymentTarget: deploymentTarget,
            bundleID: bundleID,
            infoPlist: infoPlist,
            resources: resources
        )
    }

    private func dumpPackage(at path: String) async throws -> PackageDump {
        let data = try await _dumpAction(arguments: ["describe", "--type", "json"], path: path)
        try Task.checkCancellation()
        return try Self.decoder.decode(PackageDump.self, from: data)
    }

    private func _dumpAction(arguments: [String], path: String) async throws -> Data {
        let dump = swiftPMSettings.invocation(
            forTool: "package",
            arguments: arguments,
            packagePathOverride: path
        )
        let pipe = Pipe()
        dump.standardOutput = pipe
        try dump.run()
        async let task = Data(reading: pipe.fileHandleForReading)
        await dump.waitForExit()
        return try await task
    }

    private func selectLibrary(
        from products: [PackageDump.Product],
        matching name: String?
    ) throws -> PackageDump.Product {
        switch products.count {
        case 0:
            throw StringError("No .static library products were found in the package")
        case 1:
            let product = products[0]
            if let name, product.name != name {
                throw StringError("""
                Product name ('\(product.name)') does not match the 'product' value in the schema ('\(name)')
                """)
            }
            return product
        default:
            guard let name else {
                throw StringError("""
                Multiple .static library products were found (\(products.map(\.name))). Please either:
                1) Expose exactly one .static library product, or
                2) Specify the product you want via the 'product' key in swiftpack.yml.
                """)
            }
            guard let product = products.first(where: { $0.name == name }) else {
                throw StringError("""
                Schema declares a 'product' name of '\(name)' but no matching product was found.
                Found: \(products.map(\.name)).
                """)
            }
            return product
        }
    }
}

public struct Plan: Sendable {
    public var product: String
    public var deploymentTarget: String
    public var bundleID: String
    public var infoPlist: [String: any Sendable]
    public var resources: [Resource]
}

public enum Resource: Codable, Sendable {
    case bundle(package: String, target: String)
    case binaryTarget(name: String)
    case library(name: String)
}

private struct PackageDependency: Decodable {
    let identity: String
    let name: String
    let path: String // on disk
    let dependencies: [PackageDependency]
}

private struct PackageDump: Decodable {
    enum ProductType: Decodable {
        case executable
        case dynamicLibrary
        case staticLibrary
        case other

        private enum CodingKeys: String, CodingKey {
            case executable
            case library
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if container.contains(.executable) {
                self = .executable
            } else if let library = try container.decodeIfPresent([String].self, forKey: .library) {
                if library == ["dynamic"] {
                    self = .dynamicLibrary
                } else if library == ["static"] {
                    self = .staticLibrary
                } else {
                    self = .other
                }
            } else {
                self = .other
            }
        }
    }

    struct Product: Decodable {
        let name: String
        let targets: [String]
        let type: ProductType
    }

    struct Target: Decodable {
        let name: String
        let moduleType: String
        let productDependencies: [String]?
        let targetDependencies: [String]?
        let resources: [Resource]?
    }

    struct Resource: Decodable {
        let path: String
    }

    struct Platform: Decodable {
        let name: String
        let version: String
    }

    let name: String
    let products: [Product]?
    let targets: [Target]?
    let platforms: [Platform]?
}
