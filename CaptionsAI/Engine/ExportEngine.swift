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
        case .exportFailed(let reason): return "Export failed: \(reason)"
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
    private var progressTask: Task<Void, Never>?
    
    // MARK: - Export
    
    /// Exports the video with captions burned in.
    @MainActor
    func export(
        videoURL: URL,
        preset: ExportPreset,
        segments: [CaptionSegment],
        style: CaptionStyle,
        addWatermark: Bool
    ) async throws -> URL {
        isExporting = true
        progress = 0
        error = nil
        
        defer { isExporting = false }
        
        let asset = AVURLAsset(url: videoURL)
        
        // Determine output size
        let outputSize: CGSize
        if preset == .original {
            if let videoTrack = try await asset.loadTracks(withMediaType: .video).first {
                outputSize = try await videoTrack.load(.naturalSize)
            } else {
                throw ExportError.noVideoTrack
            }
        } else {
            outputSize = preset.resolution
        }
        
        // Build video composition with captions
        let renderer = CaptionRenderer()
        let videoComposition = try await renderer.buildVideoComposition(
            for: asset,
            segments: segments,
            style: style,
            outputSize: outputSize
        )
        
        // Configure export session
        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw ExportError.exportFailed("Could not create export session")
        }
        
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionsAI_\(UUID().uuidString)")
            .appendingPathExtension("mp4")
        
        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.videoComposition = videoComposition
        session.shouldOptimizeForNetworkUse = true
        
        self.exportSession = session
        
        // Start progress polling
        progressTask = startProgressPolling(session: session)
        
        // Export
        await session.export()
        
        progressTask?.cancel()
        
        switch session.status {
        case .completed:
            progress = 1.0
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
        exportSession?.cancelExport()
        progressTask?.cancel()
        isExporting = false
    }
    
    // MARK: - Progress Polling
    
    private func startProgressPolling(session: AVAssetExportSession) -> Task<Void, Never> {
        Task { @MainActor in
            while !Task.isCancelled && session.status == .exporting {
                self.progress = Double(session.progress)
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }
}
