#if canImport(Security)
import Security
import Foundation
// get yourself a private SDK or copy the headers from libsecurity OSS
import SecuritySPI
import X509

struct CodesignSigner: Signer {
    private static func check(_ code: OSStatus) throws {
        if code == errSecSuccess { return }
        var userInfo: [String: Any] = [:]
        if let message = SecCopyErrorMessageString(code, nil) as? String {
            userInfo[NSLocalizedDescriptionKey] = message
        }
        throw NSError(domain: NSOSStatusErrorDomain, code: Int(code), userInfo: userInfo)
    }

    func analyze(url: URL) async throws -> Data {
        let staticCode = try staticCode(at: url)

        var info: CFDictionary!
        try Self.check(SecCodeCopySigningInformation(staticCode, .init(rawValue: kSecCSRequirementInformation), &info))
        guard let dict = info as? [String: Any], let blob = dict["entitlements"] as? Data
            else { throw StringError("Could not parse entitlements") }
        return EntitlementsBlob(blob: blob).entitlements
    }

    func codesign(url: URL, certificate: Certificate, key: Certificate.PrivateKey, entitlements: Data?) async throws {
        let secCertificate = try certificate.asSecCertificate()
        let secKey = try key.asSecKey()
        // we use this SPI instead of SecPKCS12Import because the latter
        // mutates the user's keychain
        guard let identity = SecIdentityCreate(nil, secCertificate, secKey) else {
            throw StringError("Failed to create signing identity")
        }

        var signerOptions: [CFString: Any] = [
            kSecCodeSignerIdentity: identity
        ]
        if let entitlements {
            signerOptions[kSecCodeSignerEntitlements] = EntitlementsBlob(entitlements: entitlements).blob
        }
        var signer: SecCodeSignerRef!
        try Self.check(SecCodeSignerCreate(signerOptions as CFDictionary, [], &signer))

        let staticCode = try staticCode(at: url)

        var rawError: Unmanaged<CFError>?
        let osError = SecCodeSignerAddSignatureWithErrors(signer, staticCode, [], &rawError)
        if let rawError { throw rawError.takeRetainedValue() }
        try Self.check(osError)
    }

    private func staticCode(at url: URL) throws -> SecStaticCode {
        var staticCode: SecStaticCode!
        try Self.check(SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode))
        return staticCode
    }
}

private struct EntitlementsBlob {
    let blob: Data
}

// libsecurity represents entitlements as `Blob`s: magic + length + data
extension EntitlementsBlob {
    private static let headerSize = MemoryLayout<UInt32>.size + MemoryLayout<UInt32>.size
    private static let magic: UInt32 = 0xfade7171

    init(entitlements: Data) {
        let entitlementsLen = Self.headerSize + entitlements.count
        var data = Data()
        data.reserveCapacity(entitlementsLen)
        data.append(contentsOf: Self.magic.bigEndianBytes)
        data.append(contentsOf: UInt32(entitlementsLen).bigEndianBytes)
        data.append(entitlements)
        self.blob = data
    }

    var entitlements: Data {
        blob[Self.headerSize...]
    }
}
#endif
