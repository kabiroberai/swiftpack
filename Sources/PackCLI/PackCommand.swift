import Foundation
import ArgumentParser
import PackCore
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
        help: ArgumentHelp(
            "Generate an Xcode project",
            discussion: "This option does nothing on Linux."
        )
    ) var xcode: Bool = false

    @Flag(
        help: ArgumentHelp(
            "Dump output as parsable JSON",
            discussion: "The output format is described in PackCore."
        )
    ) var json = false

    // MARK: - Building options

    @Option(
        name: .shortAndLong,
        help: "Build with configuration"
    ) var configuration: BuildConfiguration = .debug

    // MARK: - Implementation

    public init() {}

    public func run() async throws {
        stderrPrint("Planning...")

        let schema: PackSchema
        if FileManager.default.fileExists(atPath: configPath.path) {
            schema = try await PackSchema(url: configPath)
        } else {
            schema = .default
            stderrPrint("""
            warning: Could not locate configuration file '\(configPath.path)'. Using default \
            configuration with 'com.example' organization ID.
            """)
        }

        let buildSettings = try await BuildSettings(
            configuration: configuration,
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
            stderrPrint("Project: \(output.path)")
            return
        }
        #endif

        let packer = Packer(
            buildSettings: buildSettings,
            plan: plan
        )
        let output = try await packer.pack()

        if json {
            let json = try PackOutput(path: output.path).encode()
            print(String(decoding: json, as: UTF8.self))
        } else {
            stderrPrint("Output: ", terminator: "")
            print(output.path)
        }
    }
}

extension BuildConfiguration: ExpressibleByArgument {}
