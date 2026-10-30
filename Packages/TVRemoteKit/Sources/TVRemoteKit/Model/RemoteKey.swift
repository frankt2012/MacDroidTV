import Foundation

/// Android key codes used by the remote protocol.
public enum RemoteKey: String, CaseIterable, Codable, Sendable {
    case power
    case up
    case down
    case left
    case right
    case select
    case back
    case home
    case menu
    case tv
    case info
    case settings
    case search
    case volumeUp
    case volumeDown
    case mute
    case playPause
    case next
    case previous
    case rewind
    case fastForward

    public var keyCode: UInt64 {
        switch self {
        case .power: return 26
        case .up: return 19
        case .down: return 20
        case .left: return 21
        case .right: return 22
        case .select: return 23
        case .back: return 4
        case .home: return 3
        case .menu: return 82
        case .tv: return 170
        case .info: return 165
        case .settings: return 176
        case .search: return 84
        case .volumeUp: return 24
        case .volumeDown: return 25
        case .mute: return 164
        case .playPause: return 85
        case .next: return 87
        case .previous: return 88
        case .rewind: return 89
        case .fastForward: return 90
        }
    }

    public var accessibilityLabel: String {
        switch self {
        case .power: return "Power"
        case .up: return "Up"
        case .down: return "Down"
        case .left: return "Left"
        case .right: return "Right"
        case .select: return "Select"
        case .back: return "Back"
        case .home: return "Home"
        case .menu: return "Menu"
        case .tv: return "Live TV"
        case .info: return "Info"
        case .settings: return "Settings"
        case .search: return "Search"
        case .volumeUp: return "Volume up"
        case .volumeDown: return "Volume down"
        case .mute: return "Mute"
        case .playPause: return "Play or pause"
        case .next: return "Next"
        case .previous: return "Previous"
        case .rewind: return "Rewind"
        case .fastForward: return "Fast forward"
        }
    }
}
