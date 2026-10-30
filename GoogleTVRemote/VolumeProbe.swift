import Foundation
import TVRemoteKit

/// Developer-only probe used to learn how a particular TV reports volume.
///
/// Run the app binary directly:
///
///     GoogleTVRemote.app/Contents/MacOS/GoogleTVRemote --volume-probe
///
/// It connects with the saved pairing, presses volume up/down and mute, and
/// prints every protocol frame the TV sends. The net effect on the TV is zero
/// (three up, three down, mute twice).
enum VolumeProbe {
    static func run() async {
        let store = SharedStore.shared
        let state = store.load()

        func report(_ line: String) {
            print(line)
            store.appendDebugLog(line)
        }

        guard let device = state.activeDevice, let identity = state.identity else {
            report("not paired")
            return
        }

        let host = ProcessInfo.processInfo.environment["TV_PROBE_HOST"] ?? device.host
        report("device=\(device.name) host=\(host)")
        report("--- volume probe \(device.name) host=\(host) ---")

        let connection = TVConnection(
            device: PairedDevice(
                id: device.id,
                name: device.name,
                host: host,
                port: device.port,
                serverCertificate: device.serverCertificate,
                lastSeen: device.lastSeen
            ),
            identity: identity,
            onEvent: { event in
                print("event=\(event)")
                SharedStore.shared.appendDebugLog("event=\(event)")
            },
            debugLog: { line in
                print(line)
                SharedStore.shared.appendDebugLog(line)
            }
        )

        do {
            try await connection.connect()
            let initial = await connection.volumeInfo
            let isOn = await connection.isOn
            report("connected isOn=\(isOn) volume=\(String(describing: initial))")

            let keys: [RemoteKey] = [
                .volumeUp, .volumeUp, .volumeUp,
                .volumeDown, .volumeDown, .volumeDown,
                .mute, .mute,
            ]

            for key in keys {
                report("--- sending \(key.rawValue) ---")
                try await connection.sendKey(key)
                try await Task.sleep(nanoseconds: 1_500_000_000)
                let volume = await connection.volumeInfo
                report("after \(key.rawValue): volume=\(String(describing: volume))")
            }

            await connection.disconnect()
            report("--- volume probe done ---")
        } catch {
            report("error=\(error)")
        }
    }
}
