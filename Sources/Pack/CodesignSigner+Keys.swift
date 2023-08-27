#if canImport(Security)
import Foundation
import Security
import X509
import Crypto
import _CryptoExtras

extension Certificate.PrivateKey {
    func asSecKey() throws -> SecKey {
        // round-trip through PEM because Certificate.PrivateKey doesn't
        // offer other export options
        let pem = try serializeAsPEM()
        guard let key = privateKeyTypes.lazy
            .compactMap({ try? $0.init(pemRepresentation: pem.pemString) })
            .first
            else { throw StringError("Could not parse private key") }
        return try key.asSecKey()
    }
}

private protocol PrivateKeyProtocol {
    init(pemRepresentation: String) throws
    func asSecKey() throws -> SecKey
}
private let privateKeyTypes: [any PrivateKeyProtocol.Type] = [
    _RSA.Signing.PrivateKey.self,
    P256.Signing.PrivateKey.self,
    P384.Signing.PrivateKey.self,
    P521.Signing.PrivateKey.self,
]

private protocol SimplePrivateKeyProtocol: PrivateKeyProtocol {
    var secRepresentation: Data { get }
    var secOptions: [CFString: Any] { get }
}
extension SimplePrivateKeyProtocol {
    func asSecKey() throws -> SecKey {
        var options = secOptions
        options[kSecAttrKeyClass] = kSecAttrKeyClassPrivate
        var error: Unmanaged<CFError>?
        let key = SecKeyCreateWithData(secRepresentation as CFData, options as CFDictionary, &error)
        // libsecurity returns errors as owned (+1)
        if let error { throw error.takeRetainedValue() }
        guard let key else { throw StringError("Failed to parse private key")}
        return key
    }
}
private protocol NISTPrivateKeyProtocol: SimplePrivateKeyProtocol {
    var x963Representation: Data { get }
}
extension NISTPrivateKeyProtocol {
    var secRepresentation: Data { x963Representation }
    var secOptions: [CFString: Any] { [kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom] }
}
extension _RSA.Signing.PrivateKey: SimplePrivateKeyProtocol {
    var secRepresentation: Data { derRepresentation }
    var secOptions: [CFString: Any] { [kSecAttrKeyType: kSecAttrKeyTypeRSA] }
}
extension P256.Signing.PrivateKey: NISTPrivateKeyProtocol {}
extension P384.Signing.PrivateKey: NISTPrivateKeyProtocol {}
extension P521.Signing.PrivateKey: NISTPrivateKeyProtocol {}
#endif
