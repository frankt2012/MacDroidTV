import Foundation
import Observation
import TVRemoteKit
import WidgetKit

/// The menu bar app's single source of truth. It owns discovery, the live
/// connection, pairing, and the shared state file the widget also reads.
@MainActor
@Observable
final class AppModel {
    enum Status: Equatable {
        case idle
        case connecting
        case connected
        case failed(String)
    }

    enum PairingStage: Equatable {
        case idle
        case starting
        case enterCode
        case finishing
    }

    private(set) var state: RemoteState
    private(set) var discovered: [DiscoveredDevice] = []
    private(set) var status: Status = .idle
    private(set) var pairingStage: PairingStage = .idle
    private(set) var pairingError: String?
    private(set) var lastError: String?
    private(set) var isRefreshing = false

    var showingDevices = false
    var showingPairing = false

    @ObservationIgnored private let store: SharedStore
    @ObservationIgnored private let discovery = TVDiscovery()
    @ObservationIgnored private var connection: TVConnection?
    @ObservationIgnored private var connectionDeviceID: UUID?
    @ObservationIgnored private var connectingDeviceID: UUID?
    @ObservationIgnored private var pairingClient: PairingClient?
    @ObservationIgnored private var pendingPairingHost: String?
    @ObservationIgnored private var pendingPairingName: String?

    init(store: SharedStore = .shared) {
        self.store = store

        var loaded = store.load()
        if loaded.clientName.isEmpty || loaded.clientName == "Mac Remote" {
            loaded.clientName = Host.current().localizedName ?? "Mac Remote"
            store.replace(with: loaded)
        }
        state = loaded

        discovery.onChange = { [weak self] devices in
            Task { @MainActor [weak self] in
                self?.discovered = devices
            }
        }
        discovery.start()

        Task { [weak self] in
            await self?.connectToActiveDeviceIfNeeded()
        }
    }

    // MARK: - Derived state

    var activeDevice: PairedDevice? { state.activeDevice }
    var deviceName: String { state.activeDevice?.name ?? "Google TV" }
    var isPaired: Bool { state.identity != nil && state.activeDevice != nil }
    var isConnected: Bool {
        if case .connected = status { return true }
        return false
    }
    var isOn: Bool { state.cache.isOn }
    var isUsingAppGroup: Bool { store.isUsingAppGroup }
    var storageLocation: String { store.locationDescription }
    var storageError: String? { store.lastSaveError }

    var volumeFraction: Double {
        guard let level = state.cache.volume,
              let maxVolume = state.cache.volumeMax,
              maxVolume > 0 else { return 0 }
        return Swift.min(Swift.max(Double(level) / Double(maxVolume), 0), 1)
    }

    var volumeText: String {
        if state.cache.muted { return "Muted" }
        guard let level = state.cache.volume else { return "Volume —" }
        return "Volume \(level)"
    }

    var statusText: String {
        switch status {
        case .idle:
            return isPaired ? "Not connected" : "Not paired"
        case .connecting:
            return "Connecting…"
        case .connected:
            return isOn ? "Connected · On" : "Connected · Standby"
        case .failed(let message):
            return message
        }
    }

    var statusColor: ColorToken {
        switch status {
        case .idle:
            return isPaired ? .orange : .gray
        case .connecting:
            return .orange
        case .connected:
            return .green
        case .failed:
            return .red
        }
    }

    /// Small abstraction so `AppModel` does not need to import SwiftUI.
    enum ColorToken {
        case gray, green, orange, red
    }

    // MARK: - Connection

    func connectToActiveDeviceIfNeeded() async {
        guard state.identity != nil, let device = state.activeDevice else { return }
        await connect(to: device)
    }

