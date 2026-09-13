import AVFoundation
import PhotosUI
import SwiftData
import SwiftUI

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

            // Keep it somewhere the system will not reclaim. `tmp/` is emptied
            // whenever iOS wants the space back, which is how a project could
            // still show its thumbnail long after its video had gone.
            let fileName = try VideoLibrary.store(data: videoData)
            guard let videoFileURL = VideoLibrary.resolve(fileName) else {
                error = "Could not save the imported video"
                return
            }
            selectedVideoURL = videoFileURL

            // Generate thumbnail
            thumbnailImage = await generateThumbnail(for: videoFileURL)

            // Get video duration
            let asset = AVURLAsset(url: videoFileURL)
            let duration = try await CMTimeGetSeconds(asset.load(.duration))

            // Create project
            let project = Project(
                name: "Video \(DateFormatter.shortDate.string(from: Date()))",
                videoURL: videoFileURL,
                videoDuration: duration
            )

            if let thumbnailImage,
               let jpegData = thumbnailImage.jpegData(compressionQuality: 0.6)
            {
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
        // Now that videos are kept deliberately rather than parked in `tmp/`,
        // nothing else will ever clean them up. Read the reference before the
        // delete, while the object is still valid.
        let videoReference = project.videoURLString

        context.delete(project)
        try? context.save()
        VideoLibrary.remove(videoReference)
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
