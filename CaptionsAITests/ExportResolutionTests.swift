@testable import CaptionsAI
import AVFoundation
import CoreGraphics
import XCTest

/// What the resolution picker means.
///
/// The defect these cover: the picker's values were applied as *scale factors*
/// against whatever canvas the format preset produced, so the number in the UI
/// described a multiplication rather than a result. On a 4K source, "4K"
/// produced 7680×4320 and "720p" produced 2562×1440 — a size that is neither
/// 720p nor a multiple of 16 — while "Original" and "1080p" were
/// indistinguishable, both being ×1.0.
///
/// Most of these are pure arithmetic and run in microseconds. The last one
/// pays for a real 4K encode, because arithmetic that the engine does not
/// actually call is worth nothing.
final class ExportResolutionTests: XCTestCase {
    private let fourK = CGSize(width: 3840, height: 2160)
    private let hd = CGSize(width: 1920, height: 1080)

    // MARK: - The reported symptoms

    func testFourKOnAFourKSourceStaysAtFourK() {
        XCTAssertEqual(ExportResolution.uhd4K.outputSize(for: fourK), fourK)
    }

    func testSevenTwentyOnAFourKSourceIsActuallySevenTwenty() {
        XCTAssertEqual(
            ExportResolution.hd720.outputSize(for: fourK),
            CGSize(width: 1280, height: 720)
        )
    }

    func testTenEightyOnAFourKSourceIsActuallyTenEighty() {
        XCTAssertEqual(
            ExportResolution.full1080.outputSize(for: fourK),
            CGSize(width: 1920, height: 1080)
        )
    }

    /// `.original` and `.full1080` were behaviourally identical, both ×1.0.
    /// They must now differ on any source that is not already 1080p.
    func testOriginalAndTenEightyDifferOnAFourKSource() {
        XCTAssertNotEqual(
            ExportResolution.original.outputSize(for: fourK),
            ExportResolution.full1080.outputSize(for: fourK)
        )
    }

    func testOriginalKeepsTheSourceSize() {
        XCTAssertEqual(ExportResolution.original.outputSize(for: fourK), fourK)
        XCTAssertEqual(ExportResolution.original.outputSize(for: hd), hd)
    }

    // MARK: - Orientation

    /// The named value is the short side, so a portrait clip is 1080p for the
    /// same reason the landscape clip it was rotated from is.
    func testPortraitIsMeasuredOnItsShortSide() {
        let portraitFourK = CGSize(width: 2160, height: 3840)
        XCTAssertEqual(
            ExportResolution.full1080.outputSize(for: portraitFourK),
            CGSize(width: 1080, height: 1920)
        )
        XCTAssertEqual(ExportResolution.uhd4K.outputSize(for: portraitFourK), portraitFourK)
    }

    func testAspectRatioIsPreserved() {
        for resolution in ExportResolution.allCases {
            let out = resolution.outputSize(for: fourK)
            XCTAssertEqual(
                out.width / out.height,
                fourK.width / fourK.height,
                accuracy: 0.01,
                "\(resolution.rawValue) changed the aspect ratio"
            )
        }
    }

    // MARK: - Encoder constraints

    /// H.264 rejects odd dimensions, and an odd size survives a long way down
    /// the pipeline before anything complains.
    func testEveryOutputDimensionIsEven() {
        let awkwardSources = [
            CGSize(width: 1080, height: 1920),
            CGSize(width: 1440, height: 1080),
            CGSize(width: 641, height: 361),
            CGSize(width: 3840, height: 2160),
        ]
        for source in awkwardSources {
            for resolution in ExportResolution.allCases {
                let out = resolution.outputSize(for: source)
                XCTAssertEqual(
                    out.width.truncatingRemainder(dividingBy: 2), 0,
                    "\(resolution.rawValue) of \(source) gave an odd width \(out.width)"
                )
                XCTAssertEqual(
                    out.height.truncatingRemainder(dividingBy: 2), 0,
                    "\(resolution.rawValue) of \(source) gave an odd height \(out.height)"
                )
            }
        }
    }

    func testAnEmptyCanvasIsLeftAlone() {
        XCTAssertEqual(ExportResolution.uhd4K.outputSize(for: .zero), .zero)
    }

    // MARK: - Combined with a format preset

    /// A format preset supplies the canvas; the resolution setting supplies the
    /// line count. Reels at 4K is 2160×3840, not 1080×1920 and not 4320×7680.
    func testAFormatPresetSuppliesTheAspectAndTheSettingSuppliesTheLines() {
        let reels = ExportPreset.instagramReels.resolution
        XCTAssertEqual(
            ExportResolution.uhd4K.outputSize(for: reels),
            CGSize(width: 2160, height: 3840)
        )
        XCTAssertEqual(
            ExportResolution.hd720.outputSize(for: reels),
            CGSize(width: 720, height: 1280)
        )
    }

    // MARK: - The engine actually uses it

    /// Arithmetic the engine does not call is worth nothing, so this one reads
    /// a genuine 4K asset through the same method `export` uses.
    func testTheEngineSizesAFourKSourceFromTheRealTrack() async throws {
        let url = try await TestSupport.makeTestVideo(seconds: 0.5, size: fourK, fps: 4)
        defer { TestSupport.remove(url) }

        let engine = ExportEngine()
        var settings = ExportSettings()

        settings.resolution = .uhd4K
        let atFourK = try await engine.renderSize(
            for: AVURLAsset(url: url), settings: settings, preset: .original
        )
        XCTAssertEqual(atFourK, fourK, "asking a 4K source for 4K must not produce 8K")

        settings.resolution = .full1080
        let atTenEighty = try await engine.renderSize(
            for: AVURLAsset(url: url), settings: settings, preset: .original
        )
        XCTAssertEqual(atTenEighty, CGSize(width: 1920, height: 1080))
    }

    // MARK: - The estimate is untouched

    /// The size estimate borrowed the same property, so it is worth pinning
    /// that separating them changed none of its numbers.
    func testTheFileSizeEstimateIsUnchanged() {
        var settings = ExportSettings()
        settings.resolution = .uhd4K
        settings.quality = .high
        settings.codec = .h264
        XCTAssertEqual(settings.estimatedFileSize(durationSeconds: 60), "~75 MB")
    }
}
