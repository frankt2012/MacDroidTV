import SwiftUI
import TVRemoteKit

struct PairingSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var manualHost = ""
    @State private var code = ""
    @FocusState private var codeFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title)
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Cancel") {
                    model.cancelPairing()
                    model.showingPairing = false
                    dismiss()
                }
            }

            if let error = model.pairingError {
                InlineErrorBanner(message: error) {
                    model.clearError()
                }
            }

            switch model.pairingStage {
            case .idle:
                discovery
            case .starting:
                starting
            case .enterCode, .finishing:
                codeEntry
            }
        }
        .padding(20)
        .frame(width: 440, height: 440)
        .onDisappear {
            if model.pairingStage != .idle {
                model.cancelPairing()
            }
        }
    }

    private var title: String {
        switch model.pairingStage {
        case .enterCode, .finishing:
            return "Enter the TV code"
        default:
            return "Pair a TV"
        }
    }

    // MARK: - Discovery

    private var discovery: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose a TV on your network, or enter its IP address.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if model.discovered.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking for Google TVs…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(model.discovered) { device in
                            HStack(spacing: 10) {
                                Image(systemName: "tv")
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(device.name)
                                    if let host = device.host {
                                        Text(host)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Button("Pair") {
                                    model.pair(with: device)
                                }
                                .controlSize(.small)
                                .buttonStyle(.borderedProminent)
                            }
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.primary.opacity(0.04))
                            )
                        }
                    }
                }
                .frame(maxHeight: 190)
            }

            Divider()

            Text("Add manually")
                .font(.headline)

            HStack(spacing: 8) {
                TextField("192.168.1.50", text: $manualHost)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(pairManually)
                Button("Pair", action: pairManually)
                    .buttonStyle(.borderedProminent)
                    .disabled(manualHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Text("The TV must be on and connected to the same network as this Mac. Keep the TV remote handy to confirm the pairing request.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func pairManually() {
        let host = manualHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return }
        model.pairManually(host: host)
    }

    // MARK: - Starting

    private var starting: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Connecting to the TV…")
                .font(.headline)
            Text("Accept the pairing request on your TV if it appears.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Code entry

    private var codeEntry: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your TV is showing a six-character code. Type it below.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("A1B2C3", text: $code)
                .textFieldStyle(.roundedBorder)
                .font(.system(.title2, design: .monospaced))
                .focused($codeFocused)
                .onSubmit(submit)
                .onChange(of: code) { _, newValue in
                    let filtered = String(
                        newValue
                            .uppercased()
                            .filter { $0.isHexDigit }
                            .prefix(6)
                    )
                    if filtered != newValue {
                        code = filtered
                    }
                }

            HStack {
                Text("Characters are 0–9 and A–F.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Pair") {
                    submit()
                }
                .buttonStyle(.borderedProminent)
                .disabled(code.count != 6 || model.pairingStage == .finishing)
            }

            if model.pairingStage == .finishing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking the code…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .onAppear {
            codeFocused = true
        }
    }

    private func submit() {
        guard code.count == 6 else { return }
        model.finishPairing(code: code)
    }
}