    func connect(to device: PairedDevice) async {
        guard let identity = state.identity else {
            status = .idle
            return
        }

        if connectionDeviceID == device.id, case .connected = status, connection != nil {
            return
        }
        if connectingDeviceID == device.id {
            return
        }

        if let existing = connection {
            await existing.disconnect()
            connection = nil
            connectionDeviceID = nil
        }

        connectingDeviceID = device.id
        status = .connecting
        lastError = nil

        let newConnection = TVConnection(
            device: device,
            identity: identity,
            onEvent: { [weak self] event in
                Task { @MainActor [weak self] in
                    self?.handle(event, deviceID: device.id)
                }
            }
        )
        connection = newConnection
        connectionDeviceID = device.id

        do {
            try await newConnection.connect()
            let isOn = await newConnection.isOn
            let volume = await newConnection.volumeInfo

            connectingDeviceID = nil
            status = .connected
            markSeen(device)
            updateCache(isOn: isOn, volume: volume)
        } catch {
            connectingDeviceID = nil
            await newConnection.disconnect()
            if connection === newConnection {
                connection = nil
                connectionDeviceID = nil
            }
            status = .failed(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    func disconnect() async {
        if let connection {
            await connection.disconnect()
        }
        connection = nil
        connectionDeviceID = nil
        connectingDeviceID = nil
        if case .failed = status {
            // Keep the failure visible until the user retries or dismisses it.
        } else {
            status = .idle
        }
    }

    func send(_ key: RemoteKey) {
        Task { [weak self] in
            await self?.performSend(key)
        }
    }

    func togglePower() {
        send(.power)
    }

    func refresh() {
        Task { [weak self] in
            guard let self else { return }
            self.isRefreshing = true
            defer { self.isRefreshing = false }

            guard let connection = await self.ensureConnection() else { return }
            do {
                let isOn = try await connection.refresh()
                let volume = await connection.volumeInfo
                self.status = .connected
                if let device = self.state.activeDevice {
                    self.markSeen(device)
                }
                self.updateCache(isOn: isOn, volume: volume)
            } catch {
                self.lastError = error.localizedDescription
                self.status = .failed(error.localizedDescription)
                self.connection = nil
                self.connectionDeviceID = nil
            }
        }
    }

    private func ensureConnection() async -> TVConnection? {
        if let connection,
           connectionDeviceID == state.activeDevice?.id,
           case .connected = status {
            return connection
        }
        guard let device = state.activeDevice else { return nil }
        await connect(to: device)
        if case .connected = status {
            return connection
        }
        return nil
    }

    private func performSend(_ key: RemoteKey) async {
        guard let connection = await ensureConnection() else { return }

        do {
            try await connection.sendKey(key)
            let isOn = await connection.isOn
            let volume = await connection.volumeInfo

            updateCache(isOn: isOn, volume: volume) { state in
                guard volume == nil else { return }
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
        } catch {
            lastError = error.localizedDescription
            status = .failed(error.localizedDescription)
            self.connection = nil
            connectionDeviceID = nil
        }
    }

    private func handle(_ event: TVEvent, deviceID: UUID) {
        guard connectionDeviceID == deviceID else { return }

        switch event {
        case .connected(_, let isOn):
            status = .connected
            updateCache(isOn: isOn, volume: nil)

        case .power(let isOn):
            updateCache(isOn: isOn, volume: nil)

        case .volume(let level, let max, let muted):
            mutateState { state in
                state.cache.volume = level
                state.cache.volumeMax = max
                state.cache.muted = muted
                state.cache.updatedAt = Date()
            }

        case .disconnected(let message):
            connection = nil
            connectionDeviceID = nil
            status = message.map { .failed($0) } ?? .idle
            if let message {
                lastError = message
            }
        }
    }

    private func updateCache(
        isOn: Bool,
        volume: VolumeInfo?,
        extra: ((inout RemoteState) -> Void)? = nil
    ) {
        mutateState { state in
            state.cache.isOn = isOn
            if let volume {
                state.cache.volume = volume.level
                state.cache.volumeMax = volume.max
                state.cache.muted = volume.muted
            }
            extra?(&state)
            state.cache.updatedAt = Date()
        }
    }

    private func markSeen(_ device: PairedDevice) {
        mutateState { state in
            guard let index = state.devices.firstIndex(where: { $0.id == device.id }) else { return }
            state.devices[index].lastSeen = Date()
        }
    }

    private func mutateState(_ mutate: (inout RemoteState) -> Void) {
        state = store.update(mutate)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Devices

    func select(_ device: PairedDevice) {
        mutateState { state in
            state.activeDeviceID = device.id
        }
        Task { [weak self] in
            await self?.connect(to: device)
        }
    }

    func forget(_ device: PairedDevice) {
        if connectionDeviceID == device.id {
            Task { [weak self] in
                await self?.disconnect()
            }
        }

        mutateState { state in
            state.devices.removeAll { $0.id == device.id }
            if state.activeDeviceID == device.id {
                state.activeDeviceID = state.devices.first?.id
            }
            if state.devices.isEmpty {
                state.cache = CachedTVState()
            }
        }
    }

    func resetIdentity() {
        Task { [weak self] in
            await self?.disconnect()
        }
        cancelPairing()
        mutateState { state in
            state.identity = nil
            state.devices = []
            state.activeDeviceID = nil
            state.cache = CachedTVState()
        }
        status = .idle
    }

    func setClientName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutateState { state in
            state.clientName = trimmed
        }
    }

    // MARK: - Pairing

    func pair(with device: DiscoveredDevice) {
        Task { [weak self] in
            guard let self else { return }
            self.pairingError = nil
            self.pairingStage = .starting

            guard let host = await self.discovery.resolveHost(for: device.serviceName) else {
                self.pairingStage = .idle
                self.pairingError = "Could not find \(device.name) on the network. Make sure the TV is on and on the same Wi-Fi network."
                return
            }
            await self.beginPairing(host: host, name: device.name)
        }
    }

    func pairManually(host rawHost: String) {
        let host = Self.normalizeHost(rawHost)
        guard !host.isEmpty else {
            pairingError = "Enter the TV's IP address or hostname."
            return
        }
        Task { [weak self] in
            await self?.beginPairing(host: host, name: host)
        }
    }

    func beginPairing(host: String, name: String) async {
        pairingError = nil
        pairingStage = .starting
        lastError = nil

        do {
            let identity = try ensureIdentity()
            let client = PairingClient(
                host: host,
                identity: identity,
                clientName: state.clientName
            )
            pairingClient = client
            pendingPairingHost = host
            pendingPairingName = name

            try await client.begin()
            pairingStage = .enterCode
        } catch {
            if let client = pairingClient {
                await client.cancel()
            }
            pairingClient = nil
            pendingPairingHost = nil
            pendingPairingName = nil
            pairingStage = .idle
            pairingError = error.localizedDescription
        }
    }

    func finishPairing(code: String) {
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count == 6, code.allSatisfy({ $0.isHexDigit }) else {
            pairingError = "Enter the 6-character code shown on your TV."
            return
        }
        guard let client = pairingClient,
              let host = pendingPairingHost else {
            pairingError = "The pairing session expired. Start again."
            pairingStage = .idle
            return
        }

        Task { [weak self] in
            guard let self else { return }
            self.pairingStage = .finishing
            self.pairingError = nil

            do {
                try await client.finish(code: code)
                let certificate = await client.serverCertificateDER()
                let device = PairedDevice(
                    name: self.pendingPairingName ?? host,
                    host: host,
                    serverCertificate: certificate,
                    lastSeen: Date()
                )

                self.mutateState { state in
                    state.devices.removeAll { $0.host == host }
                    state.devices.append(device)
                    state.activeDeviceID = device.id
                }

                self.pairingClient = nil
                self.pendingPairingHost = nil
                self.pendingPairingName = nil
                self.pairingStage = .idle
                self.pairingError = nil
                self.showingPairing = false

                await self.connect(to: device)
            } catch {
                await client.cancel()
                self.pairingClient = nil
                self.pendingPairingHost = nil
                self.pendingPairingName = nil
                self.pairingStage = .idle
                self.pairingError = error.localizedDescription
            }
        }
    }

    func cancelPairing() {
        if let client = pairingClient {
            Task { await client.cancel() }
        }
        pairingClient = nil
        pendingPairingHost = nil
        pendingPairingName = nil
        pairingStage = .idle
        pairingError = nil
    }

    func clearError() {
        lastError = nil
        pairingError = nil
    }

    private func ensureIdentity() throws -> StoredIdentity {
        if let identity = state.identity {
            return identity
        }

        let generated = try CertificateFactory.generate(commonName: state.clientName)
        let identity = StoredIdentity(
            certificateDER: generated.certificateDER,
            privateKeyDER: generated.privateKeyDER,
            displayName: state.clientName
        )
        mutateState { state in
            state.identity = identity
        }
        return identity
    }

    private static func normalizeHost(_ raw: String) -> String {
        var host = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let schemeRange = host.range(of: "://") {
            host = String(host[schemeRange.upperBound...])
        }
        if let slash = host.firstIndex(of: "/") {
            host = String(host[..<slash])
        }
        if let colon = host.lastIndex(of: ":"), host.filter({ $0 == ":" }).count == 1 {
            let portPart = host[host.index(after: colon)...]
            if Int(portPart) != nil {
                host = String(host[..<colon])
            }
        }
        return host
    }
}
