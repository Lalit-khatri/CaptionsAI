import Foundation
import SwiftData

// MARK: - Project

/// Root model representing a captioning project.
/// Contains the video reference, generated caption segments, and style choice.
@Model
final class Project {
    var id: UUID
    var name: String
    
    /// Video URL stored as string for SwiftData compatibility
    var videoURLString: String
    
    /// Thumbnail image data (JPEG compressed)
    var thumbnailData: Data?
    
    var createdAt: Date
    var modifiedAt: Date
    
    /// Name of the selected caption style preset
    var selectedStyleName: String
    
    /// Caption segments with cascade delete
    @Relationship(deleteRule: .cascade, inverse: \CaptionSegment.project)
    var segments: [CaptionSegment]
    
    /// Last used export preset name
    var lastExportPreset: String
    
    /// Duration of the source video in seconds
    var videoDuration: Double
    
    // MARK: - Computed Properties
    
    var videoURL: URL? {
        URL(string: videoURLString)
    }
    
    var selectedStyle: CaptionStyle {
        CaptionStyle.presets.first { $0.name == selectedStyleName } ?? .clean
    }
    
    var sortedSegments: [CaptionSegment] {
        segments.sorted { $0.sortOrder < $1.sortOrder }
    }
    
    var formattedDuration: String {
        let mins = Int(videoDuration) / 60
        let secs = Int(videoDuration) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    // MARK: - Initialization
    
    init(
        id: UUID = UUID(),
        name: String = "Untitled",
        videoURL: URL,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        selectedStyleName: String = "Clean",
        segments: [CaptionSegment] = [],
        lastExportPreset: String = ExportPreset.instagramReels.rawValue,
        videoDuration: Double = 0
    ) {
        self.id = id
        self.name = name
        self.videoURLString = videoURL.absoluteString
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.selectedStyleName = selectedStyleName
        self.segments = segments
        self.lastExportPreset = lastExportPreset
        self.videoDuration = videoDuration
    }
    
    // MARK: - Methods
    
    func addSegment(_ segment: CaptionSegment) {
        segment.sortOrder = segments.count
        segments.append(segment)
        modifiedAt = Date()
    }
    
    func removeSegment(_ segment: CaptionSegment) {
        segments.removeAll { $0.id == segment.id }
        modifiedAt = Date()
    }
    
    func updateStyle(_ styleName: String) {
        selectedStyleName = styleName
        modifiedAt = Date()
    }
}
