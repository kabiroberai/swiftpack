import PackagePlugin
import Foundation

@main struct Plugin: CommandPlugin {
    func performCommand(
        context: PluginContext,
        arguments: [String]
    ) async throws {
        let executables = context.package.dependencies[0].package.products(ofType: ExecutableProduct.self)
        let executable: ExecutableProduct
        if executables.count == 1 {
            executable = executables[0]
        } else {
            throw StringError("Your package should include 1 executable product")
        }

        guard let sourceModule = executable.mainTarget.sourceModule
            else { throw StringError("Expected main target to be a source module") }
        guard let plist = sourceModule.sourceFiles.first(where: {
            $0.type == .resource && $0.path.lastComponent == "PackInfo.plist"
        })?.path
            else { throw StringError("Expected main target to contain a PackInfo.plist") }

        var planResources: [Resource] = []
        var targets = executable.targets
        // this is depth-first but that's okay because we scan everything
        while let target = targets.popLast() {
            if let binaryTarget = target as? BinaryArtifactTarget {
                planResources += [.binaryTarget(name: binaryTarget.name)]
            } else if let sourceTarget = target as? SourceModuleTarget {
                planResources += sourceTarget.sourceFiles
                    .filter { $0.type == .resource }
                    .map(\.path)
                    .map { $0 == plist ? .infoPlist(path: $0.string) : .normal(path: $0.string) }
            }
            for dependency in target.dependencies {
                switch dependency {
                case .product(let product):
                    if let dylib = product as? LibraryProduct, dylib.kind == .dynamic {
                        planResources += [.library(name: dylib.name)]
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
