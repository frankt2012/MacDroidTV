import Foundation
import Observation
import TVRemoteKit
import WidgetKit

/// The menu bar app's single source of truth. It owns discovery, the live
/// connection, pairing, and the shared state file the widget also reads.
@MainActor
@Observable
final class AppModel {
    /// The menu bar app's live model, used by the URL handler that opens the
    /// volume sync window from the widget.
    @MainActor static weak var shared: AppModel?

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
    /// True while a sleeping TV is being woken, so extra power presses cannot
    /// toggle it back off mid-wake.
    private(set) var isWaking = false
    /// When the TV last woke, so boot-time volume reports do not clobber a
    /// volume the user synced while the TV was off.
    private var wokenAt: Date?

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
    @ObservationIgnored private var commandTask: Task<Void, Never>?

    init(store: SharedStore = .shared) {
        self.store = store

        var loaded = store.load()
        if loaded.clientName.isEmpty || loaded.clientName == "Mac Remote" {
            loaded.clientName = Host.current().localizedName ?? "Mac Remote"
            store.replace(with: loaded)
        }
        // Older builds cached the 0/0 volume some TVs report when they do not
        // expose a volume scale. Treat that as "unknown" instead of "0".
        if loaded.cache.volumeMax == 0 {
            loaded.cache.volume = nil
            loaded.cache.volumeMax = nil
            store.replace(with: loaded)
        }
        state = loaded

        discovery.onChange = { [weak self] devices in
            Task { @MainActor [weak self] in
                self?.discovered = devices
            }
        }
        discovery.start()

        // Widget buttons hand their key presses to this process through the
        // shared container so taps use the live connection instead of paying
        // for a fresh TLS handshake each time. Polling is used rather than
        // DistributedNotificationCenter, which the sandbox does not deliver.
        commandTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                if let self, let command = CommandBridge.takePending() {
                    // Ignore a command left over from a previous launch.
                    if Date().timeIntervalSince(command.createdAt) < 30 {
                        self.lastError = nil
                        if let rawKey = command.key, let key = RemoteKey(rawValue: rawKey) {
                            await self.performSend(key)
                        } else if let link = command.link {
                            await self.performAppLink(link)
                        }
                        CommandBridge.writeResult(id: command.id, error: self.lastError)
                    } else {
                        CommandBridge.writeResult(id: command.id, error: "stale command")
                    }
                }
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
        }

        Task { [weak self] in
            await self?.connectToActiveDeviceIfNeeded()
        }

