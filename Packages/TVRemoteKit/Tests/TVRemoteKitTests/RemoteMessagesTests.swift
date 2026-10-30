import XCTest
@testable import TVRemoteKit

final class RemoteMessagesTests: XCTestCase {
    func testKeyInjectBytesMatchProtocol() {
        // field 10 (0x52), length 4, key_code 26 (0x08 0x1A),
        // direction SHORT=3 (0x10 0x03)
        let data = RemoteMessage.keyInject(RemoteKey.power.keyCode)
        XCTAssertEqual(Array(data), [0x52, 0x04, 0x08, 0x1A, 0x10, 0x03])
    }

    func testKeyInjectRoundTrip() throws {
        let data = RemoteMessage.keyInject(RemoteKey.select.keyCode)
        XCTAssertEqual(
            try RemoteMessage.decode(data),
            .keyInject(keyCode: 23, direction: 3)
        )
    }

    func testConfigureDecode() throws {
        var writer = ProtoWriter()
        writer.writeMessage(1) { configure in
            configure.writeVarint(1, 611)
            configure.writeMessage(2) { device in
                device.writeString(1, "Chromecast")
                device.writeString(2, "Google")
                device.writeString(6, "1.2.3")
            }
        }

        XCTAssertEqual(
            try RemoteMessage.decode(writer.data),
            .configure(
                code1: 611,
                device: RemoteDeviceInfo(model: "Chromecast", vendor: "Google", appVersion: "1.2.3")
            )
        )
    }

    func testSetActiveDecode() throws {
        var writer = ProtoWriter()
        writer.writeMessage(2) { setActive in
            setActive.writeVarint(1, 611)
        }
        XCTAssertEqual(try RemoteMessage.decode(writer.data), .setActive(active: 611))
    }

    func testRemoteStartDecode() throws {
        var writer = ProtoWriter()
        writer.writeMessage(40) { start in
            start.writeVarint(1, 1)
        }
        XCTAssertEqual(try RemoteMessage.decode(writer.data), .remoteStart(started: true))
    }

    func testVolumeDecode() throws {
        var writer = ProtoWriter()
        writer.writeMessage(50) { volume in
            volume.writeVarint(6, 100)
            volume.writeVarint(7, 42)
            volume.writeVarint(8, 1)
        }
        XCTAssertEqual(try RemoteMessage.decode(writer.data), .volume(level: 42, max: 100, muted: true))
    }

    func testPingRequestAndResponse() throws {
        var request = ProtoWriter()
        request.writeMessage(8) { ping in
            ping.writeVarint(1, 7)
            ping.writeVarint(2, 0)
        }
        XCTAssertEqual(try RemoteMessage.decode(request.data), .pingRequest(val1: 7, val2: 0))

        let response = RemoteMessage.pingResponse(7)
        XCTAssertEqual(try RemoteMessage.decode(response), .pingResponse(val1: 7))
    }

    func testConfigureReplyContainsFeatureMask() throws {
        let data = RemoteMessage.configureReply(features: 611)
        guard case .configure(let features, let device) = try RemoteMessage.decode(data) else {
            return XCTFail("Expected a configure message")
        }
        XCTAssertEqual(features, 611)
        XCTAssertEqual(device.appVersion, "1.0.0")
    }

    func testRequestedFeaturesExcludeIME() {
        XCTAssertEqual(RemoteMessage.requestedFeatures, 611)
        XCTAssertEqual(RemoteMessage.requestedFeatures & (1 << 10), 0)
    }

    func testUnknownMessageDecodesAsUnknown() throws {
        var writer = ProtoWriter()
        writer.writeMessage(99) { _ in }
        XCTAssertEqual(try RemoteMessage.decode(writer.data), .unknown)
    }
}
