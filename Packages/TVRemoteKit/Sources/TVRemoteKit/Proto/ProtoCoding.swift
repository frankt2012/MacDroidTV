import Foundation

/// Errors raised while reading a protobuf message.
public enum ProtoError: Error, Equatable, LocalizedError {
    case truncated
    case malformedVarint
    case unsupportedWireType(Int)
    case invalidField

    public var errorDescription: String? {
        switch self {
        case .truncated:
            return "The message ended unexpectedly."
        case .malformedVarint:
            return "The message contained a malformed number."
        case .unsupportedWireType(let type):
            return "The message used an unsupported field type (\(type))."
        case .invalidField:
            return "The message contained an invalid field."
        }
    }
}

/// A very small protobuf writer. The Google TV protocol only needs varints,
/// strings, bytes and nested messages, so pulling in a full protobuf runtime
/// (and a code generator) would be more machinery than the protocol warrants.
public struct ProtoWriter {
    public private(set) var data = Data()

    public init() {}

    public mutating func writeVarint(_ field: Int, _ value: UInt64) {
        data.append(contentsOf: Self.tag(field, 0))
        data.append(contentsOf: Self.varint(value))
    }

    public mutating func writeBool(_ field: Int, _ value: Bool) {
        writeVarint(field, value ? 1 : 0)
    }

    public mutating func writeString(_ field: Int, _ value: String) {
        writeBytes(field, Data(value.utf8))
    }

    public mutating func writeBytes(_ field: Int, _ value: Data) {
        data.append(contentsOf: Self.tag(field, 2))
        data.append(contentsOf: Self.varint(UInt64(value.count)))
        data.append(value)
    }

    public mutating func writeMessage(_ field: Int, _ body: (inout ProtoWriter) -> Void) {
        var nested = ProtoWriter()
        body(&nested)
        writeBytes(field, nested.data)
    }

    public static func varint(_ value: UInt64) -> [UInt8] {
        var value = value
        var output: [UInt8] = []
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 {
                byte |= 0x80
            }
            output.append(byte)
        } while value != 0
        return output
    }

    public static func tag(_ field: Int, _ wireType: Int) -> [UInt8] {
        varint(UInt64((field << 3) | wireType))
    }
}

/// One decoded protobuf field. Unknown fields are kept so messages can be
/// inspected without having to model every field in the schema.
public struct ProtoField: Equatable {
    public let number: Int
    public let wireType: Int
    public let varintValue: UInt64?
    public let bytesValue: Data?

    public init(number: Int, wireType: Int, varintValue: UInt64? = nil, bytesValue: Data? = nil) {
        self.number = number
        self.wireType = wireType
        self.varintValue = varintValue
        self.bytesValue = bytesValue
    }
}

public enum ProtoReader {
    public static func parse(_ data: Data) throws -> [ProtoField] {
        var fields: [ProtoField] = []
        var index = data.startIndex

        while index < data.endIndex {
            let (key, afterKey) = try readVarint(data, index)
            index = afterKey

            let number = Int(key >> 3)
            let wireType = Int(key & 0x07)
            guard number > 0 else { throw ProtoError.invalidField }

            switch wireType {
            case 0:
                let (value, next) = try readVarint(data, index)
                index = next
                fields.append(ProtoField(number: number, wireType: 0, varintValue: value))

            case 1:
                guard data.distance(from: index, to: data.endIndex) >= 8 else {
                    throw ProtoError.truncated
                }
                index = data.index(index, offsetBy: 8)
                fields.append(ProtoField(number: number, wireType: 1))

            case 2:
                let (length, next) = try readVarint(data, index)
                index = next
                guard let length = Int(exactly: length),
                      data.distance(from: index, to: data.endIndex) >= length else {
                    throw ProtoError.truncated
                }
                let end = data.index(index, offsetBy: length)
                fields.append(ProtoField(number: number, wireType: 2, bytesValue: Data(data[index..<end])))
                index = end

            case 5:
                guard data.distance(from: index, to: data.endIndex) >= 4 else {
                    throw ProtoError.truncated
                }
                index = data.index(index, offsetBy: 4)
                fields.append(ProtoField(number: number, wireType: 5))

            default:
                throw ProtoError.unsupportedWireType(wireType)
            }
        }

        return fields
    }

    public static func readVarint(_ data: Data, _ start: Data.Index) throws -> (UInt64, Data.Index) {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        var index = start

        while index < data.endIndex {
            let byte = data[index]
            value |= UInt64(byte & 0x7F) << shift
            index = data.index(after: index)

            if byte & 0x80 == 0 {
                return (value, index)
            }

            shift += 7
            if shift >= 64 {
                throw ProtoError.malformedVarint
            }
        }

        throw ProtoError.truncated
    }
}

public extension Array where Element == ProtoField {
    func first(_ number: Int) -> ProtoField? {
        first { $0.number == number }
    }

    func all(_ number: Int) -> [ProtoField] {
        filter { $0.number == number }
    }

    func varint(_ number: Int) -> UInt64? {
        first(number)?.varintValue
    }

    func bytes(_ number: Int) -> Data? {
        first(number)?.bytesValue
    }

    func string(_ number: Int) -> String? {
        guard let bytes = bytes(number) else { return nil }
        return String(data: bytes, encoding: .utf8)
    }
}
