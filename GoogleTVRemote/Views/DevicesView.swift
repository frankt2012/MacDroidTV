import SwiftUI
import TVRemoteKit

struct DevicesView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var clientName = ""
    @State private var wakeMAC = ""
    @State private var showResetConfirmation = false
    @State private var showingWakeHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Devices")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            pairedDevices

            HStack {
                Button {
                    model.showingPairing = true
                } label: {
                    Label("Pair a TV…", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            }

            Divider()

            settings

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 480, height: 540)
        .onAppear {
            clientName = model.state.clientName
            wakeMAC = model.wakeMAC ?? ""
        }
        .sheet(isPresented: $model.showingPairing, onDismiss: {
            model.cancelPairing()
        }) {
            PairingSheet(model: model)
        }
        .sheet(isPresented: $showingWakeHelp) {
            WakeHelpView()
        }
    }

    @ViewBuilder
    private var pairedDevices: some View {
        if model.state.devices.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "tv.slash")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.secondary)
                Text("No paired TVs")
                    .font(.headline)
                Text("Pair a Google TV to get started.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.state.devices) { device in
                        deviceRow(device)
                    }
                }
            }
            .frame(maxHeight: 180)
        }
    }

    private func deviceRow(_ device: PairedDevice) -> some View {
        let isActive = model.state.activeDevice?.id == device.id

        return HStack(spacing: 10) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.body.weight(.medium))
                Text("\(device.host) · \(lastSeenText(device))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !isActive {
                Button("Use") {
                    model.select(device)
                }
                .controlSize(.small)
            }

            Button {
                model.forget(device)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
            .help("Forget this TV")
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(isActive ? 0.06 : 0.03))
        )
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Settings")
                .font(.headline)

            HStack(spacing: 8) {
                Text("Name on TV")
                TextField("Mac", text: $clientName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.setClientName(clientName) }
                Button("Save") {
                    model.setClientName(clientName)
                }
                .disabled(
                    clientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || clientName == model.state.clientName
                )
            }

            HStack {
                Text("Shared storage")
                Spacer()
                Text(model.isUsingAppGroup ? "App Group" : "Local fallback")
                    .foregroundStyle(model.isUsingAppGroup ? Color.green : Color.orange)
            }
            .font(.callout)

            Text(model.storageLocation)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            if let storageError = model.storageError {
                Text("Could not save shared state: \(storageError)")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !model.isUsingAppGroup {
                Text("The widget can only read state through the App Group container. This build fell back to Application Support, so the widget cannot see the app's state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Text("Wake-on-LAN MAC")
                TextField("AA:BB:CC:DD:EE:FF", text: $wakeMAC)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.setWakeMAC(wakeMAC) }
                Button("Save") {
                    model.setWakeMAC(wakeMAC)
                }
                .disabled(
                    wakeMAC.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                        == (model.wakeMAC ?? "")
                )
            }

            Text("Optional. Only helps if the TV keeps its network alive in standby; the power button then sends a magic packet before connecting.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("How to keep the TV reachable in standby…") {
                showingWakeHelp = true
            }
            .buttonStyle(.link)
            .font(.caption)

            HStack {
                Text("Pairing identity")
                Spacer()
                Text(model.state.identity == nil ? "Not created" : "Ready")
                    .foregroundStyle(model.state.identity == nil ? Color.secondary : Color.green)
            }
            .font(.callout)

            Button("Reset pairing identity…", role: .destructive) {
                showResetConfirmation = true
            }
            .confirmationDialog(
                "Reset pairing identity?",
                isPresented: $showResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset Identity and Forget TVs", role: .destructive) {
                    model.resetIdentity()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes the client certificate and every paired TV. You will need to pair again.")
            }
        }
    }

    private func lastSeenText(_ device: PairedDevice) -> String {
        guard let lastSeen = device.lastSeen else {
            return "not connected yet"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: lastSeen, relativeTo: Date())
    }
}
