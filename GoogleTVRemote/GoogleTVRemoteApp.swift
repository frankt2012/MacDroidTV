import Foundation
import SwiftUI
import TVRemoteKit
import WidgetKit

@main
struct GoogleTVRemoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel

    init() {
        if CommandLine.arguments.contains("--touch-state") {
            let store = SharedStore.shared
            store.update { state in
                if let v = state.cache.volume { state.cache.volume = v + 1 }
                state.cache.updatedAt = Date()
            }
            WidgetCenter.shared.reloadAllTimelines()
            print("touched")
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { exit(0) }
            // Fall through to normal init so the app can run briefly.
        }
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
            print("quickApps=\(state.selectedQuickApps.map(\.id).joined(separator: ","))")
            print("customApps=\(state.customApps?.map(\.name).joined(separator: ",") ?? "nil")")
            print("cacheUpdatedAt=\(state.cache.updatedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "nil")")
            print("lastSaveError=\(store.lastSaveError ?? "nil")")
            print("showMenuBarIcon=\(UserDefaults.standard.object(forKey: "showMenuBarIcon").map { "\($0)" } ?? "nil")")
            print("hostName=\(Host.current().localizedName ?? "nil")")
            print("--- debug.log tail ---")
            for line in store.debugLogTail(maxLines: 80) {
                print(line)
            }
            // Never print the state file itself: it contains the pairing private key.
            exit(0)
        }

        if let index = CommandLine.arguments.firstIndex(of: "--post-command") {
            let raw = CommandLine.arguments.dropFirst(index + 1).first ?? "volumeUp"
            guard let key = RemoteKey(rawValue: raw) else {
                print("unknown key \(raw)")
                exit(2)
            }
            print("container=\(SharedStore.shared.directoryURL?.path ?? "nil")")
            let id = CommandBridge.post(key)
            let dir = SharedStore.shared.directoryURL
            let cmdPath = dir?.appendingPathComponent("command.json").path ?? "nil"
            print("posted id=\(id) commandPath=\(cmdPath) exists=\(FileManager.default.fileExists(atPath: cmdPath))")
            let sem = DispatchSemaphore(value: 0)
            var message = "no response"
            Task.detached {
                if let outcome = await CommandBridge.waitForResult(id: id, timeout: 8) {
                    message = outcome.flatMap { $0.isEmpty ? nil : $0 } ?? "ok"
                }
                sem.signal()
            }
            _ = sem.wait(timeout: .now() + 10)
            print("post-command \(raw): \(message)")
            exit(0)
        }

        if CommandLine.arguments.contains("--post-refresh") {
            let id = CommandBridge.postRefresh()
            let sem = DispatchSemaphore(value: 0)
            var message = "no response"
            Task.detached {
                if let outcome = await CommandBridge.waitForResult(id: id, timeout: 10) {
                    message = outcome.flatMap { $0.isEmpty ? nil : $0 } ?? "ok"
                }
                sem.signal()
            }
            _ = sem.wait(timeout: .now() + 12)
            print("post-refresh: \(message)")
            exit(0)
        }

        if let index = CommandLine.arguments.firstIndex(of: "--post-link") {
            let link = CommandLine.arguments.dropFirst(index + 1).first ?? "market://launch?id=com.netflix.ninja"
            let id = CommandBridge.post(link: link)
            let sem = DispatchSemaphore(value: 0)
            var message = "no response"
            Task.detached {
                if let outcome = await CommandBridge.waitForResult(id: id, timeout: 10) {
                    message = outcome.flatMap { $0.isEmpty ? nil : $0 } ?? "ok"
                }
                sem.signal()
            }
            _ = sem.wait(timeout: .now() + 12)
            print("post-link: \(message)")
            exit(0)
        }

        if let index = CommandLine.arguments.firstIndex(of: "--post-app") {
            let raw = CommandLine.arguments.dropFirst(index + 1).first ?? "netflix"
            guard let app = QuickApp.common.first(where: { $0.id == raw }) else {
                print("unknown app \(raw). options: \(QuickApp.common.map(\.id).joined(separator: " "))")
                exit(2)
            }
            let id = CommandBridge.post(link: app.link)
            let sem = DispatchSemaphore(value: 0)
            var message = "no response"
            Task.detached {
                if let outcome = await CommandBridge.waitForResult(id: id, timeout: 10) {
                    message = outcome.flatMap { $0.isEmpty ? nil : $0 } ?? "ok"
                }
                sem.signal()
            }
            _ = sem.wait(timeout: .now() + 12)
            print("post-app \(raw): \(message)")
            exit(0)
        }

        _model = State(initialValue: AppModel())

        if let index = CommandLine.arguments.firstIndex(of: "--set-menu-bar") {
            let value = CommandLine.arguments.dropFirst(index + 1).first != "0"
            UserDefaults.standard.set(value, forKey: "showMenuBarIcon")
            print("showMenuBarIcon=\(value)")
            exit(0)
        }

        if CommandLine.arguments.contains("--reset-apps") {
            let model = _model.wrappedValue
            Task { @MainActor in
                await Task.yield()
                model.resetQuickApps()
                print("reset quick apps")
                exit(0)
            }
        }

        if let index = CommandLine.arguments.firstIndex(of: "--add-custom-app") {
            let rest = Array(CommandLine.arguments.dropFirst(index + 1))
            guard rest.count >= 2 else {
                print("usage: --add-custom-app <name> <package-or-link>")
                exit(2)
            }
            let model = _model.wrappedValue
            Task { @MainActor in
                await Task.yield()
                model.addCustomQuickApp(name: rest[0], link: rest[1])
                print("added \(rest[0])")
                exit(0)
            }
        }


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
        // The status item is owned by AppDelegate so it is inserted reliably
        // on a cold launch. An empty Settings scene keeps SwiftUI happy.
        Settings {
            EmptyView()
        }
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
