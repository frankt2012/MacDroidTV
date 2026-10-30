import Security
import XCTest
@testable import TVRemoteKit

final class CertificateTests: XCTestCase {
    func testGeneratedCertificateIsValidX509() throws {
        let generated = try CertificateFactory.generate(commonName: "TVRemoteKit Test")
        let certificate = try XCTUnwrap(SecCertificateCreateWithData(nil, generated.certificateDER as CFData))
        XCTAssertEqual(SecCertificateCopySubjectSummary(certificate) as String?, "TVRemoteKit Test")

        let key = try XCTUnwrap(SecCertificateCopyKey(certificate))
        XCTAssertEqual(SecKeyGetBlockSize(key) * 8, 2048)
    }

    func testGeneratedIdentityCanBeRecreated() throws {
        let generated = try CertificateFactory.generate(commonName: "TVRemoteKit Test")
        let stored = StoredIdentity(
            certificateDER: generated.certificateDER,
            privateKeyDER: generated.privateKeyDER,
            displayName: "TVRemoteKit Test"
        )

        let identity = try stored.makeSecIdentity()
        var certificateRef: SecCertificate?
        SecIdentityCopyCertificate(identity, &certificateRef)
        let certificate = try XCTUnwrap(certificateRef)
        XCTAssertEqual(
            SecCertificateCopyData(certificate) as Data,
            generated.certificateDER
        )
    }

    func testCertificateHasRSAKey() throws {
        let generated = try CertificateFactory.generate(commonName: "TVRemoteKit Test")
        let numbers = try PairingSecret.rsaNumbers(certificateDER: generated.certificateDER)
        // 65537 is the standard RSA exponent and must hash as 01 00 01, not
        // 00 01 00 01 (the old double-padded bug).
        XCTAssertEqual(numbers.exponent, Data([0x01, 0x00, 0x01]))
        XCTAssertEqual(numbers.modulus.count, 256)
    }
}
