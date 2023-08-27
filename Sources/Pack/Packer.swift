import Foundation
import X509

struct Packer {
    var plan: Plan
    var info: URL
    var binDir: URL

    var certificate: Certificate
    var key: Certificate.PrivateKey
    var profile: Data?
    var entitlements: Data?
    var signer: any Signer = .default

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
                try await signer.codesign(url: dstURL, certificate: certificate, key: key, entitlements: nil)
            }
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for command in plan.resources {
                group.addTask {
                    switch command {
                    case .bundle(let package, let target):
                        try await packFile(srcName: "\(package)_\(target).bundle")
                    case .binaryTarget(let name):
                        let src = URL(fileURLWithPath: "\(name).framework/\(name)", relativeTo: binDir)
                        let magic = Data("!<arch>\n".utf8)
                        let thinMagic = Data("!<thin>\n".utf8)
                        let bytes = try FileHandle(forReadingFrom: src).read(upToCount: magic.count)
                        // if the magic matches one of these it's a static archive; don't embed it.
                        // https://github.com/apple/llvm-project/blob/e716ff14c46490d2da6b240806c04e2beef01f40/llvm/include/llvm/Object/Archive.h#L33
                        if bytes != magic && bytes != thinMagic {
                            try await packFile(srcName: "\(name).framework", dstName: "Frameworks/\(name).framework", sign: true)
                        }
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
        try await signer.codesign(url: output.url, certificate: certificate, key: key, entitlements: entitlements)

        let dest = URL(fileURLWithPath: output.url.lastPathComponent)
        try? FileManager.default.removeItem(at: dest)
        try output.persist(at: dest)
        return dest
    }
}
