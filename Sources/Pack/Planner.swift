import Foundation

struct Planner {
    var swiftPMSettings: SwiftPMSettings = .init()

    func createPlan(packagePath: String) async throws -> Plan {
        let package = URL(
            fileURLWithPath: packagePath,
            isDirectory: true,
            relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        ).standardized

        let tmp = package.appendingPathComponent(".build/swiftpack/planner")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let tarInput = Pipe()
        let tar = Process()
        tar.standardInput = tarInput
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        tar.arguments = ["tar", "-C", tmp.path, "-xzf", "-"]
        try tar.run()
        try tarInput.fileHandleForWriting.write(contentsOf: PackageResources.swiftpack_support_tar_gz)
        try tarInput.fileHandleForWriting.close()
        await tar.waitForExit()

        let outPipe = Pipe()
        let process = swiftPMSettings.invocation(
            forTool: "package",
            arguments: ["--package-path", tmp.path, "plan-swiftpack"]
        )
        process.environment = {
            var env = ProcessInfo.processInfo.environment
            env["SWIFTPACK_TARGET_PATH"] = package.path
            return env
        }()
        process.standardOutput = outPipe
        try process.run()
        // waitForExit needs to run asap to wire up cancellation, so
        // we start bytesTask as a structured child
        async let bytesTask = Data(reading: outPipe.fileHandleForReading)
        await process.waitForExit()
        let bytes = try await bytesTask

        try Task.checkCancellation()

        do {
            return try JSONDecoder().decode(Plan.self, from: bytes)
        } catch {
            throw StringError("Planning failed: \(error)")
        }
    }
}
