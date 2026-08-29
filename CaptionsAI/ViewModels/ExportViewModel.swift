import SwiftUI
import AVFoundation

// MARK: - Export Quality

enum ExportQuality: String, CaseIterable, Identifiable {
    case high = "High"
    case maximum = "Maximum"
    
    var id: String { rawValue }
}

// MARK: - ExportViewModel

/// Manages the export workflow including format selection, progress, and sharing.
@Observable
final class ExportViewModel {
    
    // MARK: - State
    
    var selectedPreset: ExportPreset = .instagramReels
    var quality: ExportQuality = .high
    var isExporting = false
    var exportProgress: Double = 0
    var exportedFileURL: URL?
    var showShareSheet = false
    var error: String?
    
    // MARK: - Engine
    
    let exportEngine = ExportEngine()
    
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
                preset: selectedPreset,
                segments: segments,
                style: style,
                captionYPosition: captionYPosition,
                addWatermark: addWatermark
            )
            
            exportedFileURL = outputURL
            exportProgress = 1.0
            
            // Increment daily count
            incrementExportCount()
            
            AnalyticsService.exportCompleted(
                preset: selectedPreset.displayName,
                isPro: isPro
            )
            
        } catch {
            self.error = error.localizedDescription
        }
        
        isExporting = false
    }
    
    // MARK: - Save to Photos
    
    @MainActor
    func saveToPhotos() async {
        guard let url = exportedFileURL else { return }
        
        do {
            try await exportEngine.saveToPhotoLibrary(url)
        } catch {
            self.error = "Failed to save to Photos: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Cancel
    
    func cancelExport() {
        exportEngine.cancelExport()
        isExporting = false
    }
    
    // MARK: - Quota Management
    
    func checkExportQuota(isPro: Bool) -> Bool {
        if isPro { return true }
        
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
