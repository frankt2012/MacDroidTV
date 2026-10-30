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

        if CommandLine.arguments.contains("--diagnose") {
            let store = SharedStore.shared
            let state = store.load()
            print("appGroup=\(store.isUsingAppGroup)")
            print("path=\(store.locationDescription)")
            print("exists=\(FileManager.default.fileExists(atPath: store.locationDescription))")
            print("devices=\(state.devices.count)")
            print("identity=\(state.identity != nil)")
            print("clientName=\(state.clientName)")
            print("lastSaveError=\(store.lastSaveError ?? "nil")")
            print("hostName=\(Host.current().localizedName ?? "nil")")
            // Never print the state file itself: it contains the pairing private key.
            exit(0)
        }

        _model = State(initialValue: AppModel())
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
