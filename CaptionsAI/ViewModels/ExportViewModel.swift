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

    /// Turns auto-lock off (true) and back on (false) around an export.
    /// Injected so tests can see it without touching `UIApplication`.
    private let keepScreenAwake: (Bool) -> Void

    init(
        exportEngine: any VideoExporting = ExportEngine(),
        keepScreenAwake: @escaping (Bool) -> Void = { UIApplication.shared.isIdleTimerDisabled = $0 }
    ) {
        self.exportEngine = exportEngine
        self.keepScreenAwake = keepScreenAwake
    }

    // MARK: - Format

    /// The format the export screen opens on.
    ///
    /// It used to be Reels 9:16 every time, so a landscape clip exported
    /// without a second look came out 1080×1920 with the picture shrunk into
    /// the middle and two thirds of the frame black. Now: the format last
    /// exported for this project if the user ever changed it from the
    /// default, otherwise the one that matches the clip's shape (judged from
    /// its thumbnail, which is drawn upright).
    static func initialPreset(lastUsed: String, sourceSize: CGSize?) -> ExportPreset {
        if let remembered = ExportPreset(rawValue: lastUsed), remembered != .instagramReels {
            return remembered
        }
        if let size = sourceSize, size.width > size.height {
            return .youtube
        }
        return .instagramReels
    }

    /// The size that will actually be rendered, for the summary card.
    ///
    /// The card used to print the preset's base canvas (1080×1920) whatever
    /// Resolution was set to, so 4K and 720p both claimed to be 1080p.
    static func resolutionLabel(preset: ExportPreset, settings: ExportSettings) -> String {
        guard preset != .original else { return settings.resolution.displayName }
        let size = settings.resolution.outputSize(for: preset.resolution)
        return "\(Int(size.width))×\(Int(size.height))"
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
        // One export at a time. A second tap used to start a second render
        // over the first, both writing progress into the same screen.
        guard !isExporting else { return }

        guard checkExportQuota(isPro: isPro) else {
            error = "Daily export limit reached. Upgrade to Pro for unlimited exports."
            return
        }

        isExporting = true
        exportProgress = 0
        error = nil
        exportedFileURL = nil

        // Auto-lock mid-render suspends the app and the export fails with
        // nothing to show for it. Keep the screen on while it runs.
        keepScreenAwake(true)
        defer { keepScreenAwake(false) }

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
        // `isExporting` is left alone on purpose. The export is still
        // unwinding; `startExport` clears the flag when it has returned. Clearing
        // it here showed the settings screen with a render still running, and
        // a second tap on Export started another one on top.
        exportEngine.cancelExport()
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
