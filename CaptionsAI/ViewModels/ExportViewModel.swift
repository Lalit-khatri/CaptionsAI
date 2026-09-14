import AVFoundation
import SwiftUI

// MARK: - ExportViewModel

/// Manages the export workflow including settings, progress, and sharing.
@Observable
final class ExportViewModel {
    // MARK: - State

    var settings = ExportSettings()
    var selectedPreset: ExportPreset = .instagramReels
    var isExporting = false
    var exportProgress: Double = 0
    var exportedFileURL: URL?
    var showShareSheet = false
    var error: String?

    // MARK: - Engine

    let exportEngine: any VideoExporting

    init(exportEngine: any VideoExporting = ExportEngine()) {
        self.exportEngine = exportEngine
    }

    // MARK: - Export

    @MainActor
    func startExport(
        videoURL: URL,
        segments: [CaptionSegment],
        style: CaptionStyle,
        captionYPosition: Double,
        isPro: Bool
    ) async {
        guard checkExportQuota(isPro: isPro) else {
            error = "Daily export limit reached. Upgrade to Pro for unlimited exports."
            return
        }

        isExporting = true
        exportProgress = 0
        error = nil
        exportedFileURL = nil

        let addWatermark = !isPro

        do {
            let outputURL = try await exportEngine.export(
                videoURL: videoURL,
                settings: settings,
                preset: selectedPreset,
                segments: segments,
                style: style,
                captionYPosition: captionYPosition,
                addWatermark: addWatermark
            )

            exportedFileURL = outputURL
            exportProgress = 1.0

            // The render survived a refused Photos permission, so say what
            // happened and leave the file on offer — the Share button on the
            // success screen still works.
            if !exportEngine.savedToPhotoLibrary {
                error = ExportError.saveFailed.localizedDescription
            }

            // Increment daily count
            incrementExportCount()

            AnalyticsService.exportCompleted(
                preset: selectedPreset.displayName,
                isPro: isPro
            )

        } catch ExportError.cancelled {
            // The user pressed Stop and confirmed it. Answering that with an
            // alert titled "Error" reads as though something went wrong, when
            // what happened is exactly what was asked for.
            exportProgress = 0
        } catch {
            self.error = error.localizedDescription
        }

        isExporting = false
    }

    // MARK: - Cancel

    func cancelExport() {
        exportEngine.cancelExport()
        isExporting = false
    }

    // MARK: - File Size Estimation

    /// Returns the estimated file size for the current settings and video duration.
    func estimatedFileSize(videoDuration: Double) -> String {
        settings.estimatedFileSize(durationSeconds: videoDuration)
    }

    // MARK: - Quota Management

    func checkExportQuota(isPro: Bool) -> Bool {
        if isPro {
            return true
        }

        resetCountIfNewDay()
        let count = UserDefaults.standard.integer(forKey: "dailyExportCount")
        return count < AppState.freeExportLimit
    }

    private func incrementExportCount() {
        resetCountIfNewDay()
        let count = UserDefaults.standard.integer(forKey: "dailyExportCount")
        UserDefaults.standard.set(count + 1, forKey: "dailyExportCount")
    }

    private func resetCountIfNewDay() {
        let lastReset = UserDefaults.standard.object(forKey: "lastExportResetDate") as? Date ?? .distantPast
        if !Calendar.current.isDateInToday(lastReset) {
            UserDefaults.standard.set(0, forKey: "dailyExportCount")
            UserDefaults.standard.set(Date(), forKey: "lastExportResetDate")
        }
    }
}
