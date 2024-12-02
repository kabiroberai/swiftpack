import Foundation

public struct SwiftPMSettings: Sendable {
    private static let customBinDir =
        // this is the same option used by SwiftPM itself for dev builds
        ProcessInfo.processInfo.environment["SWIFTPM_CUSTOM_BIN_DIR"].map { URL(fileURLWithPath: $0) }

    private static let envURL = URL(fileURLWithPath: "/usr/bin/env")

    public var packagePath: String = "."
    public var options: [String] = []

    public init(packagePath: String, options: [String]) {
        self.packagePath = packagePath
        self.options = options
    }

    public func invocation(
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
        process.arguments = base + ["--package-path", packagePathOverride ?? packagePath] + options + arguments
        return process
    }
}