        Self.shared = self
    }

    deinit {
        commandTask?.cancel()
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
        guard let max = state.cache.volumeMax, max > 0,
              let level = state.cache.volume else { return "Volume —" }
        if isVolumeEstimated { return "Volume ≈ \(level)" }
        return "Volume \(level)"
    }

    var isVolumeEstimated: Bool { state.cache.volumeEstimated == true }
    var wakeMAC: String? { state.activeDevice?.wakeMAC }

    func setWakeMAC(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalised = trimmed.isEmpty ? nil : trimmed.uppercased()
        guard let device = state.activeDevice else { return }
        mutateState { state in
            if let index = state.devices.firstIndex(where: { $0.id == device.id }) {
                state.devices[index].wakeMAC = normalised
            }
        }
    }

    var volumeScaleMax: Int {
        let maxVolume = state.cache.volumeMax ?? 0
        return maxVolume > 0 ? maxVolume : VolumeEstimate.defaultMax
    }
    var volumeStep: Int {
        state.cache.volumeStep ?? max(1, volumeScaleMax / 50)
    }

    var selectedQuickApps: [QuickApp] { state.selectedQuickApps }
    var allQuickApps: [QuickApp] { state.allQuickApps }

    func isQuickAppSelected(_ id: String) -> Bool {
        selectedQuickApps.contains { $0.id == id }
    }

    func setQuickApp(id: String, selected: Bool) {
        mutateState { state in
            var ids = state.quickAppIDs ?? state.selectedQuickApps.map(\.id)
            if selected {
                if !ids.contains(id) { ids.append(id) }
            } else {
                ids.removeAll { $0 == id }
            }
            state.quickAppIDs = ids
        }
    }

    func addCustomQuickApp(name: String, link: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLink = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedLink.isEmpty else { return }

        let app = QuickApp(
            id: "custom-\(UUID().uuidString)",
            name: trimmedName,
            shortLabel: String(trimmedName.prefix(2)).uppercased(),
            link: QuickApp.launchLink(from: trimmedLink)
        )
        mutateState { state in
            var customs = state.customApps ?? []
            customs.append(app)
            state.customApps = customs
            var ids = state.quickAppIDs ?? state.selectedQuickApps.map(\.id)
            ids.append(app.id)
            state.quickAppIDs = ids
        }
    }

    func resetQuickApps() {
        mutateState { state in
            state.quickAppIDs = nil
            state.customApps = nil
        }
    }

    func removeCustomQuickApp(id: String) {
        mutateState { state in
            state.customApps?.removeAll { $0.id == id }
            state.quickAppIDs?.removeAll { $0 == id }
        }
    }

    func syncVolume(level: Int, step: Int) {
        mutateState { state in
            VolumeEstimate.sync(level: level, step: step, to: &state.cache)
            state.cache.updatedAt = Date()
        }
    }

    var statusText: String {
        switch status {
        case .idle:
            guard isPaired else { return "Not paired" }
            return state.cache.isOn ? "Not connected" : "Standby"
        case .connecting:
            return isWaking ? "Waking TV…" : "Connecting…"
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

    func connect(
        to device: PairedDevice,
        timeout: TimeInterval = 10,
        discoveryTimeout: TimeInterval = 5,
        reportFailure: Bool = true
    ) async {
        guard let identity = state.identity else {
            status = .idle
            return
        }

        if let connection, connectionDeviceID == device.id, case .connected = status,
           await connection.isReady {
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

        var connected = false
        do {
            try await establishConnection(
                to: device,
                host: device.host,
                identity: identity,
                timeout: timeout
            )
            connected = true
        } catch {
            // A saved host can go stale when the TV's DHCP lease or link-local
            // address changes. Only ask Bonjour after the saved host fails:
            // resolving first opens an extra connection, which can race the
            // TV's single-session handling. A TV that is off cannot answer
            // Bonjour either, so skip the extra wait when waking it.
            if let resolved = await resolvedHost(for: device, timeout: discoveryTimeout),
               resolved != device.host {
                do {
                    try await establishConnection(
                        to: device,
                        host: resolved,
                        identity: identity,
                        timeout: timeout
                    )
                    connected = true
                    mutateState { state in
                        if let index = state.devices.firstIndex(where: { $0.id == device.id }) {
                            state.devices[index].host = resolved
                        }
                    }
                } catch {
                    if reportFailure { reportConnectFailure(error) }
                }
            } else {
                if reportFailure { reportConnectFailure(error) }
            }
        }

        connectingDeviceID = nil
        if connected {
            status = .connected
            markSeen(device)
        }
    }

    /// Opens a connection to `host` and waits for the handshake to finish.
    ///
    /// On success the connection and the cache are up to date. On failure the
    /// half-open connection is torn down and the error is rethrown.
    private func establishConnection(
        to device: PairedDevice,
        host: String,
        identity: StoredIdentity,
        timeout: TimeInterval = 10
    ) async throws {
        var target = device
        target.host = host

        let newConnection = TVConnection(
            device: target,
            identity: identity,
            onEvent: { [weak self] event in
                Task { @MainActor [weak self] in
                    self?.handle(event, deviceID: device.id)
                }
            },
            debugLog: { line in
                #if DEBUG
                SharedStore.shared.appendDebugLog(line)
                #endif
            }
        )
        connection = newConnection
        connectionDeviceID = device.id

        do {
            try await newConnection.connect(timeout: timeout)
            let isOn = await newConnection.isOn
            let volume = await newConnection.volumeInfo
            status = .connected
            updateCache(isOn: isOn, volume: volume)
        } catch {
            await newConnection.disconnect()
            if connection === newConnection {
                connection = nil
                connectionDeviceID = nil
            }
            throw error
        }
    }

    private func reportConnectFailure(_ error: Error) {
        status = .failed(error.localizedDescription)
        lastError = error.localizedDescription
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
        // A wake is in progress: another power press would toggle the TV back
        // off the moment it comes up.
        if key == .power, isWaking { return }
        Task { [weak self] in
            await self?.performSend(key)
        }
    }

    func togglePower() {
        send(.power)
    }

    /// Opens an app on the TV through its Android TV deep link.
    func openApp(_ app: QuickApp) {
        Task { [weak self] in
            await self?.performAppLink(app.link)
        }
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

    private func ensureConnection(
        timeout: TimeInterval = 10,
        discoveryTimeout: TimeInterval = 5,
        reportFailure: Bool = true
    ) async -> TVConnection? {
        if let connection,
           connectionDeviceID == state.activeDevice?.id,
           case .connected = status,
           await connection.isReady {
            return connection
        }
        guard let device = state.activeDevice else { return nil }
        await connect(
            to: device,
            timeout: timeout,
            discoveryTimeout: discoveryTimeout,
            reportFailure: reportFailure
        )
        if case .connected = status {
            return connection
        }
        return nil
    }

    /// Current Bonjour address for a paired TV, if it is currently discoverable.
    private func resolvedHost(for device: PairedDevice, timeout: TimeInterval = 5) async -> String? {
        guard let discoveredDevice = discovered.first(where: {
            $0.name == device.name || $0.serviceName == device.name
        }) else {
            return nil
        }
        return await discovery.resolveHost(for: discoveredDevice.serviceName, timeout: timeout)
    }

    #if DEBUG
    /// Developer hook behind the `--key-test` CLI flag. Sends keys through the
    /// same path as the UI, so the cached state ends up exactly as it would
    /// after clicking the buttons.
    func sendForTesting(_ keys: [RemoteKey]) async {
        func waiting() -> Bool {
            switch status {
            case .connecting: return true
            case .idle: return state.activeDevice != nil
            default: return false
            }
        }

        for _ in 0..<150 where waiting() {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        if case .connected = status {} else {
            await connectToActiveDeviceIfNeeded()
        }

        for key in keys {
            await performSend(key)
            try? await Task.sleep(nanoseconds: 800_000_000)
        }
    }
    #endif

    func performSend(_ key: RemoteKey) async {
        // Waking a sleeping TV has its own flow: a power key sent while it is
        // still starting would put it straight back into standby.
        if key == .power, !state.cache.isOn {
            await wake()
            return
        }

        let wasOff = !state.cache.isOn
        // A sleeping TV should fail fast: waiting ten seconds per attempt to
        // report that a wake did not work feels broken.
        let connectTimeout: TimeInterval = wasOff ? 5 : 10
        let discoveryTimeout: TimeInterval = wasOff ? 2 : 5

        guard let connection = await ensureConnection(
            timeout: connectTimeout,
            discoveryTimeout: discoveryTimeout
        ) else {
            return
        }

        do {
            try await connection.sendKey(key, connectTimeout: connectTimeout)
            let isOn = await connection.isOn
            let volume = await connection.volumeInfo
            let hasVolumeFeedback = (volume?.max ?? 0) > 0

            updateCache(isOn: isOn, volume: volume) { state in
                guard !hasVolumeFeedback else { return }
                if key == .volumeUp || key == .volumeDown {
                    VolumeEstimate.apply(key, to: &state.cache)
                }
            }
            // Mute is optimistic: the TV's volume report may lag, so flip the
            // cached state now and let a later real report correct it.
            if key == .mute {
                mutateState { state in state.cache.muted.toggle() }
            }
        } catch {
            lastError = error.localizedDescription
            status = .failed(error.localizedDescription)
            self.connection = nil
            connectionDeviceID = nil
        }
    }

    /// Sends an app deep link over the live connection.
    private func performAppLink(_ link: String) async {
        if !state.cache.isOn {
            await wake()
            guard state.cache.isOn else { return }
        }
        guard let connection = await ensureConnection() else { return }
        do {
            try await connection.sendAppLink(link)
        } catch {
            lastError = error.localizedDescription
            status = .failed(error.localizedDescription)
            self.connection = nil
            connectionDeviceID = nil
        }
    }

    /// Turns a sleeping TV on. Sends a Wake-on-LAN packet, then waits for the
    /// TV to come back and announce itself. The power key is only used when the
    /// TV is reachable but the packet did not wake it: a key sent while the TV
    /// is still starting would put it straight back into standby.
    private func wake() async {
        guard !isWaking else { return }
        isWaking = true
        defer { isWaking = false }

        var sentWakePacket = false
        if let mac = wakeMAC, !mac.isEmpty {
            let sent = WakeOnLAN.send(mac: mac)
            sentWakePacket = sent > 0
            #if DEBUG
            SharedStore.shared.appendDebugLog(
                "[\(ISO8601DateFormatter().string(from: Date()))] wake mac=\(mac) sent=\(sent)"
            )
            #endif
        }

        // The TV's network stack needs a moment to come back after the packet;
        // connecting too early just burns a timeout.
        if sentWakePacket {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }

        let deadline = Date().addingTimeInterval(12)
        var reachableAt: Date?
        var sentPowerKey = false

        while Date() < deadline {
            if let connection = await ensureConnection(
                timeout: 2,
                discoveryTimeout: 1,
                reportFailure: false
            ) {
                if reachableAt == nil { reachableAt = Date() }

                if await connection.waitUntilOn(timeout: 2) {
                    await finishWake(connection)
                    return
                }

                // The TV is reachable but still asleep, so the magic packet did
                // not wake it. Wait a bit first: the power key would otherwise
                // interrupt a TV that is still starting up.
                if !sentPowerKey,
                   Date().timeIntervalSince(reachableAt ?? Date()) > 4 {
                    sentPowerKey = true
                    let keyTime = Date()
                    try? await connection.sendKey(.power, connectTimeout: 2)
                    if await connection.waitForWake(after: keyTime, timeout: 6) {
                        await finishWake(connection)
                        return
                    }
                }
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }

        let message = wakeFailureMessage
        lastError = message
        status = .failed(message)
    }

    private func finishWake(_ connection: TVConnection) async {
        wokenAt = Date()
        status = .connected
        if let device = state.activeDevice {
            markSeen(device)
        }
        // Do not apply the volume here: a report that arrived during boot may
        // be a transient (often 6) and would clobber a value the user synced.
        // Volume reports are handled by `handle(.volume)`, which keeps a synced
        // estimate during the wake window.
        updateCache(isOn: true, volume: nil)
    }

    /// Shown when a powered-off TV could not be reached or woken.
    private var wakeFailureMessage: String {
        if wakeMAC == nil {
            return "The TV is off and not on the network. Turn it on with its remote, or enable the TV's always-on/networked standby setting so the app can reach it."
        }
        return "The TV is off and did not answer Wake-on-LAN. Check that the TV's always-on/networked standby setting is enabled and that the MAC address is correct."
    }

    private func handle(_ event: TVEvent, deviceID: UUID) {
        guard connectionDeviceID == deviceID else { return }

        switch event {
        case .connected(_, let isOn):
            status = .connected
            updateCache(isOn: isOn, volume: nil)

        case .power(let isOn):
            if !isOn { wokenAt = nil }
            updateCache(isOn: isOn, volume: nil)

        case .volume(let level, let max, let muted):
            // A max of zero means the TV did not report a volume scale. Several
            // TVs send 0/0 when audio is handled outside the Android TV service
            // (the TV's own audio pipeline, an AVR, or CEC). Caching that would
            // display a bogus "Volume 0".
            guard max > 0 else { return }
            // Right after waking, the TV sometimes reports a transient level
            // (often 6) that does not match what the user synced. Keep the
            // synced estimate's level during that window, but still take the
            // TV's mute state.
            let wakeWindow = state.cache.volumeEstimated == true
                && wokenAt != nil
                && Date().timeIntervalSince(wokenAt!) < 15
            mutateState { state in
                if !wakeWindow {
                    state.cache.volume = level
                    state.cache.volumeMax = max
                    state.cache.volumeEstimated = false
                } else if (state.cache.volumeMax ?? 0) == 0 {
                    state.cache.volumeMax = max
                }
                state.cache.muted = muted
                state.cache.updatedAt = Date()
            }

        case .disconnected(let message):
            connection = nil
            connectionDeviceID = nil
            // A TV that just powered off drops the socket. That is expected, so
            // do not turn it into an error banner.
            if let message, state.cache.isOn {
                status = .failed(message)
                lastError = message
            } else {
                status = .idle
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
            if let volume, volume.max > 0 {
                let wakeWindow = state.cache.volumeEstimated == true
                    && wokenAt != nil
                    && Date().timeIntervalSince(wokenAt!) < 15
                if !wakeWindow {
                    state.cache.volume = volume.level
                    state.cache.volumeMax = volume.max
                    state.cache.volumeEstimated = false
                } else if (state.cache.volumeMax ?? 0) == 0 {
                    state.cache.volumeMax = volume.max
                }
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
