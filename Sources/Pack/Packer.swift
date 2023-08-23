import Foundation

struct Packer {
    let plan: Plan
    let info: URL
    let binDir: URL
    let signer: any Signer
    let profile: Data?
    let entitlements: URL?

    func pack() async throws -> URL {
        let output = try TemporaryDirectory(name: "\(plan.product).app")

        let outputURL = output.url
        @Sendable func packFile(srcName: String, dstName: String? = nil, sign: Bool = false) async throws {
            let srcURL = URL(fileURLWithPath: srcName, relativeTo: binDir)
            let dstURL = URL(fileURLWithPath: dstName ?? srcURL.lastPathComponent, relativeTo: outputURL)
            try? FileManager.default.createDirectory(at: dstURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: srcURL, to: dstURL)

            try Task.checkCancellation()

            if sign {
                try await signer.codesign(url: dstURL, entitlements: nil)
            }
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for command in plan.resources {
                group.addTask {
                    switch command {
                    case .bundle(let package, let target):
                        try await packFile(srcName: "\(package)_\(target).bundle")
                    case .binaryTarget(let name):
                        try await packFile(srcName: "\(name).framework", dstName: "Frameworks/\(name).framework", sign: true)
                    case .library(let name):
                        try await packFile(srcName: "lib\(name).dylib", dstName: "Frameworks/lib\(name).dylib", sign: true)
                    }
                }
            }
            group.addTask {
                try await packFile(srcName: plan.product)
            }
            group.addTask {
                try profile?.write(to: outputURL.appendingPathComponent("embedded.mobileprovision"))
            }
            group.addTask {
                try await packFile(srcName: info.path, dstName: "Info.plist")
            }
            while !group.isEmpty {
                do {
                    try await group.next()
                } catch is CancellationError {
                    // continue
                } catch {
                    group.cancelAll()
                    throw error
                }
            }
        }
        try await signer.codesign(url: output.url, entitlements: entitlements)

        let dest = URL(fileURLWithPath: output.url.lastPathComponent)
        try? FileManager.default.removeItem(at: dest)
        try output.persist(at: dest)
        return dest
    }
}
