import AppKit
import Foundation
import SwiftUI
import TVRemoteKit
import WidgetKit

struct TVRemoteEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct TVRemoteProvider: TimelineProvider {
    func placeholder(in context: Context) -> TVRemoteEntry {
        TVRemoteEntry(
            date: Date(),
            snapshot: WidgetSnapshot(
                isPaired: true,
                deviceName: "Living Room TV",
                isOn: true,
                volume: 24,
                volumeMax: 100,
                muted: false,
                updatedAt: Date()
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TVRemoteEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TVRemoteEntry>) -> Void) {
        let entry = makeEntry()
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date())
            ?? Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func makeEntry() -> TVRemoteEntry {
        SharedStore.shared.invalidateCache()
        return TVRemoteEntry(date: Date(), snapshot: WidgetSnapshot.load())
    }
}

struct TVRemoteWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TVRemoteEntry

    var body: some View {
        Group {
            if !entry.snapshot.isPaired {
                unpaired
            } else if family == .systemSmall {
                smallLayout
            } else {
                mediumLayout
            }
        }
        .containerBackground(for: .widget) {
            Color.clear
        }
    }

    // MARK: - Layouts

    private var smallLayout: some View {
        VStack(spacing: 5) {
            header(compact: true)

            HStack(spacing: 8) {
                dpad(buttonSize: 20)

                VStack(spacing: 4) {
                    key(.volumeUp, "speaker.plus", size: 20)
                    key(.mute, "speaker.slash", size: 20)
                    key(.volumeDown, "speaker.minus", size: 20)
                }
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 8) {
                key(.rewind, "backward.fill", size: 18)
                key(.playPause, "playpause.fill", size: 18)
                key(.fastForward, "forward.fill", size: 18)
            }

            HStack(spacing: 6) {
                key(.back, "arrow.uturn.backward", size: 18)
                key(.home, "house", size: 18)
                key(.settings, "gearshape", size: 18)
                Spacer(minLength: 0)
                syncLink(size: 18)
                Text(volumeText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var mediumLayout: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                header(compact: false)

                Spacer(minLength: 0)

                WidgetVolumeBar(fraction: volumeFraction)

                HStack(spacing: 6) {
                    key(.volumeDown, "speaker.minus", size: 24)
                    key(.mute, "speaker.slash", size: 24)
                    key(.volumeUp, "speaker.plus", size: 24)
                    Text(volumeText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    syncLink(size: 24)
                }

                HStack(spacing: 10) {
                    key(.rewind, "backward.fill", size: 22)
                    key(.playPause, "playpause.fill", size: 24)
                    key(.fastForward, "forward.fill", size: 22)
                }

                HStack(spacing: 4) {
                    ForEach(Array(entry.snapshot.quickApps.prefix(8))) { app in
                        appButton(app, size: 22)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 6) {
                dpad(buttonSize: 31)

                HStack(spacing: 6) {
                    key(.back, "arrow.uturn.backward", size: 22)
                    key(.home, "house", size: 22)
                    key(.menu, "list.bullet", size: 22)
                    key(.settings, "gearshape", size: 22)
                }
            }
        }
    }

    private var unpaired: some View {
        VStack(spacing: 7) {
            Image(systemName: "tv")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text("MacDroid TV")
                .font(.headline)
            Text("Open the menu bar app to pair a TV.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Pieces

    @ViewBuilder
    private var powerDot: some View {
        let name = entry.snapshot.isOn ? "PowerDotGreen" : "PowerDotRed"
        if #available(macOS 15.0, *) {
            Image(name)
                .resizable()
                .widgetAccentedRenderingMode(.fullColor)
                .frame(width: 7, height: 7)
        } else {
            Image(name)
                .resizable()
                .frame(width: 7, height: 7)
        }
    }

    private func header(compact: Bool) -> some View {
        HStack(spacing: 5) {
            powerDot

            Text(entry.snapshot.deviceName)
                .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                .lineLimit(1)

            Spacer(minLength: 2)

            refreshButton(size: compact ? 16 : 18)
            settingsLink(size: compact ? 16 : 18)

            Button(intent: RemoteKeyIntent(key: .power)) {
                Image(systemName: "power")
                    .font(.system(size: (compact ? 20 : 24) * 0.42, weight: .bold))
                    .frame(width: compact ? 20 : 24, height: compact ? 20 : 24)
                    .background(
                        Circle().fill(
                            entry.snapshot.isOn
                                ? Color.red.opacity(0.18)
                                : Color.primary.opacity(0.08)
                        )
                    )
                    .foregroundStyle(entry.snapshot.isOn ? Color.red : Color.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func dpad(buttonSize: CGFloat) -> some View {
        VStack(spacing: 3) {
            key(.up, "chevron.up", size: buttonSize)
            HStack(spacing: 3) {
                key(.left, "chevron.left", size: buttonSize)
                Button(intent: RemoteKeyIntent(key: .select)) {
                    Text("OK")
                        .font(.system(size: buttonSize * 0.30, weight: .bold))
                        .frame(width: buttonSize, height: buttonSize)
                        .background(Circle().fill(Color.accentColor.opacity(0.20)))
                }
                .buttonStyle(.plain)
                key(.right, "chevron.right", size: buttonSize)
            }
            key(.down, "chevron.down", size: buttonSize)
        }
    }

    private func key(_ key: RemoteKey, _ symbol: String, size: CGFloat) -> some View {
        Button(intent: RemoteKeyIntent(key: key)) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.44, weight: .semibold))
                .frame(width: size, height: size)
                .background(Circle().fill(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    /// Opens the menu bar app's volume calibration window.
    private func syncLink(size: CGFloat) -> some View {
        Link(destination: URL(string: "googletvremote://volume-sync")!) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: size * 0.40, weight: .semibold))
                .frame(width: size, height: size)
                .background(Circle().fill(Color.primary.opacity(0.08)))
        }
        .help("Sync volume")
    }

    /// Opens a streaming app through its Android TV deep link.
    private func appButton(_ app: QuickApp, size: CGFloat) -> some View {
        Button(intent: RemoteAppLinkIntent(link: app.link, appName: app.name)) {
            QuickAppBadge(app: app, size: size)
        }
        .buttonStyle(.plain)
        .help("Open \(app.name)")
    }

    /// Opens the app's settings window.
    /// Re-reads the TV's power and volume state.
    private func refreshButton(size: CGFloat) -> some View {
        Button(intent: RefreshTVStateIntent()) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: size * 0.55, weight: .semibold))
                .frame(width: size, height: size)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Refresh TV status")
    }

    private func settingsLink(size: CGFloat) -> some View {
        Link(destination: URL(string: "googletvremote://settings")!) {
            Image(systemName: "gearshape.2")
                .font(.system(size: size * 0.55, weight: .semibold))
                .frame(width: size, height: size)
                .foregroundStyle(.secondary)
        }
        .help("App settings")
    }

    // MARK: - Derived state

    private var volumeText: String {
        if entry.snapshot.muted { return "Muted" }
        guard let volume = entry.snapshot.volume,
              let max = entry.snapshot.volumeMax,
              max > 0 else { return "—" }
        return entry.snapshot.volumeEstimated ? "≈\(volume)" : "\(volume)"
    }

    private var statusText: String {
        let power = entry.snapshot.isOn ? "On" : "Standby"
        if entry.snapshot.muted { return "\(power) · Muted" }
        if let volume = entry.snapshot.volume,
           let max = entry.snapshot.volumeMax,
           max > 0 {
            let prefix = entry.snapshot.volumeEstimated ? "Volume ≈" : "Volume"
            return "\(power) · \(prefix)\(volume)"
        }
        return power
    }

    private var volumeFraction: Double {
        guard let level = entry.snapshot.volume,
              let maxVolume = entry.snapshot.volumeMax,
              maxVolume > 0 else { return 0 }
        return Swift.min(Swift.max(Double(level) / Double(maxVolume), 0), 1)
    }
}

private struct WidgetVolumeBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 5)
    }
}

struct TVRemoteWidget: Widget {
    let kind = "TVRemoteWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TVRemoteProvider()) { entry in
            TVRemoteWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("MacDroid TV")
        .description("Control your Google TV and see its power and volume.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct TVRemoteWidgetBundle: WidgetBundle {
    var body: some Widget {
        TVRemoteWidget()
    }
}
