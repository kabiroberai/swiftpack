import Foundation
import ArgumentParser
import PackLib

public struct PackCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "swiftpack")

    // MARK: - General options

    @Option(
        help: "Path to the configuration file",
        completion: .file(extensions: ["yml"]),
        transform: URL.init(fileURLWithPath:)
    ) var configPath = URL(fileURLWithPath: "swiftpack.yml")

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
    var info = URL(fileURLWithPath: "Info.plist")

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

        let schema: PackSchema
        if FileManager.default.fileExists(atPath: configPath.path) {
            schema = try await PackSchema(url: configPath)
        } else {
            schema = .default
            print("""
            warning: Could not locate configuration file '\(configPath.path)'. Using default \
            configuration with 'com.example' organization ID.
            """)
        }

        let infoPlist = try? await Data(reading: info)

        let planner = Planner(
            swiftPMSettings: swiftPMSettings,
            infoPlist: infoPlist,
            schema: schema
        )
        let plan = try await planner.createPlan()

        let builder = swiftPMSettings.invocation(
            forTool: "build",
            arguments: [
                "--product", plan.binaryProduct,
                "-Xlinker", "-rpath", "-Xlinker", "@executable_path/Frameworks",
                "-Xswiftc", "-parse-as-library", // don't generate _main for exec target
            ]
        )
        try builder.run()
        await builder.waitForExit()
        let binDir = URL(fileURLWithPath: packagePath, isDirectory: true)
            .appendingPathComponent(".build/\(triple)/\(configuration.rawValue)", isDirectory: true)

        let packer = Packer(
            plan: plan,
            binDir: binDir
        )
        let output = try await packer.pack()

        print("Output: \(output.path)")
    }
}