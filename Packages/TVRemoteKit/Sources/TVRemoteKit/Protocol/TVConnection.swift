import Foundation
import Security

public enum TVEvent: Sendable {
    case connected(device: RemoteDeviceInfo, isOn: Bool)
    case power(Bool)
    case volume(level: Int, max: Int, muted: Bool)
    case disconnected(String?)
}

/// Owns a live connection to one TV: TLS, the configure/set-active handshake,
/// keepalive ping responses and key injection.
public actor TVConnection {
    public let device: PairedDevice
    private let identity: StoredIdentity
    private let onEvent: (@Sendable (TVEvent) -> Void)?
    private let debugLog: (@Sendable (String) -> Void)?

    private var frame: FrameConnection?
    private var readTask: Task<Void, Never>?
    private var connectTask: Task<Void, Error>?
    private var generation = 0
    private var ready = false

    public private(set) var deviceInfo = RemoteDeviceInfo()
    public private(set) var isOn = false
    public private(set) var volumeInfo: VolumeInfo?

    public init(
        device: PairedDevice,
        identity: StoredIdentity,
        onEvent: (@Sendable (TVEvent) -> Void)? = nil,
        debugLog: (@Sendable (String) -> Void)? = nil
    ) {
        self.device = device
        self.identity = identity
        self.onEvent = onEvent
        self.debugLog = debugLog
    }

    public func connect() async throws {
        try await ensureReady()
    }

    public func disconnect() {
        disconnectInternal()
    }

    public func sendKey(_ key: RemoteKey) async throws {
        try await ensureReady()
        guard let frame else { throw TVConnectionError.notPaired }
        log("-> key \(key.rawValue) code=\(key.keyCode)")

        do {
            try await frame.send(RemoteMessage.keyInject(key.keyCode))
        } catch {
            // One reconnect attempt: TVs drop idle sessions fairly often, and a
            // key press should not fail just because the session went stale.
            disconnectInternal()
            try await ensureReady()
            guard let retryFrame = self.frame else { throw TVConnectionError.closed }
            try await retryFrame.send(RemoteMessage.keyInject(key.keyCode))
        }

        if key == .power {
            isOn.toggle()
            onEvent?(.power(isOn))
        }
    }

    public func sendAppLink(_ link: String) async throws {
        try await ensureReady()
        guard let frame else { throw TVConnectionError.notPaired }
        try await frame.send(RemoteMessage.appLink(link))
    }

    /// Re-runs the handshake and returns the TV's current power state.
    @discardableResult
    public func refresh() async throws -> Bool {
        disconnectInternal()
        try await ensureReady()
        return isOn
    }

    // MARK: - Private

    private func ensureReady() async throws {
        if ready, frame != nil {
            return
        }

        if let connectTask {
            try await connectTask.value
            return
        }

        let task = Task { try await self.performConnect() }
        connectTask = task
        do {
            try await task.value
            connectTask = nil
        } catch {
            connectTask = nil
            throw error
        }
    }

    private func performConnect() async throws {
        disconnectInternal()
        log("connect host=\(device.host):\(device.port)")

        let secIdentity: SecIdentity
        do {
            secIdentity = try identity.makeSecIdentity()
        } catch {
            throw TVConnectionError.tls(error.localizedDescription)
        }

        let newFrame = try FrameConnection(
            host: device.host,
            port: device.port,
            identity: secIdentity
        )
        frame = newFrame

        do {
            try await newFrame.connect()

            while true {
                let data = try await newFrame.receive(timeout: 10)
                let message = try RemoteMessage.decode(data)
                if let text = Self.describe(message) {
                    log("<- \(text) raw=\(Self.hex(data))")
                }

                switch message {
                case .configure(let supportedFeatures, let info):
                    deviceInfo = info
                    let activeFeatures = supportedFeatures & RemoteMessage.requestedFeatures
                    try await newFrame.send(RemoteMessage.configureReply(features: activeFeatures))

                case .setActive:
                    try await newFrame.send(
                        RemoteMessage.setActiveReply(features: RemoteMessage.requestedFeatures)
                    )

                case .remoteStart(let started):
                    isOn = started
                    ready = true
                    onEvent?(.connected(device: deviceInfo, isOn: started))
                    startReadLoop(for: newFrame)
                    return

                case .pingRequest(let val1, _):
                    try await newFrame.send(RemoteMessage.pingResponse(val1))

                case .volume(let level, let max, let muted):
                    volumeInfo = VolumeInfo(level: level, max: max, muted: muted)
                    onEvent?(.volume(level: level, max: max, muted: muted))

                case .error:
                    throw TVConnectionError.protocolError("The TV reported an error.")

                default:
                    continue
                }
            }
        } catch {
            log("connect failed: \(error.localizedDescription)")
            newFrame.close()
            if frame === newFrame {
                frame = nil
            }
            ready = false
            throw error
        }
    }

    private func startReadLoop(for frame: FrameConnection) {
        generation += 1
        let generation = self.generation
        readTask?.cancel()

        readTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                do {
                    let data = try await frame.receive(timeout: 120)
                    let message = try RemoteMessage.decode(data)
                    if let text = Self.describe(message) {
                        self.log("<- \(text) raw=\(Self.hex(data))")
                    }
                    await self.handle(message, generation: generation)
                } catch {
                    await self.handleDisconnect(error, generation: generation)
                    return
                }
            }
        }
    }

    private func handle(_ message: RemoteMessage, generation: Int) async {
        guard generation == self.generation else { return }

        switch message {
        case .pingRequest(let val1, _):
            if let frame {
                try? await frame.send(RemoteMessage.pingResponse(val1))
            }

        case .volume(let level, let max, let muted):
            volumeInfo = VolumeInfo(level: level, max: max, muted: muted)
            onEvent?(.volume(level: level, max: max, muted: muted))

        case .remoteStart(let started):
            isOn = started
            onEvent?(.power(started))

        case .error:
            onEvent?(.disconnected("The TV reported an error."))

        default:
            break
        }
    }

    private func handleDisconnect(_ error: Error, generation: Int) {
        guard generation == self.generation else { return }
        ready = false
        frame?.close()
        frame = nil
        onEvent?(.disconnected(error.localizedDescription))
    }

    private func disconnectInternal() {
        generation += 1
        readTask?.cancel()
        readTask = nil
        frame?.close()
        frame = nil
        ready = false
    }

    // MARK: - Debug logging

    private nonisolated func log(_ line: String) {
        guard let debugLog else { return }
        let stamp = ISO8601DateFormatter().string(from: Date())
        debugLog("[\(stamp)] \(line)")
    }

    private nonisolated static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    /// Human-readable form of a received message, or `nil` for keepalive pings
    /// (which would otherwise flood the debug log).
    private static func describe(_ message: RemoteMessage) -> String? {
        switch message {
        case .configure(let features, let info):
            return "configure features=\(features) device=\(info.vendor)/\(info.model)/\(info.appVersion)"
        case .setActive(let active):
            return "setActive \(active)"
        case .error:
            return "error"
        case .pingRequest:
            return nil
        case .pingResponse:
            return nil
        case .keyInject(let code, let direction):
            return "keyInject \(code) dir=\(direction)"
        case .appInfo(let package):
            return "appInfo \(package)"
        case .imeBatchEdit(let ime, let field):
            return "imeBatchEdit \(ime) \(field)"
        case .remoteStart(let started):
            return "remoteStart \(started)"
        case .volume(let level, let max, let muted):
            return "volume level=\(level) max=\(max) muted=\(muted)"
        case .appLink(let link):
            return "appLink \(link)"
        case .unknown:
            return "unknown"
        }
    }
}
