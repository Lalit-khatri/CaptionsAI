import AVFoundation
import Photos
import UIKit

// MARK: - Export Error

enum ExportError: Error, LocalizedError {
    case exportFailed(String)
    case cancelled
    case saveFailed
    case noVideoTrack

    var errorDescription: String? {
        switch self {
        case let .exportFailed(reason): return "Export failed: \(reason)"
        case .cancelled: return "Export was cancelled."
        case .saveFailed: return "Failed to save video to Photo Library."
        case .noVideoTrack: return "No video track found in the source file."
        }
    }
}

// MARK: - ExportEngine

/// Handles the full export pipeline: composition → encode → save.
@Observable
final class ExportEngine {
    // MARK: - State

    var isExporting = false
    var progress: Double = 0
    var error: ExportError?

    // MARK: - Private

    private var exportSession: AVAssetExportSession?
    private var progressTimer: Timer?

    // MARK: - Export

    /// Exports the video with captions burned in.
    @MainActor
    func export(
        videoURL: URL,
        settings: ExportSettings,
        preset: ExportPreset,
        segments: [CaptionSegment],
        style: CaptionStyle,
        captionYPosition: Double,
        addWatermark _: Bool
    ) async throws -> URL {
        isExporting = true
        progress = 0
        error = nil

        defer { isExporting = false }

        let asset = AVURLAsset(url: videoURL)

        let renderSize = try await self.renderSize(for: asset, settings: settings, preset: preset)

        // Build an AVMutableComposition to get full control
        let mutableComposition = AVMutableComposition()

        guard let sourceVideoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw ExportError.noVideoTrack
        }

        let duration = try await asset.load(.duration)
        let timeRange = CMTimeRange(start: .zero, duration: duration)

        // Add video track
        guard let compositionVideoTrack = mutableComposition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ExportError.exportFailed("Could not add video track to composition")
        }
        try compositionVideoTrack.insertTimeRange(timeRange, of: sourceVideoTrack, at: .zero)

        // Copy the transform so portrait videos stay upright
        let transform = try await sourceVideoTrack.load(.preferredTransform)
        let orientation = getVideoOrientation(from: transform)
        compositionVideoTrack.preferredTransform = transform

        // Add audio track if present and included
        if settings.includeAudio {
            if let sourceAudioTrack = try await asset.loadTracks(withMediaType: .audio).first {
                if let compositionAudioTrack = mutableComposition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) {
                    try compositionAudioTrack.insertTimeRange(timeRange, of: sourceAudioTrack, at: .zero)
                }
            }
        }

        // Build video composition with captions
        let renderer = CaptionRenderer()
        let videoComposition = try await renderer.buildVideoComposition(
            for: mutableComposition,
            segments: segments,
            style: style,
            outputSize: renderSize,
            captionYPosition: captionYPosition,
            preferredTransform: transform,
            orientation: orientation
        )

        // Select export preset based on codec and quality
        let exportPresetName = await selectExportPreset(
            settings: settings,
            asset: mutableComposition
        )

        guard let session = AVAssetExportSession(
            asset: mutableComposition,
            presetName: exportPresetName
        ) else {
            throw ExportError.exportFailed("Could not create export session")
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionsAI_\(UUID().uuidString)")
            .appendingPathExtension(settings.codec == .h265 ? "mov" : "mp4")

        session.outputURL = outputURL
        session.outputFileType = settings.codec == .h265 ? .mov : .mp4
        session.videoComposition = videoComposition
        session.shouldOptimizeForNetworkUse = true

        exportSession = session

        // Start Timer-based progress polling (FrameForge pattern)
        startProgressPolling(session: session)

        // Export
        await session.export()

        // Stop timer
        progressTimer?.invalidate()
        progressTimer = nil

        switch session.status {
        case .completed:
            progress = 1.0
            // Auto-save to Photo Library
            try await saveToPhotoLibrary(outputURL)
            return outputURL
        case .cancelled:
            throw ExportError.cancelled
        case .failed:
            let reason = session.error?.localizedDescription ?? "Unknown error"
            throw ExportError.exportFailed(reason)
        default:
            throw ExportError.exportFailed("Unexpected export status")
        }
    }

    // MARK: - Save to Photos

    /// Saves the exported video to the user's Photo Library.
    func saveToPhotoLibrary(_ url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw ExportError.saveFailed
        }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }

    // MARK: - Cancel

    func cancelExport() {
        progressTimer?.invalidate()
        progressTimer = nil
        exportSession?.cancelExport()
        isExporting = false
    }

    // MARK: - Helpers

    private func getVideoOrientation(from transform: CGAffineTransform) -> CGImagePropertyOrientation {
        // Portrait
        if transform.a == 0 && transform.b == 1.0 && transform.c == -1.0 && transform.d == 0 {
            return .right
        }
        // Portrait Upside Down
        else if transform.a == 0 && transform.b == -1.0 && transform.c == 1.0 && transform.d == 0 {
            return .left
        }
        // Landscape Right
        else if transform.a == -1.0 && transform.b == 0 && transform.c == 0 && transform.d == -1.0 {
            return .down
        }
        // Landscape Left (Default)
        else {
            return .up
        }
    }

    /// The size the composition will render at.
    ///
    /// Two independent choices meet here and used to be conflated. The *format*
    /// preset decides the canvas — its own fixed frame, or the source's own
    /// dimensions for `.original`. The *resolution* setting then decides how
    /// many lines that canvas gets. Keeping them separate is what stops "4K"
    /// meaning "double whatever you had".
    ///
    /// Not private: this is the seam the resolution tests assert against, since
    /// ``export(videoURL:settings:preset:segments:style:captionYPosition:addWatermark:)``
    /// cannot run in a test bundle — it ends in a Photo Library write.
    func renderSize(
        for asset: AVURLAsset,
        settings: ExportSettings,
        preset: ExportPreset
    ) async throws -> CGSize {
        let canvas: CGSize
        if preset == .original {
            canvas = try await resolveOriginalSize(from: asset)
        } else {
            canvas = preset.resolution
        }
        return settings.resolution.outputSize(for: canvas)
    }

    /// Reads the actual video dimensions from the source track, handling rotation.
    private func resolveOriginalSize(from asset: AVURLAsset) async throws -> CGSize {
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw ExportError.noVideoTrack
        }
        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let isPortrait = abs(transform.b) == 1 && abs(transform.c) == 1
        return isPortrait
            ? CGSize(width: naturalSize.height, height: naturalSize.width)
            : naturalSize
    }

    /// Selects the best compatible export preset based on settings.
    private func selectExportPreset(
        settings: ExportSettings,
        asset: AVAsset
    ) async -> String {
        // Prefer codec-specific preset first
        let codecPreset = settings.codec.exportPreset
        let qualityPreset = settings.quality.exportPreset

        // Try codec preset, then quality preset, then fallback
        let candidates = [codecPreset, qualityPreset, AVAssetExportPresetHighestQuality]
        for preset in candidates {
            let compatible = await AVAssetExportSession.compatibility(
                ofExportPreset: preset,
                with: asset,
                outputFileType: settings.codec == .h265 ? .mov : .mp4
            )
            if compatible {
                return preset
            }
        }

        return AVAssetExportPresetMediumQuality
    }

    /// Polls `session.progress` every 100ms via a RunLoop timer (FrameForge pattern).
    private func startProgressPolling(session: AVAssetExportSession) {
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self, weak session] _ in
            guard let s = session else { return }
            DispatchQueue.main.async {
                self?.progress = Double(s.progress)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
    }
}
