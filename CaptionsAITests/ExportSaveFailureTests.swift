@testable import CaptionsAI
import AVFoundation
import XCTest

/// What happens to a finished render when the Photo Library refuses it.
///
/// The defect: `export()` ended with `try await saveToPhotoLibrary(outputURL)`.
/// A refused permission threw out of the whole export, so the encoded file —
/// which is sitting on disk, finished — was never returned. The export screen
/// never set `exportedFileURL`, the Share button never appeared, and the user
/// was told to start again over a permission they can grant in Settings.
///
/// The engine-level test drives a real export of a real fixture with the save
/// stubbed to refuse, because a test bundle cannot hold a Photos
/// authorization.
@MainActor
final class ExportSaveFailureTests: XCTestCase {
    private struct RefusedByPhotos: Error {}

    private func renderSomething(
        savingWith saver: @escaping (URL) async throws -> Void
    ) async throws -> (engine: ExportEngine, output: URL?) {
        let source = try await TestSupport.makeTestVideo(
            seconds: 0.5, size: CGSize(width: 320, height: 240), fps: 4
        )
        defer { TestSupport.remove(source) }

        let engine = ExportEngine()
        engine.photoLibrarySaver = saver

        var output: URL?
        do {
            output = try await engine.export(
                videoURL: source,
                settings: ExportSettings(),
                preset: .original,
                segments: [CaptionSegment(startTime: 0, endTime: 0.4, text: "hello")],
                style: .hormozi,
                captionYPosition: 0.8,
                addWatermark: false
            )
        } catch {
            XCTFail("export threw \(error) instead of handing back the finished file")
        }
        return (engine, output)
    }

    // MARK: - The render survives

    func testARefusedPhotoLibraryDoesNotThrowAwayTheRender() async throws {
        let (engine, output) = try await renderSomething(savingWith: { _ in throw RefusedByPhotos() })

        let url = try XCTUnwrap(output, "the finished file was discarded")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: url.path),
            "export returned \(url.lastPathComponent), which is not there"
        )
        XCTAssertFalse(engine.savedToPhotoLibrary)
        TestSupport.remove(url)
    }

    func testASavedRenderSaysSo() async throws {
        let (engine, output) = try await renderSomething(savingWith: { _ in })

        let url = try XCTUnwrap(output)
        XCTAssertTrue(engine.savedToPhotoLibrary)
        TestSupport.remove(url)
    }

    // MARK: - What the screen does with it

    func testAnUnsavedRenderIsStillOfferedForSharing() async {
        let exporter = FakeExporter()
        let output = URL(fileURLWithPath: "/tmp/finished-but-unsaved.mp4")
        exporter.outcome = .succeed(output)
        exporter.savedToPhotoLibrary = false
        let viewModel = ExportViewModel(exportEngine: exporter)

        await viewModel.startExport(
            videoURL: TestSupport.placeholderVideoURL,
            segments: [], style: .hormozi, captionYPosition: 0.8, isPro: true
        )

        XCTAssertEqual(viewModel.exportedFileURL, output, "the only copy of the render was dropped")
    }

    func testAnUnsavedRenderSaysWhyItIsNotInPhotos() async {
        let exporter = FakeExporter()
        exporter.savedToPhotoLibrary = false
        let viewModel = ExportViewModel(exportEngine: exporter)

        await viewModel.startExport(
            videoURL: TestSupport.placeholderVideoURL,
            segments: [], style: .hormozi, captionYPosition: 0.8, isPro: true
        )

        XCTAssertEqual(viewModel.error, "Failed to save video to Photo Library.")
    }

    func testASavedRenderSaysNothing() async {
        let exporter = FakeExporter()
        exporter.savedToPhotoLibrary = true
        let viewModel = ExportViewModel(exportEngine: exporter)

        await viewModel.startExport(
            videoURL: TestSupport.placeholderVideoURL,
            segments: [], style: .hormozi, captionYPosition: 0.8, isPro: true
        )

        XCTAssertNil(viewModel.error)
    }
}
