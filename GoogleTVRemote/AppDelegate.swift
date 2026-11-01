import AppKit
import SwiftUI

/// Handles the widget's `googletvremote://volume-sync` link by opening a small
/// sync window. The menu bar app has no normal window, so this is the only way
/// to bring the calibration UI up from the widget.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var syncWindow: NSWindow?

    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: {
            $0.scheme == "googletvremote" && $0.host == "volume-sync"
        }) else { return }

        if AppModel.shared == nil {
            // The URL can arrive just before SwiftUI finishes creating the
            // model on a cold launch.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showVolumeSync()
            }
        } else {
            showVolumeSync()
        }
    }

    private func showVolumeSync() {
        guard let model = AppModel.shared else { return }

        if let syncWindow {
            syncWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sync Volume"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: VolumeSyncView(model: model) { [weak self] in
                self?.syncWindow?.close()
            }
        )
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        syncWindow = window
    }

    func windowWillClose(_ notification: Notification) {
        syncWindow = nil
    }
}
