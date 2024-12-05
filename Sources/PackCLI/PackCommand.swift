import Foundation
import ArgumentParser
import PackLib
import XcodePacker

public struct PackCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "swiftpack")

    // MARK: - General options

    @Option(
        help: "Path to the configuration file",
        completion: .file(extensions: ["yml"]),
        transform: URL.init(fileURLWithPath:)
    ) var configPath = URL(fileURLWithPath: "swiftpack.yml")

    @Flag(
        inversion: .prefixedEnableDisable,
        help: ArgumentHelp(
            "Allow generating Xcode project instead of building with SwiftPM.",
            discussion: "This option does nothing on Linux."
        )
    ) var xcode: Bool = true

    // MARK: - Building options

    @Option(
        name: .shortAndLong,
        help: "Build with configuration"
    ) var configuration: BuildConfiguration = .debug

    // MARK: - Implementation

    public init() {}

    public func run() async throws {
        print("Planning...")

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

        let buildSettings = try await BuildSettings(
            configuration: configuration,
            packagePath: ".",
            options: []
        )

        let planner = Planner(
            buildSettings: buildSettings,
            schema: schema
        )
        let plan = try await planner.createPlan()

        #if os(macOS)
        if xcode {
            let packer = XcodePacker(plan: plan)
            let output = try await packer.createProject()
            print("Output: \(output.path)")
            return
        }
        #endif

        let packer = Packer(
            buildSettings: buildSettings,
            plan: plan
        )
        let output = try await packer.pack()

        print("Output: \(output.path)")
    }
}

extension BuildConfiguration: ExpressibleByArgument {}
