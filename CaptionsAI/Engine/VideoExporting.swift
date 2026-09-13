import Foundation

// MARK: - VideoExporting

/// The export pipeline, as the export screen sees it.
///
/// This is a protocol because ``ExportEngine/export(videoURL:settings:preset:segments:style:captionYPosition:addWatermark:)``
/// ends in a write to the Photo Library, which a test bundle cannot perform.
/// What the screen *does* with the engine's outcome — what it shows when the
/// user cancels, or when a render succeeds — is behaviour of its own, and it
/// needs a stand-in to be reachable.
protocol VideoExporting: AnyObject {
    /// Fraction of the render that is done, 0...1.
    var progress: Double { get }

    /// Whether the last finished render reached the Photo Library.
    var savedToPhotoLibrary: Bool { get }

    @MainActor
    func export(
        videoURL: URL,
        settings: ExportSettings,
        preset: ExportPreset,
        segments: [CaptionSegment],
        style: CaptionStyle,
        captionYPosition: Double,
        addWatermark: Bool
    ) async throws -> URL

    func cancelExport()
}

extension ExportEngine: VideoExporting {}
