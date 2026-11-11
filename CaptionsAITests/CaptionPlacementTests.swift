@testable import CaptionsAI
import XCTest

/// The preview places captions on the picture inside the player, the way
/// the export places them on the video frame.
final class CaptionPlacementTests: XCTestCase {
    private let player = CGSize(width: 393, height: 630)

    func testALandscapeClipSitsInABandAcrossTheMiddle() {
        let rect = CaptionOverlay.videoRect(in: player, videoSize: CGSize(width: 1920, height: 1080))
        XCTAssertEqual(rect.width, 393, accuracy: 0.5)
        XCTAssertEqual(rect.height, 393 * 9 / 16, accuracy: 0.5)
        XCTAssertEqual(rect.midY, 315, accuracy: 0.5)
    }

    func testAPortraitClipIsNarrowerThanThePlayer() {
        // So the caption font, scaled by width like the export's, comes out
        // smaller than it did against the full 393pt player.
        let rect = CaptionOverlay.videoRect(in: player, videoSize: CGSize(width: 1080, height: 1920))
        XCTAssertEqual(rect.height, 630, accuracy: 0.5)
        XCTAssertEqual(rect.width, 630 * 9 / 16, accuracy: 0.5)
        XCTAssertEqual(rect.midX, 196.5, accuracy: 0.5)
    }

    func testUnknownSizeUsesTheWholePlayer() {
        XCTAssertEqual(CaptionOverlay.videoRect(in: player, videoSize: nil), CGRect(origin: .zero, size: player))
        XCTAssertEqual(
            CaptionOverlay.videoRect(in: player, videoSize: CGSize(width: 0, height: 0)),
            CGRect(origin: .zero, size: player)
        )
    }

    func testTheDisplaySizeOfARealClipIsRead() async throws {
        let video = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "spanish_speech", withExtension: "mp4"))
        let size = await EditorViewModel.displaySize(of: video)
        XCTAssertEqual(size, CGSize(width: 160, height: 90))
    }

    func testAFileWithNoVideoTrackHasNoDisplaySize() async {
        let size = await EditorViewModel.displaySize(of: URL(fileURLWithPath: "/nonexistent/clip.mov"))
        XCTAssertNil(size)
    }
}
