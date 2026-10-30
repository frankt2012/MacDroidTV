import Foundation

public struct RemoteDeviceInfo: Equatable, Sendable {
    public var model: String
    public var vendor: String
    public var appVersion: String

    public init(model: String = "", vendor: String = "", appVersion: String = "") {
        self.model = model
        self.vendor = vendor
        self.appVersion = appVersion
    }

    public var displayName: String {
        let parts = [vendor, model].filter { !$0.isEmpty }
        return parts.isEmpty ? "Google TV" : parts.joined(separator: " ")
    }
}

/// A decoded `RemoteMessage` from remotemessage.proto.
public enum RemoteMessage: Equatable, Sendable {
    case configure(code1: UInt64, device: RemoteDeviceInfo)
    case setActive(active: UInt64)
    case error
    case pingRequest(val1: Int32, val2: Int32)
    case pingResponse(val1: Int32)
    case keyInject(keyCode: UInt64, direction: UInt64)
    case appInfo(package: String)
    case imeBatchEdit(imeCounter: Int32, fieldCounter: Int32)
    case remoteStart(started: Bool)
    case volume(level: Int, max: Int, muted: Bool)
    case appLink(String)
    case unknown
}

public extension RemoteMessage {
    /// Feature bits understood by this client.
    static let featurePing: UInt64 = 1 << 0
    static let featureKey: UInt64 = 1 << 1
    static let featurePower: UInt64 = 1 << 5
    static let featureVolume: UInt64 = 1 << 6
    static let featureAppLink: UInt64 = 1 << 9

    /// 611: ping, key, power, volume and app links. IME is deliberately left
    /// out because enabling it makes some TVs show a "use your keyboard" card.
    static let requestedFeatures: UInt64 =
        featurePing | featureKey | featurePower | featureVolume | featureAppLink

    static func configureReply(features: UInt64) -> Data {
        var writer = ProtoWriter()
        writer.writeMessage(1) { configure in
            configure.writeVarint(1, features)
            configure.writeMessage(2) { device in
                device.writeVarint(3, 1)
                device.writeString(4, "1")
                device.writeString(5, "atvremote")
                device.writeString(6, "1.0.0")
            }
        }
        return writer.data
    }

    static func setActiveReply(features: UInt64) -> Data {
        var writer = ProtoWriter()
        writer.writeMessage(2) { setActive in
            setActive.writeVarint(1, features)
        }
        return writer.data
    }

    static func pingResponse(_ val1: Int32) -> Data {
        var writer = ProtoWriter()
        writer.writeMessage(9) { response in
            response.writeVarint(1, UInt64(UInt32(bitPattern: val1)))
        }
        return writer.data
    }

    static func keyInject(_ keyCode: UInt64) -> Data {
        var writer = ProtoWriter()
        writer.writeMessage(10) { key in
            key.writeVarint(1, keyCode)
            key.writeVarint(2, 3) // RemoteDirection.SHORT
        }
        return writer.data
    }

    static func appLink(_ link: String) -> Data {
        var writer = ProtoWriter()
        writer.writeMessage(90) { request in
            request.writeString(1, link)
        }
        return writer.data
    }

    static func decode(_ data: Data) throws -> RemoteMessage {
        let fields = try ProtoReader.parse(data)

        if let body = fields.bytes(1) {
            let nested = try ProtoReader.parse(body)
            let deviceFields = try ProtoReader.parse(nested.bytes(2) ?? Data())
            return .configure(
                code1: nested.varint(1) ?? 0,
                device: RemoteDeviceInfo(
                    model: deviceFields.string(1) ?? "",
                    vendor: deviceFields.string(2) ?? "",
                    appVersion: deviceFields.string(6) ?? ""
                )
            )
        }

        if let body = fields.bytes(2) {
            let nested = try ProtoReader.parse(body)
            return .setActive(active: nested.varint(1) ?? 0)
        }

        if fields.first(3) != nil {
            return .error
        }

        if let body = fields.bytes(8) {
            let nested = try ProtoReader.parse(body)
            return .pingRequest(
                val1: Int32(truncatingIfNeeded: nested.varint(1) ?? 0),
                val2: Int32(truncatingIfNeeded: nested.varint(2) ?? 0)
            )
        }

        if let body = fields.bytes(9) {
            let nested = try ProtoReader.parse(body)
            return .pingResponse(val1: Int32(truncatingIfNeeded: nested.varint(1) ?? 0))
        }

        if let body = fields.bytes(10) {
            let nested = try ProtoReader.parse(body)
            return .keyInject(
                keyCode: nested.varint(1) ?? 0,
                direction: nested.varint(2) ?? 0
            )
        }

        if let body = fields.bytes(20) {
            let nested = try ProtoReader.parse(body)
            let appInfo = try ProtoReader.parse(nested.bytes(1) ?? Data())
            return .appInfo(package: appInfo.string(12) ?? "")
        }

        if let body = fields.bytes(21) {
            let nested = try ProtoReader.parse(body)
            return .imeBatchEdit(
                imeCounter: Int32(truncatingIfNeeded: nested.varint(1) ?? 0),
                fieldCounter: Int32(truncatingIfNeeded: nested.varint(2) ?? 0)
            )
        }

        if let body = fields.bytes(40) {
            let nested = try ProtoReader.parse(body)
            return .remoteStart(started: (nested.varint(1) ?? 0) != 0)
        }

        if let body = fields.bytes(50) {
            let nested = try ProtoReader.parse(body)
            return .volume(
                level: Int(nested.varint(7) ?? 0),
                max: Int(nested.varint(6) ?? 0),
                muted: (nested.varint(8) ?? 0) != 0
            )
        }

        if let body = fields.bytes(90) {
            return .appLink(try ProtoReader.parse(body).string(1) ?? "")
        }

        return .unknown
    }
}
