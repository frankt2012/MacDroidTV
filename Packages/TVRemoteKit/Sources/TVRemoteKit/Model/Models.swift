import Foundation

/// A TV that has completed the pairing handshake.
public struct PairedDevice: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var host: String
    public var port: UInt16
    /// The certificate the TV presented while pairing. Kept for diagnostics and
    /// for a future pinning check; the protocol itself does not require it.
    public var serverCertificate: Data?
    public var lastSeen: Date?
    /// Network adapter address used for a Wake-on-LAN magic packet. Only some
    /// TVs keep their network alive in standby, so this is optional.
    public var wakeMAC: String?

    public init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: UInt16 = 6466,
        serverCertificate: Data? = nil,
        lastSeen: Date? = nil,
        wakeMAC: String? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.serverCertificate = serverCertificate
        self.lastSeen = lastSeen
        self.wakeMAC = wakeMAC
    }
}

/// The client certificate and private key created once per installation.
/// The TV remembers this certificate after pairing, so it must stay stable.
public struct StoredIdentity: Codable, Equatable, Sendable {
    public var certificateDER: Data
    public var privateKeyDER: Data
    public var displayName: String

    public init(certificateDER: Data, privateKeyDER: Data, displayName: String) {
        self.certificateDER = certificateDER
        self.privateKeyDER = privateKeyDER
        self.displayName = displayName
    }
}

public struct VolumeInfo: Equatable, Sendable {
    public var level: Int
    public var max: Int
    public var muted: Bool

    public init(level: Int, max: Int, muted: Bool) {
        self.level = level
        self.max = max
        self.muted = muted
    }
}

public struct CachedTVState: Codable, Equatable, Sendable {
    public var isOn: Bool
    public var volume: Int?
    public var volumeMax: Int?
    public var muted: Bool
    public var updatedAt: Date?
    /// True when the TV does not report a volume scale and the value is a
    /// local estimate driven by key presses. Optional so state files written by
    /// older builds still decode.
    public var volumeEstimated: Bool?
    /// How much one volume key press changes the estimate, when the user has
    /// calibrated it. `nil` means use the default derived from the scale.
    public var volumeStep: Int?

    public init(
        isOn: Bool = false,
        volume: Int? = nil,
        volumeMax: Int? = nil,
        muted: Bool = false,
        updatedAt: Date? = nil,
        volumeEstimated: Bool? = nil,
        volumeStep: Int? = nil
    ) {
        self.isOn = isOn
        self.volume = volume
        self.volumeMax = volumeMax
        self.muted = muted
        self.updatedAt = updatedAt
        self.volumeEstimated = volumeEstimated
        self.volumeStep = volumeStep
    }
}

/// Everything the app and the widget share through the App Group container.
public struct RemoteState: Codable, Equatable, Sendable {
    public var identity: StoredIdentity?
    public var devices: [PairedDevice]
    public var activeDeviceID: UUID?
    public var cache: CachedTVState
    public var clientName: String
    /// IDs of the quick app buttons to show. Nil means the default set.
    public var quickAppIDs: [String]?
    /// User-defined app shortcuts.
    public var customApps: [QuickApp]?
    /// Opacity of the widget background (0.1...1.0). Nil means 1.0.
    public var widgetOpacity: Double?

    public init(
        identity: StoredIdentity? = nil,
        devices: [PairedDevice] = [],
        activeDeviceID: UUID? = nil,
        cache: CachedTVState = CachedTVState(),
        clientName: String = "Mac Remote",
        quickAppIDs: [String]? = nil,
        customApps: [QuickApp]? = nil,
        widgetOpacity: Double? = nil
    ) {
        self.identity = identity
        self.devices = devices
        self.activeDeviceID = activeDeviceID
        self.cache = cache
        self.clientName = clientName
        self.quickAppIDs = quickAppIDs
        self.customApps = customApps
        self.widgetOpacity = widgetOpacity
    }

    /// Every app the settings UI can offer.
    public var allQuickApps: [QuickApp] {
        QuickApp.common + (customApps ?? [])
    }

    /// The apps selected for the widget and panel, in user order.
    public var selectedQuickApps: [QuickApp] {
        guard let quickAppIDs else { return QuickApp.featured }
        let all = allQuickApps
        return quickAppIDs.compactMap { id in all.first { $0.id == id } }
    }

    public var activeDevice: PairedDevice? {
        if let activeDeviceID, let device = devices.first(where: { $0.id == activeDeviceID }) {
            return device
        }
        return devices.first
    }
}

/// A TV found over Bonjour but not paired yet.
public struct DiscoveredDevice: Identifiable, Equatable, Sendable {
    public let serviceName: String
    public let name: String
    public var host: String?
    /// Raw Bonjour TXT record. Android TV advertises `bt` (Bluetooth address)
    /// and `rs`, which are handy when diagnosing wake support.
    public let txt: [String: String]

    public var id: String { serviceName }

    public init(
        serviceName: String,
        name: String,
        host: String? = nil,
        txt: [String: String] = [:]
    ) {
        self.serviceName = serviceName
        self.name = name
        self.host = host
        self.txt = txt
    }
}

/// What a widget needs to render, without exposing the pairing secrets.
public struct WidgetSnapshot: Equatable, Sendable {
    public var isPaired: Bool
    public var deviceName: String
    public var isOn: Bool
    public var volume: Int?
    public var volumeMax: Int?
    public var muted: Bool
    public var updatedAt: Date?
    public var volumeEstimated: Bool
    public var quickApps: [QuickApp]
    public var widgetOpacity: Double

    public init(
        isPaired: Bool,
        deviceName: String,
        isOn: Bool,
        volume: Int?,
        volumeMax: Int?,
        muted: Bool,
        updatedAt: Date?,
        volumeEstimated: Bool = false,
        quickApps: [QuickApp] = QuickApp.featured,
        widgetOpacity: Double = 1.0
    ) {
        self.isPaired = isPaired
        self.deviceName = deviceName
        self.isOn = isOn
        self.volume = volume
        self.volumeMax = volumeMax
        self.muted = muted
        self.updatedAt = updatedAt
        self.volumeEstimated = volumeEstimated
        self.quickApps = quickApps
        self.widgetOpacity = widgetOpacity
    }

    public static func load(from store: SharedStore = .shared) -> WidgetSnapshot {
        let state = store.load()
        let device = state.activeDevice
        return WidgetSnapshot(
            isPaired: device != nil && state.identity != nil,
            deviceName: device?.name ?? "Google TV",
            isOn: state.cache.isOn,
            volume: state.cache.volume,
            volumeMax: state.cache.volumeMax,
            muted: state.cache.muted,
            updatedAt: state.cache.updatedAt,
            volumeEstimated: state.cache.volumeEstimated ?? false,
            quickApps: state.selectedQuickApps,
            widgetOpacity: state.widgetOpacity ?? 1.0
        )
    }
}
