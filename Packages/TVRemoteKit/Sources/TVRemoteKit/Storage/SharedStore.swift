import Foundation

/// Small JSON store shared by the menu bar app and the widget extension.
///
/// The two processes cannot share a normal `Application Support` directory when
/// the app is sandboxed, so the store lives in the App Group container.
///
/// macOS requires App Group identifiers to start with the team identifier. A
/// bare `group.…` identifier still resolves to a container URL, but the sandbox
/// rejects every write, so the team prefix below is load-bearing.
///
/// The fallback exists for unsandboxed development builds where the entitlement
/// is not present; in that case the widget will not see the app's state.
public final class SharedStore: @unchecked Sendable {
    public static let appGroupID = "BJB8XCZ8X9.group.com.franktriolo.googletvremote"
    public static let shared = SharedStore()

    private let lock = NSLock()
    private let fileURL: URL?
    private var cached: RemoteState?

    public let isUsingAppGroup: Bool
    /// Set when the last write failed. Surfaced in the app's diagnostics so a
    /// missing App Group entitlement does not fail silently.
    public private(set) var lastSaveError: String?

    private init() {
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID) {
            fileURL = container.appendingPathComponent("state.json", isDirectory: false)
            isUsingAppGroup = true
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            fileURL = base
                .appendingPathComponent("GoogleTVRemote", isDirectory: true)
                .appendingPathComponent("state.json", isDirectory: false)
            isUsingAppGroup = false
        }
    }

    public var locationDescription: String {
        fileURL?.path ?? "unavailable"
    }

    public func load() -> RemoteState {
        lock.lock()
        defer { lock.unlock() }
        return loadLocked()
    }

    @discardableResult
    public func update(_ mutate: (inout RemoteState) -> Void) -> RemoteState {
        lock.lock()
        defer { lock.unlock() }

        var state = loadLocked()
        mutate(&state)
        saveLocked(state)
        return state
    }

    public func replace(with state: RemoteState) {
        lock.lock()
        defer { lock.unlock() }
        saveLocked(state)
    }

    /// Forget the in-memory copy. Useful in the widget, which may be woken in a
    /// process that previously read a stale file.
    public func invalidateCache() {
        lock.lock()
        cached = nil
        lock.unlock()
    }

    /// Drop the cache and read the file again. Used by the `--write-test`
    /// diagnostic to prove the state really reached disk.
    @discardableResult
    public func reloadFromDisk() -> RemoteState {
        lock.lock()
        defer { lock.unlock() }
        cached = nil
        return loadLocked()
    }

    /// Appends a line to `debug.log` next to the state file. Development builds
    /// use this to capture protocol traffic that is hard to see from the UI.
    public func appendDebugLog(_ line: String) {
        guard let fileURL else { return }
        let url = fileURL.deletingLastPathComponent().appendingPathComponent("debug.log")
        let entry = Data((line + "\n").utf8)

        lock.lock()
        defer { lock.unlock() }

        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: entry)
        } else {
            try? entry.write(to: url, options: .atomic)
        }
    }

    public func debugLogTail(maxLines: Int = 60) -> [String] {
        guard let fileURL else { return [] }
        let url = fileURL.deletingLastPathComponent().appendingPathComponent("debug.log")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: true)
            .suffix(maxLines)
            .map(String.init)
    }

    private func loadLocked() -> RemoteState {
        if let cached {
            return cached
        }

        guard let fileURL, let data = try? Data(contentsOf: fileURL) else {
            let empty = RemoteState()
            cached = empty
            return empty
        }

        do {
            let state = try JSONDecoder.tvRemote.decode(RemoteState.self, from: data)
            cached = state
            return state
        } catch {
            // A corrupt file should not brick the app; start fresh and let the
            // next save overwrite it.
            let empty = RemoteState()
            cached = empty
            return empty
        }
    }

    private func saveLocked(_ state: RemoteState) {
        cached = state
        guard let fileURL else {
            lastSaveError = "The shared state file location is unavailable."
            return
        }

        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(state)
            try data.write(to: fileURL, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            lastSaveError = nil
        } catch {
            lastSaveError = error.localizedDescription
        }
    }
}

extension JSONDecoder {
    static var tvRemote: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
