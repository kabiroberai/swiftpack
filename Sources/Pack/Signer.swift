import Foundation
import X509

protocol Signer {
    func analyze(url: URL) async throws -> Data

    func codesign(
        url: URL,
        identity: SigningIdentity,
        entitlements: Data?
    ) async throws
}

struct SigningIdentity {
    var certificate: Certificate
    var key: Certificate.PrivateKey
}

struct NoOpSigner: Signer {
    func analyze(url: URL) async throws -> Data { Data() }
    func codesign(url: URL, identity: SigningIdentity, entitlements: Data?) async throws {}
}

#if canImport(Security)
extension Signer where Self == CodesignSigner {
    static var `default`: Self { .init() }
}
#else
extension Signer where Self == NoOpSigner {
    static var `default`: Self { .init() }
}
// TODO: Support non-codesign signers (ldid?)
#endif
