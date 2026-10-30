import CryptoKit
import Foundation
import Security
import XCTest
@testable import TVRemoteKit

final class PairingSecretTests: XCTestCase {
    func testSecretMatchesIndependentComputation() throws {
        let generated = try CertificateFactory.generate(commonName: "Pairing Secret Test")
        let numbers = try Self.rsaNumbers(certificateDER: generated.certificateDER)

        // The digest does not depend on the first two characters of the code,
        // so compute it for a fixed suffix and use the digest's first byte as
        // the code prefix, exactly as a TV would.
        let suffix = "A1B2"
        let expected = try Self.digest(numbers: numbers, suffix: suffix)
        let code = String(format: "%02X", expected[0]) + suffix

        let actual = try PairingSecret.compute(
            clientCertificateDER: generated.certificateDER,
            serverCertificateDER: generated.certificateDER,
            code: code
        )
        XCTAssertEqual(actual, expected)
    }

    func testCodePrefixMismatchIsRejected() throws {
        let generated = try CertificateFactory.generate(commonName: "Pairing Secret Test")
        let numbers = try Self.rsaNumbers(certificateDER: generated.certificateDER)

        let correctSuffix = "A1B2"
        let correct = try Self.digest(numbers: numbers, suffix: correctSuffix)

        // Find a suffix whose digest has a different first byte so the test is
        // deterministic rather than failing 1 time in 256.
        var wrongCode: String?
        for value in 0..<4096 {
            let suffix = String(format: "%04X", value)
            let candidate = try Self.digest(numbers: numbers, suffix: suffix)
            if candidate[0] != correct[0] {
                wrongCode = String(format: "%02X", correct[0]) + suffix
                break
            }
        }

        let code = try XCTUnwrap(wrongCode)
        XCTAssertThrowsError(
            try PairingSecret.compute(
                clientCertificateDER: generated.certificateDER,
                serverCertificateDER: generated.certificateDER,
                code: code
            )
        ) { error in
            XCTAssertEqual(error as? PairingError, .codeMismatch)
        }
    }

    func testInvalidCodesAreRejected() throws {
        let generated = try CertificateFactory.generate(commonName: "Pairing Secret Test")

        for code in ["", "12345", "1234567", "GGGGGG", "12 456"] {
            XCTAssertThrowsError(
                try PairingSecret.compute(
                    clientCertificateDER: generated.certificateDER,
                    serverCertificateDER: generated.certificateDER,
                    code: code
                )
            ) { error in
                XCTAssertEqual(error as? PairingError, .invalidCode)
            }
        }
    }

    func testLowercaseCodeIsAccepted() throws {
        let generated = try CertificateFactory.generate(commonName: "Pairing Secret Test")
        let numbers = try Self.rsaNumbers(certificateDER: generated.certificateDER)

        let suffix = "beef"
        let expected = try Self.digest(numbers: numbers, suffix: "BEEF")
        let code = String(format: "%02x", expected[0]) + suffix

        XCTAssertEqual(
            try PairingSecret.compute(
                clientCertificateDER: generated.certificateDER,
                serverCertificateDER: generated.certificateDER,
                code: code
            ),
            expected
        )
    }

    // MARK: - Independent helpers

    /// Parses `RSAPublicKey ::= SEQUENCE { modulus INTEGER, publicExponent INTEGER }`
    /// without using the production DER parser.
    private static func rsaNumbers(certificateDER: Data) throws -> (modulus: Data, exponent: Data) {
        let certificate = try XCTUnwrap(SecCertificateCreateWithData(nil, certificateDER as CFData))
        let key = try XCTUnwrap(SecCertificateCopyKey(certificate))
        var error: Unmanaged<CFError>?
        let pkcs1 = try XCTUnwrap(SecKeyCopyExternalRepresentation(key, &error) as Data?)

        var cursor = pkcs1.startIndex
        let sequence = try readTLV(pkcs1, &cursor)
        XCTAssertEqual(sequence.tag, 0x30)
        var inner = sequence.content.startIndex
        let modulus = try readTLV(sequence.content, &inner)
        let exponent = try readTLV(sequence.content, &inner)
        XCTAssertEqual(modulus.tag, 0x02)
        XCTAssertEqual(exponent.tag, 0x02)
        return (stripZeros(modulus.content), stripZeros(exponent.content))
    }

    private static func digest(
        numbers: (modulus: Data, exponent: Data),
        suffix: String
    ) throws -> Data {
        var hasher = SHA256()
        // The protocol hashes the minimal big-endian RSA numbers. Keeping this
        // independent of the production hex conversion is what catches the
        // "double-padded exponent" regression.
        hasher.update(data: numbers.modulus)
        hasher.update(data: numbers.exponent)
        hasher.update(data: numbers.modulus)
        hasher.update(data: numbers.exponent)
        hasher.update(data: hexBytes(suffix))
        return Data(hasher.finalize())
    }

    private static func hexBytes(_ hex: String) -> Data {
        var hex = hex
        if hex.count % 2 != 0 { hex = "0" + hex }
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        return Data(bytes)
    }

    private static func stripZeros(_ data: Data) -> Data {
        var data = data
        while data.count > 1, data.first == 0 {
            data.removeFirst()
        }
        return data
    }

    private static func readTLV(_ data: Data, _ cursor: inout Data.Index) throws -> (tag: UInt8, content: Data) {
        let tag = data[cursor]
        cursor = data.index(after: cursor)
        let first = data[cursor]
        cursor = data.index(after: cursor)

        let length: Int
        if first & 0x80 == 0 {
            length = Int(first)
        } else {
            let count = Int(first & 0x7F)
            var value = 0
            for _ in 0..<count {
                value = (value << 8) | Int(data[cursor])
                cursor = data.index(after: cursor)
            }
            length = value
        }

        let end = data.index(cursor, offsetBy: length)
        let content = Data(data[cursor..<end])
        cursor = end
        return (tag, content)
    }
}
