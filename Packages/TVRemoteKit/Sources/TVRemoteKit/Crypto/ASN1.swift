import Foundation

/// Minimal ASN.1 DER helpers used to build the client certificate and to read
/// the RSA modulus/exponent out of a certificate.
enum DERCoding {
    enum Error: Swift.Error, LocalizedError {
        case invalid
        case unexpectedTag(UInt8)

        var errorDescription: String? {
            switch self {
            case .invalid:
                return "The certificate data was not valid DER."
            case .unexpectedTag(let tag):
                return "The certificate contained an unexpected ASN.1 tag (0x\(String(tag, radix: 16)))."
            }
        }
    }

    struct Element {
        let tag: UInt8
        let content: Data
        let nextIndex: Data.Index
    }

    // MARK: - Encoding

    static func length(_ count: Int) -> Data {
        if count < 0x80 {
            return Data([UInt8(count)])
        }

        var bytes: [UInt8] = []
        var value = count
        while value > 0 {
            bytes.insert(UInt8(value & 0xFF), at: 0)
            value >>= 8
        }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }

    static func tlv(_ tag: UInt8, _ content: Data) -> Data {
        var data = Data([tag])
        data.append(length(content.count))
        data.append(content)
        return data
    }

    static func sequence(_ items: [Data]) -> Data {
        sequence(items.reduce(into: Data()) { $0.append($1) })
    }

    static func sequence(_ content: Data) -> Data {
        tlv(0x30, content)
    }

    static func set(_ items: [Data]) -> Data {
        tlv(0x31, items.reduce(into: Data()) { $0.append($1) })
    }

    static func integer(_ value: Int) -> Data {
        var bytes: [UInt8] = []
        var remaining = value
        repeat {
            bytes.insert(UInt8(remaining & 0xFF), at: 0)
            remaining >>= 8
        } while remaining > 0
        return integer(Data(bytes))
    }

    static func integer(_ bytes: Data) -> Data {
        var bytes = stripLeadingZeros(bytes)
        if let first = bytes.first, first & 0x80 != 0 {
            bytes.insert(0, at: 0)
        }
        return tlv(0x02, bytes)
    }

    static func oid(_ bytes: [UInt8]) -> Data {
        tlv(0x06, Data(bytes))
    }

    static func null() -> Data {
        Data([0x05, 0x00])
    }

    static func utf8String(_ string: String) -> Data {
        tlv(0x0C, Data(string.utf8))
    }

    static func boolean(_ value: Bool) -> Data {
        tlv(0x01, Data([value ? 0xFF : 0x00]))
    }

    static func octetString(_ data: Data) -> Data {
        tlv(0x04, data)
    }

    static func bitString(_ data: Data) -> Data {
        tlv(0x03, Data([0x00]) + data)
    }

    static func explicit(_ tag: UInt8, _ content: Data) -> Data {
        tlv(0xA0 | tag, content)
    }

    static func utcTime(_ date: Date) -> Data {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        return tlv(0x17, Data(formatter.string(from: date).utf8))
    }

    static func stripLeadingZeros(_ data: Data) -> Data {
        var bytes = data
        while bytes.count > 1, bytes.first == 0 {
            bytes.removeFirst()
        }
        return bytes
    }

    // MARK: - Decoding

    static func readElement(_ data: Data, at index: Data.Index) throws -> Element {
        guard index < data.endIndex else { throw Error.invalid }
        let tag = data[index]
        var cursor = data.index(after: index)
        guard cursor < data.endIndex else { throw Error.invalid }

        let firstLength = data[cursor]
        cursor = data.index(after: cursor)

        let length: Int
        if firstLength & 0x80 == 0 {
            length = Int(firstLength)
        } else {
            let byteCount = Int(firstLength & 0x7F)
            guard byteCount > 0, byteCount <= 4 else { throw Error.invalid }
            var value = 0
            for _ in 0..<byteCount {
                guard cursor < data.endIndex else { throw Error.invalid }
                value = (value << 8) | Int(data[cursor])
                cursor = data.index(after: cursor)
            }
            length = value
        }

        guard data.distance(from: cursor, to: data.endIndex) >= length else {
            throw Error.invalid
        }
        let end = data.index(cursor, offsetBy: length)
        return Element(tag: tag, content: Data(data[cursor..<end]), nextIndex: end)
    }

    /// Reads `RSAPublicKey ::= SEQUENCE { modulus INTEGER, publicExponent INTEGER }`.
    static func rsaPublicNumbers(fromPKCS1 data: Data) throws -> (modulus: Data, exponent: Data) {
        let sequence = try readElement(data, at: data.startIndex)
        guard sequence.tag == 0x30 else { throw Error.unexpectedTag(sequence.tag) }

        let modulus = try readElement(sequence.content, at: sequence.content.startIndex)
        guard modulus.tag == 0x02 else { throw Error.unexpectedTag(modulus.tag) }

        let exponent = try readElement(sequence.content, at: modulus.nextIndex)
        guard exponent.tag == 0x02 else { throw Error.unexpectedTag(exponent.tag) }

        return (
            stripLeadingZeros(modulus.content),
            stripLeadingZeros(exponent.content)
        )
    }

}
