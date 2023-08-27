#if canImport(Security)
import Security
import Foundation
import X509
import SwiftASN1

extension Certificate {
    func asSecCertificate() throws -> SecCertificate {
        var serializer = DER.Serializer()
        try serializer.serialize(self)
        let der = Data(serializer.serializedBytes)
        guard let secCertificate = SecCertificateCreateWithData(nil, der as CFData) else {
            throw StringError("Could not parse certificate")
        }
        return secCertificate
    }
}
#endif
