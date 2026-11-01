import Foundation

/// A shortcut to open an app on the TV. Android TV exposes a universal launcher
/// URI, `market://launch?id=<package>`, which opens any installed app without
/// depending on that app supporting a deep link.
public struct QuickApp: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let name: String
    /// Short monogram shown on compact buttons (SF Symbols have no brand logos).
    public let shortLabel: String
    public let link: String

    public init(id: String, name: String, shortLabel: String, link: String) {
        self.id = id
        self.name = name
        self.shortLabel = shortLabel
        self.link = link
    }

    /// Asset-catalog name for the app's logo, when one is bundled.
    public var logoName: String? {
        switch id {
        case "netflix", "youtube", "primevideo", "disneyplus", "max",
             "plex", "spotify", "appletv", "youtubetv":
            return "AppLogo_\(id)"
        default:
            return nil
        }
    }

    /// Turns a package name or a full URI into a launch link. Android TV's
    /// remote service rejects `market://launch` links, but accepts
    /// `android-app://<package>`, which resolves to the installed app.
    public static func launchLink(from input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("://") { return trimmed }
        return "android-app://\(trimmed)"
    }

    private static func app(_ id: String, _ name: String, _ label: String, _ link: String) -> QuickApp {
        QuickApp(id: id, name: name, shortLabel: label, link: link)
    }

    /// The services that show up as dedicated buttons on most Google TV
    /// remotes, plus the most-used installed apps.
    public static let common: [QuickApp] = [
        app("netflix", "Netflix", "N", "https://www.netflix.com/title"),
        app("youtube", "YouTube", "YT", "https://www.youtube.com"),
        app("primevideo", "Prime Video", "P", "https://app.primevideo.com"),
        app("disneyplus", "Disney+", "D+", "https://www.disneyplus.com"),
        app("max", "Max", "Max", "https://play.max.com"),
        app("plex", "Plex", "Plex", "plex://"),
        app("youtubetv", "YouTube TV", "YTTV", "https://tv.youtube.com"),
        app("spotify", "Spotify", "S", "spotify://"),
        app("appletv", "Apple TV", "TV", "https://tv.apple.com")
    ]

    /// The default selection when the user has not chosen anything yet.
    public static let featured: [QuickApp] = Array(common.prefix(6))
}
