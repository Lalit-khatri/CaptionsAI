@testable import CaptionsAI
import XCTest

/// A stand-in for the export pipeline, so the export screen's own behaviour
/// can be exercised without a render or a Photo Library write.
final class FakeExporter: VideoExporting {
    enum Outcome {
        case succeed(URL)
        case fail(Error)
    }

    var outcome: Outcome = .succeed(URL(fileURLWithPath: "/tmp/fake-export.mp4"))
    var progress: Double = 0
    var savedToPhotoLibrary = true
    private(set) var cancelCount = 0
    private(set) var exportCount = 0

    /// Awaited inside `export` before the outcome, so a test can hold an
    /// export open and look at the screen while it runs.
    var whileExporting: (@MainActor () async -> Void)?

    @MainActor
    func export(
        videoURL _: URL,
        settings _: ExportSettings,
        preset _: ExportPreset,
        segments _: [CaptionSegment],
        style _: CaptionStyle,
        captionYPosition _: Double,
        addWatermark _: Bool
    ) async throws -> URL {
        exportCount += 1
        await whileExporting?()
        switch outcome {
        case let .succeed(url): return url
        case let .fail(error): throw error
        }
    }

    func cancelExport() {
        cancelCount += 1
    }
}
