import PackagePlugin
import Foundation

@main struct Plugin: CommandPlugin {
    func performCommand(
        context: PluginContext,
        arguments: [String]
    ) async throws {
        var packageByTargetID: [Target.ID: Package] = [:]
        var packageStack = [context.package]
        while let package = packageStack.popLast() {
            for target in package.targets {
                packageByTargetID[target.id] = package
            }
            packageStack.append(contentsOf: package.dependencies.map(\.package))
        }

        let executables = context.package.dependencies[0].package.products(ofType: ExecutableProduct.self)
        let executable: ExecutableProduct
        if executables.count == 1 {
            executable = executables[0]
        } else {
            throw StringError("Your package should include 1 executable product")
        }

        var planResources: [Resource] = []
        var targets = executable.targets
        // this is depth-first but that's okay because we scan everything
        while let target = targets.popLast() {
            if let binaryTarget = target as? BinaryArtifactTarget {
                planResources.append(.binaryTarget(name: binaryTarget.name))
            } else if let sourceTarget = target as? SourceModuleTarget,
                sourceTarget.sourceFiles.contains(where: { $0.type == .resource }) {
                guard let package = packageByTargetID[sourceTarget.id] else {
                    throw StringError("internal inconsistency: could not determine package for target id=\(sourceTarget.id)")
                }
                planResources.append(.bundle(package: package.displayName, target: target.name))
            }
            for dependency in target.dependencies {
                switch dependency {
                case .product(let product):
                    if let dylib = product as? LibraryProduct, dylib.kind == .dynamic {
                        planResources.append(.library(name: dylib.name))
                    }
                    targets.append(contentsOf: product.targets)
                case .target(let target):
                    targets.append(target)
                @unknown default:
                    break
                }
            }
        }

        let plan = Plan(product: executable.name, resources: planResources)
        print(try String(decoding: JSONEncoder().encode(plan), as: UTF8.self))
    }
}

struct StringError: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) {
        self.description = description
    }
}
