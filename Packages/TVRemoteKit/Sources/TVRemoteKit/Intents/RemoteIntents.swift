import AppIntents
import Foundation
import WidgetKit

/// A short-lived connection used by widget buttons. Widgets run in their own
/// process, so they cannot reuse the menu bar app's connection. The connection
/// is cached for a few seconds to keep repeated taps snappy.
public actor WidgetRemote {
    public static let shared = WidgetRemote()

    private let store = SharedStore.shared
    private var connection: TVConnection?
    private var connectionDeviceID: UUID?
    private var connectionOpened: Date?

    public func send(_ key: RemoteKey) async throws {
        let state = store.load()
        guard let device = state.activeDevice, let identity = state.identity else {
            throw TVConnectionError.notPaired
        }

        let wasOff = !state.cache.isOn
        var sentWakePacket = false
        if key == .power, wasOff, let mac = device.wakeMAC, !mac.isEmpty {
            sentWakePacket = WakeOnLAN.send(mac: mac) > 0
        }

        // The TV's network stack needs a moment to come back after the packet.
        if sentWakePacket {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }

        var connection = try? await openConnection(
            for: device,
            identity: identity,
            timeout: sentWakePacket ? 3 : 10
        )
        if connection == nil, sentWakePacket {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            connection = try? await openConnection(
                for: device,
                identity: identity,
                timeout: 3
            )
        }
        guard let connection else { throw TVConnectionError.closed }

        if key == .power, wasOff,
           await connection.waitUntilOn(timeout: sentWakePacket ? 6 : 0) {
            // The TV woke from the magic packet (or was already on). A power
            // key now would toggle it straight back into standby.
        } else {
            try await connection.sendKey(key)
        }

        if key == .volumeUp || key == .volumeDown || key == .mute {
            // The TV reports the new level asynchronously; give that message a
            // moment to arrive so the widget can show the real number.
            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        let isOn = await connection.isOn
        let volumeInfo = await connection.volumeInfo

        store.update { state in
            state.cache.isOn = isOn
            if let volumeInfo {
                state.cache.volume = volumeInfo.level
                state.cache.volumeMax = volumeInfo.max
                state.cache.muted = volumeInfo.muted
            } else {
                switch key {
                case .volumeUp:
                    if let level = state.cache.volume, let max = state.cache.volumeMax {
                        state.cache.volume = min(level + 1, max)
                    }
                case .volumeDown:
                    if let level = state.cache.volume {
                        state.cache.volume = max(level - 1, 0)
                    }
                case .mute:
                    state.cache.muted.toggle()
                default:
                    break
                }
            }
            state.cache.updatedAt = Date()
        }

        WidgetCenter.shared.reloadAllTimelines()
    }

    public func refresh() async throws {
        let state = store.load()
        guard let device = state.activeDevice, let identity = state.identity else {
            return
        }

        let connection = try await openConnection(for: device, identity: identity)
        let isOn = try await connection.refresh()
        let volumeInfo = await connection.volumeInfo

        store.update { state in
            state.cache.isOn = isOn
            if let volumeInfo {
                state.cache.volume = volumeInfo.level
                state.cache.volumeMax = volumeInfo.max
                state.cache.muted = volumeInfo.muted
            }
            state.cache.updatedAt = Date()
        }

        WidgetCenter.shared.reloadAllTimelines()
    }

    private func openConnection(
        for device: PairedDevice,
        identity: StoredIdentity,
        timeout: TimeInterval = 10
    ) async throws -> TVConnection {
        if let connection,
           connectionDeviceID == device.id,
           let connectionOpened,
           Date().timeIntervalSince(connectionOpened) < 20,
           await connection.isReady {
            return connection
        }

        if let connection {
            await connection.disconnect()
        }

        let newConnection = TVConnection(device: device, identity: identity)
        try await newConnection.connect(timeout: timeout)

        connection = newConnection
        connectionDeviceID = device.id
        connectionOpened = Date()
        return newConnection
    }
}

/// Sends one key press. Used by the interactive widget buttons.
public struct RemoteKeyIntent: AppIntent {
    public static var title: LocalizedStringResource = "Send TV Remote Key"
    public static var description = IntentDescription("Sends a key press to your Google TV.")
    public static var isDiscoverable: Bool = false

    @Parameter(title: "Key")
    public var key: String

    public init() {}

    public init(key: RemoteKey) {
        self.key = key.rawValue
    }

    public func perform() async throws -> some IntentResult {
        guard let remoteKey = RemoteKey(rawValue: key) else {
            return .result()
        }
        try await WidgetRemote.shared.send(remoteKey)
        return .result()
    }
}

/// Re-reads the TV's power and volume state from the widget.
public struct RefreshTVStateIntent: AppIntent {
    public static var title: LocalizedStringResource = "Refresh TV Status"
    public static var description = IntentDescription("Asks your Google TV for its current power and volume state.")
    public static var isDiscoverable: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult {
        try await WidgetRemote.shared.refresh()
        return .result()
    }
}
