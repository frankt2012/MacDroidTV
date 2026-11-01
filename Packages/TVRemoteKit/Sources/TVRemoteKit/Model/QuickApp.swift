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

    /// Turns a package name or a full URI into a launch link.
    public static func launchLink(from input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("://") { return trimmed }
        return "market://launch?id=\(trimmed)"
    }

    private static func app(_ id: String, _ name: String, _ label: String, _ package: String) -> QuickApp {
        QuickApp(id: id, name: name, shortLabel: label, link: launchLink(from: package))
    }

    /// The services that show up as dedicated buttons on most Google TV
    /// remotes, plus the most-used installed apps.
    public static let common: [QuickApp] = [
        app("netflix", "Netflix", "N", "com.netflix.ninja"),
        app("youtube", "YouTube", "YT", "com.google.android.youtube.tv"),
        app("primevideo", "Prime Video", "P", "com.amazon.amazonvideo.livingroom"),
        app("disneyplus", "Disney+", "D+", "com.disney.disneyplus"),
        app("max", "Max", "Max", "com.wbd.stream"),
        app("plex", "Plex", "Plex", "com.plexapp.android"),
        app("youtubetv", "YouTube TV", "YTTV", "com.google.android.apps.youtube.unplugged"),
        app("spotify", "Spotify", "S", "com.spotify.tv.android"),
        app("appletv", "Apple TV", "TV", "com.apple.atve.androidtv.appletv")
    ]

    /// The default selection when the user has not chosen anything yet.
    public static let featured: [QuickApp] = Array(common.prefix(6))
}
