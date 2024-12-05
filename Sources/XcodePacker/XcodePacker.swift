#if os(macOS)
import Foundation
import PathKit
import Version
import ProjectSpec
import XcodeGenKit
import PackLib

public struct XcodePacker {
    public var plan: Plan

    public init(plan: Plan) {
        self.plan = plan
    }

    public func createProject() async throws -> URL {
        let projectDir: Path = "swiftpack"
        try? projectDir.delete()
        try projectDir.mkpath()

        let infoPath = projectDir + "Info.plist"
        var plist = plan.infoPlist
        let families = (plist.removeValue(forKey: "UIDeviceFamily") as? [Int]) ?? [1, 2]
        let encodedPlist = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try infoPath.write(encodedPlist)

        let emptyFile = projectDir + "empty.c"
        try emptyFile.write(Data("// leave this file empty".utf8))

        let fromProjectToRoot = try Path(".").relativePath(from: projectDir)

        guard let libraryProduct = plan.libraryProduct else {
            throw StringError("Could not find libraryProduct")
        }
        guard let deploymentTarget = Version(tolerant: plan.deploymentTarget) else {
            throw StringError("Could not parse deployment target '\(plan.deploymentTarget)'")
        }
        let project = Project(
            name: plan.binaryProduct,
            targets: [
                Target(
                    name: plan.binaryProduct,
                    type: .application,
                    platform: .iOS,
                    deploymentTarget: deploymentTarget,
                    settings: Settings(buildSettings: [
                        "PRODUCT_BUNDLE_IDENTIFIER": plan.bundleID,
                        "TARGETED_DEVICE_FAMILY": families.map { "\($0)" }.joined(separator: ","),
                    ]),
                    sources: [
                        TargetSource(path: (fromProjectToRoot + emptyFile).string),
                    ],
                    dependencies: [
                        Dependency(
                            type: .package(products: [libraryProduct]),
                            reference: "LocalPackage"
                        ),
                    ],
                    info: Plist(
                        path: (fromProjectToRoot + infoPath).string,
                        attributes: [:]
                    )
                )
            ],
            packages: [
                "LocalPackage": .local(
                    path: fromProjectToRoot.string,
                    group: nil
                ),
            ],
            options: SpecOptions(
                createIntermediateGroups: false,
                localPackagesGroup: ""
            )
        )
        let generator = ProjectGenerator(project: project)
        let output = projectDir + "\(plan.binaryProduct).xcodeproj"
        do {
            let current = Path.current
            Path.current = projectDir
            defer { Path.current = current }
            let xcodeProject = try generator.generateXcodeProject(userName: NSUserName())
            try xcodeProject.write(path: fromProjectToRoot + output)
        }
        return output.url
    }
}
#endif
