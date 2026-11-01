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
    }

}
