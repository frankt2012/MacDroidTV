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
        XCTAssertEqual(numbers.exponentHex, "010001")
        XCTAssertEqual(numbers.modulusHex.count, 512)
    }
}
