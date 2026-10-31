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
    private let discovery = TVDiscovery()

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

        var connection: TVConnection?
        do {
            connection = try await openConnection(
                for: device,
                identity: identity,
                timeout: sentWakePacket ? 3 : 10
            )
        } catch {
            SharedStore.shared.appendDebugLog("[widget] openConnection1 failed: \(error)")
        }
        if connection == nil, sentWakePacket {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            do {
                connection = try await openConnection(
                    for: device,
                    identity: identity,
                    timeout: 3
                )
            } catch {
                SharedStore.shared.appendDebugLog("[widget] openConnection2 failed: \(error)")
            }
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

        // Try the saved host first; if it fails, ask Bonjour for a fresh
        // address. The saved link-local address can go stale or be scoped to
        // an interface the widget process cannot reach.
        var hostsToTry: [String] = [device.host]

        // Bonjour fallback: the saved link-local address may be scoped to an
        // interface the widget process cannot reach. Browse briefly and resolve
        // a fresh address the way the app's connect() does.
        discovery.start()
        let discovered: [DiscoveredDevice] = await withCheckedContinuation { cont in
            var done = false
            discovery.onChange = { devices in
                guard !done else { return }
                if !devices.isEmpty {
                    done = true
                    cont.resume(returning: devices)
                }
            }
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if !done {
                    done = true
                    cont.resume(returning: [])
                }
            }
        }
        var resolvedHost: String?
        if let match = discovered.first(where: { $0.name == device.name || $0.serviceName == device.name }) {
            resolvedHost = await discovery.resolveHost(for: match.serviceName, timeout: 3)
        }
        discovery.stop()
        if let resolved = resolvedHost, !hostsToTry.contains(resolved) {
            hostsToTry.append(resolved)
        }

        var lastError: Error?
        for host in hostsToTry {
            let newConnection = TVConnection(
                device: { var d = device; d.host = host; return d }(),
                identity: identity,
                debugLog: { line in
                    #if DEBUG
                    SharedStore.shared.appendDebugLog(line)
                    #endif
                }
            )
            do {
                try await newConnection.connect(timeout: timeout)
                connection = newConnection
                connectionDeviceID = device.id
                connectionOpened = Date()
                // (connection succeeded)
                return newConnection
            } catch {
                lastError = error

                await newConnection.disconnect()
            }
        }
        throw lastError ?? TVConnectionError.closed
    }
}

/// Sends one key press. Used by the interactive widget buttons.
public struct RemoteKeyIntent: AppIntent {
    public static var title: LocalizedStringResource = "Send TV Remote Key"
    public static var description = IntentDescription("Sends a key press to your Google TV.")
    public static var isDiscoverable: Bool = false
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public static var supportedModes: IntentModes { .background }

    @Parameter(title: "Key")
    public var key: String

    public init() {}

    public init(key: RemoteKey) {
        self.key = key.rawValue
    }

    public func perform() async throws -> some IntentResult {
        SharedStore.shared.appendDebugLog("[widget-intent] perform key=\(key)")
        guard let remoteKey = RemoteKey(rawValue: key) else { return .result() }
        try? await WidgetRemote.shared.send(remoteKey)
        return .result()
    }
}

/// Re-reads the TV's power and volume state from the widget.
public struct RefreshTVStateIntent: AppIntent {
    public static var title: LocalizedStringResource = "Refresh TV Status"
    public static var description = IntentDescription("Asks your Google TV for its current power and volume state.")
    public static var isDiscoverable: Bool = false
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    public static var supportedModes: IntentModes { .background }

    public init() {}

    public func perform() async throws -> some IntentResult {
        try await WidgetRemote.shared.refresh()
        return .result()
    }
}
