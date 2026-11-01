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
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.18), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
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
                key(.back, "arrow.uturn.backward", size: 20)
                key(.home, "house", size: 20)
                Spacer(minLength: 0)
                syncLink(size: 20)
                Text(volumeText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var mediumLayout: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                header(compact: false)

                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

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
                    key(.back, "arrow.uturn.backward", size: 24)
                    key(.home, "house", size: 24)
                    key(.menu, "list.bullet", size: 24)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            dpad(buttonSize: 31)
        }
    }

    private var unpaired: some View {
        VStack(spacing: 7) {
            Image(systemName: "tv")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text("Google TV Remote")
                .font(.headline)
            Text("Open the menu bar app to pair a TV.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Pieces

    private func header(compact: Bool) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(entry.snapshot.isOn ? Color.green : Color.secondary)
                .frame(width: 6, height: 6)

            Text(entry.snapshot.deviceName)
                .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                .lineLimit(1)

            Spacer(minLength: 2)

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
        .configurationDisplayName("Google TV Remote")
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
