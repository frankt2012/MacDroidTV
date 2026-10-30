import XCTest
@testable import TVRemoteKit

final class ProtoCodingTests: XCTestCase {
    func testVarintRoundTrip() throws {
        let values: [UInt64] = [0, 1, 127, 128, 300, 611, 16_384, UInt64.max]
        for value in values {
            let encoded = Data(ProtoWriter.varint(value))
            let (decoded, end) = try ProtoReader.readVarint(encoded, encoded.startIndex)
            XCTAssertEqual(decoded, value)
            XCTAssertEqual(end, encoded.endIndex)
        }
    }

    func testWriterUsesExpectedTags() {
        var writer = ProtoWriter()
        writer.writeVarint(1, 611)
        writer.writeString(2, "hi")
        XCTAssertEqual(Array(writer.data), [0x08, 0xE3, 0x04, 0x12, 0x02, 0x68, 0x69])
    }

    func testNestedMessageParsing() throws {
        var writer = ProtoWriter()
        writer.writeMessage(10) { nested in
            nested.writeVarint(1, 26)
            nested.writeVarint(2, 3)
        }

        let fields = try ProtoReader.parse(writer.data)
        let body = try XCTUnwrap(fields.bytes(10))
        let nested = try ProtoReader.parse(body)
        XCTAssertEqual(nested.varint(1), 26)
        XCTAssertEqual(nested.varint(2), 3)
    }

    func testTruncatedMessageThrows() {
        let data = Data([0x52, 0x04, 0x08])
        XCTAssertThrowsError(try ProtoReader.parse(data))
    }

    func testMalformedVarintThrows() {
        let data = Data(repeating: 0x80, count: 12)
        XCTAssertThrowsError(try ProtoReader.readVarint(data, data.startIndex))
    }

    func testUnknownWireTypeThrows() {
        let data = Data([0x0F])
        XCTAssertThrowsError(try ProtoReader.parse(data)) { error in
            XCTAssertEqual(error as? ProtoError, .unsupportedWireType(7))
        }
    }
}
