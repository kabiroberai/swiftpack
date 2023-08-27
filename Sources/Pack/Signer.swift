import Foundation
import X509

protocol Signer {
    func analyze(url: URL) async throws -> Data

    func codesign(
        url: URL,
        certificate: Certificate,
        key: Certificate.PrivateKey,
        entitlements: Data?
    ) async throws
}

#if canImport(Security)
extension Signer where Self == CodesignSigner {
    static var `default`: Self { .init() }
}
#else
// TODO: Support non-codesign signers (ldid?)
#endif
