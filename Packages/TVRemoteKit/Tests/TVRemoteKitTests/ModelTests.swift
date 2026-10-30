import XCTest
@testable import TVRemoteKit

final class ModelTests: XCTestCase {
    func testCachedStateDecodesStateWrittenByOlderBuild() throws {
        // Older builds did not write volumeEstimated. Missing optional keys must
        // decode as nil instead of failing the whole state file.
        let json = #"{"isOn":true,"volume":10,"volumeMax":100,"muted":false}"#
        let state = try JSONDecoder().decode(CachedTVState.self, from: Data(json.utf8))

        XCTAssertTrue(state.isOn)
        XCTAssertEqual(state.volume, 10)
        XCTAssertEqual(state.volumeMax, 100)
        XCTAssertNil(state.volumeEstimated)
        XCTAssertNil(state.volumeStep)
    }

    func testCachedStateRoundTripsEstimatedVolume() throws {
        let state = CachedTVState(
            isOn: true,
            volume: 52,
            volumeMax: 100,
            muted: false,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            volumeEstimated: true
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(CachedTVState.self, from: data)

        XCTAssertEqual(decoded, state)
    }

    func testWidgetSnapshotCarriesEstimatedFlag() {
        let state = RemoteState(
            cache: CachedTVState(volume: 52, volumeMax: 100, volumeEstimated: true)
        )
        let snapshot = WidgetSnapshot(
            isPaired: true,
            deviceName: "TV",
            isOn: state.cache.isOn,
            volume: state.cache.volume,
            volumeMax: state.cache.volumeMax,
            muted: state.cache.muted,
            updatedAt: state.cache.updatedAt,
            volumeEstimated: state.cache.volumeEstimated ?? false
        )

        XCTAssertTrue(snapshot.volumeEstimated)
        XCTAssertEqual(snapshot.volume, 52)
    }

    func testVolumeEstimateStartsInTheMiddleAndMoves() {
        var cache = CachedTVState()

        XCTAssertTrue(VolumeEstimate.apply(.volumeUp, to: &cache))
        XCTAssertEqual(cache.volumeMax, 100)
        XCTAssertEqual(cache.volume, 52)
        XCTAssertEqual(cache.volumeEstimated, true)

        VolumeEstimate.apply(.volumeDown, to: &cache)
        XCTAssertEqual(cache.volume, 50)
    }

    func testVolumeEstimateClampsAtBounds() {
        var cache = CachedTVState(volume: 100, volumeMax: 100)

        VolumeEstimate.apply(.volumeUp, to: &cache)
        XCTAssertEqual(cache.volume, 100)

        cache.volume = 0
        VolumeEstimate.apply(.volumeDown, to: &cache)
        XCTAssertEqual(cache.volume, 0)
    }

    func testVolumeEstimateIgnoresNonVolumeKeys() {
        var cache = CachedTVState()

        XCTAssertFalse(VolumeEstimate.apply(.home, to: &cache))
        XCTAssertNil(cache.volume)
        XCTAssertNil(cache.volumeMax)
    }

    func testVolumeEstimateTogglesMute() {
        var cache = CachedTVState()

        VolumeEstimate.apply(.mute, to: &cache)
        XCTAssertTrue(cache.muted)
        XCTAssertEqual(cache.volumeEstimated, true)

        VolumeEstimate.apply(.mute, to: &cache)
        XCTAssertFalse(cache.muted)
    }

    func testVolumeEstimateUsesCalibratedStep() {
        var cache = CachedTVState(volume: 50, volumeMax: 100, volumeStep: 5)

        VolumeEstimate.apply(.volumeUp, to: &cache)
        XCTAssertEqual(cache.volume, 55)
        XCTAssertEqual(cache.volumeStep, 5)
    }

    func testVolumeEstimateSyncBaselinesAndClamps() {
        var cache = CachedTVState()

        VolumeEstimate.sync(level: 200, step: 0, to: &cache)
        XCTAssertEqual(cache.volume, 100)
        XCTAssertEqual(cache.volumeMax, 100)
        XCTAssertEqual(cache.volumeStep, 1)
        XCTAssertEqual(cache.volumeEstimated, true)

        var cache2 = CachedTVState(volume: 10, volumeMax: 80)
        VolumeEstimate.sync(level: 50, step: 3, to: &cache2)
        XCTAssertEqual(cache2.volume, 50)
        XCTAssertEqual(cache2.volumeMax, 80)
        XCTAssertEqual(cache2.volumeStep, 3)
    }
}
