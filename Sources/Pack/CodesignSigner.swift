#if canImport(Security)
import Security
import Foundation
import SecuritySPI

struct CodesignSigner: Signer {
    let identity: SecIdentity

    private static func check(_ code: OSStatus) throws {
        if code == errSecSuccess { return }
        var userInfo: [String: Any] = [:]
        if let message = SecCopyErrorMessageString(code, nil) as? String {
            userInfo[NSLocalizedDescriptionKey] = message
        }
        throw NSError(domain: NSOSStatusErrorDomain, code: Int(code), userInfo: userInfo)
    }

    /// Create a new ``CodesignSigner``.
    ///
    /// - Parameter certificate: A DER encoded x509 certificate.
    ///
    /// - Parameter privateKey: A DER encoded PKCS1 RSA private key.
    init(certificate: Data, privateKey: Data) throws {
        guard let certificate = SecCertificateCreateWithData(nil, certificate as CFData) else {
            throw StringError("Could not parse certificate")
        }

        var error: Unmanaged<CFError>?
        let key = SecKeyCreateWithData(privateKey as CFData, [
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            kSecAttrKeyType: kSecAttrKeyTypeRSA
        ] as CFDictionary, &error)
        if let error { throw error.takeUnretainedValue() }

        guard let identity = SecIdentityCreate(nil, certificate, key) else {
            throw StringError("Failed to create signing identity")
        }

        self.identity = identity
    }

    private static let blobHeaderSize = MemoryLayout<UInt32>.size + MemoryLayout<UInt32>.size
    private static let entitlementsBlobMagic: UInt32 = 0xfade7171

    static func analyze(url: URL) async throws -> Data {
        var staticCode: SecStaticCode!
        try Self.check(SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode))

        var info: CFDictionary!
        try Self.check(SecCodeCopySigningInformation(staticCode, .init(rawValue: kSecCSRequirementInformation), &info))
        guard let dict = info as? [String: Any], let entitlementsRaw = dict["entitlements"] as? Data
            else { throw StringError("Could not parse entitlements") }
        return entitlementsRaw[Self.blobHeaderSize...]
    }

    func codesign(url: URL, entitlements: URL?) async throws {
        var signerOptions: [CFString: Any] = [
            kSecCodeSignerIdentity: identity
        ]
        if let entitlements {
            let entitlementsData = try await Data(reading: entitlements)
            let entitlementsLen = Self.blobHeaderSize + entitlementsData.count
            // kSecCodeSignerEntitlements expects an EntitlementsBlob
            var data = Data()
            data.reserveCapacity(entitlementsLen)
            data.append(contentsOf: Self.entitlementsBlobMagic.bigEndianBytes)
            data.append(contentsOf: UInt32(entitlementsLen).bigEndianBytes)
            data.append(entitlementsData)
            signerOptions[kSecCodeSignerEntitlements] = data
        }
        var signer: SecCodeSignerRef!
        try Self.check(SecCodeSignerCreate(signerOptions as CFDictionary, [], &signer))

        var staticCode: SecStaticCode!
        try Self.check(SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode))

        var rawError: Unmanaged<CFError>?
        let osError = SecCodeSignerAddSignatureWithErrors(signer, staticCode, [], &rawError)
        if let rawError { throw rawError.takeRetainedValue() }
        try Self.check(osError)
    }
}
#endif
