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

    /// Whether the last finished render reached the Photo Library.
    ///
    /// `false` after a refused permission — the file is still on disk and is
    /// still returned, so the caller can offer it for sharing.
    var savedToPhotoLibrary = false

    // MARK: - Private

    private var exportSession: AVAssetExportSession?
    private var progressTimer: Timer?

    /// Set by ``cancelExport()``. The session only exists for the encode, so
    /// a Stop during setup had nothing to cancel and the export carried on —
    /// then saved to Photos — after the screen said it had stopped.
    private var cancelRequested = false

    /// Whether an AVAssetExportSession is currently active or retained.
    var hasActiveExportSession: Bool {
        exportSession != nil
    }

    /// Supplied by tests only. A test bundle cannot hold a Photos
    /// authorization, so the refusal path is unreachable without this.
    var photoLibrarySaver: ((URL) async throws -> Void)?

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
        addWatermark: Bool
    ) async throws -> URL {
        // Copied here, on the main actor and before the first suspension. The
        // compositor reads captions on its own queue for every frame, and
        // `CaptionSegment` is a SwiftData model that must stay on this one.
        let captions = segments.map(CaptionSnapshot.init)

        isExporting = true
        progress = 0
        error = nil
        savedToPhotoLibrary = false
        cancelRequested = false

        defer {
            isExporting = false
            exportSession = nil
        }

        let asset = AVURLAsset(url: videoURL)

        let renderSize = try await self.renderSize(for: asset, settings: settings, preset: preset)
        try throwIfCancelled()

        // Build an AVMutableComposition to get full control
        let mutableComposition = AVMutableComposition()

        guard let sourceVideoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw ExportError.noVideoTrack
        }

        let duration = try await asset.load(.duration)
        let timeRange = CMTimeRange(start: .zero, duration: duration)
        try throwIfCancelled()

        // Add video track
        guard let compositionVideoTrack = mutableComposition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ExportError.exportFailed("Could not add video track to composition")
        }
        try compositionVideoTrack.insertTimeRange(timeRange, of: sourceVideoTrack, at: .zero)

        // How the frame has to be turned before it is shown. Copying the
        // transform onto the composition track was a no-op and its comment
        // claimed the credit for this: with a custom compositor,
        // `sourceFrame(byTrackID:)` hands back the raw buffer with the
        // transform *not* applied, so `.oriented()` in the compositor is the
        // only rotation in the pixel path.
        let transform = try await sourceVideoTrack.load(.preferredTransform)
        let preferredOrientation = Self.preferredOrientation(for: transform)

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
            segments: captions,
            style: style,
            outputSize: renderSize,
            captionYPosition: captionYPosition,
            preferredOrientation: preferredOrientation,
            addWatermark: addWatermark
        )

        // Select export preset based on codec and quality
        let exportPresetName = await selectExportPreset(
            settings: settings,
            asset: mutableComposition
        )
        try throwIfCancelled()

        guard let session = AVAssetExportSession(
            asset: mutableComposition,
            presetName: exportPresetName
        ) else {
            throw ExportError.exportFailed("Could not create export session")
        }

        // Earlier renders are gone from the user's reach the moment a new one
        // starts, but they stayed on disk. Nothing ever deleted them, so a few
        // dozen exports quietly held on to the user's storage.
        Self.removeStaleExports()

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(Self.scratchPrefix)\(UUID().uuidString)")
            .appendingPathExtension(settings.codec == .h265 ? "mov" : "mp4")

        session.outputURL = outputURL
        session.outputFileType = settings.codec == .h265 ? .mov : .mp4
        session.videoComposition = videoComposition
        session.shouldOptimizeForNetworkUse = true

        exportSession = session

        // Start Timer-based progress polling (FrameForge pattern)
        startProgressPolling(session: session)

        // Export. A cancelled task used to leave the encode running to the end.
        await withTaskCancellationHandler {
            await session.export()
        } onCancel: {
            session.cancelExport()
        }

        // Stop timer
        progressTimer?.invalidate()
        progressTimer = nil

        switch session.status {
        case .completed:
            progress = 1.0
            // The render is finished and the file is on disk. A refused Photos
            // permission used to throw out of here, which discarded minutes of
            // encoding over something the user can fix — or work around, by
            // sharing the file straight from the export screen. The outcome is
            // recorded instead, and the file is handed back either way.
            do {
                try await save(outputURL)
                savedToPhotoLibrary = true
            } catch {
                savedToPhotoLibrary = false
            }
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

    // MARK: - Scratch files

    /// Prefix on every file an export writes, so the app can tell its own
    /// leavings from anything else sharing the temporary directory.
    static let scratchPrefix = "CaptionsAI_"

    /// Exports this app left in `directory`, `keeping` one aside.
    static func staleExports(in directory: URL, keeping: URL? = nil) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let spared = keeping?.standardizedFileURL
        return names
            .filter { $0.hasPrefix(scratchPrefix) }
            .map { directory.appendingPathComponent($0) }
            .filter { $0.standardizedFileURL != spared }
    }

    /// Deletes this app's earlier exports and returns how many went.
    ///
    /// Only files carrying ``scratchPrefix`` are touched: the temporary
    /// directory belongs to the whole app, and deleting by wildcard there
    /// would eventually take something that mattered.
    @discardableResult
    static func removeStaleExports(
        in directory: URL = FileManager.default.temporaryDirectory,
        keeping: URL? = nil
    ) -> Int {
        var removed = 0
        for url in staleExports(in: directory, keeping: keeping) {
            if (try? FileManager.default.removeItem(at: url)) != nil {
                removed += 1
            }
        }
        return removed
    }

    // MARK: - Save to Photos

    /// Saves through the injected hook if there is one, otherwise for real.
    private func save(_ url: URL) async throws {
        if let photoLibrarySaver {
            try await photoLibrarySaver(url)
        } else {
            try await saveToPhotoLibrary(url)
        }
    }

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
        cancelRequested = true
        progressTimer?.invalidate()
        progressTimer = nil
        exportSession?.cancelExport()
        exportSession = nil
        isExporting = false
    }

    /// Throws ``ExportError/cancelled`` if Stop was pressed or the calling
    /// task was cancelled. Called between setup steps, before the session
    /// that ``cancelExport()`` can reach exists.
    private func throwIfCancelled() throws {
        if cancelRequested || Task.isCancelled {
            throw ExportError.cancelled
        }
    }

    // MARK: - Helpers

    /// The orientation the decoded frame has to be drawn in for it to appear
    /// the way the file asks.
    ///
    /// This used to match four exact transforms and silently answer `.up` to
    /// anything else, while ``swapsDimensions(_:)``'s job was done separately
    /// by a looser test. They disagreed on a front-camera transform such as
    /// `a=0, b=1, c=1, d=0`: the canvas was turned portrait but the frame was
    /// not, so a landscape frame was letterboxed into a portrait video. There
    /// is now one decision and both callers read it.
    ///
    /// Mirroring is deliberately not modelled. A reflected transform is
    /// classified as the rotation it is nearest to, so the frame fills the
    /// canvas the right way up but is not un-flipped. That is a gap, not a
    /// regression — the old code declined to turn such a frame at all.
    static func preferredOrientation(for transform: CGAffineTransform) -> CGImagePropertyOrientation {
        if swapsDimensions(transform) {
            return transform.b > 0 ? .right : .left
        }
        return transform.a < 0 ? .down : .up
    }

    /// Whether `transform` maps the frame's width onto the display's height,
    /// in which case what the viewer sees is the natural size swapped.
    ///
    /// Tested on the axes rather than on `± 1` so that a transform carrying a
    /// scale is still recognised as a quarter turn.
    static func swapsDimensions(_ transform: CGAffineTransform) -> Bool {
        transform.a == 0 && transform.d == 0 && transform.b != 0 && transform.c != 0
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
        return Self.swapsDimensions(transform)
            ? CGSize(width: naturalSize.height, height: naturalSize.width)
            : naturalSize
    }

    /// Selects the best compatible export preset based on settings.
    ///
    /// Order matters and used to be wrong. The *codec* preset was tried first,
    /// and `.h264` maps to `AVAssetExportPresetHighestQuality`, which is
    /// compatible with everything — so it always won, and the Quality picker
    /// changed nothing but the estimate. The tier the user chose now leads,
    /// and the codec's catch-all is only a fallback for an asset that refuses
    /// it.
    private func selectExportPreset(
        settings: ExportSettings,
        asset: AVAsset
    ) async -> String {
        let candidates = [
            settings.quality.exportPreset(for: settings.codec),
            settings.codec.exportPreset,
            AVAssetExportPresetHighestQuality,
        ]
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
        // A timer left from an earlier export would keep writing its stale
        // session's progress into the bar.
        progressTimer?.invalidate()
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
