import CoreGraphics
import Foundation

// MARK: - ExportPreset

/// Platform-specific export format presets.
enum ExportPreset: String, CaseIterable, Identifiable, Codable {
    case instagramReels
    case youtube
    case original

    var id: String {
        rawValue
    }

    // MARK: - Display Properties

    var displayName: String {
        switch self {
        case .instagramReels: return "Instagram Reels / TikTok / Shorts "
        case .youtube: return "YouTube"
        case .original: return "Original"
        }
    }

    var iconName: String {
        switch self {
        case .instagramReels: return "camera.filters"
        case .youtube: return "play.rectangle.fill"
        case .original: return "doc.fill"
        }
    }

    // MARK: - Technical Properties

    var resolution: CGSize {
        switch self {
        case .instagramReels: return CGSize(width: 1080, height: 1920)
//    case .tiktok: return CGSize(width: 1080, height: 1920)
        case .youtube: return CGSize(width: 1920, height: 1080)
//    case .youtubeShorts: return CGSize(width: 1080, height: 1920)
        case .original: return .zero // Will use source resolution
        }
    }

    var aspectRatioString: String {
        switch self {
        case .instagramReels: return "9:16"
        case .youtube: return "16:9"
        case .original: return "Original"
        }
    }

    var resolutionString: String {
        switch self {
        case .original: return "Keep source"
        default: return "\(Int(resolution.width))×\(Int(resolution.height))"
        }
    }
}
