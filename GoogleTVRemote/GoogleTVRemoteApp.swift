import Foundation
import SwiftUI
import TVRemoteKit

@main
struct GoogleTVRemoteApp: App {
    @State private var model: AppModel

    init() {
        // Developer escape hatches for checking shared storage from Terminal.
        // Run the app binary directly, e.g.
        //   GoogleTVRemote.app/Contents/MacOS/GoogleTVRemote --diagnose
        if CommandLine.arguments.contains("--write-test") {
            let store = SharedStore.shared
            let original = store.load()
            let marker = "__write_test__"
            store.update { state in
                state.clientName = marker
            }
            let saveError = store.lastSaveError
            let readBack = store.reloadFromDisk().clientName
            store.replace(with: original)
            print("path=\(store.locationDescription)")
            print("appGroup=\(store.isUsingAppGroup)")
            print("saved=\(saveError == nil)")
            print("error=\(saveError ?? "nil")")
            print("readBackMatches=\(readBack == marker)")
            exit(saveError == nil && readBack == marker ? 0 : 1)
        }

        if CommandLine.arguments.contains("--reset-state") {
            let store = SharedStore.shared
            do {
                try FileManager.default.removeItem(atPath: store.locationDescription)
                print("removed=\(store.locationDescription)")
            } catch CocoaError.fileNoSuchFile {
                print("alreadyEmpty=\(store.locationDescription)")
            } catch {
                print("error=\(error)")
                exit(1)
            }
            exit(0)
        }

        if CommandLine.arguments.contains("--volume-probe") {
            let done = DispatchSemaphore(value: 0)
            Task.detached {
                await VolumeProbe.run()
                done.signal()
            }
            done.wait()
            exit(0)
        }

        if let index = CommandLine.arguments.firstIndex(of: "--set-wake-mac") {
            let mac = CommandLine.arguments.dropFirst(index + 1).first ?? ""
            let store = SharedStore.shared
            let current = store.load()
            guard let device = current.activeDevice else {
                print("no active device")
                exit(1)
            }
            let trimmed = mac.trimmingCharacters(in: .whitespacesAndNewlines)
            let updated = store.update { state in
                if let index = state.devices.firstIndex(where: { $0.id == device.id }) {
                    state.devices[index].wakeMAC = trimmed.isEmpty ? nil : trimmed.uppercased()
                }
            }
            print("device=\(device.name) wakeMAC=\(updated.activeDevice?.wakeMAC ?? "nil")")
            exit(0)
        }

        if let index = CommandLine.arguments.firstIndex(of: "--wol-test") {
            let mac = CommandLine.arguments.dropFirst(index + 1).first ?? "f4:4d:ad:05:75:d7"
            let sent = WakeOnLAN.send(mac: mac)
            let line = "wol mac=\(mac) sent=\(sent) broadcasts=\(WakeOnLAN.localBroadcastAddresses().joined(separator: ","))"
            #if DEBUG
            SharedStore.shared.appendDebugLog(line)
            #endif
            print(line)
            exit(sent > 0 ? 0 : 1)
        }

        if CommandLine.arguments.contains("--discover") {
            let discovery = TVDiscovery()
            let box = DiscoveryBox()
            discovery.onChange = { devices in box.update(devices) }
            let done = DispatchSemaphore(value: 0)
            Task.detached {
                discovery.start()
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                let devices = box.snapshot()
                var lines: [String] = []
                for device in devices {
                    let host = await discovery.resolveHost(for: device.serviceName)
                    let txt = device.txt
                        .sorted { $0.key < $1.key }
                        .map { "\($0.key)=\($0.value)" }
                        .joined(separator: ",")
                    lines.append("discover service=\(device.serviceName) name=\(device.name) host=\(host ?? "nil") txt=[\(txt)]")
                }
                lines.append("discover count=\(devices.count)")
                #if DEBUG
                for line in lines { SharedStore.shared.appendDebugLog(line) }
                #endif
                for line in lines { print(line) }
                done.signal()
            }
            done.wait()
            exit(0)
        }

        if CommandLine.arguments.contains("--diagnose") {
            let store = SharedStore.shared
            let state = store.load()
            print("appGroup=\(store.isUsingAppGroup)")
            print("path=\(store.locationDescription)")
            print("exists=\(FileManager.default.fileExists(atPath: store.locationDescription))")
            print("devices=\(state.devices.count)")
            print("wakeMAC=\(state.activeDevice?.wakeMAC ?? "nil")")
            print("identity=\(state.identity != nil)")
            print("clientName=\(state.clientName)")
            print("isOn=\(state.cache.isOn)")
            print("volume=\(state.cache.volume.map(String.init) ?? "nil")")
            print("volumeMax=\(state.cache.volumeMax.map(String.init) ?? "nil")")
            print("muted=\(state.cache.muted)")
            print("volumeEstimated=\(state.cache.volumeEstimated.map(String.init) ?? "nil")")
            print("cacheUpdatedAt=\(state.cache.updatedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "nil")")
            print("lastSaveError=\(store.lastSaveError ?? "nil")")
            print("hostName=\(Host.current().localizedName ?? "nil")")
            print("--- debug.log tail ---")
            for line in store.debugLogTail(maxLines: 80) {
                print(line)
            }
            // Never print the state file itself: it contains the pairing private key.
            exit(0)
        }

        _model = State(initialValue: AppModel())

        #if DEBUG
        // Drives the real UI code path without clicking:
        //   open -a "$APP" --args --key-test volumeUp volumeUp volumeDown volumeDown
        if let index = CommandLine.arguments.firstIndex(of: "--key-test") {
            let keys = CommandLine.arguments
                .dropFirst(index + 1)
                .compactMap(RemoteKey.init(rawValue:))
            guard !keys.isEmpty else {
                print("usage: --key-test <key> [<key> ...]")
                print("keys: \(RemoteKey.allCases.map(\.rawValue).joined(separator: " "))")
                exit(2)
            }

            let model = _model.wrappedValue
            Task { @MainActor in
                await model.sendForTesting(keys)
                let cache = SharedStore.shared.load().cache
                print("isOn=\(cache.isOn)")
                print("volume=\(cache.volume.map(String.init) ?? "nil")")
                print("volumeMax=\(cache.volumeMax.map(String.init) ?? "nil")")
                print("muted=\(cache.muted)")
                print("volumeEstimated=\(cache.volumeEstimated.map(String.init) ?? "nil")")
                exit(0)
            }
        }
        #endif

        #if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--widget-test") {
            let raw = CommandLine.arguments.dropFirst(index + 1).first ?? "power"
            guard let key = RemoteKey(rawValue: raw) else {
                print("unknown key \(raw)")
                exit(2)
            }
            Task {
                do {
                    try await WidgetRemote.shared.send(key)
                    print("widget send \(raw) OK")
                } catch {
                    print("widget send \(raw) FAILED: \(error)")
                }
                let cache = SharedStore.shared.load().cache
                print("isOn=\(cache.isOn) volume=\(cache.volume.map(String.init) ?? "nil") muted=\(cache.muted)")
                exit(0)
            }
        }
        #endif
    }

    var body: some Scene {
        MenuBarExtra {
            RemotePanelView(model: model)
        } label: {
            Label(
                "Google TV Remote",
                systemImage: model.isConnected ? "av.remote.fill" : "av.remote"
            )
        }
        .menuBarExtraStyle(.window)
    }
}

private final class DiscoveryBox: @unchecked Sendable {
    private let lock = NSLock()
    private var devices: [DiscoveredDevice] = []

    func update(_ devices: [DiscoveredDevice]) {
        lock.lock()
        self.devices = devices
        lock.unlock()
    }

    func snapshot() -> [DiscoveredDevice] {
        lock.lock()
        defer { lock.unlock() }
        return devices
    }
}
