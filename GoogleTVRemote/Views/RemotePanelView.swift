import AppKit
import SwiftUI
import TVRemoteKit

struct RemotePanelView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            header

            if let error = model.lastError {
                InlineErrorBanner(message: error) {
                    model.clearError()
                }
            }

            if model.isPaired {
                controls
            } else {
                emptyState
            }

            footer
        }
        .padding(14)
        .frame(width: 340)
        .sheet(isPresented: $model.showingDevices) {
            DevicesView(model: model)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(model.deviceName)
                    .font(.headline)
                    .lineLimit(1)
                Text(model.statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 6)

            Menu {
                if model.state.devices.isEmpty {
                    Text("No paired TVs")
                } else {
                    ForEach(model.state.devices) { device in
                        Button {
                            model.select(device)
                        } label: {
                            if device.id == model.activeDevice?.id {
                                Label(device.name, systemImage: "checkmark")
                            } else {
                                Text(device.name)
                            }
                        }
                    }
                }
                Divider()
                Button("Manage Devices…") {
                    model.showingDevices = true
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Choose a TV")

            Button {
                model.togglePower()
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 28, height: 28)
                    .background(
                        Circle().fill(
                            model.isOn
                                ? Color.red.opacity(0.16)
                                : Color.primary.opacity(0.08)
                        )
                    )
                    .foregroundStyle(model.isOn ? Color.red : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(!model.isPaired)
            .help("Power")
        }
    }

    private var statusColor: Color {
        switch model.statusColor {
        case .gray: return .secondary
        case .green: return .green
        case .orange: return .orange
        case .red: return .red
        }
    }

    // MARK: - Remote

    private var controls: some View {
        VStack(spacing: 12) {
            navigationRow
            dpad
            volumeRow
            mediaRow
        }
    }

    private var navigationRow: some View {
        HStack(spacing: 10) {
            keyButton(.back, "arrow.uturn.backward")
            keyButton(.home, "house")
            keyButton(.menu, "list.bullet")
            keyButton(.tv, "tv")
            keyButton(.settings, "gearshape")
        }
    }

    private var dpad: some View {
        ZStack {
            Circle()
                .fill(Color.primary.opacity(0.045))
                .frame(width: 198, height: 198)

            VStack(spacing: 4) {
                keyButton(.up, "chevron.up", size: 46)

                HStack(spacing: 4) {
                    keyButton(.left, "chevron.left", size: 46)
                    selectButton
                    keyButton(.right, "chevron.right", size: 46)
                }

                keyButton(.down, "chevron.down", size: 46)
            }
        }
    }

    private var selectButton: some View {
        Button {
            model.send(.select)
        } label: {
            Text("OK")
                .font(.system(size: 15, weight: .bold))
                .frame(width: 58, height: 58)
                .background(Circle().fill(Color.accentColor.opacity(0.16)))
                .overlay(
                    Circle()
                        .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Select")
    }

    private var volumeRow: some View {
        HStack(spacing: 10) {
            keyButton(.volumeDown, "speaker.minus", size: 34)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(model.volumeText)
                        .font(.caption)
                    Spacer()
                    if model.isVolumeEstimated {
                        Text("estimated")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if let level = model.state.cache.volume,
                              let max = model.state.cache.volumeMax,
                              max > 0 {
                        Text("\(level) / \(max)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                VolumeBar(fraction: model.volumeFraction)
            }

            keyButton(.volumeUp, "speaker.plus", size: 34)
            keyButton(.mute, "speaker.slash", size: 34)
        }
        .padding(.horizontal, 4)
    }

    private var mediaRow: some View {
        HStack(spacing: 18) {
            keyButton(.previous, "backward.end", size: 34)
            keyButton(.rewind, "backward", size: 34)
            keyButton(.playPause, "playpause", size: 40)
            keyButton(.fastForward, "forward", size: 34)
            keyButton(.next, "forward.end", size: 34)
        }
    }

    private func keyButton(_ key: RemoteKey, _ symbol: String, size: CGFloat = 36) -> some View {
        RemoteKeyButton(key: key, systemImage: symbol, size: size) {
            model.send(key)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tv")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text("No TV paired yet")
                .font(.headline)
            Text("Pair with your Google TV to use the remote from the menu bar and the widget.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Pair a TV…") {
                model.showingDevices = true
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 2)
        }
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 14) {
            Button {
                model.showingDevices = true
            } label: {
                Label("Devices", systemImage: "tv")
            }

            Button {
                model.refresh()
            } label: {
                if model.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .disabled(!model.isPaired || model.isRefreshing)
            .help("Refresh TV status")

            Spacer()

            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
