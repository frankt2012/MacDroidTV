import SwiftUI
import TVRemoteKit

struct SettingsView: View {
    @Bindable var model: AppModel
    var onFinish: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
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

                    Divider()

                    Text("Quick apps")
                        .font(.subheadline.weight(.semibold))
                    Text("Choose which app buttons appear in the panel and widget. Up to 8 appear in the widget.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(model.allQuickApps) { app in
                        HStack(spacing: 10) {
                            Group {
                                if let logo = app.logoName {
                                    Image(logo)
                                        .resizable()
                                        .interpolation(.high)
                                        .scaledToFit()
                                        .frame(width: 22, height: 22)
                                        .clipShape(RoundedRectangle(cornerRadius: 5))
                                } else {
                                    Text(app.shortLabel)
                                        .font(.system(size: 10, weight: .bold))
                                        .frame(width: 30, height: 22)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(appTint(app).opacity(0.18))
                                        )
                                        .foregroundStyle(appTint(app))
                                }
                            }
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

    private func appTint(_ app: QuickApp) -> Color {
        switch app.id {
        case "netflix", "youtube", "youtubetv": return .red
        case "primevideo", "disneyplus": return .blue
        case "hulu": return .green
        case "max": return .purple
        case "plex": return .orange
        case "spotify": return Color(red: 0.1, green: 0.7, blue: 0.3)
        default: return .gray
        }
    }
}
