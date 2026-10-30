import XCTest
@testable import TVRemoteKit

final class PairingMessagesTests: XCTestCase {
    func testPairingRequestRoundTrip() throws {
        let message = OuterMessage(pairingRequest: PairingRequest(clientName: "Mac Remote"))
        let decoded = try OuterMessage.decode(message.encoded())
        XCTAssertEqual(decoded.protocolVersion, 2)
        XCTAssertEqual(decoded.status, 200)
        XCTAssertEqual(decoded.pairingRequest, PairingRequest(clientName: "Mac Remote"))
    }

    func testOptionsRoundTrip() throws {
        let message = OuterMessage(
            options: PairingOptions(
                inputEncodings: [PairingEncoding(type: 3, symbolLength: 6)],
                preferredRole: 1
            )
        )
        let decoded = try OuterMessage.decode(message.encoded())
        XCTAssertEqual(decoded.options?.preferredRole, 1)
        XCTAssertEqual(decoded.options?.inputEncodings, [PairingEncoding(type: 3, symbolLength: 6)])
    }

    func testConfigurationRoundTrip() throws {
        let message = OuterMessage(
            configuration: PairingConfiguration(
                encoding: PairingEncoding(type: 3, symbolLength: 6),
                clientRole: 1
            )
        )
        let decoded = try OuterMessage.decode(message.encoded())
        XCTAssertEqual(decoded.configuration?.clientRole, 1)
        XCTAssertEqual(decoded.configuration?.encoding.symbolLength, 6)
    }

    func testConfigurationAck() throws {
        let message = OuterMessage(configurationAck: true)
        let decoded = try OuterMessage.decode(message.encoded())
        XCTAssertTrue(decoded.configurationAck)
    }

    func testSecretRoundTrip() throws {
        let secret = Data(repeating: 0xAB, count: 32)
        let message = OuterMessage(secret: secret)
        let decoded = try OuterMessage.decode(message.encoded())
        XCTAssertEqual(decoded.secret, secret)
    }

    func testSecretAckRoundTrip() throws {
        let message = OuterMessage(secretAck: Data())
        let decoded = try OuterMessage.decode(message.encoded())
        XCTAssertNotNil(decoded.secretAck)
    }

    func testNonOKStatusSurvivesDecoding() throws {
        let message = OuterMessage(status: 400, pairingRequest: PairingRequest(clientName: "x"))
        let decoded = try OuterMessage.decode(message.encoded())
        XCTAssertEqual(decoded.status, 400)
    }
}
