import SwiftUI
import SwiftData
import PhotosUI
import AVFoundation

// MARK: - ImportViewModel

/// Handles video selection and project creation.
@Observable
final class ImportViewModel {
    
    // MARK: - State
    
    var selectedVideoURL: URL?
    var recentProjects: [Project] = []
    var isLoading = false
    var thumbnailImage: UIImage?
    var error: String?
    var createdProject: Project?
    
    // MARK: - Video Selection
    
    /// Processes a video selected from PhotosPicker.
    @MainActor
    func handleVideoSelection(_ item: PhotosPickerItem, context: ModelContext) async {
        isLoading = true
        error = nil
        
        defer { isLoading = false }
        
        do {
            // Load video data
            guard let videoData = try await item.loadTransferable(type: Data.self) else {
                error = "Could not load video data"
                return
            }
            
            // Save to temp location
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("CaptionsAI_\(UUID().uuidString)")
                .appendingPathExtension("mp4")
            
            try videoData.write(to: tempURL)
            selectedVideoURL = tempURL
            
            // Generate thumbnail
            thumbnailImage = await generateThumbnail(for: tempURL)
            
            // Get video duration
            let asset = AVURLAsset(url: tempURL)
            let duration = try await CMTimeGetSeconds(asset.load(.duration))
            
            // Create project
            let project = Project(
                name: "Video \(DateFormatter.shortDate.string(from: Date()))",
                videoURL: tempURL,
                videoDuration: duration
            )
            
            if let thumbnailImage,
               let jpegData = thumbnailImage.jpegData(compressionQuality: 0.6) {
                project.thumbnailData = jpegData
            }
            
            context.insert(project)
            try context.save()
            
            createdProject = project
            
            AnalyticsService.videoImported(duration: duration)
            
        } catch {
            self.error = "Failed to import video: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Recent Projects
    
    func loadRecentProjects(context: ModelContext) {
        let descriptor = FetchDescriptor<Project>(
            sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]
        )
        recentProjects = (try? context.fetch(descriptor)) ?? []
    }
    
    // MARK: - Delete
    
    func deleteProject(_ project: Project, context: ModelContext) {
        context.delete(project)
        try? context.save()
        loadRecentProjects(context: context)
    }
    
    // MARK: - Thumbnail
    
    func generateThumbnail(for url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 400)
        
        do {
            let (cgImage, _) = try await generator.image(at: .zero)
            return UIImage(cgImage: cgImage)
        } catch {
            return nil
        }
    }
}

// MARK: - DateFormatter Extension

extension DateFormatter {
    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()
}
