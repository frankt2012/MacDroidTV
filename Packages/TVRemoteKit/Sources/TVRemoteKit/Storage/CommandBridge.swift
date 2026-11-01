import Foundation

/// A key press queued by the widget for the menu bar app to send over its
/// already-open connection. Widgets run in a separate, short-lived process, so
/// opening a fresh TLS connection for every tap is slow and occasionally loses
/// the race with the app's session.
public struct RemoteCommand: Codable, Sendable {
    public let id: UUID
    /// A remote key press, or nil when this command opens an app.
    public let key: String?
    /// An app deep link, or nil when this command sends a key.
    public let link: String?
    /// Re-read the TV's power/volume state.
    public let refresh: Bool?
    /// Which paired TV to target; nil means the active TV.
    public let deviceID: String?
    public let createdAt: Date

    public init(id: UUID = UUID(), key: RemoteKey, deviceID: UUID? = nil, createdAt: Date = Date()) {
        self.id = id
        self.key = key.rawValue
        self.link = nil
        self.refresh = nil
        self.deviceID = deviceID?.uuidString
        self.createdAt = createdAt
    }

    public init(id: UUID = UUID(), link: String, deviceID: UUID? = nil, createdAt: Date = Date()) {
        self.id = id
        self.key = nil
        self.link = link
        self.refresh = nil
        self.deviceID = deviceID?.uuidString
        self.createdAt = createdAt
    }

    public init(id: UUID = UUID(), refresh: Bool, deviceID: UUID? = nil, createdAt: Date = Date()) {
        self.id = id
        self.key = nil
        self.link = nil
        self.refresh = refresh
        self.deviceID = deviceID?.uuidString
        self.createdAt = createdAt
    }
}

/// Hands widget actions to the running menu bar app through the shared App
/// Group container.
///
/// The widget writes a command, the app polls for it, performs it on its live
/// connection, and writes a result file. The widget waits briefly for that
/// result and falls back to its own connection if the app is not running.
public enum CommandBridge {
    private static var directory: URL? { SharedStore.shared.directoryURL }
    private static var commandURL: URL? { directory?.appendingPathComponent("command.json") }
    private static var resultURL: URL? { directory?.appendingPathComponent("command-result.json") }

    @discardableResult
    public static func post(_ key: RemoteKey, deviceID: UUID? = nil) -> UUID {
        post(RemoteCommand(key: key, deviceID: deviceID))
    }

    @discardableResult
    public static func post(link: String, deviceID: UUID? = nil) -> UUID {
        post(RemoteCommand(link: link, deviceID: deviceID))
    }

    @discardableResult
    public static func postRefresh(deviceID: UUID? = nil) -> UUID {
        post(RemoteCommand(refresh: true, deviceID: deviceID))
    }

    private static func post(_ command: RemoteCommand) -> UUID {
        guard let commandURL else { return command.id }
        do {
            let data = try JSONEncoder().encode(command)
            try data.write(to: commandURL, options: .atomic)
        } catch {
            return command.id
        }
        return command.id
    }

    /// Called by the app when the notification arrives.
    public static func takePending() -> RemoteCommand? {
        guard let commandURL,
              let data = try? Data(contentsOf: commandURL),
              let command = try? JSONDecoder().decode(RemoteCommand.self, from: data)
        else { return nil }
        try? FileManager.default.removeItem(at: commandURL)
        return command
    }

    public static func writeResult(id: UUID, error: String?) {
        guard let resultURL else { return }
        let payload: [String: String] = [
            "id": id.uuidString,
            "error": error ?? ""
        ]
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: resultURL, options: .atomic)
    }

    /// Returns `nil` when the app did not answer in time. An empty string means
    /// the command succeeded; otherwise the string is the failure message.
    public static func waitForResult(id: UUID, timeout: TimeInterval) async -> String?? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let resultURL,
               let data = try? Data(contentsOf: resultURL),
               let payload = try? JSONDecoder().decode([String: String].self, from: data),
               payload["id"] == id.uuidString {
                try? FileManager.default.removeItem(at: resultURL)
                return payload["error"] ?? ""
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return nil
    }
}
