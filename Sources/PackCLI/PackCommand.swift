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

    enum BuildConfiguration: String, CaseIterable, ExpressibleByArgument {
        case debug
        case release
    }

    @Option(
        name: .shortAndLong,
        help: "Build with configuration"
    ) var configuration: BuildConfiguration = .debug

    // MARK: - Implementation

    public init() {}

    public func run() async throws {
        print("Planning...")

        let triple = "arm64-apple-ios"

        var options: [String] = []
        #if os(macOS)
        let xcrun = Process()
        let pipe = Pipe()
        xcrun.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        xcrun.arguments = ["-show-sdk-path", "--sdk", "iphoneos"]
        xcrun.standardOutput = pipe
        try xcrun.run()
        await xcrun.waitForExit()
        let sdkPath = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        options += [
            "--triple", triple,
            "--sdk", sdkPath,
        ]
        #else
        options += [
            "--swift-sdk", triple
        ]
        #endif

        let swiftPMSettings = SwiftPMSettings(
            packagePath: ".",
            configuration: configuration.rawValue,
            options: options
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

        let planner = Planner(
            swiftPMSettings: swiftPMSettings,
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

        let binDir = URL(fileURLWithPath: ".build/\(triple)/\(configuration.rawValue)", isDirectory: true)
        let packer = Packer(
            plan: plan,
            settings: swiftPMSettings,
            binDir: binDir
        )
        let output = try await packer.pack()

        print("Output: \(output.path)")
    }
}
