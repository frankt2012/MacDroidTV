import AppKit
import SwiftUI

/// Handles widget links that open small utility windows. The menu bar app has
/// no normal window, so this is how the widget reaches calibration and
/// settings.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var syncWindow: NSWindow?
    private var settingsWindow: NSWindow?

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "googletvremote" {
            switch url.host {
            case "volume-sync":
                withModel { [weak self] model in self?.showVolumeSync(model) }
            case "settings":
                withModel { [weak self] _ in self?.showSettings() }
            default:
                break
            }
        }
    }

    /// Double-clicking the app while the menu bar control is hidden should
    /// bring settings back, otherwise there would be no way to re-enable it.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showSettings()
        }
        return true
    }

    private func withModel(_ action: @escaping (AppModel) -> Void) {
        if let model = AppModel.shared {
            action(model)
        } else {
            // The URL can arrive just before SwiftUI finishes creating the
            // model on a cold launch.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, let model = AppModel.shared else { return }
                action(model)
            }
        }
    }

    private func showVolumeSync(_ model: AppModel) {
        if let syncWindow {
            syncWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = makeWindow(
            title: "Sync Volume",
            size: NSSize(width: 300, height: 340),
            content: VolumeSyncView(model: model) { [weak self] in
                self?.syncWindow?.close()
            }
        )
        syncWindow = window
    }

    private func showSettings() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = makeWindow(
            title: "Settings",
            size: NSSize(width: 320, height: 220),
            content: SettingsView { [weak self] in
                self?.settingsWindow?.close()
            }
        )
        settingsWindow = window
    }

    private func makeWindow<Content: View>(
        title: String,
        size: NSSize,
        content: Content
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: content)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return window
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === syncWindow { syncWindow = nil }
        if window === settingsWindow { settingsWindow = nil }
    }
}
