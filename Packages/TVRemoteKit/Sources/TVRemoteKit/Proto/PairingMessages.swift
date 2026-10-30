import Foundation

/// One accepted code encoding in the pairing handshake.
public struct PairingEncoding: Equatable, Sendable {
    /// `ENCODING_TYPE_HEXADECIMAL` is 3 in polo.proto.
    public var type: UInt64
    public var symbolLength: UInt64

    public init(type: UInt64 = 3, symbolLength: UInt64 = 6) {
        self.type = type
        self.symbolLength = symbolLength
    }
}

public struct PairingRequest: Equatable, Sendable {
    public var serviceName: String
    public var clientName: String

    public init(serviceName: String = "atvremote", clientName: String) {
        self.serviceName = serviceName
        self.clientName = clientName
    }
}

public struct PairingRequestAck: Equatable, Sendable {
    public var serverName: String?

    public init(serverName: String? = nil) {
        self.serverName = serverName
    }
}

public struct PairingOptions: Equatable, Sendable {
    public var inputEncodings: [PairingEncoding]
    public var preferredRole: UInt64?

    public init(inputEncodings: [PairingEncoding], preferredRole: UInt64? = nil) {
        self.inputEncodings = inputEncodings
        self.preferredRole = preferredRole
    }
}

public struct PairingConfiguration: Equatable, Sendable {
    public var encoding: PairingEncoding
    public var clientRole: UInt64

    public init(encoding: PairingEncoding, clientRole: UInt64) {
        self.encoding = encoding
        self.clientRole = clientRole
    }
}

/// `OuterMessage` from the Google TV pairing protocol (polo.proto).
public struct OuterMessage: Equatable, Sendable {
    public var protocolVersion: UInt64
    public var status: UInt64
    public var pairingRequest: PairingRequest?
    public var pairingRequestAck: PairingRequestAck?
    public var options: PairingOptions?
    public var configuration: PairingConfiguration?
    public var configurationAck: Bool
    public var secret: Data?
    public var secretAck: Data?

    public static let statusOK: UInt64 = 200

    public init(
        protocolVersion: UInt64 = 2,
        status: UInt64 = OuterMessage.statusOK,
        pairingRequest: PairingRequest? = nil,
        pairingRequestAck: PairingRequestAck? = nil,
        options: PairingOptions? = nil,
        configuration: PairingConfiguration? = nil,
        configurationAck: Bool = false,
        secret: Data? = nil,
        secretAck: Data? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.status = status
        self.pairingRequest = pairingRequest
        self.pairingRequestAck = pairingRequestAck
        self.options = options
        self.configuration = configuration
        self.configurationAck = configurationAck
        self.secret = secret
        self.secretAck = secretAck
    }

    public func encoded() -> Data {
        var writer = ProtoWriter()
        writer.writeVarint(1, protocolVersion)
        writer.writeVarint(2, status)

        if let pairingRequest {
            writer.writeMessage(10) { message in
                message.writeString(1, pairingRequest.serviceName)
                message.writeString(2, pairingRequest.clientName)
            }
        }

        if let pairingRequestAck {
            writer.writeMessage(11) { message in
                if let serverName = pairingRequestAck.serverName {
                    message.writeString(1, serverName)
                }
            }
        }

        if let options {
            writer.writeMessage(20) { message in
                for encoding in options.inputEncodings {
                    message.writeMessage(1) { nested in
                        nested.writeVarint(1, encoding.type)
                        nested.writeVarint(2, encoding.symbolLength)
                    }
                }
                if let preferredRole = options.preferredRole {
                    message.writeVarint(3, preferredRole)
                }
            }
        }

        if let configuration {
            writer.writeMessage(30) { message in
                message.writeMessage(1) { encoding in
                    encoding.writeVarint(1, configuration.encoding.type)
                    encoding.writeVarint(2, configuration.encoding.symbolLength)
                }
                message.writeVarint(2, configuration.clientRole)
            }
        }

        if configurationAck {
            writer.writeMessage(31) { _ in }
        }

        if let secret {
            writer.writeMessage(40) { message in
                message.writeBytes(1, secret)
            }
        }

        if let secretAck {
            writer.writeMessage(41) { message in
                message.writeBytes(1, secretAck)
            }
        }

        return writer.data
    }

    public static func decode(_ data: Data) throws -> OuterMessage {
        let fields = try ProtoReader.parse(data)

        var message = OuterMessage()
        message.protocolVersion = fields.varint(1) ?? 1
        message.status = fields.varint(2) ?? OuterMessage.statusOK

        if let body = fields.bytes(10) {
            let nested = try ProtoReader.parse(body)
            message.pairingRequest = PairingRequest(
                serviceName: nested.string(1) ?? "atvremote",
                clientName: nested.string(2) ?? ""
            )
        }

        if let body = fields.bytes(11) {
            let nested = try ProtoReader.parse(body)
            message.pairingRequestAck = PairingRequestAck(serverName: nested.string(1))
        }

        if let body = fields.bytes(20) {
            let nested = try ProtoReader.parse(body)
            let encodings = try nested.all(1).map { field -> PairingEncoding in
                let encodingFields = try ProtoReader.parse(field.bytesValue ?? Data())
                return PairingEncoding(
                    type: encodingFields.varint(1) ?? 0,
                    symbolLength: encodingFields.varint(2) ?? 0
                )
            }
            message.options = PairingOptions(
                inputEncodings: encodings,
                preferredRole: nested.varint(3)
            )
        }

        if let body = fields.bytes(30) {
            let nested = try ProtoReader.parse(body)
            let encodingFields = try ProtoReader.parse(nested.bytes(1) ?? Data())
            message.configuration = PairingConfiguration(
                encoding: PairingEncoding(
                    type: encodingFields.varint(1) ?? 0,
                    symbolLength: encodingFields.varint(2) ?? 0
                ),
                clientRole: nested.varint(2) ?? 0
            )
        }

        message.configurationAck = fields.first(31) != nil

        if let body = fields.bytes(40) {
            message.secret = try ProtoReader.parse(body).bytes(1)
        }

        if let body = fields.bytes(41) {
            message.secretAck = try ProtoReader.parse(body).bytes(1)
        }

        return message
    }
}
