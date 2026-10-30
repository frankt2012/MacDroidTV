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

        if CommandLine.arguments.contains("--diagnose") {
            let store = SharedStore.shared
            let state = store.load()
            print("appGroup=\(store.isUsingAppGroup)")
            print("path=\(store.locationDescription)")
            print("exists=\(FileManager.default.fileExists(atPath: store.locationDescription))")
            print("devices=\(state.devices.count)")
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
