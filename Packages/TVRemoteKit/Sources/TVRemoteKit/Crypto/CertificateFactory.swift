import Foundation
import Security

/// Creates the self-signed RSA identity the TV pairs with.
///
/// The Android TV pairing protocol derives its confirmation secret from the
/// RSA modulus and exponent of the client certificate, so the key must be RSA
/// (not EC). The certificate is generated once and then reused forever: the TV
/// remembers it, and a new certificate would require pairing again.
public enum CertificateFactory {
    public struct GeneratedIdentity {
        public let certificateDER: Data
        public let privateKeyDER: Data
    }

    public enum Error: Swift.Error, LocalizedError {
        case keyGenerationFailed(String)
        case certificateCreationFailed
        case identityCreationFailed
        case signatureFailed(String)

        public var errorDescription: String? {
            switch self {
            case .keyGenerationFailed(let message):
                return "Could not create a pairing key: \(message)"
            case .certificateCreationFailed:
                return "Could not create the pairing certificate."
            case .identityCreationFailed:
                return "Could not combine the pairing certificate and key."
            case .signatureFailed(let message):
                return "Could not sign the pairing certificate: \(message)"
            }
        }
    }

    // OIDs
    private static let oidSHA256WithRSA: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B]
    private static let oidRSAEncryption: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]
    private static let oidCommonName: [UInt8] = [0x55, 0x04, 0x03]
    private static let oidBasicConstraints: [UInt8] = [0x55, 0x1D, 0x13]
    private static let oidKeyUsage: [UInt8] = [0x55, 0x1D, 0x0F]
    private static let oidExtendedKeyUsage: [UInt8] = [0x55, 0x1D, 0x25]
    private static let oidClientAuth: [UInt8] = [0x2B, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x02]

    public static func generate(commonName: String) throws -> GeneratedIdentity {
        var error: Unmanaged<CFError>?

        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits: 2048,
            kSecAttrIsPermanent: false
        ]

        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw Error.keyGenerationFailed(errorMessage(error))
        }

        guard let publicKey = SecKeyCopyPublicKey(privateKey),
              let publicKeyDER = SecKeyCopyExternalRepresentation(publicKey, &error) as Data?,
              let privateKeyDER = SecKeyCopyExternalRepresentation(privateKey, &error) as Data? else {
            throw Error.keyGenerationFailed(errorMessage(error))
        }

        let signatureAlgorithm = DERCoding.sequence([
            DERCoding.oid(oidSHA256WithRSA),
            DERCoding.null()
        ])

        let name = DERCoding.sequence([
            DERCoding.set([
                DERCoding.sequence([
                    DERCoding.oid(oidCommonName),
                    DERCoding.utf8String(commonName)
                ])
            ])
        ])

        let now = Date()
        let validity = DERCoding.sequence([
            DERCoding.utcTime(now.addingTimeInterval(-60 * 60 * 24)),
            DERCoding.utcTime(now.addingTimeInterval(60 * 60 * 24 * 365 * 10))
        ])

        let subjectPublicKeyInfo = DERCoding.sequence([
            DERCoding.sequence([
                DERCoding.oid(oidRSAEncryption),
                DERCoding.null()
            ]),
            DERCoding.bitString(publicKeyDER)
        ])

        let extensions = DERCoding.explicit(3, DERCoding.sequence([
            extensionValue(oid: oidBasicConstraints, critical: true, value: DERCoding.sequence(Data())),
            // digitalSignature (bit 0) + keyEncipherment (bit 2)
            extensionValue(oid: oidKeyUsage, critical: true, value: DERCoding.bitString(Data([0xA0]))),
            extensionValue(
                oid: oidExtendedKeyUsage,
                critical: false,
                value: DERCoding.sequence([DERCoding.oid(oidClientAuth)])
            )
        ]))

        var serial = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        serial[0] &= 0x7F
        if serial.allSatisfy({ $0 == 0 }) {
            serial[15] = 1
        }

        let tbsCertificate = DERCoding.sequence([
            DERCoding.explicit(0, DERCoding.integer(2)), // v3
            DERCoding.integer(serial),
            signatureAlgorithm,
            name,
            validity,
            name,
            subjectPublicKeyInfo,
            extensions
        ])

        guard let signature = SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            tbsCertificate as CFData,
            &error
        ) as Data? else {
            throw Error.signatureFailed(errorMessage(error))
        }

        let certificateDER = DERCoding.sequence([
            tbsCertificate,
            signatureAlgorithm,
            DERCoding.bitString(signature)
        ])

        return GeneratedIdentity(certificateDER: certificateDER, privateKeyDER: privateKeyDER)
    }

    private static func extensionValue(oid: [UInt8], critical: Bool, value: Data) -> Data {
        var items: [Data] = [DERCoding.oid(oid)]
        if critical {
            items.append(DERCoding.boolean(true))
        }
        items.append(DERCoding.octetString(value))
        return DERCoding.sequence(items)
    }

    private static func errorMessage(_ error: Unmanaged<CFError>?) -> String {
        guard let error else { return "unknown error" }
        return (error.takeRetainedValue() as Swift.Error).localizedDescription
    }
}

public extension StoredIdentity {
    /// Rebuilds a `SecIdentity` suitable for the TLS client certificate.
    func makeSecIdentity() throws -> SecIdentity {
        var error: Unmanaged<CFError>?
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate
        ]

        guard let privateKey = SecKeyCreateWithData(privateKeyDER as CFData, attributes as CFDictionary, &error) else {
            let message = error.map { ($0.takeRetainedValue() as Swift.Error).localizedDescription } ?? "unknown error"
            throw CertificateFactory.Error.keyGenerationFailed(message)
        }

        guard let certificate = SecCertificateCreateWithData(nil, certificateDER as CFData) else {
            throw CertificateFactory.Error.certificateCreationFailed
        }

        guard let identity = SecIdentityCreate(nil, certificate, privateKey) else {
            throw CertificateFactory.Error.identityCreationFailed
        }

        return identity
    }
}
