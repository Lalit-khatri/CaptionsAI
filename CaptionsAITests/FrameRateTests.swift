@testable import CaptionsAI
import AVFoundation
import XCTest

/// What frame rate an export comes out at.
///
/// The defect: `composition.frameDuration` was `CMTime(value: 1, timescale: 30)`
/// whatever went in. A 60 fps clip came back at half its smoothness — every
/// other frame thrown away — and 24 fps film was resampled onto a 30 fps grid,
/// which is judder you can see on any pan.
///
/// The end-to-end test builds a composition from a real fixture, because
/// arithmetic the renderer does not use is worth nothing.
final class FrameRateTests: XCTestCase {
    private func duration(min: CMTime, nominal: Float) -> CMTime {
        CaptionRenderer.frameDuration(minFrameDuration: min, nominalFrameRate: nominal)
    }

    // MARK: - The source decides

    func testASixtyFrameSourceStaysAtSixty() {
        let result = duration(min: CMTime(value: 1, timescale: 60), nominal: 60)

        XCTAssertEqual(result.seconds, 1.0 / 60, accuracy: 1e-9)
    }

    func testTwentyFourFrameFilmStaysAtTwentyFour() {
        let result = duration(min: CMTime(value: 1, timescale: 24), nominal: 24)

        XCTAssertEqual(result.seconds, 1.0 / 24, accuracy: 1e-9)
    }

    /// NTSC is 30000/1001, not 30. Rounding it to 30 drifts a frame every
    /// thousand, which is why the exact value is preferred over the float.
    func testAnNtscSourceKeepsItsExactRate() {
        let ntsc = CMTime(value: 1001, timescale: 30000)

        XCTAssertEqual(duration(min: ntsc, nominal: 29.97), ntsc)
    }

    // MARK: - Sources that will not say

    func testAnUnknownRateFallsBackToThirty() {
        XCTAssertEqual(duration(min: .invalid, nominal: 0), CMTime(value: 1, timescale: 30))
        XCTAssertEqual(duration(min: .zero, nominal: 0), CMTime(value: 1, timescale: 30))
        XCTAssertEqual(duration(min: .indefinite, nominal: 0), CMTime(value: 1, timescale: 30))
        XCTAssertEqual(duration(min: .invalid, nominal: .nan), CMTime(value: 1, timescale: 30))
    }

    func testTheNominalRateIsUsedWhenThereIsNoFrameDuration() {
        XCTAssertEqual(duration(min: .invalid, nominal: 50), CMTime(value: 1, timescale: 50))
    }

    func testAnAbsurdRateIsClamped() {
        let result = duration(min: .invalid, nominal: 100_000)

        XCTAssertEqual(result, CMTime(value: 1, timescale: 240))
    }

    func testAMissingTrackFallsBackToThirty() async throws {
        let result = try await CaptionRenderer.frameDuration(of: nil)

        XCTAssertEqual(result, CMTime(value: 1, timescale: 30))
    }

    // MARK: - The renderer actually uses it

    func testACompositionTakesItsRateFromTheVideo() async throws {
        let url = try await TestSupport.makeTestVideo(
            seconds: 0.5, size: CGSize(width: 320, height: 240), fps: 24
        )
        defer { TestSupport.remove(url) }

        let asset = AVURLAsset(url: url)
        let composition = try await CaptionRenderer().buildVideoComposition(
            for: asset,
            segments: [],
            style: .hormozi,
            outputSize: CGSize(width: 320, height: 240),
            captionYPosition: 0.8
        )

        XCTAssertEqual(
            composition.frameDuration.seconds, 1.0 / 24, accuracy: 1e-6,
            "a 24 fps source exported at \(1 / composition.frameDuration.seconds) fps"
        )
    }

    func testAnAbsurdlyShortFrameDurationIsClamped() {
        let result = duration(min: CMTime(value: 1, timescale: 100_000), nominal: 0)

        XCTAssertEqual(result, CMTime(value: 1, timescale: 240))
    }

    /// The export never hands the renderer the file itself. It builds an
    /// AVMutableComposition over it, and passes the file's track for the rate.
    func testAnExportShapedCompositionTakesItsRateFromTheSourceFile() async throws {
        let url = try await TestSupport.makeTestVideo(
            seconds: 0.5, size: CGSize(width: 320, height: 240), fps: 24
        )
        defer { TestSupport.remove(url) }

        let asset = AVURLAsset(url: url)
        let source = try XCTUnwrap(try await asset.loadTracks(withMediaType: .video).first)
        let mutable = AVMutableComposition()
        let track = try XCTUnwrap(
            mutable.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        )
        let duration = try await asset.load(.duration)
        try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: source, at: .zero)

        let composition = try await CaptionRenderer().buildVideoComposition(
            for: mutable,
            segments: [],
            style: .hormozi,
            outputSize: CGSize(width: 320, height: 240),
            captionYPosition: 0.8,
            frameRateSource: source
        )

        XCTAssertEqual(composition.frameDuration.seconds, 1.0 / 24, accuracy: 1e-6)
    }
}
