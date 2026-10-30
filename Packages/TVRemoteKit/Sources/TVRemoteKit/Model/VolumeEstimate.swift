import Foundation

/// Local volume estimate used when the TV does not report a volume scale.
///
/// Some TVs (including several TCL models) answer `RemoteSetVolumeLevel` with
/// `volume_max = 0` and `volume_level = 0` no matter what the actual speaker
/// volume is. In that case the remote can still move a bar locally so the
/// buttons feel responsive, but the value is approximate and must be labelled
/// as such in the UI. A real value from the TV always replaces the estimate.
public enum VolumeEstimate {
    public static let defaultMax = 100

    /// Applies a key press to the cached volume. Returns `true` when the cache
    /// changed.
    @discardableResult
    public static func apply(_ key: RemoteKey, to cache: inout CachedTVState) -> Bool {
        switch key {
        case .volumeUp, .volumeDown:
            let maxVolume: Int
            if let existing = cache.volumeMax, existing > 0 {
                maxVolume = existing
            } else {
                maxVolume = defaultMax
                cache.volumeMax = maxVolume
            }

            let current = cache.volume ?? maxVolume / 2
            let step = Swift.max(1, maxVolume / 50)
            let delta = key == .volumeUp ? step : -step
            cache.volume = Swift.min(Swift.max(current + delta, 0), maxVolume)
            cache.volumeEstimated = true
            return true

        case .mute:
            cache.muted.toggle()
            cache.volumeEstimated = true
            return true

        default:
            return false
        }
    }
}
