import Foundation

struct Planner {
    var swiftPMSettings: SwiftPMSettings

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    func createPlan() async throws -> Plan {
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
        let executables = rootPackage.products?.filter { $0.type == .executable } ?? []
        let executable: PackageDump.Product
        if executables.count == 1 {
            executable = executables[0]
        } else {
            throw StringError("Your package should include 1 executable product")
        }

        var resources: [Resource] = []
        var visited: Set<String> = []
        var targets = executable.targets.map { (rootPackage, $0) }
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

        return Plan(product: executable.name, resources: resources)
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
}

struct Plan: Codable {
    let product: String
    let resources: [Resource]
}

enum Resource: Codable {
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
        case other

        private enum CodingKeys: String, CodingKey {
            case executable
            case library
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if container.contains(.executable) {
                self = .executable
            } else if let library = try container.decodeIfPresent([String].self, forKey: .library), library == ["dynamic"] {
                self = .dynamicLibrary
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

    let name: String
    let products: [Product]?
    let targets: [Target]?
}
