import AVFoundation
import CoreTransferable
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - MovieFile Transferable

/// File-based transferable representation of a video asset.
/// Avoids materializing entire video files into RAM as `Data`, preventing Jetsam kills.
struct MovieFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mp4" : received.file.pathExtension
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("import-\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: received.file, to: tempURL)
            return MovieFile(url: tempURL)
        }
    }
}

// MARK: - ImportViewModel

/// Handles video selection and project creation.
@Observable
final class ImportViewModel {
    // MARK: - State

    var selectedVideoURL: URL?
    var recentProjects: [Project] = []

    /// How many projects exist, not how many are shown. ``recentProjects`` is
    /// capped, so it cannot be asked this.
    var totalProjectCount = 0
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

        // The copy is made before the project exists. If anything after it
        // fails, no project refers to the file and nothing would ever delete
        // it, so a failed import used to leave a whole video behind.
        var storedFileName: String?
        var imported = false
        defer {
            if !imported, let storedFileName {
                VideoLibrary.remove(storedFileName)
            }
        }

        do {
            // Stream video via file transfer to avoid materializing large assets in RAM
            let fileName: String
            if let movie = try await item.loadTransferable(type: MovieFile.self) {
                defer { try? FileManager.default.removeItem(at: movie.url) }
                fileName = try VideoLibrary.store(movingFileAt: movie.url)
            } else if let videoData = try await item.loadTransferable(type: Data.self) {
                fileName = try VideoLibrary.store(data: videoData)
            } else {
                error = "Could not load video data"
                return
            }
            storedFileName = fileName

            // Keep it somewhere the system will not reclaim. `tmp/` is emptied
            // whenever iOS wants the space back, which is how a project could
            // still show its thumbnail long after its video had gone.
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
            imported = true

            createdProject = project

            AnalyticsService.videoImported(duration: duration)

        } catch {
            self.error = "Failed to import video: \(error.localizedDescription)"
        }
    }

    // MARK: - Recent Projects

    /// How many projects the home screen's strip shows.
    ///
    /// A *window*, not a cull. Project eleven is still stored, still has its
    /// video, and is still reachable from the full list — it simply is not one
    /// of the ten thumbnails decoded every time the home screen appears.
    static let recentProjectsLimit = 10

    func loadRecentProjects(context: ModelContext) {
        var descriptor = FetchDescriptor<Project>(
            sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]
        )
        descriptor.fetchLimit = Self.recentProjectsLimit
        recentProjects = (try? context.fetch(descriptor)) ?? []

        // Counted separately because the strip cannot answer this about
        // itself: capped at ten, a library of ten and a library of five
        // hundred both load ten rows. `fetchCount` does it in the store
        // rather than by materialising every project to call `.count`.
        totalProjectCount = (try? context.fetchCount(FetchDescriptor<Project>())) ?? recentProjects.count
    }

    // MARK: - Delete

    func deleteProject(_ project: Project, context: ModelContext) {
        ProjectDeletion.delete(project, context: context)
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
