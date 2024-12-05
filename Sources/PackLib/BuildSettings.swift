import Foundation

public struct BuildSettings: Sendable {
    private static let customBinDir =
        // this is the same option used by SwiftPM itself for dev builds
        ProcessInfo.processInfo.environment["SWIFTPM_CUSTOM_BIN_DIR"].map { URL(fileURLWithPath: $0) }

    private static let envURL = URL(fileURLWithPath: "/usr/bin/env")

    public let packagePath: String
    public let configuration: BuildConfiguration
    public let triple: String
    public let sdkOptions: [String]
    public let options: [String]

    public init(
        configuration: BuildConfiguration,
        packagePath: String = ".",
        options: [String] = []
    ) async throws {
        self.packagePath = packagePath
        self.configuration = configuration
        self.options = options

        // TODO: allow customizing?
        self.triple = "arm64-apple-ios"

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
        self.sdkOptions = [
            "--triple", triple,
            "--sdk", sdkPath,
        ]
        #else
        self.sdkOptions = [
            "--swift-sdk", triple
        ]
        #endif
    }

    public func swiftPMInvocation(
        forTool tool: String,
        arguments: [String],
        packagePathOverride: String? = nil
    ) -> Process {
        let process = Process()
        process.executableURL = Self.envURL
        let base = if let customBinDir = Self.customBinDir {
            [customBinDir.appendingPathComponent("swift-\(tool)").path]
        } else {
            ["swift", tool]
        }
        process.arguments = base + [
            "--package-path", packagePathOverride ?? packagePath,
            "--configuration", configuration.rawValue,
        ] + options + arguments
        return process
    }
}

public enum BuildConfiguration: String, CaseIterable, Sendable {
    case debug
    case release
}
