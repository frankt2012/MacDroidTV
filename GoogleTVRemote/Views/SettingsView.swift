import ServiceManagement
import SwiftUI
import TVRemoteKit

struct SettingsView: View {
    @Bindable var model: AppModel
    var onFinish: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage("showPowerDot") private var showPowerDot = true
    @State private var customName = ""
    @State private var customLink = ""
    @State private var launchAtLogin = false
    @State private var launchAtLoginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Settings")
                        .font(.headline)

                    Toggle("Show menu bar control", isOn: $showMenuBarIcon)
                    Text("Turn this off to use the widget only. Reopen this window with the gear button on the widget.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Toggle("Show TV power dot in the menu bar", isOn: $showPowerDot)
                    Text("Green means the TV is on; red means it is off.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Launch at login", isOn: Binding(
                        get: { launchAtLogin },
                        set: { setLaunchAtLogin($0) }
                    ))
                    if let launchAtLoginError {
                        Text(launchAtLoginError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if SMAppService.mainApp.status == .requiresApproval {
                        Text("Approve MacDroid TV in System Settings → General → Login Items.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    Text("Quick apps")
                        .font(.subheadline.weight(.semibold))
                    Text("Choose which app buttons appear in the panel and widget. Up to 8 appear in the widget.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(model.allQuickApps) { app in
                        HStack(spacing: 10) {
                            QuickAppBadge(app: app, size: 22)
                                .frame(width: 30, height: 22)

                            Toggle(app.name, isOn: Binding(
                                get: { model.isQuickAppSelected(app.id) },
                                set: { model.setQuickApp(id: app.id, selected: $0) }
                            ))
                            .toggleStyle(.checkbox)

                            if app.id.hasPrefix("custom-") {
                                Button {
                                    model.removeCustomQuickApp(id: app.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help("Remove \(app.name)")
                            }
                        }
                    }

                    if model.selectedQuickApps.count > 1 {
                        Divider()
                        Text("Quick app order")
                            .font(.subheadline.weight(.semibold))
                        Text("Use the arrows to choose the order used in the widget and panel.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(model.selectedQuickApps) { app in
                            HStack(spacing: 10) {
                                QuickAppBadge(app: app, size: 22)
                                    .frame(width: 30, height: 22)
                                Text(app.name)
                                Spacer()
                                Button {
                                    model.moveQuickApp(id: app.id, up: true)
                                } label: {
                                    Image(systemName: "chevron.up")
                                }
                                .buttonStyle(.borderless)
                                .disabled(model.selectedQuickApps.first?.id == app.id)
                                Button {
                                    model.moveQuickApp(id: app.id, up: false)
                                } label: {
                                    Image(systemName: "chevron.down")
                                }
                                .buttonStyle(.borderless)
                                .disabled(model.selectedQuickApps.last?.id == app.id)
                            }
                        }
                    }

                    Divider()

                    Text("Add a custom app")
                        .font(.subheadline.weight(.semibold))
                    Text("Enter a package name (for example com.netflix.ninja) or a full app link.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    TextField("App name", text: $customName)
                        .textFieldStyle(.roundedBorder)
                    TextField("Package name or link", text: $customLink)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Spacer()
                        Button("Add App") {
                            model.addCustomQuickApp(name: customName, link: customLink)
                            customName = ""
                            customLink = ""
                        }
                        .disabled(
                            customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || customLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                    }
                }
                .padding(16)
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                    onFinish?()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 380, height: 560)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = enabled
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

}
