import SwiftUI

/// A square app shortcut tile used by the menu bar panel, the widget, and the
/// settings list.
public struct QuickAppBadge: View {
    public let app: QuickApp
    public let size: CGFloat

    public init(app: QuickApp, size: CGFloat) {
        self.app = app
        self.size = size
    }

    public var body: some View {
        Group {
            if let logo = app.logoName {
                logoImage(logo)
            } else {
                monogram
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        // A hairline edge keeps light logos (and dark ones) from disappearing
        // into wallpapers and the panel's translucent background.
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.18), lineWidth: max(0.5, size * 0.02))
        )
    }

    /// Widgets switch to an accented/monochrome mode while the desktop is
    /// active; keep the brand logos in full color.
    @ViewBuilder
    private func logoImage(_ name: String) -> some View {
        if #available(macOS 15.0, *) {
            Image(name)
                .resizable()
                .interpolation(.high)
                .widgetAccentedRenderingMode(.fullColor)
                .scaledToFit()
        } else {
            Image(name)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        }
    }

    private var monogram: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(monogramColor)
            Text(app.shortLabel)
                .font(.system(size: size * 0.40, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.45)
                .lineLimit(1)
                .padding(size * 0.08)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 0.5, y: 0.5)
        }
    }

    /// Known services keep a brand color; custom shortcuts get a stable color
    /// picked from their name, so every monogram is a solid tile with white
    /// text instead of a translucent gray that vanishes on some backgrounds.
    private var monogramColor: Color {
        switch app.id {
        case "netflix", "youtube", "youtubetv":
            return Color(red: 0.80, green: 0.04, blue: 0.10)
        case "primevideo":
            return Color(red: 0.00, green: 0.42, blue: 0.82)
        case "disneyplus":
            return Color(red: 0.08, green: 0.22, blue: 0.72)
        case "hulu":
            return Color(red: 0.08, green: 0.62, blue: 0.28)
        case "max":
            return Color(red: 0.34, green: 0.10, blue: 0.72)
        case "plex":
            return Color(red: 0.88, green: 0.47, blue: 0.03)
        case "spotify":
            return Color(red: 0.06, green: 0.62, blue: 0.28)
        case "appletv":
            return Color(red: 0.16, green: 0.17, blue: 0.19)
        default:
            let palette: [Color] = [
                Color(red: 0.16, green: 0.42, blue: 0.86),
                Color(red: 0.72, green: 0.16, blue: 0.22),
                Color(red: 0.10, green: 0.55, blue: 0.36),
                Color(red: 0.47, green: 0.26, blue: 0.78),
                Color(red: 0.85, green: 0.43, blue: 0.08),
                Color(red: 0.05, green: 0.55, blue: 0.62),
                Color(red: 0.78, green: 0.20, blue: 0.52),
                Color(red: 0.22, green: 0.28, blue: 0.65)
            ]
            let key = (app.name.isEmpty ? app.id : app.name).lowercased()
            let value = key.unicodeScalars.reduce(0) {
                (($0 &* 31) &+ Int($1.value)) & 0x7fff_ffff
            }
            return palette[value % palette.count]
        }
    }
}
