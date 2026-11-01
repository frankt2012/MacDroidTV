import AppKit
import SwiftUI
import TVRemoteKit

/// Handles widget links that open small utility windows. The menu bar app has
/// no normal window, so this is how the widget reaches calibration and
/// settings.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var syncWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var defaultsObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
    }

    /// SwiftUI's MenuBarExtra proved unreliable on cold launch, so the status
    /// item is owned directly. The popover hosts the same remote panel.
    private func setupStatusItem() {
        guard let model = AppModel.shared else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.setupStatusItem()
            }
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = makeStatusImage(filled: false)
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(togglePopover(_:))
        }

        let hosting = NSHostingController(rootView: RemotePanelView(model: model))
        hosting.view.layoutSubtreeIfNeeded()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = hosting
        let fitting = hosting.view.fittingSize
        popover.contentSize = fitting.width > 0 && fitting.height > 0
            ? fitting
            : NSSize(width: 340, height: 620)

        statusItem = item
        self.popover = popover

        applyMenuBarVisibility()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyMenuBarVisibility()
        }
    }

    private func applyMenuBarVisibility() {
        let visible = UserDefaults.standard.object(forKey: "showMenuBarIcon") as? Bool ?? true
        statusItem?.isVisible = visible
    }

    /// Render the `av.remote` symbol into a bitmap-backed template image.
    /// A plain `NSImage(systemSymbolName:)` did not paint in the status item.
    private func makeStatusImage(filled: Bool) -> NSImage {
        // macOS will not paint `av.remote` (or a custom bitmap of it) in a
        // status item; the app icon is a remote and renders reliably.
        if let icon = NSImage(named: NSImage.applicationIconName) {
            icon.size = NSSize(width: 22, height: 22)
            icon.isTemplate = false
            return icon
        }
        let image = NSImage(systemSymbolName: "mediastick", accessibilityDescription: "Google TV Remote")!
        image.size = NSSize(width: 22, height: 22)
        image.isTemplate = true
        return image
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let statusItem, let button = statusItem.button, let popover else { return }

        if popover.isShown {
            popover.performClose(sender)
            return
        }

        if let model = AppModel.shared {
            button.image = makeStatusImage(filled: model.isConnected)
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Widget-only mode hides the status item; the app must stay alive so
        // the widget can keep using its connection.
        false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "googletvremote" {
            switch url.host {
            case "volume-sync":
                withModel { [weak self] model in self?.showVolumeSync(model) }
            case "settings":
                withModel { [weak self] model in self?.showSettings(model: model) }
            case "panel":
                withModel { [weak self] _ in self?.togglePopover(nil) }
            default:
                break
            }
        }
    }

    /// Double-clicking the app while the menu bar control is hidden should
    /// bring settings back, otherwise there would be no way to re-enable it.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, let model = AppModel.shared {
            showSettings(model: model)
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

    private func showSettings(model: AppModel) {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = makeWindow(
            title: "Settings",
            size: NSSize(width: 380, height: 600),
            content: SettingsView(model: model) { [weak self] in
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
