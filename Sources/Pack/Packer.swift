import Foundation

struct Packer {
    let plan: Plan
    let profile: Data?
    let entitlements: URL?
    let signer: any Signer
    let binDir: URL

    func pack() async throws -> URL {
        let output = try TemporaryDirectory(name: "\(plan.product).app")

        let outputURL = output.url
        @Sendable func packFile(srcName: String, dstName: String? = nil, sign: Bool = false) async throws {
            let srcURL = URL(fileURLWithPath: srcName, relativeTo: binDir)
            let dstURL = URL(fileURLWithPath: dstName ?? srcURL.lastPathComponent, relativeTo: outputURL)
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
                    case .normal(let path):
                        try await packFile(srcName: path)
                    case .infoPlist(let path):
                        try await packFile(srcName: path, dstName: "Info.plist")
                    case .binaryTarget(let name):
                        try await packFile(srcName: "\(name).framework", sign: true)
                    case .library(let name):
                        try await packFile(srcName: "lib\(name).dylib", sign: true)
                    }
                }
            }
            group.addTask {
                try await packFile(srcName: plan.product)
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
        try profile?.write(to: outputURL.appendingPathComponent("embedded.mobileprovision"))
        try await signer.codesign(url: output.url, entitlements: entitlements)

        let dest = URL(fileURLWithPath: output.url.lastPathComponent)
        try? FileManager.default.removeItem(at: dest)
        try output.persist(at: dest)
        return dest
    }
}
