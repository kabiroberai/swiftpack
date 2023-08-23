import Foundation

struct SwiftPMSettings {
    private static let customBinDir =
        // this is the same option used by SwiftPM itself for dev builds
        ProcessInfo.processInfo.environment["SWIFTPM_CUSTOM_BIN_DIR"].map { URL(fileURLWithPath: $0) }

    private static let envURL = URL(fileURLWithPath: "/usr/bin/env")

    var options: [String] = []

    func invocation(
        forTool tool: String,
        arguments: [String]
    ) -> Process {
        let process = Process()
        process.executableURL = Self.envURL
        let base = if let customBinDir = Self.customBinDir {
            [customBinDir.appendingPathComponent("swift-\(tool)").path]
        } else {
            ["swift", tool]
        }
        process.arguments = base + options + arguments
        return process
    }
}
