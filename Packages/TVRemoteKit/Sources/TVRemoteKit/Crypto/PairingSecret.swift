import CryptoKit
import Foundation
import Security

public enum PairingError: Error, Equatable, LocalizedError {
    case invalidCode
    case codeMismatch
    case certificateReadFailed

    public var errorDescription: String? {
        switch self {
        case .invalidCode:
            return "Enter the 6-character code shown on your TV."
        case .codeMismatch:
            return "That code didn't match. Check the TV and try again."
        case .certificateReadFailed:
            return "Could not read the TV's certificate."
        }
    }
}

/// Implements the confirmation step of the Google TV pairing protocol.
///
/// The secret is SHA-256 over the client RSA modulus/exponent, the server
/// RSA modulus/exponent, and the last four characters of the on-screen code.
/// The first byte of the digest is the first two characters of the code, which
/// is what makes a mistyped code detectable before it is sent to the TV.
public enum PairingSecret {
    public static func compute(clientCertificateDER: Data, serverCertificateDER: Data, code: String) throws -> Data {
        let normalized = code.uppercased()
        guard normalized.count == 6,
              normalized.allSatisfy({ $0.isHexDigit }),
              let prefix = UInt8(normalized.prefix(2), radix: 16) else {
            throw PairingError.invalidCode
        }

        let client = try rsaNumbers(certificateDER: clientCertificateDER)
        let server = try rsaNumbers(certificateDER: serverCertificateDER)

        var hasher = SHA256()
        hasher.update(data: try hexBytes(client.modulusHex))
        hasher.update(data: try hexBytes("0" + client.exponentHex))
        hasher.update(data: try hexBytes(server.modulusHex))
        hasher.update(data: try hexBytes("0" + server.exponentHex))
        hasher.update(data: try hexBytes(String(normalized.dropFirst(2))))

        let digest = Data(hasher.finalize())
        guard digest.first == prefix else {
            throw PairingError.codeMismatch
        }
        return digest
    }

    static func rsaNumbers(certificateDER: Data) throws -> (modulusHex: String, exponentHex: String) {
        guard let certificate = SecCertificateCreateWithData(nil, certificateDER as CFData),
              let publicKey = SecCertificateCopyKey(certificate) else {
            throw PairingError.certificateReadFailed
        }

        var error: Unmanaged<CFError>?
        guard let pkcs1 = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw PairingError.certificateReadFailed
        }

        let numbers = try DERCoding.rsaPublicNumbers(fromPKCS1: pkcs1)
        return (
            modulusHex: DERCoding.hexString(numbers.modulus),
            exponentHex: DERCoding.hexString(numbers.exponent)
        )
    }

    static func hexBytes(_ hex: String) throws -> Data {
        var hex = hex
        if hex.count % 2 != 0 {
            hex = "0" + hex
        }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else {
                throw PairingError.certificateReadFailed
            }
            bytes.append(byte)
            index = next
        }
        return Data(bytes)
    }
}
