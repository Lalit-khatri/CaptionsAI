@testable import CaptionsAI
import XCTest

/// The export screen's format default, its summary label, and keeping the
/// phone awake while it renders.
@MainActor
final class ExportDefaultsTests: XCTestCase {
    // MARK: - Format

    func testALandscapeClipOpensOnYouTube() {
        XCTAssertEqual(
            ExportViewModel.initialPreset(lastUsed: "instagramReels", sourceSize: CGSize(width: 1920, height: 1080)),
            .youtube
        )
    }

    func testAPortraitClipOpensOnReels() {
        XCTAssertEqual(
            ExportViewModel.initialPreset(lastUsed: "instagramReels", sourceSize: CGSize(width: 1080, height: 1920)),
            .instagramReels
        )
    }

    func testAFormatTheUserChoseLastTimeWins() {
        XCTAssertEqual(
            ExportViewModel.initialPreset(lastUsed: "original", sourceSize: CGSize(width: 1080, height: 1920)),
            .original
        )
    }

    func testNoThumbnailOrAnUnknownStoredValueFallsBackToReels() {
        XCTAssertEqual(ExportViewModel.initialPreset(lastUsed: "garbage", sourceSize: nil), .instagramReels)
    }

    // MARK: - Summary label

    func testTheSummaryShowsTheResolutionThatWillBeRendered() {
        var settings = ExportSettings()
        settings.resolution = .uhd4K
        XCTAssertEqual(ExportViewModel.resolutionLabel(preset: .instagramReels, settings: settings), "2160×3840")

        settings.resolution = .hd720
        XCTAssertEqual(ExportViewModel.resolutionLabel(preset: .youtube, settings: settings), "1280×720")
    }

    // MARK: - Screen awake

    func testTheScreenStaysOnForTheExportAndNotAfter() async {
        var calls: [Bool] = []
        let exporter = FakeExporter()
        let viewModel = ExportViewModel(exportEngine: exporter, keepScreenAwake: { calls.append($0) })

        await viewModel.startExport(
            videoURL: TestSupport.placeholderVideoURL,
            segments: [], style: .hormozi, captionYPosition: 0.8, isPro: true
        )

        XCTAssertEqual(calls, [true, false])
    }

    func testAFailedExportStillLetsTheScreenSleepAgain() async {
        var calls: [Bool] = []
        let exporter = FakeExporter()
        exporter.outcome = .fail(ExportError.exportFailed("boom"))
        let viewModel = ExportViewModel(exportEngine: exporter, keepScreenAwake: { calls.append($0) })

        await viewModel.startExport(
            videoURL: TestSupport.placeholderVideoURL,
            segments: [], style: .hormozi, captionYPosition: 0.8, isPro: true
        )

        XCTAssertEqual(calls.last, false)
    }
}
