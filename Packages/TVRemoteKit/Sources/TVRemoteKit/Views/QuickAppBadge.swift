import SwiftUI
import WidgetKit

/// Draws a quick-app button. The built-in services use their bundled logos;
/// Max and YouTube TV are drawn as vectors so they stay crisp and have no
/// baked-in border, and custom apps fall back to a tinted monogram.
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
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
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
        Text(app.shortLabel)
            .font(.system(size: size * 0.38, weight: .bold))
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.28)
                    .fill(tint.opacity(0.18))
            )
            .foregroundStyle(tint)
    }

    private var tint: Color {
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
