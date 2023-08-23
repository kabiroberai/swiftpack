import Foundation
import ArgumentParser

struct PackCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "swiftpack")

    // MARK: - Building options

    enum BuildConfiguration: String, CaseIterable, ExpressibleByArgument {
        case debug
        case release
    }

    @Option(
        help: "The Swift Package path to operate on",
        completion: .directory
    ) var packagePath = "."

    @Option(
        name: .shortAndLong,
        help: "Build with configuration"
    ) var configuration: BuildConfiguration = .debug

    @Option(
        help: "The target triple to build for"
    ) var triple = "arm64-apple-ios"

    // MARK: - Packaging options

    @Option(
        help: "Path to the Info plist",
        completion: .file(extensions: ["plist"]),
        transform: URL.init(fileURLWithPath:)
    )
    var info: URL = URL(fileURLWithPath: "Info.plist")

    @Option(
        help: "Path to the entitlements plist",
        completion: .file(),
        transform: URL.init(fileURLWithPath:)
    ) 
    var entitlements: URL?

    @Option(
        help: .init(
            "Path to signing certficiate",
            discussion: "The certificate should be a DER encoded, x509."
        ),
        completion: .file(),
        transform: URL.init(fileURLWithPath:)
    ) 
    var certificate: URL

    @Option(
        help: .init(
            "Path to private key",
            discussion: "The key should be DER encoded, PKCS1, RSA."
        ),
        completion: .file(),
        transform: URL.init(fileURLWithPath:)
    ) 
    var key: URL

    @Option(
        help: "Path to mobileprovision file",
        completion: .file(extensions: ["mobileprovision"]),
        transform: URL.init(fileURLWithPath:)
    ) 
    var profile: URL?

    // MARK: - Implementation

    func run() async throws {
        print("Planning...")
        let swiftPMSettings = SwiftPMSettings(options: [
            "--configuration", configuration.rawValue,
            "--experimental-swift-sdk", triple
        ])

        let planner = Planner(swiftPMSettings: swiftPMSettings)
        let plan = try await planner.createPlan(packagePath: packagePath)

        let builder = swiftPMSettings.invocation(
            forTool: "build",
            arguments: [
                "--package-path", packagePath,
                "--product", plan.product,
                "-Xlinker", "-rpath", "-Xlinker", "@executable_path/Frameworks",
            ]
        )
        try builder.run()
        await builder.waitForExit()
        let binDir = URL(fileURLWithPath: packagePath, isDirectory: true)
            .appendingPathComponent(".build/\(triple)/\(configuration.rawValue)", isDirectory: true)

        async let certData = try await Data(reading: certificate)
        async let keyData = try await Data(reading: key)
        // TODO: Support non-codesign signers (ldid?)
        let signer = try await CodesignSigner(certificate: certData, privateKey: keyData)

        let profileData = if let profile { try await Data(reading: profile) } else { Data?.none }
        let packer = Packer(
            plan: plan,
            info: info,
            binDir: binDir,
            signer: signer,
            profile: profileData,
            entitlements: entitlements
        )
        let output = try await packer.pack()

        print("Output: \(output.path)")
    }
}
