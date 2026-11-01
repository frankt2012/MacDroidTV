import Foundation

/// A shortcut to open a streaming app on the TV through an Android TV app
/// link. The links are the deep links Android TV apps register for; the TV
/// routes them to the matching app instead of a browser.
public struct QuickApp: Identifiable, Hashable, Sendable {
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

    /// The services that show up as dedicated buttons on most Google TV
    /// remotes, plus the most-used installed apps.
    public static let common: [QuickApp] = [
        QuickApp(id: "netflix", name: "Netflix", shortLabel: "N", link: "https://www.netflix.com/title"),
        QuickApp(id: "youtube", name: "YouTube", shortLabel: "YT", link: "https://www.youtube.com"),
        QuickApp(id: "primevideo", name: "Prime Video", shortLabel: "P", link: "https://app.primevideo.com"),
        QuickApp(id: "disneyplus", name: "Disney+", shortLabel: "D+", link: "https://www.disneyplus.com"),
        QuickApp(id: "hulu", name: "Hulu", shortLabel: "H", link: "https://www.hulu.com"),
        QuickApp(id: "max", name: "Max", shortLabel: "Max", link: "https://www.max.com"),
        QuickApp(id: "plex", name: "Plex", shortLabel: "Plex", link: "plex://"),
        QuickApp(id: "youtubetv", name: "YouTube TV", shortLabel: "YTTV", link: "https://tv.youtube.com"),
        QuickApp(id: "spotify", name: "Spotify", shortLabel: "S", link: "https://open.spotify.com"),
        QuickApp(id: "appletv", name: "Apple TV", shortLabel: "TV", link: "https://tv.apple.com")
    ]

    /// A few apps that fit comfortably in the remote widget/panel.
    public static let featured: [QuickApp] = Array(common.prefix(6))
}
