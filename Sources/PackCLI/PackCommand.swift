import Foundation
import ArgumentParser
import PackLib

public struct PackCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "swiftpack")

    // MARK: - Building options

    enum BuildConfiguration: String, CaseIterable, ExpressibleByArgument {
        case debug
        case release
    }

    @Option(
        help: "The Swift Package path to operate on",
        completion: .directory
    ) var packagePath = "."

    @Option(
        name: .shortAndLong,
        help: "Build with configuration"
    ) var configuration: BuildConfiguration = .debug

    @Option(
        help: "The target triple to build for"
    ) var triple = "arm64-apple-ios"

    // MARK: - Packaging options

    @Option(
        help: "Path to the Info plist",
        completion: .file(extensions: ["plist"]),
        transform: URL.init(fileURLWithPath:)
    )
    var info: URL = URL(fileURLWithPath: "Info.plist")

    // MARK: - Implementation

    public init() {}

    public func run() async throws {
        print("Planning...")
        let swiftPMSettings = SwiftPMSettings(
            packagePath: packagePath,
            options: [
                "--configuration", configuration.rawValue,
                "--swift-sdk", triple
            ]
        )

        let planner = Planner(swiftPMSettings: swiftPMSettings)
        let plan = try await planner.createPlan()

        let builder = swiftPMSettings.invocation(
            forTool: "build",
            arguments: [
                "--product", plan.product,
                "-Xlinker", "-rpath", "-Xlinker", "@executable_path/Frameworks",
            ]
        )
        try builder.run()
        await builder.waitForExit()
        let binDir = URL(fileURLWithPath: packagePath, isDirectory: true)
            .appendingPathComponent(".build/\(triple)/\(configuration.rawValue)", isDirectory: true)

        let packer = Packer(
            plan: plan,
            info: info,
            binDir: binDir
        )
        let output = try await packer.pack()

        print("Output: \(output.path)")
    }
}
