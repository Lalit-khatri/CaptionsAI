@testable import CaptionsAI
import XCTest

/// What the export screen shows when the user stops an export.
///
/// The defect: cancelling threw `ExportError.cancelled`, the view model caught
/// every error the same way, and the view puts `error` in an alert titled
/// "Error". So pressing Stop, confirming "Stop Export", and being told "Your
/// export progress will be lost" was followed by an error dialogue reporting
/// that the thing you asked for had happened.
///
/// A genuine failure must still be reported, so that is asserted alongside.
@MainActor
final class ExportCancellationTests: XCTestCase {
    private func startExport(_ viewModel: ExportViewModel) async {
        await viewModel.startExport(
            videoURL: TestSupport.placeholderVideoURL,
            segments: [],
            style: .hormozi,
            captionYPosition: 0.8,
            isPro: true
        )
    }

    // MARK: - Cancelling

    func testStoppingAnExportDoesNotRaiseAnError() async {
        let exporter = FakeExporter()
        exporter.outcome = .fail(ExportError.cancelled)
        let viewModel = ExportViewModel(exportEngine: exporter)

        await startExport(viewModel)

        XCTAssertNil(viewModel.error, "alert would read: \(viewModel.error ?? "")")
    }

    func testStoppingAnExportLeavesTheScreenIdle() async {
        let exporter = FakeExporter()
        exporter.outcome = .fail(ExportError.cancelled)
        let viewModel = ExportViewModel(exportEngine: exporter)

        await startExport(viewModel)

        XCTAssertFalse(viewModel.isExporting)
        XCTAssertNil(viewModel.exportedFileURL)
        XCTAssertEqual(viewModel.exportProgress, 0)
    }

    func testStopReachesTheEngine() {
        let exporter = FakeExporter()
        let viewModel = ExportViewModel(exportEngine: exporter)

        viewModel.cancelExport()

        XCTAssertEqual(exporter.cancelCount, 1)
        XCTAssertFalse(viewModel.isExporting)
    }

    // MARK: - Real failures are still reported

    func testAFailedExportIsStillReported() async {
        let exporter = FakeExporter()
        exporter.outcome = .fail(ExportError.exportFailed("the disk is full"))
        let viewModel = ExportViewModel(exportEngine: exporter)

        await startExport(viewModel)

        XCTAssertEqual(viewModel.error, "Export failed: the disk is full")
    }

    func testASuccessfulExportReportsNoErrorAndKeepsTheFile() async {
        let exporter = FakeExporter()
        let output = URL(fileURLWithPath: "/tmp/finished-export.mp4")
        exporter.outcome = .succeed(output)
        let viewModel = ExportViewModel(exportEngine: exporter)

        await startExport(viewModel)

        XCTAssertNil(viewModel.error)
        XCTAssertEqual(viewModel.exportedFileURL, output)
    }

    func testExportSessionIsClearedOnCancel() {
        let engine = ExportEngine()
        engine.cancelExport()
        XCTAssertFalse(engine.hasActiveExportSession)
    }
}

